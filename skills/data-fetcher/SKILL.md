---
name: "data-fetcher"
description: "Dataset acquisition and preprocessing agent specialized in Recommendation Systems. Downloads standard RecSys datasets (Amazon, MovieLens, Yelp, Steam, etc.), applies exact preprocessing from paper (K-core filtering, timestamp sorting, leave-one-out split), and validates statistics match the paper. Outputs data_report.json."
---

# Data Fetcher — 推荐系统数据集获取与预处理

参数: $ARGUMENTS

从参数中解析：
- **`run_id`**：当前 run_id
- **`knowledge_policy`**：控制**信息搜索行为**（不控制数据集下载）

> **`knowledge_policy` 在本 skill 中的含义**：
> - `allow_web: false`（offline/library 模式）：数据集下载**始终允许**（从已知 URL 下载是执行操作，不是搜索）；禁止的是为了补充数据集信息而主动联网搜索（如搜索数据集的镜像站、搜索替代下载链接）
> - `allow_web: true`（free/blacklist 模式）：允许搜索替代下载源，blacklist 模式下所有 HTTP 请求（包括数据集下载）须经黑名单检查

读取（必须存在）：`runs/<run_id>/paper_analysis.json`  
输出：`runs/<run_id>/data_report.json`，`runs/<run_id>/data/`

---

## 推荐领域常用数据集速查表

| 数据集 | 来源 | 下载方式 | 官方地址 |
|--------|------|---------|---------|
| MovieLens-1M/10M/20M/100K | GroupLens | wget | https://grouplens.org/datasets/movielens/ |
| Amazon-* (Beauty/Sports/Toys/Books/...) | UCSD | wget | https://jmcauley.ucsd.edu/data/amazon/ |
| Amazon 2018 版 | UCSD | wget | https://nijianmo.github.io/amazon/index.html |
| Yelp | Yelp | manual (需注册) | https://www.yelp.com/dataset |
| Steam | UCSD | wget | https://cseweb.ucsd.edu/~jmcauley/datasets.html |
| LastFM | HetRec | wget | https://grouplens.org/datasets/hetrec-2011/ |
| Epinions | various | wget | varies |
| Gowalla | Stanford SNAP | wget | https://snap.stanford.edu/data/loc-Gowalla.html |
| Foursquare | various | manual | varies |
| Book-Crossing | Informatik | wget | http://www2.informatik.uni-freiburg.de/~cziegler/BX/ |

---

## 工作流程

### Step 1 — 解析数据集需求

从 `paper_analysis.datasets` 读取所有数据集定义。

**如果 `input.json` 中 `target_datasets` 不为 null**，将 `paper_analysis.datasets` 过滤为只包含其中指定的数据集（大小写不敏感匹配）：

```python
target_datasets = input_json.get('target_datasets')  # None 或 list
all_datasets = paper_analysis['datasets']

if target_datasets:
    # 大小写不敏感匹配，支持简写（如 "Beauty" 匹配 "Amazon-Beauty"）
    datasets = [
        d for d in all_datasets
        if any(t.lower() in d['name'].lower() for t in target_datasets)
    ]
    if not datasets:
        raise ValueError(f"target_datasets {target_datasets} 和论文数据集 {[d['name'] for d in all_datasets]} 无匹配")
else:
    datasets = all_datasets

print(f"将处理数据集：{[d['name'] for d in datasets]}")
```

后续所有步骤仅针对过滤后的 `datasets` 列表操作。确认每个数据集的名称、版本、`download_method`、预处理步骤和论文统计量。

### Step 2 — 检查数据复用（优先）

**在下载任何数据之前**，首先检查全局 `runs/` 目录下是否已有相同数据集的预处理结果可复用：

```python
import os, json
from pathlib import Path

def find_existing_dataset(dataset_name: str, dataset_version: str) -> str | None:
    """扫描所有已有 run 的 data/ 目录，找到同名同版本且预处理完成的数据集。"""
    for run_dir in sorted(Path('runs').iterdir(), reverse=True):  # 最新的优先
        data_dir = run_dir / 'data' / dataset_name
        stats_file = data_dir / 'processed' / 'stats.json'
        if not stats_file.exists():
            continue
        # 检查版本是否一致（从 data_report.json 读取）
        data_report_path = run_dir / 'data_report.json'
        if data_report_path.exists():
            report = json.loads(data_report_path.read_text())
            for ds in report.get('datasets', []):
                if ds['name'] == dataset_name and ds.get('version') == dataset_version and ds['status'] == 'ready':
                    return str(data_dir)  # 返回已处理好的数据目录
    return None

for dataset in datasets:
    existing = find_existing_dataset(dataset['name'], dataset.get('version', ''))
    if existing:
        # 覆用已有数据：创建符号链接或直接复制路径引用
        target = f"runs/{run_id}/data/{dataset['name']}"
        os.makedirs(os.path.dirname(target), exist_ok=True)
        os.symlink(os.path.abspath(existing), target)
        print(f"✅ 复用已有数据：{dataset['name']} ← {existing}")
        dataset['_reused'] = True
        dataset['_reused_from'] = existing
    else:
        dataset['_reused'] = False
```

