# PaperAgent

> 给我一篇推荐系统论文（或模型名），我帮你自动复现它。

**PaperAgent** 是专针推荐系统（Recommendation Systems）领域的 Multi-Agent 论文复现框架，支持 10 个内置 Skill 和 5 种知识来源控制模式。

**领域专为内置**：K-core 过滤、leave-one-out 划分、full/sampled ranking 评估协议、序列/协同过滤/图推荐任务类型识别、Amazon/MovieLens/Yelp 等标准数据集自动处理。

**三方结果对比**：最终报告对比「论文汇报值 vs 官方库复现值 vs 自实现复现值」，帮助定位差距来源。

---

## 安装到你的研究项目

```bash
# 安装到目标项目（创建 symlink + 更新 AGENTS.md）
bash ~/PaperAgent/install.sh ~/my-research-project

# 进入项目，启动 CLI（加 --dangerously-skip-permissions 跳过逐条确认）
cd ~/my-research-project
codex --dangerously-skip-permissions    # 或 claude --dangerously-skip-permissions
```

---

## 5 种复现模式

> `— official-lib:` 在所有模式下均可选。提供后，pipeline 会在自实现跑完之后用官方库跑一遍相同数据集，`audit_report.md` 展示三方对比；不提供则自动降级为论文 vs 自实现的二方对比。

---

### 模式 1：自由探索（推荐，效果最好）

```
/paper-agent "GRU4Rec" \
  — mode: free \
  — official-lib: "https://github.com/hidasib/GRU4Rec" \
  — datasets: "Amazon-Beauty,MovieLens-1M"
```

联网搜索定位 PDF + GitHub，自动归档所有使用的材料来源，完整复现。

**Pipeline**：`paper-scout → paper-reader → design-architect → data-fetcher → code-implementer → env-setup → runner → official-runner → result-auditor`

---

### 模式 2：纯离线（只有模型名，禁止联网）

```
/paper-agent "GRU4Rec" \
  — mode: offline \
  — official-lib: "https://github.com/hidasib/GRU4Rec" \
  — datasets: "Amazon-Beauty"
```

完全使用 AI 已有知识推断实现方案，每个假设标注置信度。`official-lib` 支持 GitHub URL（clone 官方库和下载数据集性质相同，属于「下载已知资源」，所有模式均允许）。

**Pipeline**：`design-architect → data-fetcher → code-implementer → env-setup → runner → official-runner → result-auditor`

---

### 模式 3：给定 PDF + 禁止联网

```
/paper-agent "papers/gru4rec.pdf" \
  — mode: pdf-offline \
  — official-lib: "https://github.com/hidasib/GRU4Rec" \
  — datasets: "Amazon-Beauty,MovieLens-1M"
```

只使用给定 PDF 的内容，不联网搜索信息。`official-lib` 支持 GitHub URL（全流程仅允许数据集下载和 clone 官方库两种网络操作）。

**Pipeline**：`paper-reader → design-architect → data-fetcher → code-implementer → env-setup → runner → official-runner → result-auditor`

---

### 模式 4：黑名单联网

```
# 内联写法（域名少时）
/paper-agent "papers/gru4rec.pdf" \
  — mode: blacklist \
  — blacklist: "github.com/xxx,site.com" \
  — official-lib: "https://github.com/hidasib/GRU4Rec" \
  — datasets: "Amazon-Beauty"

# 文件写法（域名多时推荐，两种可同时使用）
/paper-agent "papers/gru4rec.pdf" \
  — mode: blacklist \
  — blacklist-file: "blacklist.txt" \
  — official-lib: "https://github.com/hidasib/GRU4Rec" \
  — datasets: "Amazon-Beauty,MovieLens-1M"
```

`blacklist.txt` 格式：每行一个域名，`#` 开头为注释：

```
# 不想参考的实现
github.com/competitor/gru4rec
paperswithcode.com
```

所有被拦截的 URL 记录在 `sources_manifest.json` 中。

**Pipeline**：与模式 1 相同，所有 HTTP 请求经过黑名单过滤器

---

### 模式 5：领域知识辅助（禁止联网）

```
/paper-agent "papers/gru4rec.pdf" \
  — mode: library \
  — domain-knowledge: "~/rec-knowledge/domain-knowledge.md" \
  — official-lib: "https://github.com/hidasib/GRU4Rec" \
  — datasets: "Amazon-Beauty,MovieLens-1M"
```

读取用户手写的领域经验 md 文件（已验证配置、已知踩坑、数据集经验），用领域先验辅助实现方案设计，不联网。`official-lib` 同样支持 GitHub URL（clone 官方库属于"下载已知资源"，所有模式均允许）。

`domain-knowledge.md` 示例片段：

```markdown
## SASRec on Amazon-Beauty
- embedding_dim=64, dropout=0.5, max_seq_len=50
- 结果: HR@10=0.0712, NDCG@10=0.0453 (full ranking)
- 必须用 left padding，right padding 掉点约 3%
```

