---
name: "paper-reader"
description: "Deep paper analysis expert specialized in Recommendation Systems. Reads a PDF or arXiv paper and exhaustively extracts method architecture, hyperparameters, datasets, training config, evaluation metrics, training tricks, ablation insights, and implementation pitfalls. Outputs paper_analysis.json."
---

# Paper Reader — 推荐系统论文深度解析

参数: $ARGUMENTS

从参数中解析：
- **`paper_path`**：PDF 路径（主参数，或从 sources_manifest.json 中读取）
- **`run_id`**：当前 run_id
- **`knowledge_policy`**：控制是否可以联网补充信息

输出：`runs/<run_id>/paper_analysis.json`

---

## 工作流程

### Step 1 — 获取论文内容

**若是 PDF 路径**：直接读取文件内容，提取所有文本（含附录）。

**若是 arXiv 链接/ID**（knowledge_policy.allow_web 为 true 时）：
1. 访问 `https://ar5iv.org/html/<id>` 获取 HTML 全文（格式更易解析）
2. 若失败，访问 `https://arxiv.org/pdf/<id>` 下载 PDF
3. 同时访问 `https://arxiv.org/abs/<id>` 获取元信息

**若 allow_web 为 false**：只能读取本地 PDF 文件，不进行**搜索**（不访问 arXiv 搜索、Google Scholar 等），不网络请求任何资料。

### Step 2 — 识别推荐任务类型

**首先确认本文属于哪类推荐任务**，这决定了后续所有解析维度的重点：

| 任务类型 | 关键特征 | 代表方法 |
|---------|---------|---------|
| **序列推荐** | 利用用户历史交互序列预测下一个 | SASRec, BERT4Rec, GRU4Rec |
| **协同过滤** | 仅用 user-item 交互矩阵 | BPR-MF, LightGCN, NGCF |
| **图神经网络推荐** | 在 user-item 二部图上传播 | LightGCN, SimGCL, SGL |
| **知识图谱推荐** | 融合 item 侧知识图谱 | KGNN-LS, KGAT |
| **多行为推荐** | 利用多种交互类型（点击/购买/收藏） | MBGCN, MB-GMN |
| **跨域推荐** | 跨不同域迁移知识 | CoNet, EMCDR |
| **对话推荐** | 通过对话交互推荐 | KGSF, UniCRS |
| **基于内容/多模态** | 融合 item 文本/图像特征 | BM3, FREEDOM |

记录到 `paper_analysis.rec_task_type`。

### Step 3 — 系统性深度阅读

**必须逐一覆盖以下所有维度，不跳过任何一项：**

**A. 基本信息**
- 标题、作者列表、发表年份、会议/期刊（RecSys/WWW/SIGIR/KDD/AAAI/WSDM/CIKM/NeurIPS/ICML/ICLR）

**B. 核心贡献**
- 解决了推荐中的什么问题（稀疏性/冷启动/序列建模/公平性等）？
- 本文的 novelty 是什么（1-3 条）？

**C. 模型架构（最关键，需穷尽细节）**
- 逐层描述：每一层的类型、维度变化、激活函数
- 残差连接、注意力机制的具体实现方式
- 归一化层的位置（pre-norm vs post-norm）
- Embedding 的维度和初始化方式（user embedding、item embedding 是否共用 size）
- Dropout 的位置和具体加在哪一层之后
- **图结构方法**额外关注：图卷积层数、邻居聚合方式、节点 dropout vs 边 dropout

**D. 关键算法**
- 若有伪代码或 Algorithm 框，逐行理解并记录
- 若无，从方法描述重建算法步骤

**E. 损失函数（推荐系统特有细节）**
- 完整公式（含所有符号说明）
- 损失类型：BPR / BCE / Softmax / InfoNCE / 自监督辅助损失
- **负采样策略**（极其重要）：
  - 训练时负采样数量（e.g., 1 vs 100）
  - 负采样方法（uniform random / popularity-based / hard negative / in-batch）
  - 是否有负采样去噪
