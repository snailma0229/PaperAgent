---
name: "official-runner"
description: "Official library runner for Recommendation Systems. Installs and runs the paper's official implementation (GitHub repo or local path) on the same preprocessed dataset, producing official_metrics.json for three-way comparison: self-implementation vs official library vs paper-reported."
---

# Official Runner — 官方库运行器

参数: $ARGUMENTS

从参数中解析：
- **`run_id`**：当前 run_id
- **`official_lib`**：官方库 GitHub 链接或本地路径（从 `input.json` 读取，若为空则跳过本 skill）

> **`git clone official-lib` 属于「下载已知资源」，在所有模式下始终允许**（与下载数据集性质相同）。offline/library 模式不禁止 clone，禁止的是主动搜索官方库地址的行为。

读取：
- `runs/<run_id>/input.json`（获取 `official_lib` 和数据集路径）
- `runs/<run_id>/data_report.json`（数据集路径、预处理配置）
- `runs/<run_id>/paper_analysis.json`（超参、评估协议）

输出：`runs/<run_id>/official_metrics.json`

---

## 工作流程

### Step 0 — 前置检查

从 `runs/<run_id>/input.json` 读取 `official_lib`：
- 若为 `null` / 未提供：**立即退出**，写入 `official_metrics.json`：
  ```json
  {"status": "skipped", "reason": "no official_lib provided"}
  ```
  不影响后续 result-auditor 运行。

### Step 0.5 — 检查官方库结果复用

**在 clone 仓库和运行实验之前**，扫描 `runs/` 下已有 run，查找满足以下条件的官方库结果：

1. `official_metrics.json` 存在且 `status == "success"`
2. `official_lib` 与本次完全一致（URL 或绝对路径完全相同）
3. 涉及的数据集名称与本次 `target_datasets` 有交集

```python
import json
from pathlib import Path

my_official_lib = input_json['official_lib']
my_datasets = set(input_json.get('target_datasets') or
                  [d['name'] for d in paper_analysis['datasets']])

def find_reusable_official_result(official_lib: str, datasets: set) -> dict | None:
    """返回可复用的 official_metrics，仅包含 datasets 中的指标。"""
    for run_dir in sorted(Path('runs').iterdir(), reverse=True):
        if str(run_dir).endswith(run_id):
            continue
        om_path = run_dir / 'official_metrics.json'
        if not om_path.exists():
            continue
        om = json.loads(om_path.read_text())
        if om.get('status') != 'success':
            continue
        if om.get('official_lib') != official_lib:
            continue
        # 检查数据集覆盖：本次需要的数据集是否在已有结果中都有指标
        existing_datasets = set(om.get('datasets_evaluated', []))
        if not datasets.issubset(existing_datasets):
            continue
        return om
    return None

reusable = find_reusable_official_result(my_official_lib, my_datasets)
```

**若找到可复用结果**：
- 从已有 `official_metrics.json` 中提取本次需要的数据集指标
- 写入本次的 `runs/<run_id>/official_metrics.json`，标注 `reused_from`：

```json
{
  "status": "success",
  "reused": true,
  "reused_from": "runs/2026-05-24-tiger-generative-retrieval/official_metrics.json",
  "official_lib": "https://github.com/...",
  "datasets_evaluated": ["Amazon-Beauty"],
  "metrics": { "Amazon-Beauty_HR@10": 0.0715, "Amazon-Beauty_NDCG@10": 0.0458 },
  "reused_at": "ISO8601"
}
```

- **跳过 Step 1-8**，直接进入 result-auditor。

**若未找到**：继续 Step 1。

**若是 GitHub 链接**：所有模式均允许 clone（属于「下载已知资源」，不是搜索）：

```bash
git clone --depth=1 "<official_lib>" runs/<run_id>/official_repo
```

**blacklist 模式**：如果 `official_lib` 的域名在黑名单中，记录 `status: "blocked"` 后退出。

**若是本地路径**：直接使用，无需下载。

### Step 2 — 分析官方库数据加载格式

扫描官方库的数据加载文件（通常是 `dataset.py` / `data_utils.py` / `dataloader.py`），精确理解其期望的输入格式：

**需要确认的关键信息**：

