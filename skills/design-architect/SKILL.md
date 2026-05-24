---
name: "design-architect"
description: "Implementation plan designer specialized in Recommendation Systems. Synthesizes paper_analysis.json + knowledge_base.json + reference repos to produce a complete, unambiguous implementation plan for RecSys papers. Every hyperparameter has a source and confidence level. Produces impl_plan.json."
---

# Design Architect — 推荐系统实现方案设计师

参数: $ARGUMENTS

从参数中解析：
- **`run_id`**：当前 run_id
- **`knowledge_policy`**：控制**信息搜索行为**（不控制实际代码执行）

> **`knowledge_policy` 在本 skill 中的含义**：
> - `allow_web: false`（offline/library 模式）：禁止为设计方案而主动搜索（如搜索相关论文、搜索参考实现代码）；只能使用已有的 paper_analysis / knowledge_base / AI 自身知识
> - `allow_web: true`（free/blacklist 模式）：可以搜索补充信息，blacklist 模式下搜索请求须经黑名单检查

可用输入（按优先级读取，不存在的跳过）：
1. `runs/<run_id>/paper_analysis.json` — 论文详细解析
2. `runs/<run_id>/knowledge_base.json` — 领域先验知识库
3. `runs/<run_id>/sources_manifest.json` — 参考代码位置
4. AI 已有知识（所有模式下都可用，offline 模式下这是唯一的补充来源）

输出：`runs/<run_id>/impl_plan.json`

---

## 工作流程

这是整个系统中**最重要的 skill**，直接决定复现质量。目标是在写任何代码前，把所有可能出错的地方都明确化。

### Step 1 — 确定信息来源状态

检查哪些输入文件存在：

```
paper_analysis.json 存在？ → 信息来源：论文（最可靠）
knowledge_base.json 存在？ → 信息来源：领域知识库
sources_manifest.json 中有 GitHub repo？ → 信息来源：参考实现
以上都不存在？ → 仅凭 AI 已有 RecSys 知识（offline 模式）
```

### Step 2 — 确认任务类型与对应实现模式

从 `paper_analysis.rec_task_type` 读取任务类型，针对不同任务使用不同的模块拆分策略：

**序列推荐（sequential）** — 核心模块：
- `ItemEmbedding`：item_id → embedding，注意 padding_idx=0
- `PositionEmbedding`（若有）：位置编码方式（learned vs sinusoidal）
- 序列编码器（GRU / Transformer Blocks / MLP-Mixer）
- 预测层：dot product / MLP

**协同过滤（collaborative_filtering）** — 核心模块：
- `UserEmbedding`、`ItemEmbedding`
- 交互层（dot product / MLP / 神经因子分解机）

**图神经网络（graph）** — 核心模块：
- 图构建（邻接矩阵归一化方式）
- 图卷积层（LightGCN / NGCF / GAT 的具体公式）
- Embedding 传播（层数、聚合方式）
- 数据增强（节点 dropout vs 边 dropout vs 特征增强）

**知识图谱（knowledge_graph）** — 核心模块：
- KG 关系嵌入（TransR / RotatE）
- 知识传播（ripple propagation / attention）
- 与 CF 信号的融合方式

### Step 3 — 建立模块清单

将论文方法拆分成**独立可实现的模块**：

```json
// 示例：SASRec
{
  "name": "TransformerBlock",
  "paper_ref": "Section 3.2, Eq.3-7",
  "input": "seq_emb: [B, T, D]",
  "output": "seq_emb: [B, T, D]",
  "critical_details": [
    "pre-norm (LayerNorm before attention, not after)",
    "causal mask: lower triangular, future positions masked",
    "dropout applied to attention output BEFORE residual add"
  ],
  "confidence": "high",
  "confidence_source": "paper_explicit"
}
```

### Step 4 — 超参决策表

对**每一个**超参，记录来源和置信度：

```json
{
  "name": "embedding_dim",
  "value": 64,
  "source": "paper_table_3_ablation",
  "confidence": "high",
  "alternatives_tried_in_paper": [16, 32, 64, 128],
  "note": "论文消融实验显示 64 最优"
}
```

置信度：
- `high`：论文明确给出
- `medium`：从论文上下文推断，或参考 knowledge_base 中同领域典型值
- `low`：完全推断，代码中注释 `# ASSUMED`

**推荐领域常见超参的默认值参考**（仅在 confidence=low 时使用）：

| 超参 | 典型值 | 说明 |
|------|--------|------|
| embedding_dim | 64 | SASRec/BERT4Rec/LightGCN 常用 |
| batch_size | 256 | 大多数序列推荐 |
| lr | 0.001 | Adam 默认 |
| l2_reg | 1e-4 ~ 1e-5 | 过大会欠拟合 |
| dropout | 0.1~0.5 | 序列推荐 0.1~0.2，CF 0.3~0.5 |
| max_seq_len | 50 | Amazon 类数据集 |
| num_layers | 2 | Transformer-based 方法 |
| num_heads | 1 | 很多 RecSys 论文用单头 |
| graph_layers | 3 | LightGCN 等图方法 |

### Step 5 — 关键细节清单（推荐系统特有坑）

必须包含以下类别的检查项（至少列出 15 条）：

