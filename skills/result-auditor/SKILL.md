---
name: "result-auditor"
description: "Reproduction result auditor specialized in Recommendation Systems. Compares actual results against paper targets, diagnoses gaps from multiple angles with special focus on RecSys-specific pitfalls: ranking type (full vs sampled), evaluation protocol, negative sampling, data preprocessing. Produces audit_report.md."
---

# Result Auditor — 复现结果诊断

参数: $ARGUMENTS

从参数中解析：
- **`run_id`**：当前 run_id

读取（必须存在）：
- `runs/<run_id>/results/metrics.json`
- `runs/<run_id>/impl_plan.json`
- `runs/<run_id>/paper_analysis.json`
- `runs/<run_id>/data_report.json`
- `runs/<run_id>/code/config.yaml`

读取（可选，存在则纳入对比）：
- `runs/<run_id>/official_metrics.json`

输出：`runs/<run_id>/audit_report.md`

---

## 工作流程

### Step 1 — 三方结果对比

首先检查 `official_metrics.json` 是否存在且 `status == "success"`：
- **存在**：展示三方对比（自实现 vs 官方库 vs 论文）
- **不存在 / status=skipped**：展示二方对比（自实现 vs 论文），跳过官方列

```python
import json, yaml

targets = json.load(open('impl_plan.json'))['reproduction_targets']
my_metrics = json.load(open('results/metrics.json'))
cfg = yaml.safe_load(open('code/config.yaml'))

# 读取官方库结果（可选）
try:
    official_data = json.load(open('official_metrics.json'))
    official_metrics = official_data['metrics'] if official_data.get('status') == 'success' else None
except FileNotFoundError:
    official_metrics = None

comparison = []
for t in targets:
    my_val = my_metrics.get(f"{t['dataset']}_{t['metric']}", my_metrics.get(t['metric']))
    off_val = official_metrics.get(f"{t['dataset']}_{t['metric']}") if official_metrics else None
    paper_val = t['paper_value']
    my_gap_pct = (my_val - paper_val) / paper_val * 100
    comparison.append({
        'metric': t['metric'], 'dataset': t['dataset'],
        'paper': paper_val, 'mine': my_val, 'official': off_val,
        'my_gap_pct': my_gap_pct,
        'official_gap_pct': (off_val - paper_val) / paper_val * 100 if off_val else None,
        'table_ref': t.get('table_ref'),
        'my_status': 'MATCH' if abs(my_gap_pct) <= t.get('tolerance', 0.01) * 100 else 'GAP'
    })
```

### Step 2 — 多维度差距诊断

对每个 `status: "GAP"` 的指标，从以下 5 个维度逐一检查：

**维度 A：超参一致性**
```
检查 config.yaml 中每个超参 vs paper_analysis.training_config：
- batch_size: config=256, paper=256 ✓
- lr: config=0.001, paper=0.001 ✓
- dropout: config=0.5, paper=0.5 ✓
- max_seq_len: config=50, paper=50 ✓
- num_layers: config=2, paper=2 ✓
- 有任何 ASSUMED 超参？→ 列出所有 confidence=low 的超参
```

**维度 B：数据预处理一致性**
```
检查 data_report.json 中的统计量对比：
- users: actual=6040, paper=6040 ✓
- items: actual=3706, paper=3706 ✓
- interactions: actual=1000209, paper=1000209 ✓
- preprocessing_applied 是否与 paper_analysis.preprocessing 完全一致？
- 若有 warnings，逐一分析影响
```

**维度 C：评估协议一致性（最关键）**
```
检查 impl_plan.evaluation_protocol vs 实际 evaluate.py 实现：
- ranking_type: impl_plan=full, evaluate.py=full ✓
- test_item_position: last interaction ✓
- candidate_items: all items excluding training ✓
- aggregation: mean over all users ✓
⚠ 注意：full ranking 和 sampled@100 的 HR@10 可能相差 10%+ ⚠
```

**维度 D：模型实现可疑点**
```
检查 impl_plan.critical_details 中所有 impact=critical 的条目：
- detail_001: [描述] → 检查 code/model.py 第 XX 行：[实际实现] → ✓/⚠
- detail_002: [描述] → ...
特别关注 confidence=low 的模块，这些最可能有实现偏差
```

