---
name: "paper-agent"
description: "Multi-mode paper reproduction orchestrator. Supports 5 modes: free exploration, offline, pdf-offline, blacklist-web, library-assisted. Use when user says 'reproduce this paper', 'run this paper', or provides a model name / arXiv link / PDF path."
---

# Paper Agent — 论文复现总指挥

参数: $ARGUMENTS

## knowledge_policy 语义说明

**`allow_web` 控制的是「信息搜索」，不是「网络连接」**：

| 操作 | offline/library 模式 | free/blacklist 模式 |
|------|---------------------|--------------------|
| 搜索论文 PDF（arXiv/Google Scholar）| ❌ 禁止 | ✅ 允许（blacklist 检查后）|
| 搜索 GitHub 参考实现 | ❌ 禁止 | ✅ 允许（blacklist 检查后）|
| 搜索技术博客/文档补充知识 | ❌ 禁止 | ✅ 允许（blacklist 检查后）|
| **从已知 URL 下载数据集** | ✅ **始终允许** | ✅ 允许（blacklist 检查后）|
| **访问 arXiv/HuggingFace 下载数据** | ✅ **始终允许** | ✅ 允许（blacklist 检查后）|

> 简单理解：`allow_web: false` = 不能主动去「搜」，但可以「下载」已知地址的资源（数据集、official-lib）。全流程中仅允许两种网络操作：**下载数据集**和 **clone 官方库**。

---

## 参数解析

从 `$ARGUMENTS` 中解析：
- **主输入**：模型名 / arXiv 链接 / arXiv ID / PDF 路径
- **`— mode:`** `free` | `offline` | `pdf-offline` | `blacklist` | `library`（默认 `free`）
- **`— blacklist:`** 逗号分隔的禁止域名，如 `"github.com/xxx,site.com"`（仅 `blacklist` 模式，域名少时用）
- **`— blacklist-file:`** 黑名单文件路径，每行一个域名（域名多时推荐用此方式）
- **`— library:`** 自学习库路径（仅 `library` 模式）
- **`— official-lib:`** 官方库 GitHub 链接或本地路径（所有模式均可选）；若提供，实验结束后额外用官方库跑一次，最终对比三方结果（自实现 vs 官方库 vs 论文）
- **`— domain-knowledge:`** 领域经验 `.md` 文件路径（可选，会传给 knowledge-builder / design-architect 作为先验）
- **`— datasets:`** 指定只复现哪些数据集，逗号分隔，如 `"Amazon-Beauty,MovieLens-1M"`（可选；不填则复现论文全部数据集）
- **`— run_id:`** 手动指定 run_id（可选）

## 初始化

### run_id 生成规则

run_id 格式：**`YYYY-MM-DD-<mode>-<name_slug>`**

```
模式 1 free：        2026-05-25-free-tiger-generative-retrieval
模式 2 offline：     2026-05-25-offline-tiger-generative-retrieval
模式 3 pdf-offline： 2026-05-25-pdf-offline-tiger-generative-retrieval
模式 4 blacklist：   2026-05-25-blacklist-tiger-generative-retrieval
模式 5 library：     2026-05-25-library-tiger-generative-retrieval
```

`<name_slug>` 规则：
- 论文名/模型名转小写，空格和特殊字符替换为 `-`，并排除连续的 `-`
- arXiv ID（如 `2305.05065`）直接用 arxiv-id：`2026-05-25-free-arxiv-2305-05065`
- PDF 路径（如 `papers/gru4rec.pdf`）取文件名：`2026-05-25-pdf-offline-gru4rec`
- 若用户通过 `— run_id:` 手动指定，直接使用用户指定的字符串

**run_id 必须在初始化阶段第一步就确定，不得在后续 skill（如 paper-scout）执行后再修改。**

### 初始化步骤

1. 解析所有参数，**即刻**生成 `run_id`
2. 创建 `runs/<run_id>/` 目录
3. 写入 `runs/<run_id>/input.json`：

```json
{
  "run_id": "...",
  "input": "原始输入",
  "mode": "free|offline|pdf-offline|blacklist|library",
  "knowledge_policy": {
    "allow_web": true,
    "blacklist_domains": [],   // 合并自 —blacklist 和 —blacklist-file
    "blacklist_file": null,    // 原始文件路径（供审计用）
    "library_path": null
  },
  "official_lib": null,          // — official-lib 参数
  "domain_knowledge_file": null, // — domain-knowledge 参数
  "target_datasets": null,       // — datasets 参数，如 ["Amazon-Beauty", "MovieLens-1M"]；null 表示全部
  "started_at": "ISO8601"
}
```

4. 写入 `runs/<run_id>/status.json`（初始 phase: `"init"`）

> **关键约束**：run_id 一旦在初始化时确定，后续任何 skill 均不得修改。paper-scout 等 skill 即使找到了更精确的论文名，也只在 `paper_analysis.json` 中记录，不改变 run_id。

---

## 五种模式 Pipeline

### 模式 1：free（自由探索）

适用于：只有模型名/paper 名，允许联网搜索

```
[paper-scout]     联网定位 PDF + GitHub，归档 sources_manifest.json
     ↓
[paper-reader]    深度解析论文 PDF
     ↓
[design-architect] 综合论文 + GitHub 代码，设计实现方案
     ↓
[data-fetcher]    下载数据集，验证统计量
     ↓
[code-implementer] 按 impl_plan 逐模块实现代码
     ↓
[env-setup]       创建 venv，安装依赖
     ↓
[runner]          精确复刻超参，运行实验（自实现）
     ↓
[official-runner] 用官方库跑同一数据集（若提供 — official-lib）
     ↓
[result-auditor]  三方对比：自实现 vs 官方库 vs 论文
```