**数据处理类（必须全部覆盖）**：
- `[DATA-01]` K-core 过滤的具体策略（5-core 是所有 user 和 item 都至少 5 次？还是只过滤 user？）
- `[DATA-02]` 时间戳排序（用户历史按时间升序）
- `[DATA-03]` 数据集划分（leave-one-out：最后一个为 test，倒数第二个为 valid）
- `[DATA-04]` ID 重映射（从 1 开始，0 保留给 padding）
- `[DATA-05]` 序列截断方向（超过 max_seq_len 时保留最新的 T 个，从右截断）
- `[DATA-06]` 序列 padding 方向（**left padding**，大多数序列推荐论文用 left padding）

**评估协议类（最容易出错）**：
- `[EVAL-01]` 排名类型：full ranking 还是 sampled ranking（需明确数字与哪种对应）
- `[EVAL-02]` 测试时是否排除训练集中的 item（通常是排除）
- `[EVAL-03]` 验证集 item 在测试时是否也排除（通常排除）
- `[EVAL-04]` HR@K 和 NDCG@K 的分母（HR 是否归一化为 Recall）

**模型实现类**：
- `[MODEL-01]` Causal mask 在序列推荐中的必要性（SASRec 系列必须有）
- `[MODEL-02]` Embedding L2 归一化（如果论文提到 normalize embeddings）
- `[MODEL-03]` 图方法中是否添加自环
- `[MODEL-04]` BPR 损失中正负样本的 item 是否 detach

**训练类**：
- `[TRAIN-01]` 负采样在每个 epoch 是否重新采样（dynamic negative sampling）
- `[TRAIN-02]` L2 正则化的施加范围（所有参数 vs 只对 embedding）

### Step 6 — 评估协议设计（推荐系统核心）

```json
{
  "evaluation_protocol": {
    "ranking_type": "full",
    "candidate_generation": "all items (num_items)",
    "exclude_seen_items": true,
    "exclude_valid_item_at_test": true,
    "test_item": "last interaction (leave-one-out)",
    "valid_item": "second-to-last interaction",
    "metrics": [
      {"name": "HR@10", "alias": ["Recall@10", "Hit@10"], "formula": "1 if test_item rank <= 10 else 0"},
      {"name": "NDCG@10", "formula": "1/log2(rank+1) if rank<=10 else 0, binary relevance"},
      {"name": "MRR", "formula": "1/rank"}
    ],
    "aggregation": "mean over all test users"
  }
}
```

**特别注意**：若 `paper_analysis.evaluation.ranking_type == "sampled"`，必须在 `impl_plan` 中明确标注，并在 `evaluate.py` 中实现采样逻辑。

### Step 7 — 复现目标清单

```json
{
  "reproduction_targets": [
    {
      "metric": "HR@10",
      "dataset": "Amazon-Beauty",
      "paper_value": 0.0712,
      "table_ref": "Table 2, Row: SASRec",
      "ranking_type": "full",
      "tolerance": 0.003
    }
  ]
}
```

### Step 8 — 写入 impl_plan.json

```json
{
  "run_id": "...",
  "method_name": "...",
  "rec_task_type": "sequential",
  "information_sources": {
    "paper_analysis": true,
    "knowledge_base": false,
    "reference_repo": null,
    "ai_prior_knowledge": true
  },
  "modules": [...],
  "hyperparams": [...],
  "critical_details": [...],
  "data_flow": "item_ids[B,T] → ItemEmb[B,T,D] → TransformerBlocks[B,T,D] → last_hidden[B,D] → scores[B,num_items]",
  "evaluation_protocol": {...},
  "reproduction_targets": [...],
  "file_plan": {
    "model.py": ["ItemEmbedding", "PositionEmbedding", "TransformerBlock", "SASRec"],
    "dataset.py": ["SequentialDataset", "negative_sample_train"],
    "train.py": ["main training loop with BPR loss"],
    "evaluate.py": ["full_ranking_evaluate"],
    "config.yaml": "all hyperparams with source comments",
    "requirements.txt": ["torch>=1.7.0", "numpy", "scipy", "pandas", "tqdm"]
  },
  "confidence_summary": {
    "high": 9,
    "medium": 2,
    "low": 1,
    "overall": "high"
  },
  "designed_at": "ISO8601"
}
```

---

## 对不同信息来源的处理策略

### 有 paper_analysis（模式 1/3/4/5）
- 超参直接从 `paper_analysis.training_config` 读取
- 关键细节从 `paper_analysis.implementation_pitfalls` + `training_tricks` 补充到 `critical_details`
- 评估协议从 `paper_analysis.evaluation` 精确对应

### 有 reference repo（模式 1/4）
- 扫描 repo 中的 config 文件，核对超参
- 若 repo 超参与论文不同，**优先相信论文**，记录差异
- 参考 `dataset.py` 确认 padding 方向和数据处理细节（这里最容易有论文未说清楚的细节）

### 有 knowledge_base（模式 5）
- 从 `knowledge_base.best_known_configs` 查找相同方法的配置
- 参考 `knowledge_base.evolution_chain` 了解改动点

### 仅凭 AI 已有知识（模式 2）
- 对 SASRec/BERT4Rec/LightGCN 等知名方法，AI 有足够的知识支撑 high/medium confidence
- 对较新方法（2023+），unknown 细节用 `low` 置信度标注

---

## Hard Rules

- `critical_details` **必须至少 15 条**，且必须覆盖 DATA、EVAL、MODEL、TRAIN 四个类别
- `evaluation_protocol.ranking_type` 必须从 `paper_analysis.evaluation.ranking_type` 精确继承
- 每个超参必须有 `source` 和 `confidence`
- 若 `ranking_type` 为 `sampled`，必须在 `critical_details` 中添加 `[EVAL-WARN]` 条目，提示复现结果**不可与 full ranking 论文比较**
