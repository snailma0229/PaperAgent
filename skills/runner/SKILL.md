---
name: "runner"
description: "Experiment execution agent. Activates conda environment, runs training and evaluation using exact hyperparameters from config.yaml. Captures all outputs, handles OOM gracefully, saves complete logs and results."
---

# Runner — 实验执行

参数: $ARGUMENTS

从参数中解析：
- **`run_id`**：当前 run_id

读取（必须存在）：
- `runs/<run_id>/env_report.json`（`all_ready: true`）
- `runs/<run_id>/code/config.yaml`
- `runs/<run_id>/impl_plan.json`（获取 reproduction_targets）

输出：`runs/<run_id>/results/`

---

## 前置检查

```bash
# 1. 确认环境就绪
python3 -c "
import json
r = json.load(open('runs/<run_id>/env_report.json'))
assert r['all_ready'], f'env not ready: {r.get(\"manual_steps\")}'
print('env ready:', r['python_version'])
"

# 2. 确认代码存在
ls runs/<run_id>/code/model.py runs/<run_id>/code/train.py runs/<run_id>/code/evaluate.py

# 3. 激活虚拟环境
source runs/<run_id>/venv/bin/activate

# 4. 再次运行 unit tests（确认环境一致）
cd runs/<run_id>/code
python3 tests/test_model.py 2>&1 | tail -5
```

若 unit tests 失败，停止并报告。

---

## 工作流程

### Step 1 — 展示即将使用的超参

读取 `config.yaml`，打印并确认：

```
Training config (from config.yaml):
  dataset:    ml-1m
  batch_size: 256          [source: paper_table_3]
  lr:         0.001        [source: paper_section_4.1]
  epochs:     200          [source: paper_section_4.1]
  embedding:  64           [source: paper_ablation_fig4]
  dropout:    0.5          [source: paper_table_3]
  ranking:    full         [source: paper_section_4.1] CRITICAL
```

### Step 2 — 运行训练

```bash
mkdir -p runs/<run_id>/results/checkpoints

cd runs/<run_id>
source venv/bin/activate
python3 code/train.py \
    --config code/config.yaml \
    2>&1 | tee results/train.log
```

实时监控输出：

**OOM 处理**（仅允许一次调整）：
- 若出现 `CUDA out of memory`，将 `batch_size` 减半后重试一次
- 重试时记录：`# OOM: batch_size reduced from 256 to 128`
- 若减半后仍 OOM，停止并告知用户需要更大显存

**NaN Loss 处理**：
- 若 loss 在前 10 个 epoch 变为 NaN，停止，检查 `config.yaml` 中的 lr 是否过大
- 记录错误，不强行继续

**早停日志**：记录在哪个 epoch 触发早停，以及此时的最佳指标值。

### Step 3 — 运行评估

```bash
source runs/<run_id>/venv/bin/activate
cd runs/<run_id>
python3 code/evaluate.py \
    --config code/config.yaml \
    --checkpoint results/checkpoints/best.pt \
    --output results/metrics.json \
    2>&1 | tee results/eval.log
```

### Step 4 — 验证结果

从 `impl_plan.reproduction_targets` 读取目标值，对比实际结果：

```python
import json

targets = json.load(open('runs/<run_id>/impl_plan.json'))['reproduction_targets']
metrics = json.load(open('runs/<run_id>/results/metrics.json'))

for target in targets:
    metric_key = f"{target['dataset']}_{target['metric']}"
    actual = metrics.get(metric_key, metrics.get(target['metric']))
    paper_val = target['paper_value']
    tolerance = target.get('tolerance', 0.01)
    gap_pct = (actual - paper_val) / paper_val * 100 if paper_val else None

    status = "✓ MATCH" if abs(actual - paper_val) <= tolerance else "⚠ GAP"
    print(f"{status} {target['metric']} on {target['dataset']}: actual={actual:.4f}, paper={paper_val:.4f}, gap={gap_pct:+.1f}%")
```

### Step 5 — 保存结果摘要

写入 `runs/<run_id>/results/summary.json`：

```json
{
  "run_id": "...",
  "status": "success | partial | failed",
  "config_used": "code/config.yaml",
  "training": {
    "best_epoch": 142,
    "stopped_reason": "early_stopping | max_epochs",
    "best_valid_metric": 0.448,
    "total_time_minutes": 38
  },
  "metrics": {
    "ML-1M_HR@10": 0.709,
    "ML-1M_NDCG@10": 0.450,
    "ML-1M_HR@20": 0.812
  },
  "vs_paper": [
    {
      "metric": "HR@10",
      "dataset": "ML-1M",
      "paper_value": 0.712,
      "actual_value": 0.709,
      "gap": -0.003,
      "gap_pct": -0.4,
      "within_tolerance": true
    }
  ],
  "files": {
    "train_log": "results/train.log",
    "eval_log": "results/eval.log",
    "best_checkpoint": "results/checkpoints/best.pt",
    "metrics_json": "results/metrics.json"
  },
  "hardware": {
    "gpu": "NVIDIA RTX 3090",
    "batch_size_used": 256,
    "oom_adjusted": false
  },
  "completed_at": "ISO8601"
}
```

---

## Hard Rules

- **只通过 config.yaml 传参，不在命令行覆盖任何超参**（除 OOM 时的 batch_size）
- OOM 时最多调整一次 batch_size，不修改其他超参
- train.log 和 eval.log **完整保存，不截断**
- 若训练完全失败（无 checkpoint 产出），`status` 记为 `"failed"`，如实保存错误信息
- 不修改 `code/` 目录下的任何代码（那是 code-implementer 的职责），只通过 config 控制