**knowledge_policy**：`allow_web: true, blacklist_domains: []`

---

### 模式 2：offline（纯离线，仅凭名字）

适用于：只有模型名，**完全禁止联网**，使用 AI 已有知识重建方案

```
[design-architect] 仅用 AI 已有知识推断论文方案（每个假设标注置信度）
     ↓
[data-fetcher]    仅用已知的公开数据集 URL 下载，不搜索
     ↓
[code-implementer]
     ↓
[env-setup]
     ↓
[runner]
     ↓
[official-runner] 用官方库跑同一数据集（若提供 — official-lib）
     ↓
[result-auditor]  三方对比：自实现 vs 官方库 vs 论文
```

**knowledge_policy**：`allow_web: false`  
**注意**：design-architect 必须在 `impl_plan.json` 中标注每个细节的置信度，低置信度的假设用 `# ASSUMED` 注释

---

### 模式 3：pdf-offline（给定 PDF + 离线）

适用于：有论文 PDF，**完全禁止联网**

```
[paper-reader]    深度解析给定 PDF
     ↓
[design-architect] 综合 paper_analysis，无搜索补充
     ↓
[data-fetcher]    只用 paper_analysis 中的 download_url，不搜索补充
     ↓
[code-implementer]
     ↓
[env-setup]
     ↓
[runner]
     ↓
[official-runner] 用官方库跑同一数据集（若提供 — official-lib）
     ↓
[result-auditor]  三方对比：自实现 vs 官方库 vs 论文
```

**knowledge_policy**：`allow_web: false`

---

### 模式 4：blacklist（黑名单联网）

适用于：有论文 PDF，允许联网但需排除指定域名

```
[paper-scout]     联网搜索，但跳过黑名单域名，归档 sources_manifest
     ↓
[paper-reader]    深度解析论文
     ↓
[design-architect]
     ↓
[data-fetcher]    联网下载，跳过黑名单
     ↓
[code-implementer]
     ↓
[env-setup]
     ↓
[runner]
     ↓
[official-runner] 用官方库跑同一数据集（若提供 — official-lib）
     ↓
[result-auditor]  三方对比：自实现 vs 官方库 vs 论文
```

**knowledge_policy**：`allow_web: true, blacklist_domains: ["domain1.com", "domain2.com"]`  
**注意**：paper-scout 和 data-fetcher 在每次访问 URL 前必须检查是否在黑名单，违规则跳过并在 `sources_manifest.json` 中记录为 `"blocked"`

---

### 模式 5：library（自学习库辅助）

适用于：有领域知识库（本地 PDFs + 代码），**完全禁止联网**

```
[knowledge-builder] 读取 domain-knowledge.md，构建 knowledge_base.json
     ↓
[design-architect]  综合 knowledge_base + AI 已有知识（无联网）
     ↓
[data-fetcher]
     ↓
[code-implementer]  可参考 knowledge_base 中的实现模式和配置经验
     ↓
[env-setup]
     ↓
[runner]
     ↓
[official-runner] 用官方库跑同一数据集（若提供 — official-lib）
     ↓
[result-auditor]  三方对比：自实现 vs 官方库 vs 论文
```

**knowledge_policy**：`allow_web: false, library_path: "<path>"`

---

## 阶段推进规则

每个 skill 调用结束后：
1. 验证对应产物文件存在且非空
2. 更新 `status.json` 的 `phase` 和 `completed_phases`
3. 若产物缺失，记录 `error` 并**立即停止**，告知用户

产物验证清单：

| 阶段 | 必须存在的产物 |
|------|--------------|
| paper-scout | `sources_manifest.json` |
| knowledge-builder | `knowledge_base.json` |
| paper-reader | `paper_analysis.json` |
| design-architect | `impl_plan.json` |
| data-fetcher | `data_report.json`，`data/` 非空 |
| code-implementer | `code/model.py`，`code/train.py`，`code/config.yaml` |
| env-setup | `env_report.json`，`env_report.all_ready == true` |
| runner | `results/metrics.json` |
| result-auditor | `audit_report.md` |

---

## Phase 5：生成最终报告

所有阶段完成后，亲自生成 `runs/<run_id>/final_report.md`：

```markdown
# 复现报告：<论文标题>

## 基本信息
- 模式: <mode>
- run_id: <run_id>
- 论文: <title>, <authors>, <year>

## 信息来源（模式1/4）
- 来源清单见 sources_manifest.json

## 实现方案摘要
- 核心架构（来自 impl_plan.modules）
- 关键实现细节（来自 impl_plan.critical_details 前5条）

## 实验结果

| 指标 | 论文原始 | 本次复现 | 差距 |
|------|---------|---------|------|
| ...  | ...     | ...     | ...  |

## 差距诊断
（来自 audit_report.md 摘要）

## 文件结构
- 代码: runs/<run_id>/code/
- 数据: runs/<run_id>/data/
- 结果: runs/<run_id>/results/
- 完整诊断: runs/<run_id>/audit_report.md
```

---

## Hard Rules

- 每个阶段前更新 `status.json`，完成后验证产物
- 遇到需要人工介入（付费数据集、网络访问失败），可以跳过，但是一定要存档并告知用户
- 严格遵守 `knowledge_policy`：offline/library 模式禁止**主动搜索**论文/代码/资料，但数据集下载（从已知 URL）始终允许；blacklist 模式所有 HTTP 请求（包括数据集下载）必须经过黑名单检查
- final_report.md 必须如实反映实验结果，包括失败和差异