- 正则化：L2 正则化系数、Dropout 系数
- 若有对比学习损失：温度参数 τ、数据增强方式

**F. 数据集（推荐领域标准数据集）**

对每个数据集记录：
- 名称和来源（Amazon 类需记录具体子类，如 Amazon-Beauty、Amazon-Sports）
- **数据集版本**（Amazon 数据集有 5-core 版和原始版，两者统计差异大）
- 统计量：用户数、物品数、交互数、稀疏度、平均序列长度
- 数据预处理（见 Step 4 重点）
- 数据集划分方式和负采样策略

**G. 训练配置（必须穷尽）**
- batch size、learning rate、优化器及其参数（momentum, weight decay）
- 训练 epoch 数 / early stopping 条件和 patience
- Learning rate schedule（如有）
- 梯度裁剪（clipping norm）
- 权重初始化方式（Xavier / He / 正态分布及其 std）
- 随机种子（如有）
- **序列推荐特有**：最大序列长度 `max_seq_len`

**H. 评估协议（推荐系统最容易出错的地方）**

必须精确记录以下每一项：

1. **全量排名 vs 采样排名**（full ranking vs sampled ranking）
   - full ranking：对所有 item 排序，结果可与其他 full ranking 论文直接比较
   - sampled@100/1000：只对少量负样本排序，数值与 full ranking 不可比
   - **这两种协议的 HR@10 可能相差 10%+，是复现失败的头号原因**

2. **测试时是否排除已见过的 item**（training item exclusion）
   - 大多数论文排除训练历史中的 item
   - 少数不排除，需明确

3. **测试集构造**：leave-one-out（最后一个交互）还是 ratio split

4. **评估指标的精确计算方式**：
   - HR@K（也写作 Recall@K、Hit Ratio@K）
   - NDCG@K（binary relevance，单个正样本）
   - MRR（Mean Reciprocal Rank）
   - Precision@K

5. **验证集 ground truth** 在测试时是否可见？

**I. 论文原始结果**
- 主要对比实验表格的完整数字（精确到小数点后3位）
- 注明是 full ranking 还是 sampled ranking 的结果
- 注明实验使用的是哪个版本的数据集

**J. Ablation 分析（极其重要）**
- 消融实验中哪个组件去掉后掉点最多？
- 超参敏感性分析（embedding_dim、num_layers、dropout、温度 τ 等）
- 各模块对最终结果的贡献排序

**K. Training Tricks（隐藏细节）**
- 论文附录中的额外实现细节
- 序列 padding 方向（left padding vs right padding）
- Position embedding 的实现（learned vs sinusoidal，最大长度是否可超过 max_seq_len）
- Embedding 归一化（L2 normalization on embeddings）
- 图方法中的自环处理（add self-loop vs not）

**L. 依赖框架**
- 主要框架（PyTorch / TensorFlow）
- 特殊依赖（torch_geometric / dgl / faiss / recbole）
- 硬件要求（GPU 数量、显存）

### Step 4 — 写入 paper_analysis.json

