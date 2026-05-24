---
name: "env-setup"
description: "Environment setup expert using conda. Creates a conda environment and installs dependencies for a reproduction run. Reuses an existing conda env from another run if the requirements are identical, avoiding redundant installs for the same paper."
---

# Env Setup — 环境搭建（conda）

参数: $ARGUMENTS

从参数中解析 `run_id`。

读取：
- `runs/<run_id>/code/requirements.txt`
- `runs/<run_id>/paper_analysis.json`（获取 Python 版本、框架版本要求）

输出：`runs/<run_id>/env_report.json`

---

## 工作流程

### Step 1 — 确定环境规格

从 `paper_analysis.json` 读取：

```python
python_version = paper_analysis['dependencies'].get('python_version', '3.8')
# 清理版本号：'3.8+' → '3.8', '>=3.9' → '3.9'
python_version = python_version.replace('+', '').replace('>=', '').split(',')[0].strip()

framework = paper_analysis['dependencies'].get('main_framework', 'torch')
# 示例：'torch>=1.7.0' → torch 版本约束
```

conda 环境命名规则：`paper-agent-<req_hash[:8]>`，同 hash 的论文共享同一个环境。

### Step 2 — 检查环境复用

**在创建任何新 conda 环境之前**，检查是否已有可复用的环境：

```python
import hashlib, json, subprocess
from pathlib import Path

def req_hash(req_path: str) -> str:
    """对 requirements.txt 内容排序后求哈希，忽略注释和空行。"""
    lines = []
    for line in Path(req_path).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            lines.append(line.lower())
    return hashlib.md5('\n'.join(sorted(lines)).encode()).hexdigest()

my_hash = req_hash(f"runs/{run_id}/code/requirements.txt")
env_name = f"paper-agent-{my_hash[:8]}"

# 检查 conda 中是否已有此环境
result = subprocess.run(['conda', 'env', 'list', '--json'], capture_output=True, text=True)
existing_envs = json.loads(result.stdout).get('envs', [])
env_exists = any(e.endswith(env_name) for e in existing_envs)
```

**若环境已存在**（`env_name` 在 `conda env list` 中）：
- 跳过 Step 3-4，直接进入 Step 5 验证
- 在 `env_report.json` 中记录 `conda_env_reused: true`

**若不存在**：继续 Step 3。

### Step 3 — 创建 conda 环境

```bash
conda create -n paper-agent-<hash8> python=<python_version> -y
```

**若论文依赖 GPU（`paper_analysis.dependencies.gpu_required: true`）**，同时安装 CUDA toolkit：

```bash
# 从 requirements.txt 中提取 torch 版本，选对应的 CUDA 版本
# torch 2.0.x → cudatoolkit 11.7/11.8
# torch 1.x   → cudatoolkit 11.3

conda install -n paper-agent-<hash8> \
    pytorch=<torch_version> \
    cudatoolkit=<cuda_version> \
    -c pytorch -c nvidia -y
```

若 requirements.txt 中已有 torch 的具体 pip wheel（如 `torch==2.0.1+cu118`），则跳过 conda 安装 torch，留给 Step 4 pip 安装。

### Step 4 — 安装 pip 依赖

```bash
conda run -n paper-agent-<hash8> pip install --upgrade pip
conda run -n paper-agent-<hash8> pip install -r runs/<run_id>/code/requirements.txt
```

若安装失败，按顺序尝试：
1. 降级到上一个兼容版本
2. 单独安装冲突包，其他包正常继续
3. 记录失败信息到 `env_report.json`，不阻塞后续流程

**特殊库处理**（推荐系统常见）：

```bash
# torch_geometric（需与 torch/CUDA 版本严格匹配）
conda run -n paper-agent-<hash8> pip install \
    torch_geometric \
    pyg_lib torch_scatter torch_sparse torch_cluster torch_spline_conv \
    -f https://data.pyg.org/whl/torch-<torch_ver>+cu<cuda_ver>.html

# DGL（图神经网络库）
conda run -n paper-agent-<hash8> pip install dgl -f https://data.dgl.ai/wheels/cu<cuda_ver>/repo.html
```

### Step 5 — 验证环境

```bash
# 基础验证
conda run -n paper-agent-<hash8> python -c \
    "import torch; print('torch:', torch.__version__); print('cuda:', torch.cuda.is_available())"

# 语法检查代码文件
conda run -n paper-agent-<hash8> python -m py_compile \
    runs/<run_id>/code/model.py \
    runs/<run_id>/code/dataset.py \
    runs/<run_id>/code/train.py \
    runs/<run_id>/code/evaluate.py
```

若 CUDA 不可用，记录到报告但不阻止继续。

### Step 6 — 写入 env_report.json

```json
{
  "run_id": "...",
  "conda_env_name": "paper-agent-d41d8cd9",
  "conda_env_reused": false,
  "req_hash": "d41d8cd98f00b204e9800998ecf8427e",
  "python_version": "3.10.12",
  "cuda_version": "11.8",
  "installed_packages": ["torch==2.0.0", "numpy==1.24.0"],
  "cuda_available": true,
  "syntax_check": "passed",
  "activate_cmd": "conda activate paper-agent-d41d8cd9",
  "manual_steps": [],
  "all_ready": true,
  "created_at": "ISO8601"
}
```

`runner` 使用 `conda run -n <conda_env_name> python ...` 执行训练脚本，或读取 `activate_cmd` 激活环境后运行。

---

## Hard Rules

- 环境名格式固定为 `paper-agent-<req_hash[:8]>`，同一 requirements 的论文**共享同一环境**
- 复用条件：`req_hash` 完全一致（等价于 requirements.txt 内容相同）且该环境 `all_ready: true`
- torch + CUDA 版本组合必须从 `paper_analysis.dependencies` 推断，不使用 conda 默认版本
- 若 CUDA 不可用，记录但不阻止继续
- `official-runner` 使用独立的 conda 环境（`paper-agent-official-<run_id[:8]>`），不与自实现环境冲突
