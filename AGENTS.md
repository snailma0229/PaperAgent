# PaperAgent — Recommendation Systems Paper Reproduction

> For AI agents. See README.md for human docs.

PaperAgent is a 10-skill multi-agent system specialized in **Recommendation Systems** paper reproduction. It handles RecSys-specific concerns: K-core filtering, leave-one-out splits, full/sampled ranking evaluation, sequential/CF/graph task types, and standard RecSys datasets (Amazon, MovieLens, Yelp, etc.).

---

## How to Invoke

```
/skill-name "arguments" — key: value
```

---

## 5 Reproduction Modes

### Mode 1: Free Exploration (Recommended for best results)
```
/paper-agent "GRU4Rec" — mode: free
```
Pipeline: paper-scout → paper-reader → design-architect → data-fetcher → code-implementer → env-setup → runner → official-runner → result-auditor

### Mode 2: Offline (Model/paper name only, no web access)
```
/paper-agent "GRU4Rec" — mode: offline
```
Pipeline: design-architect → data-fetcher → code-implementer → env-setup → runner → official-runner → result-auditor

### Mode 3: PDF + Offline (Given PDF, no web access)
```
/paper-agent "papers/gru4rec.pdf" — mode: pdf-offline
```
Pipeline: paper-reader → design-architect → data-fetcher → code-implementer → env-setup → runner → official-runner → result-auditor

### Mode 4: Blacklist Web (Given PDF, web allowed except blacklisted domains)
```
# 内联写法（域名少时）
/paper-agent "papers/gru4rec.pdf" — mode: blacklist — blacklist: "github.com/some/repo,paperwithcode.com"

# 文件写法（域名多时推荐）
/paper-agent "papers/gru4rec.pdf" — mode: blacklist — blacklist-file: "blacklist.txt"

# 两者可以同时用（会合并去重）
/paper-agent "papers/gru4rec.pdf" — mode: blacklist — blacklist: "extra.com" — blacklist-file: "blacklist.txt"
```
Pipeline: paper-scout (filtered) → paper-reader → design-architect → data-fetcher (filtered) → code-implementer → env-setup → runner → official-runner → result-auditor

### Mode 5: Library-Assisted (Local knowledge library, no web access)
```
/paper-agent "GRU4Rec" — mode: library — library: "~/research-library/"
```
Pipeline: knowledge-builder → design-architect → data-fetcher → code-implementer → env-setup → runner → official-runner → result-auditor

---

## Individual Skill Reference

| Skill | Invoke | What it does | Produces |
|-------|--------|-------------|---------|
| `paper-agent` | `/paper-agent "input" — mode: <mode>` | Routes to the correct pipeline based on mode | `status.json`, `final_report.md` |
| `paper-scout` | `/paper-scout "model name"` | Finds PDF + GitHub repo, archives all sources | `sources_manifest.json` |
| `paper-reader` | `/paper-reader "pdf or arxiv"` | Exhaustive paper analysis incl. tricks, ablation | `paper_analysis.json` |
| `knowledge-builder` | `/knowledge-builder "domain_knowledge.md"` | Reads user's domain experience md, compiles into structured knowledge | `knowledge_base.json` |
| `design-architect` | `/design-architect` | Designs impl plan: modules, hyperparams w/ source, critical details | `impl_plan.json` |
| `data-fetcher` | `/data-fetcher` | Downloads datasets, applies exact preprocessing, validates stats | `data_report.json`, `data/` |
| `code-implementer` | `/code-implementer` | Implements model/train/eval with unit tests | `code/` |
| `env-setup` | `/env-setup` | Creates venv, installs deps | `env_report.json` |
| `runner` | `/runner` | Trains and evaluates using config.yaml hyperparams | `results/` |
| `official-runner` | `/official-runner` | Runs official library on same data with same hyperparams (optional) | `official_metrics.json` |
| `result-auditor` | `/result-auditor` | 3-way comparison: self-impl vs official-lib vs paper; gap diagnosis | `audit_report.md` |

---

## Common Parameters

```
— mode: free | offline | pdf-offline | blacklist | library
— run_id: YYYY-MM-DD-<name>          # optional, auto-generated if omitted
— blacklist: "domain1,domain2"       # only for blacklist mode
— library: "path/to/library"         # only for library mode
— official-lib: "github.com/.."      # optional for all modes; triggers official-runner
— domain-knowledge: "path/to.md"    # optional; feeds knowledge-builder in any mode
— datasets: "Amazon-Beauty,ML-1M"   # optional; only reproduce specified datasets (case-insensitive)
```

---

## Artifact Contracts

All skills communicate through files under `runs/<run_id>/`:

| Artifact | Produced by | Consumed by |
|----------|------------|-------------|
| `input.json` | paper-agent | all |
| `sources_manifest.json` | paper-scout | paper-reader, design-architect |
| `knowledge_base.json` | knowledge-builder | design-architect, code-implementer |
| `paper_analysis.json` | paper-reader | design-architect, data-fetcher |
| `impl_plan.json` | design-architect | code-implementer, runner, result-auditor |
| `data_report.json` | data-fetcher | env-setup, runner, result-auditor |
| `code/` | code-implementer | env-setup, runner |
| `env_report.json` | env-setup | runner |
| `results/` | runner | result-auditor, paper-agent |
| `official_metrics.json` | official-runner (optional) | result-auditor |
| `audit_report.md` | result-auditor | paper-agent |
| `final_report.md` | paper-agent | user |

---

## Source of Truth

Each skill's full specification: `skills/<name>/SKILL.md`
This file is a routing index only.