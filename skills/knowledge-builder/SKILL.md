---
name: "knowledge-builder"
description: "Domain knowledge compiler for Recommendation Systems. Reads a user-maintained markdown file summarizing domain experience (classic methods, implementation lessons, evaluation pitfalls, dataset quirks), and compiles it into a structured knowledge_base.json that design-architect and code-implementer can query."
---

# Knowledge Builder — 推荐系统领域经验编译器

参数: $ARGUMENTS

从参数中解析：
- **`knowledge_file`**：领域经验 `.md` 文件路径（主参数，来自 `— domain-knowledge:` 或 `— library:`）
- **`run_id`**：当前 run_id

读取：`<knowledge_file>`（用户手写的领域经验文档）  
输出：`runs/<run_id>/knowledge_base.json`

---

## 设计理念

`domain-knowledge.md` 是一个**由用户手动维护的经验文档**，记录：
- 做过哪些推荐方法的复现，踩过哪些坑
- 某个数据集上某方法的最佳超参配置
- 哪些实现细节论文没说清楚但从代码里发现了
- 评估协议的边界情况
- 框架/依赖的版本问题

这个文档格式自由，由用户积累和维护。本 skill 的职责是解析并结构化它，让其他 skill 可以直接查询。

---

## 工作流程

### Step 1 — 读取 md 文件

读取 `<knowledge_file>` 的全部内容。若文件不存在，**立即退出**并告知用户创建方式（见末尾模板），不继续运行。

### Step 2 — 提取结构化信息

从 md 文档中识别以下类型的信息（根据文档实际内容，不强求每类都有）：

**A. 已验证的最佳配置**（`best_known_configs`）

寻找类似以下格式的记录：
```
## SASRec on Amazon-Beauty (5-core)
- embedding_dim: 64
- dropout: 0.5
- max_seq_len: 50
- result: HR@10=0.0712, NDCG@10=0.0453 (full ranking)
```

提取为：
```json
{
  "method": "SASRec",
  "dataset": "Amazon-Beauty",
  "config": {"embedding_dim": 64, "dropout": 0.5, "max_seq_len": 50},
  "result": {"HR@10": 0.0712, "NDCG@10": 0.0453},
  "evaluation_type": "full_ranking",
  "source_note": "原文档章节标题或备注"
}
```

**B. 已知的实现坑**（`known_pitfalls`）

寻找描述踩坑经历或注意事项的段落：
```
## 坑：SASRec 的 padding 方向
实验发现 right padding 导致 HR@10 下降 3%，必须用 left padding。
```

提取为：
```json
{
  "method": "SASRec",
  "category": "data_preprocessing",
  "description": "必须用 left padding，right padding 导致 HR@10 下降 3%",
  "severity": "critical",
  "source_note": "..."
}
```

**C. 数据集特有经验**（`dataset_notes`）

提取关于特定数据集的处理经验：
```json
{
  "dataset": "Amazon-Sports",
  "notes": [
    "下载地址：https://...，2018版链接已失效，用2014版",
    "5-core 过滤后只剩 18357 用户，用户较少",
    "avg_seq_len 约 8，序列比 Beauty 更短"
  ]
}
```

**D. 领域通用经验**（`general_lessons`）

不针对特定方法，而是推荐领域的通用经验：
```json
[
  "full ranking 和 sampled@100 的结果绝对不能混用对比",
  "Amazon 数据有时候同一 user-item 对有多条交互，必须去重",
  "RecBole 框架的默认超参和论文不一致，不能直接用 RecBole 默认配置复现"
]
```

**E. 方法演进关系**（`method_relations`，可选）

若文档中有方法之间的关系描述：
```json
[
  {"from": "SASRec", "to": "BERT4Rec", "relation": "BERT4Rec 在 SASRec 基础上加了 mask 预训练，但评估用 full ranking 时两者差距缩小"},
  {"from": "LightGCN", "to": "SGL", "relation": "SGL 在 LightGCN 基础上加对比学习"}
]
```

### Step 3 — 生成查询摘要

为每个方法生成简洁摘要，供 design-architect 快速查询：

```json
{
  "SASRec": {
    "rec_task_type": "sequential",
    "implementation_confidence": "high",
    "verified_configs": 2,
    "known_pitfalls_count": 3,
    "quick_summary": "Transformer-based 序列推荐，单向注意力(causal mask)，embedding_dim=64通常最优，left padding 关键"
  }
}
```

### Step 4 — 写入 knowledge_base.json

```json
{
  "run_id": "...",
  "source_file": "<knowledge_file>",
  "built_at": "ISO8601",
  "domain": "Recommendation Systems",
  "summary": {
    "total_best_configs": 5,
    "total_pitfalls": 12,
    "total_dataset_notes": 4,
    "methods_covered": ["SASRec", "LightGCN", "BERT4Rec", "BPR-MF"]
  },
  "best_known_configs": [...],
  "known_pitfalls": [...],
  "dataset_notes": [...],
  "general_lessons": [...],
  "method_relations": [...],
  "method_summaries": {...}
}
```

---

## domain-knowledge.md 文档模板

若用户尚未创建，提示参考以下模板（保存到项目根目录）：

```markdown
# 推荐系统复现经验库

> 手动维护的领域经验文档，格式自由，尽量具体。

## 通用经验

- full ranking 和 sampled@100/1000 的结果不可混用比较
- Amazon 数据集必须去重（同一 user-item 对保留最早一条）
- K-core 过滤必须迭代直到收敛，不是只过滤一次
- ID 从 1 开始（0 保留给 padding），否则 Embedding 层 padding_idx 需要特别设置

## 数据集经验

### Amazon-Beauty (5-core, 2014版)
- 下载地址：https://jmcauley.ucsd.edu/data/amazon/
- 5-core 后：22363 users, 12101 items
- avg_seq_len ≈ 8.9，序列偏短

### MovieLens-1M
- 下载地址：https://grouplens.org/datasets/movielens/1m/
- 统计：6040 users, 3706 items, 1000209 interactions

## 方法复现经验

### SASRec
- embedding_dim=64, num_heads=1, num_layers=2, dropout=0.5, max_seq_len=50
- **必须用 left padding**（right padding 掉点约 3%）
- 必须有 causal mask（下三角 mask，遮住未来位置）
- 评估时排除训练集所有 item
- Amazon-Beauty(full ranking): HR@10≈0.0712, NDCG@10≈0.0453

### LightGCN
- embedding_dim=64, num_layers=3, lr=0.001, l2_reg=1e-4
- 邻接矩阵用对称归一化：D^{-1/2} A D^{-1/2}
- 不加特征变换，不加非线性激活
- 加自环会略微损害性能

## 踩坑记录

### 坑1：评估协议混用（最常见）
full ranking 的 HR@10 比 sampled@100 低很多（同一模型可能相差 10%+）。
不同论文可能用不同协议，比较结果前必须确认。

### 坑2：数据集版本
Amazon 2014版和2018版统计量差异大，同一方法在两个版本上数字不可比。
复现前必须确认论文用的哪个版本。
```

---

## Hard Rules

- 若 `knowledge_file` 不存在，**不运行**，立即提示用户创建并给出模板
- 只读本地文件，不访问任何网络资源
- `best_known_configs` 中的数字来自文档记录，标注 `source_note`
- 文档中不确定的信息（如"大概是"、"可能"）提取时标注 `confidence: "low"`