| 检查项 | 自有预处理输出（标准格式）| 官方库期望格式 | 是否需要转换 |
|--------|----------------------|------------|------------|
| 文件格式 | `train.txt`: `uid item1 item2 ...` | `inter.csv`: `user_id\titem_id\ttimestamp` | 可能需要 |
| ID 起点 | 从 1（0=padding）| 从 0 或从 1 | 需确认 |
| 划分方式 | `train/valid/test.txt` 分开存储 | 单文件 + 按 split 列区分 | 可能需要合并 |
| 序列格式 | 每行：用户完整历史序列 | 每行：一条交互记录 | 可能需要展开 |

### Step 3 — 数据格式适配（⚠️ 必须保证 split 一致）

**核心约束：绝对不能重新划分 train/valid/test。**

所有格式转换必须从已有的 `train.txt` / `valid.txt` / `test.txt` 出发，只改变**数据格式**，不改变**数据内容和划分**。转换脚本保存为 `runs/<run_id>/official_data/<dataset_name>/data_adapter.py`。

```python
# data_adapter.py
import json
from pathlib import Path

# Step A：读取自有预处理结果（ground truth，不可更改）
data_dir = Path(f"runs/{run_id}/data/{dataset_name}/processed")
train_seqs  = {}  # {uid: [item1, item2, ...]}  训练历史序列
valid_items = {}  # {uid: item}                  验证集 ground truth
test_items  = {}  # {uid: item}                  测试集 ground truth

with open(data_dir / "train.txt") as f:
    for line in f:
        parts = line.strip().split()
        uid, items = int(parts[0]), list(map(int, parts[1:]))
        train_seqs[uid] = items

with open(data_dir / "valid.txt") as f:
    for line in f:
        uid, item = map(int, line.strip().split())
        valid_items[uid] = item

with open(data_dir / "test.txt") as f:
    for line in f:
        uid, item = map(int, line.strip().split())
        test_items[uid] = item

out_dir = Path(f"runs/{run_id}/official_data/{dataset_name}")
out_dir.mkdir(parents=True, exist_ok=True)

# Step B：根据官方库格式输出（三选一，根据实际情况选择）

# --- 格式 A：每行一条交互 + split 列（RecBole 风格）---
with open(out_dir / f"{dataset_name}.inter", "w") as f:
    f.write("user_id:token\titem_id:token\tsplit:token\n")
    for uid, items in train_seqs.items():
        for item in items:
            f.write(f"{uid}\t{item}\ttrain\n")
        if uid in valid_items:
            f.write(f"{uid}\t{valid_items[uid]}\tvalid\n")
        if uid in test_items:
            f.write(f"{uid}\t{test_items[uid]}\ttest\n")

# --- 格式 B：与自有格式相同，直接 symlink（零成本）---
# import os; os.symlink(data_dir.resolve(), out_dir / "processed")

# --- 格式 C：(user, item, label) 三元组（部分官方库）---
# with open(out_dir / "train.tsv", "w") as f:
#     for uid, items in train_seqs.items():
#         for item in items:
#             f.write(f"{uid}\t{item}\t1\n")
```

**Step C：适配验证（必须通过才能继续）**

```python
# 验证转换后的数据总量与原数据一致
original_total = (
    sum(len(v) for v in train_seqs.values())
    + len(valid_items) + len(test_items)
)
# 统计转换后的交互总数（不含 header）
with open(out_dir / f"{dataset_name}.inter") as f:
    converted_total = sum(1 for _ in f) - 1  # 减去 header

assert original_total == converted_total, \
    f"❌ 数据转换后总量不一致：原始 {original_total} != 转换后 {converted_total}"

adapter_report = {
    "source_data": str(data_dir),
    "output_data": str(out_dir),
    "format_type": "RecBole-inter",
    "split_preserved": True,
    "train_users": len(train_seqs),
    "valid_users": len(valid_items),
    "test_users": len(test_items),
    "total_interactions_original": original_total,
    "total_interactions_converted": converted_total,
    "verification_passed": True
}
json.dump(adapter_report, open(out_dir / "adapter_report.json", "w"), indent=2)
print(f"✅ 数据适配完成：train={len(train_seqs)} users, valid/test 各 {len(valid_items)} users，总交互 {original_total} 条")
```