**维度 E：已知复现难点**
```
检查 paper_analysis.implementation_pitfalls：
- pitfall_1: [描述] → 是否已正确处理？
- pitfall_2: [描述] → ...
```

### Step 3 — 生成诊断报告

写入 `runs/<run_id>/audit_report.md`：

```markdown
# 复现结果审计报告

**Run ID**: <run_id>
**审计时间**: ISO8601
**方法**: <method_name>

---

## 结果总览

**有官方库时展示三方对比：**

| 指标 | 数据集 | 论文值 | 自实现 | 官方库 | 自实现差距% | 官方库差距% | 状态 |
|------|--------|--------|--------|--------|------------|------------|------|
| HR@10 | Amazon-Beauty | 0.0712 | 0.0709 | 0.0714 | -0.4% | +0.3% | ✓ MATCH |
| NDCG@10 | Amazon-Beauty | 0.0453 | 0.0441 | 0.0450 | -2.6% | -0.7% | ⚠ GAP |

**无官方库时展示二方对比：**

| 指标 | 数据集 | 论文值 | 自实现 | 差距% | 状态 |
|------|--------|--------|--------|-------|------|
| HR@10 | Amazon-Beauty | 0.0712 | 0.0709 | -0.4% | ✓ MATCH |

**官方库对比解读**：
- 若官方库也与论文有差距：说明数据集/超参/随机性导致，自实现差距可能不是实现问题
- 若官方库接近论文但自实现差距大：差距来自自实现的代码问题，需重点排查

**总体状态**: X/Y 指标达到 ±1% 容差范围内

---

## 差距指标诊断：NDCG@10 on ML-1M

### A. 超参一致性 ✓
所有超参与论文一致。
有 1 个 low-confidence 超参：`warmup_steps=0` (ASSUMED: not mentioned in paper)

### B. 数据预处理一致性 ✓
- 统计量完全匹配（users=6040, items=3706, interactions=1000209）
- 预处理步骤一致（5-core → sort by timestamp → leave-one-out）

### C. 评估协议一致性 ⚠ 需关注
- ranking_type: full ✓
- **潜在问题**: 论文中 NDCG@10 的公式是 discounted cumulative gain，
  需确认是否用了 binary relevance（1个正样本）而非多个
  → 建议检查 evaluate.py 第 XX 行的 NDCG 计算公式

### D. 模型实现可疑点
- critical_detail: "positional embedding: learned, not sinusoidal"
  → code/model.py:45 使用 nn.Embedding(max_seq_len, dim) ✓
- critical_detail: "layer norm before self-attention (pre-norm)"
  → code/model.py:67 LayerNorm 在 attention 之前 ✓
- ASSUMED: num_heads=1（confidence=low）
  → 若论文在某处明确了 num_heads，请检查

### E. 已知实现风险
- implementation_pitfall: "sequence is padded on the LEFT, not right"
  → dataset.py:89: padding 方向为 LEFT ✓

---

## 诊断结论

**最可能的差距原因**（按可能性排序）：
1. NDCG@10 计算实现细节（见维度C）：可能性 40%
2. ASSUMED 超参 warmup_steps 影响：可能性 30%
3. 随机种子导致的训练方差：可能性 20%
4. 其他：10%

**建议的下一步检查（若要改进）**：
1. 对照论文 Appendix A 确认 NDCG 公式
2. 尝试加入 warmup（1000 steps）观察 valid 曲线变化

---

## 信息来源可靠性

| 来源 | 状态 | 影响 |
|------|------|------|
| 论文 PDF | 已读取 | 高 |
| GitHub 参考实现 | 未使用（offline模式）| - |
| 领域知识库 | 未使用 | - |
| ASSUMED 超参数 | 1 个（low confidence）| 中 |
```

---

## Hard Rules

- 审计必须**逐维度**系统检查，不能只说"结果差了一点"
- 对每个 critical 级别的 `critical_detail`，必须找到代码中对应的实现行并验证
- 诊断结论中的"可能性"是定性估计，不是精确值，但必须有依据
- 不对未检查的内容做结论（未检查的写"未验证"）