---

## 常用参数速查

| 参数 | 说明 | 示例 |
|------|------|------|
| 主输入 | 论文名 / arXiv ID / PDF 路径 | `"GRU4Rec"` / `"2305.05065"` / `"papers/x.pdf"` |
| `— mode:` | 五种模式之一 | `free` |
| `— official-lib:` | 官方库地址（触发三方对比） | `"https://github.com/..."` |
| `— datasets:` | 只复现指定数据集（逗号分隔，大小写不敏感）| `"Amazon-Beauty,ML-1M"` |
| `— domain-knowledge:` | 领域经验 md 文件（所有模式可选）| `"~/rec-knowledge/domain-knowledge.md"` |
| `— blacklist:` | 屏蔽域名（逗号分隔）| `"github.com/xxx"` |
| `— blacklist-file:` | 屏蔽域名文件 | `"blacklist.txt"` |
| `— run_id:` | 手动指定 run id | `"2025-01-01-gru4rec"` |

---

## 10 个 Skill 设计

| Skill | 层级 | 职责 | 主要产物 |
|-------|------|------|---------|
| `paper-agent` | 路由 | 总 Orchestrator，模式路由 + 状态管理 | `final_report.md` |
| `paper-scout` | 信息获取 | 联网定位 PDF + GitHub，归档所有来源 | `sources_manifest.json` |
| `paper-reader` | 信息获取 | 穷尽论文细节：架构/超参/tricks/ablation | `paper_analysis.json` |
| `knowledge-builder` | 信息获取 | 读取 domain-knowledge.md，编译为结构化领域先验 | `knowledge_base.json` |
| `design-architect` | 方案设计 | 超参决策（标注来源/置信度）+ 15个关键细节清单 | `impl_plan.json` |
| `data-fetcher` | 方案设计 | 数据集下载（跨 run 复用）、严格复刻预处理、验证统计量 | `data_report.json` |
| `code-implementer` | 实现执行 | 逐模块实现 + unit test 验证 shape | `code/` |
| `env-setup` | 实现执行 | 创建 conda 环境（跨 run 复用相同 requirements）、安装依赖 | `env_report.json` |
| `runner` | 实现执行 | 精确复刻 config.yaml 超参运行实验 | `results/` |
| `official-runner` | 实现执行 | 用官方库跑同一数据集（可选，需 `— official-lib:`）| `official_metrics.json` |
| `result-auditor` | 实现执行 | 三方对比（论文/官方库/自实现）+ 5 维度差距诊断 | `audit_report.md` |

---

## 产物结构

每次复现结果在 `runs/<run_id>/` 下，run_id 格式为 `YYYY-MM-DD-<mode>-<name_slug>`（如 `2026-05-25-free-tiger-generative-retrieval`）：

```
runs/2026-05-25-free-tiger-generative-retrieval/
├── input.json              # 模式参数（含 target_datasets、official_lib）
├── status.json             # 当前阶段
├── sources_manifest.json   # 使用的材料来源（模式1/4）
├── knowledge_base.json     # 领域知识库（模式5）
├── paper_analysis.json     # 论文结构化解析
├── impl_plan.json          # 实现方案（超参+模块+关键细节）
├── data_report.json        # 数据集状态和统计验证
├── env_report.json         # conda 环境状态
├── data/                   # 预处理后的数据集（可复用）
├── code/
│   ├── config.yaml         # 全部超参（来自 impl_plan，有来源注释）
│   ├── model.py
│   ├── dataset.py
│   ├── train.py
│   ├── evaluate.py
│   ├── requirements.txt
│   └── tests/              # 模块级 unit tests
├── results/
│   ├── metrics.json        # 自实现结果
│   ├── train.log
│   └── checkpoints/
├── official_metrics.json   # 官方库结果（若提供 — official-lib）
├── official_run.log        # 官方库训练日志
├── audit_report.md         # 三方对比 + 5维度差距诊断
└── final_report.md         # 复现总报告
```

---

## 复用机制

**数据集复用**：跨 run 自动检测同名同版本的已处理数据集，直接 symlink 复用，不重新下载和预处理。

**conda 环境复用**：`requirements.txt` 内容相同的论文共享同一 conda 环境（命名为 `paper-agent-<hash8>`），不重复安装。

---

## 需要人工介入的情况

以下情况 paper-agent 会**暂停并告知你**：

1. **数据集需要手动申请/下载**（如 Yelp，data-fetcher 会说明具体步骤）
2. **论文 PDF 无法获取**（paper-scout 会列出尝试过的所有来源）
3. **OOM 且 batch_size 减半仍不够**（runner 会告知所需显存）
4. **Unit test 失败**（code-implementer 会报告哪个模块的 shape 不对）

---

## 卸载

```bash
bash ~/PaperAgent/install.sh ~/my-research-project --uninstall
```