若验证失败：**立即停止**，记录 `status: "data_mismatch"`，不继续运行官方库。

### Step 4 — 准备官方库运行环境

```bash
cd runs/<run_id>/official_repo

# 创建独立 conda 环境，避免与自实现环境冲突
# 命名规则：paper-agent-official-<run_id[:8]>
conda create -n paper-agent-official-<run_id8> python=<python_version> -y

# 安装官方库依赖
conda run -n paper-agent-official-<run_id8> pip install -r requirements.txt 2>&1 | tail -5
```

### Step 5 — 配置超参（精确对齐论文超参）

从 `paper_analysis.training_config` 读取超参，传给官方库。**不调整任何超参**——目的是得到官方库在相同超参下的结果，而非最优超参。

从 `paper_analysis.evaluation` 读取评估协议，确保官方库用**相同的评估方式**（full ranking vs sampled）。

```bash
# 示例：RecBole 类官方库
python run_recbole.py \
    --model=SASRec \
    --dataset=amazon-beauty \
    --config_files=official_config.yaml
```

官方库的超参配置文件 `official_config.yaml` 根据 `paper_analysis.training_config` 生成，格式匹配官方库。

### Step 6 — 运行实验

```bash
conda run -n paper-agent-official-<run_id8> python <main_entry> [config_args] 2>&1 | tee runs/<run_id>/official_run.log
```

**超时限制**：与自实现相同，4 小时内未完成则停止，记录 `status: "timeout"`。

监控日志，提取最佳 epoch 的验证集/测试集指标（或官方库直接输出的 best results）。

### Step 7 — 提取结果

从 `official_run.log` 或官方库输出的结果文件中提取指标。

若官方库有多个 epoch 的结果，取 best epoch（按 `paper_analysis.training_config.early_stopping.metric` 选最佳验证集指标对应的测试集结果）。

### Step 8 — 写入 official_metrics.json

```json
{
  "run_id": "...",
  "status": "success | failed | skipped | timeout | data_mismatch",
  "reused": false,
  "reused_from": null,
  "official_lib": "https://github.com/...",
  "official_conda_env": "paper-agent-official-<run_id8>",
  "datasets_evaluated": ["Amazon-Beauty", "Amazon-Sports"],
  "data_compatibility": {
    "original_data": "runs/<run_id>/data/<dataset>/processed/",
    "converted_data": "runs/<run_id>/official_data/<dataset>/",
    "format_type": "RecBole-inter | raw-symlink | triplet | none",
    "conversion_needed": true,
    "split_preserved": true,
    "verification_passed": true,
    "adapter_report": "runs/<run_id>/official_data/<dataset>/adapter_report.json"
  },
  "hyperparams_used": {
    "source": "paper_analysis.training_config",
    "embedding_dim": 64,
    "batch_size": 256,
    "lr": 0.001
  },
  "evaluation_type": "full_ranking",
  "metrics": {
    "Amazon-Beauty_HR@10": 0.0715,
    "Amazon-Beauty_NDCG@10": 0.0458
  },
  "best_epoch": 47,
  "run_log": "runs/<run_id>/official_run.log",
  "error_message": null,
  "ran_at": "ISO8601"
}
```

---

## 与自实现的关键差异

官方库运行的目的是**基准验证**，不是竞争：

1. **数据集必须一致**：使用与自实现完全相同的预处理数据，避免因数据差异干扰对比
2. **超参必须一致**：使用论文超参，而不是官方库默认超参（两者可能不同）
3. **评估协议必须一致**：full ranking vs sampled 必须与论文一致

## Hard Rules

- 数据格式转换**必须从已有 train/valid/test 文件出发**，只改格式不改内容，绝不重新划分
- 转换后必须验证交互总数一致，验证失败立即停止（`status: "data_mismatch"`）
- 超参**必须来自** `paper_analysis.training_config`，不使用官方库默认配置
- 官方库运行在独立 conda 环境（`paper-agent-official-<run_id8>`）中，不污染自实现环境
- 若官方库运行失败，**不阻塞** result-auditor，记录 `status: failed` 后继续
