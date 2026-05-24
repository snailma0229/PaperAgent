---
name: "official-runner"
description: "Official library runner for Recommendation Systems. Installs and runs the paper's official implementation (GitHub repo or local path) on the same preprocessed dataset, producing official_metrics.json for three-way comparison: self-implementation vs official library vs paper-reported."
---

# Official Runner — 官方库运行器

参数: $ARGUMENTS

从参数中解析：
- **`run_id`**：当前 run_id
- **`official_lib`**：官方库 GitHub 链接或本地路径（从 `input.json` 读取，若为空则跳过本 skill）

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

### Step 1 — 获取官方库

**若是 GitHub 链接**（`knowledge_policy.allow_web` 须为 true，或 offline 模式下已在本地）：

```bash
git clone --depth=1 "<official_lib>" runs/<run_id>/official_repo
```

若 `allow_web: false` 且 `official_lib` 是网络链接：记录 `status: "skipped"` 并退出，在 `official_metrics.json` 中注明原因。

**若是本地路径**：直接使用，无需下载。

### Step 2 — 分析官方库结构

扫描官方库，找到：
- 主要训练入口（`main.py` / `run.py` / `train.py`）
- 配置文件（`.yaml` / `.json` / argparse）
- 数据加载逻辑（了解其期望的数据格式）

重点检查官方库的数据格式是否与 `data_report.json` 中已处理的数据格式兼容：

| 检查项 | 自有预处理输出 | 官方库期望格式 | 是否兼容 |
|--------|------------|------------|--------|
| 数据文件格式 | `train.txt`: `user item1 item2` | `inter.csv`: `user:token item:token` | 需转换 |
| ID 映射起点 | 从 1（0=padding） | 从 0 或从 1 | 确认 |
| 数据集名称 | Amazon-Beauty | ml-1m | 无关 |

### Step 3 — 准备官方库运行环境

```bash
cd runs/<run_id>/official_repo

# 创建独立 conda 环境，避免与自实现环境冲突
# 命名规则：paper-agent-official-<run_id[:8]>
conda create -n paper-agent-official-<run_id8> python=<python_version> -y

# 安装官方库依赖
conda run -n paper-agent-official-<run_id8> pip install -r requirements.txt 2>&1 | tail -5
```

### Step 4 — 配置超参（精确对齐论文超参）

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

### Step 5 — 运行实验

```bash
conda run -n paper-agent-official-<run_id8> python <main_entry> [config_args] 2>&1 | tee runs/<run_id>/official_run.log
```

**超时限制**：与自实现相同，4 小时内未完成则停止，记录 `status: "timeout"`。

监控日志，提取最佳 epoch 的验证集/测试集指标（或官方库直接输出的 best results）。

### Step 6 — 提取结果

从 `official_run.log` 或官方库输出的结果文件中提取指标。

若官方库有多个 epoch 的结果，取 best epoch（按 `paper_analysis.training_config.early_stopping.metric` 选最佳验证集指标对应的测试集结果）。

### Step 7 — 写入 official_metrics.json

```json
{
  "run_id": "...",
  "status": "success | failed | skipped | timeout",
  "official_lib": "https://github.com/...",
  "official_conda_env": "paper-agent-official-<run_id8>",
  "data_compatibility": {
    "data_reused": true,
    "conversion_needed": false,
    "conversion_note": null
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

- 数据集**必须复用** `data_report.json` 中已处理的数据，不重新下载
- 超参**必须来自** `paper_analysis.training_config`，不使用官方库默认配置
- 官方库运行在独立 venv 中，不污染自实现环境
- 若官方库运行失败，**不阻塞** result-auditor，记录 `status: failed` 后继续