**复用规则**：
- 同名同版本且已预处理完成（`stats.json` 存在，`status: ready`）才复用
- 不同版本（如 2014 vs 2018）不复用（预处理参数可能不同）
- 复用时跳过 Step 2、4，直接进入验证 Step 5

### Step 3 — 下载数据集（未复用的）

**download_method = "wget"**（覆盖大多数 RecSys 数据集）：

```bash
mkdir -p runs/<run_id>/data/<dataset_name>/raw
wget -q --show-progress \
     -O "runs/<run_id>/data/<dataset_name>/raw/<filename>" \
     "<download_url>"
```

**Amazon 数据集特别说明**：
- Amazon 数据集有多个版本（5-core、原始版）和多个时间版本（2014、2018、2023）
- 从 `paper_analysis.datasets[*].version` 确认版本，下载对应文件
- 格式通常为 JSON gzip：`wget https://jmcauley.ucsd.edu/data/amazon/categoryName_5.json.gz`

```bash
# 解压
gunzip "runs/<run_id>/data/<dataset_name>/raw/<file>.json.gz"
```

**download_method = "manual_request"** 或 `download_url = null`（如 Yelp）：
- 立即暂停，告知用户需要手动下载
- 说明下载步骤（注册/申请），提供官方地址
- 在 `data_report.json` 中记录 `status: "manual_required"`

**黑名单处理**（blacklist 模式）：`knowledge_policy.blacklist_domains` 由 paper-agent 在初始化时已合并好，在每个 HTTP 请求前调用 `is_blocked(url, blacklist_domains)` 检查，违规则跳过并尝试替代来源。

**offline / library 模式**：数据集下载**始终允许**（从 `paper_analysis.datasets[*].download_url` 中的已知 URL 直接下载）；禁止的是为了补充信息而主动搜索（如搜索镜像站、搜索替代下载链接）。

### Step 4 — 执行预处理（未复用的）

**`_reused: true` 的数据集跳过本步。**

**必须严格按照论文描述的预处理步骤执行。** 以下是推荐领域的标准预处理流程：

