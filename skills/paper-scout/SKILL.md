---
name: "paper-scout"
description: "Web research agent. Given a model name or paper name, searches arXiv, GitHub, Papers With Code, and author pages to locate the official PDF and reference implementations. Archives all sources. Only used in free/blacklist modes."
---

# Paper Scout — 论文材料定位与归档

参数: $ARGUMENTS

从参数中解析：
- **`name`**：模型名或论文名（主参数）
- **`knowledge_policy`**：包含 `allow_web`（本 skill 只在此为 true 时被调用）和 `blacklist_domains`（已合并好的列表）
- **`run_id`**：当前复现的 run_id

> **本 skill 只在 `allow_web: true` 的模式下被调用**（free / blacklist）。  
> 所有网络请求的目的是**搜索**定位论文和代码，属于知识获取行为，受 `knowledge_policy` 控制。

## 黑名单加载与检查

`blacklist_domains` 由 paper-agent 在初始化时合并好，来源为：
1. `— blacklist:` 内联参数（逗号分隔的域名字符串）
2. `— blacklist-file:` 指定的文件（每行一个域名，`#` 开头为注释，空行忽略）

两者可以同时使用，paper-agent 会在传递 `knowledge_policy` 前将它们合并去重。

```python
def load_blacklist(inline: str | None, filepath: str | None) -> list[str]:
    domains = set()
    if inline:
        domains.update(d.strip() for d in inline.split(",") if d.strip())
    if filepath:
        import pathlib
        for line in pathlib.Path(filepath).read_text().splitlines():
            line = line.split("#")[0].strip()
            if line:
                domains.add(line.lower())
    return sorted(domains)

def is_blocked(url: str, blacklist: list[str]) -> bool:
    from urllib.parse import urlparse
    domain = urlparse(url).netloc.lower()
    return any(domain == b or domain.endswith("." + b) for b in blacklist)
```

在**每次**访问 URL 之前执行 `is_blocked` 检查。若被拦截，记录到 `sources_manifest.json` 的 `blocked` 列表，**不访问**，继续搜索其他来源。

---

## 工作流程

### Step 1：arXiv 搜索

```bash
python3 -c "
import urllib.parse, urllib.request, xml.etree.ElementTree as ET, json
NS = 'http://www.w3.org/2005/Atom'
q = urllib.parse.quote('NAME_PLACEHOLDER')
url = f'http://export.arxiv.org/api/query?search_query=ti:{q}&max_results=5&sortBy=relevance'
with urllib.request.urlopen(url, timeout=30) as r:
    root = ET.fromstring(r.read())
results = []
for e in root.findall(f'{{{NS}}}entry'):
    aid = e.findtext(f'{{{NS}}}id','').split('/abs/')[-1].split('v')[0]
    results.append({'id': aid, 'title': e.findtext(f'{{{NS}}}title','').strip(), 'pdf': f'https://arxiv.org/pdf/{aid}.pdf'})
print(json.dumps(results, indent=2))
"
```

选取最匹配的论文（标题相似度最高）。若 arXiv 在黑名单，跳过此步骤。

### Step 2：下载 PDF

```bash
mkdir -p runs/<run_id>/papers
wget -q -O "runs/<run_id>/papers/<name>.pdf" "https://arxiv.org/pdf/<arxiv_id>.pdf"
```

验证：文件大小 > 100 KB，否则认为下载失败。

### Step 3：GitHub 搜索（找官方实现）

搜索策略（按优先级）：
1. 搜索 `<name> official implementation site:github.com`
2. 搜索 arXiv 论文页面中作者提供的代码链接
3. 搜索 Papers With Code（`paperswithcode.com/paper/<name>`）

筛选标准：
- 优先选 **star 数 > 100** 的 repo
- 优先选 **作者本人的** repo（检查 GitHub username 是否与 arXiv 作者名吻合）
- 若有多个候选，全部记录，选 star 最高的作为主要参考

```bash
# Clone 主要参考 repo（浅克隆，节省时间）
git clone --depth=1 "<repo_url>" "runs/<run_id>/repos/<repo_name>"
```

若 GitHub 在黑名单，跳过此步骤。

### Step 4：补充材料搜索（可选）

搜索以下内容（全部受黑名单过滤）：
- 论文项目主页（`<name> project page`）
- 作者博客或技术报告
- 相关讲解视频/slides（仅记录 URL，不下载）

### Step 5：写入 sources_manifest.json

```json
{
  "run_id": "...",
  "query": "输入的模型名/论文名",
  "scouted_at": "ISO8601",
  "paper_pdf": {
    "arxiv_id": "xxxx.xxxxx",
    "title": "...",
    "url": "https://arxiv.org/pdf/xxxx.xxxxx.pdf",
    "local_path": "runs/<run_id>/papers/<name>.pdf",
    "file_size_kb": 842,
    "fetched_at": "ISO8601"
  },
  "github_repos": [
    {
      "url": "https://github.com/...",
      "stars": 1200,
      "is_official": true,
      "local_path": "runs/<run_id>/repos/<repo_name>/",
      "cloned_at": "ISO8601",
      "reason": "Official implementation by paper author"
    }
  ],
  "supplementary": [
    {"url": "...", "type": "project_page|blog|slides", "note": "..."}
  ],
  "blocked": [
    {"url": "...", "reason": "in blacklist: domain.com"}
  ],
  "search_failed": []
}
```

---

## Hard Rules

- 每次访问 URL **必须先检查黑名单**，无例外
- PDF 必须验证大小 > 100 KB
- 若 arXiv 和 GitHub 都无法访问（黑名单或网络失败），停止并告知用户，不能凭空捏造来源
- `sources_manifest.json` 必须如实记录所有 blocked 的 URL
- 仅下载代码 repo，不运行任何代码
