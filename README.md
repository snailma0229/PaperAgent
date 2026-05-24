# PaperAgent

> 给我一篇推荐系统论文（或模型名），我帮你自动复现它。

**PaperAgent** 是专针推荐系统（Recommendation Systems）领域的 Multi-Agent 论文复现框架，支持 10 个内置 Skill 和 5 种知识来源控制模式。

**领域专为内置**：K-core 过滤、leave-one-out 划分、full/sampled ranking 评估协议、序列/协同过滤/图推荐任务类型识别、Amazon/MovieLens/Yelp 等标准数据集自动处理。

---

## 安装到你的研究项目

```bash
# 安装到目标项目（创建 symlink + 更新 AGENTS.md）
bash ~/PaperAgent/install.sh ~/my-research-project

# 进入项目，启动 CLI
cd ~/my-research-project
codex    # 或 claude / mfcli
```

---

## 5 种复现模式

### 模式 1：自由探索（推荐，效果最好）

```
/paper-agent "GRU4Rec" — mode: free
```

联网搜索定位 PDF + GitHub，自动归档所有使用的材料来源，完整复现。

**Pipeline**：`paper-scout → paper-reader → design-architect → data-fetcher → code-implementer → env-setup → runner → result-auditor`

---

### 模式 2：纯离线（只有模型名，禁止联网）

```
/paper-agent "GRU4Rec" — mode: offline
```

完全使用 AI 已有知识推断实现方案，每个假设标注置信度。

**Pipeline**：`design-architect → data-fetcher → code-implementer → env-setup → runner → result-auditor`

---

### 模式 3：给定 PDF + 禁止联网

```
/paper-agent "papers/gru4rec.pdf" — mode: pdf-offline
```

只使用给定 PDF 的内容，不联网补充信息。

**Pipeline**：`paper-reader → design-architect → data-fetcher → code-implementer → env-setup → runner → result-auditor`

---

### 模式 4：黑名单联网

```
# 内联写法（域名少时）
/paper-agent "papers/gru4rec.pdf" — mode: blacklist — blacklist: "github.com/xxx,site.com"

# 文件写法（域名多时推荐）
/paper-agent "papers/gru4rec.pdf" — mode: blacklist — blacklist-file: "blacklist.txt"
```

blacklist.txt 格式：每行一个域名，`#` 开头为注释：

```
# 竞争对手的实现
github.com/competitor/gru4rec
# 不可信的评测站
paperwithcode.com
some-leaderboard.ai
```

两种写法可以同时使用，会自动合并去重。所有被拦截的 URL 记录在 `sources_manifest.json` 中。

**Pipeline**：与模式 1 相同，所有 HTTP 请求经过黑名单过滤器

---

### 模式 5：自学习库辅助（禁止联网）

```
/paper-agent "GRU4Rec" — mode: library — library: "~/research-library/"
```

消化本地知识库（PDFs + 代码）后，用领域先验知识辅助实现，不联网。

**Pipeline**：`knowledge-builder → design-architect → data-fetcher → code-implementer → env-setup → runner → result-auditor`

---

## 10 个 Skill 设计

| Skill | 层级 | 职责 | 主要产物 |
|-------|------|------|---------|
| `paper-agent` | 路由 | 总 Orchestrator，模式路由 + 状态管理 | `final_report.md` |
| `paper-scout` | 信息获取 | 联网定位 PDF + GitHub，归档所有来源 | `sources_manifest.json` |
| `paper-reader` | 信息获取 | 穷尽论文细节：架构/超参/tricks/ablation | `paper_analysis.json` |
| `knowledge-builder` | 信息获取 | 消化本地库，构建领域先验知识图谱 | `knowledge_base.json` |
| `design-architect` | 方案设计 | 超参决策（标注来源/置信度）+ 20个关键细节清单 | `impl_plan.json` |
| `data-fetcher` | 方案设计 | 数据集下载、严格复刻预处理、验证统计量 | `data_report.json` |
| `code-implementer` | 实现执行 | 逐模块实现 + unit test 验证 shape | `code/` |
| `env-setup` | 实现执行 | 创建 venv，安装依赖 | `env_report.json` |
| `runner` | 实现执行 | 精确复刻 config.yaml 超参运行实验 | `results/` |
| `result-auditor` | 实现执行 | 5 维度差距诊断（超参/数据/评估协议/代码/风险） | `audit_report.md` |

---

## 产物结构

每次复现结果在 `runs/<run_id>/` 下：

```
runs/YYYY-MM-DD-<name>/
├── input.json              # 模式参数
├── status.json             # 当前阶段
├── sources_manifest.json   # 使用的材料来源（模式1/4）
├── knowledge_base.json     # 领域知识库（模式5）
├── paper_analysis.json     # 论文结构化解析
├── impl_plan.json          # 实现方案（超参+模块+关键细节）
├── data_report.json        # 数据集状态和统计验证
├── env_report.json         # 环境状态
├── data/                   # 预处理后的数据集
├── venv/                   # Python 虚拟环境（隔离）
├── code/
│   ├── config.yaml         # 全部超参（来自 impl_plan，有来源注释）
│   ├── model.py
│   ├── dataset.py
│   ├── train.py
│   ├── evaluate.py
│   ├── requirements.txt
│   └── tests/              # 模块级 unit tests
├── results/
│   ├── metrics.json
│   ├── comparison.md
│   ├── train.log           # 完整训练日志
│   └── checkpoints/
├── audit_report.md         # 5维度结果差距诊断
└── final_report.md         # 复现总报告
```

---

## 需要人工介入的情况

以下情况 paper-agent 会**暂停并告知你**：

1. **数据集需要手动申请/下载**（data-fetcher 会说明具体步骤）
2. **论文 PDF 无法获取**（paper-scout 会列出尝试过的所有来源）
3. **OOM 且 batch_size 减半仍不够**（runner 会告知所需显存）
4. **Unit test 失败**（code-implementer 会报告哪个模块的 shape 不对）

---

## 卸载

```bash
bash ~/PaperAgent/install.sh ~/my-research-project --uninstall
```