```json
{
  "run_id": "...",
  "rec_task_type": "sequential | collaborative_filtering | graph | knowledge_graph | multi_behavior | cross_domain | conversational | content_based",
  "paper": {
    "title": "...",
    "authors": ["..."],
    "year": 2024,
    "venue": "RecSys | WWW | SIGIR | KDD | AAAI | WSDM | CIKM | NeurIPS | ICML | ICLR",
    "arxiv_id": "... or null"
  },
  "method": {
    "name": "...",
    "core_idea": "2-4 句话",
    "architecture": {
      "overview": "...",
      "components": [
        {
          "name": "...",
          "paper_section": "Section X.X",
          "description": "...",
          "input_shape": "...",
          "output_shape": "...",
          "key_ops": [],
          "normalization": "...",
          "dropout_position": "...",
          "activation": "..."
        }
      ],
      "forward_pass_steps": [],
      "embedding": {
        "user_dim": 64,
        "item_dim": 64,
        "shared_dim": true,
        "init": "xavier_uniform",
        "l2_normalize": false
      }
    },
    "loss_function": {
      "formula": "...",
      "type": "BPR | BCE | Softmax | InfoNCE | hybrid",
      "aux_loss": null,
      "aux_loss_weight": null,
      "temperature": null,
      "negative_sampling_train": {
        "strategy": "uniform | popularity | hard_negative | in_batch",
        "num_negatives": 1
      },
      "regularization": {"l2": 1e-4, "dropout": 0.1}
    }
  },
  "datasets": [
    {
      "name": "Amazon-Beauty",
      "source": "Amazon Product Reviews",
      "version": "5-core",
      "stats": {
        "users": 22363, "items": 12101, "interactions": 198502,
        "sparsity": 0.9993, "avg_seq_len": 8.9
      },
      "preprocessing": {
        "filtering": "5-core",
        "sorting": "by timestamp",
        "split": "leave-one-out",
        "negative_sampling_eval": "full_ranking | sampled_100 | sampled_1000",
        "exclude_train_items_at_eval": true
      },
      "download_url": "https://jmcauley.ucsd.edu/data/amazon/",
      "download_method": "wget"
    }
  ],
  "training_config": {
    "framework": "PyTorch",
    "batch_size": 256,
    "learning_rate": 0.001,
    "optimizer": "Adam",
    "optimizer_params": {"betas": [0.9, 0.999], "weight_decay": 0.0},
    "l2_reg": 1e-4,
    "epochs": 200,
    "early_stopping": {"metric": "NDCG@10", "patience": 10},
    "lr_schedule": null,
    "gradient_clip": null,
    "weight_init": "xavier_uniform",
    "dropout_rate": 0.1,
    "random_seed": 42,
    "max_seq_len": 50
  },
  "evaluation": {
    "metrics": ["HR@10", "NDCG@10", "MRR"],
    "ranking_type": "full | sampled",
    "sampled_size": null,
    "exclude_train_items": true,
    "test_set_construction": "leave-one-out: last item as test, second-to-last as valid"
  },
  "original_results": {
    "main_table_description": "Table 2: Performance comparison on 3 datasets",
    "ranking_type_in_table": "full",
    "key_numbers": {
      "Amazon-Beauty_HR@10": 0.0712,
      "Amazon-Beauty_NDCG@10": 0.0453
    }
  },
  "ablation_insights": [
    {"component": "self-attention", "impact": "removing drops NDCG@10 by 8.2%", "conclusion": "最关键组件"}
  ],
  "hyperparams_sensitivity": [
    {"param": "embedding_dim", "search_range": "[16,32,64,128]", "optimal": 64, "sensitivity": "medium"},
    {"param": "dropout", "search_range": "[0.1,0.3,0.5]", "optimal": 0.1, "sensitivity": "high"}
  ],
  "training_tricks": [
    "left-pad sequence with 0 (not right-pad)",
    "apply padding mask in self-attention",
    "L2 normalize item embeddings before scoring"
  ],
  "implementation_pitfalls": [
    "evaluation uses full ranking, not sampled — numbers in Table 2 are NOT comparable with sampled-100 baselines",
    "exclude training items at evaluation time",
    "sequence padded on LEFT side"
  ],
  "dependencies": {
    "python_version": "3.8+",
    "main_framework": "torch>=1.7.0",
    "packages": ["numpy", "scipy", "pandas", "tqdm"],
    "gpu_required": true,
    "num_gpus": 1
  },
  "missing_details": [],
  "analyzed_at": "ISO8601"
}
```

---

## Hard Rules

- `evaluation.ranking_type` 和 `original_results.ranking_type_in_table` **必须精确**（full vs sampled 是推荐复现最常见的失败原因）
- `implementation_pitfalls` **必须至少包含一条关于评估协议的说明**
- `training_tricks` 中必须记录序列 padding 方向（left vs right）
- 不捏造数据，缺失字段填 `null` 并在 `missing_details` 说明
- `original_results.key_numbers` 必须来自论文表格，不填推测值
- 附录内容必须读取（很多关键实现细节在附录）