```python
# preprocessing_script.py — 根据 paper_analysis 动态生成
import pandas as pd
import json
from collections import defaultdict

# ===== Step A: 加载原始数据 =====
# Amazon JSON 格式
records = []
with open("raw/<file>.json") as f:
    for line in f:
        obj = json.loads(line)
        records.append({
            'user_id': obj['reviewerID'],
            'item_id': obj['asin'],
            'rating': obj.get('overall', 1.0),
            'timestamp': obj['unixReviewTime']
        })
df = pd.DataFrame(records)

# ===== Step B: K-core 过滤 =====
# 来自 paper_analysis.datasets[*].preprocessing.filtering
# 默认：5-core（同时对 user 和 item 迭代过滤，直到收敛）
def k_core_filter(df: pd.DataFrame, k: int = 5) -> pd.DataFrame:
    while True:
        n_before = len(df)
        user_counts = df['user_id'].value_counts()
        item_counts = df['item_id'].value_counts()
        df = df[df['user_id'].isin(user_counts[user_counts >= k].index)]
        df = df[df['item_id'].isin(item_counts[item_counts >= k].index)]
        if len(df) == n_before:
            break
    return df.reset_index(drop=True)

df = k_core_filter(df, k=5)  # k 来自 paper_analysis

# ===== Step C: 按时间戳排序 =====
df = df.sort_values(['user_id', 'timestamp']).reset_index(drop=True)

# ===== Step D: 去重（同一 user-item 对保留最早的交互）=====
df = df.drop_duplicates(subset=['user_id', 'item_id'], keep='first')

# ===== Step E: 重新映射 ID（从 1 开始，0 保留给 padding）=====
user2id = {u: i+1 for i, u in enumerate(sorted(df['user_id'].unique()))}
item2id = {v: i+1 for i, v in enumerate(sorted(df['item_id'].unique()))}
df['user_id'] = df['user_id'].map(user2id)
df['item_id'] = df['item_id'].map(item2id)

num_users = df['user_id'].nunique()
num_items = df['item_id'].nunique()

# ===== Step F: 数据集划分 =====
# leave-one-out：最后一个 item 为 test，倒数第二个为 valid，其余为 train
# 来自 paper_analysis.datasets[*].preprocessing.split
train_data, valid_data, test_data = {}, {}, {}
for user_id, group in df.groupby('user_id'):
    items = group['item_id'].tolist()  # 已按时间排好序
    if len(items) < 3:
        continue  # 过滤掉序列过短的用户
    test_data[user_id] = items[-1]
    valid_data[user_id] = items[-2]
    train_data[user_id] = items[:-2]

# ===== Step G: 保存 =====
import pathlib
out = pathlib.Path("processed/")
out.mkdir(parents=True, exist_ok=True)

# train.txt: user_id item1 item2 ... (space separated)
with open(out / "train.txt", "w") as f:
    for uid, items in train_data.items():
        f.write(f"{uid} " + " ".join(map(str, items)) + "\n")

with open(out / "valid.txt", "w") as f:
    for uid, item in valid_data.items():
        f.write(f"{uid} {item}\n")

with open(out / "test.txt", "w") as f:
    for uid, item in test_data.items():
        f.write(f"{uid} {item}\n")

json.dump(user2id, open(out / "user_map.json", "w"))
json.dump(item2id, open(out / "item_map.json", "w"))
json.dump({
    "num_users": num_users,
    "num_items": num_items,
    "num_interactions": len(df),
    "sparsity": 1 - len(df) / (num_users * num_items),
    "avg_seq_len": sum(len(v) for v in train_data.values()) / len(train_data)
}, open(out / "stats.json", "w"), indent=2)
```

### Step 5 — 验证统计量

**`_reused: true` 的数据集也需要执行本步**（确认复用的数据统计量与本次论文的期望相符）。

```python
actual = json.load(open("processed/stats.json"))
paper = paper_analysis['datasets'][i]['stats']

for key in ['num_users', 'num_items', 'num_interactions']:
    if paper.get(key):
        diff_pct = abs(actual[key] - paper[key]) / paper[key]
        status = "✓" if diff_pct < 0.05 else "⚠ WARNING"
        print(f"{status} {key}: actual={actual[key]}, paper={paper[key]}, diff={diff_pct:.1%}")
```

偏差 > 5% 记录警告，偏差 > 20% 停止并告知用户（通常说明数据集版本不对）。

### Step 6 — 写入 data_report.json

```json
{
  "run_id": "...",
  "datasets": [
    {
      "name": "Amazon-Beauty",
      "version": "5-core",
      "status": "ready | failed | manual_required | reused",
      "reused_from": null,              // 复用时记录原始路径
      "local_path": "runs/<run_id>/data/amazon-beauty/",
      "download_url_used": "https://jmcauley.ucsd.edu/data/amazon/...",
      "stats": {
        "paper_values": {"users": 22363, "items": 12101, "interactions": 198502, "avg_seq_len": 8.9},
        "actual_values": {"users": 22363, "items": 12101, "interactions": 198502, "avg_seq_len": 8.9},
        "match": true,
        "warnings": []
      },
      "preprocessing_applied": [
        "5-core filtering (2 iterations until convergence)",
        "sort by timestamp per user",
        "drop duplicate user-item pairs (keep first)",
        "leave-one-out split",
        "remap ids from 1 (0 reserved for padding)"
      ],
      "split_sizes": {
        "train_users": 22363,
        "valid_users": 22363,
        "test_users": 22363
      }
    }
  ],
  "manual_steps": [],
  "all_ready": true,
  "created_at": "ISO8601"
}
```

---

## Hard Rules

- 预处理严格来自 `paper_analysis.datasets.preprocessing`，不自行修改
- K-core 过滤**必须迭代**直到收敛（一次过滤不够）
- ID 映射**必须从 1 开始**（0 保留给 padding token）
- 统计量偏差 > 5% 记录警告，偏差 > 20% 停止告知用户（通常是数据集版本问题）
- 预处理脚本保存到 `preprocessing_script.py`，便于调试
- 任何需要手动操作的数据集，立即停止并告知用户具体的注册/申请步骤
