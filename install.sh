#!/usr/bin/env bash
# install.sh — Install PaperAgent skills into any project via symlinks.
#
# Usage:
#   bash /path/to/PaperAgent/install.sh [project_path] [options]
#
# Options:
#   --uninstall    remove managed symlinks and AGENTS.md block
#   --dry-run      show what would be done without making changes
#
# Examples:
#   bash ~/PaperAgent/install.sh .                  # install into current dir
#   bash ~/PaperAgent/install.sh ~/my-research      # install into another project
#   bash ~/PaperAgent/install.sh . --uninstall      # uninstall

set -euo pipefail

PAPER_AGENT_REPO="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$PAPER_AGENT_REPO/skills"
BLOCK_BEGIN="<!-- PAPER-AGENT:BEGIN -->"
BLOCK_END="<!-- PAPER-AGENT:END -->"
MANIFEST=".paper-agent-installed-skills.txt"

PROJECT_PATH="${1:-$(pwd)}"
ACTION="install"
DRY_RUN=false

for arg in "${@:2}"; do
    case "$arg" in
        --uninstall) ACTION="uninstall" ;;
        --dry-run)   DRY_RUN=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

[[ -d "$PROJECT_PATH" ]] || { echo "error: project path not found: $PROJECT_PATH" >&2; exit 1; }
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
TARGET_SKILLS_DIR="$PROJECT_PATH/.agents/skills"
AGENTS_MD="$PROJECT_PATH/AGENTS.md"

run() { $DRY_RUN && echo "[dry-run] $*" || "$@"; }

# ---------- uninstall ----------
if [[ "$ACTION" == "uninstall" ]]; then
    echo "Uninstalling PaperAgent skills from: $PROJECT_PATH"
    if [[ -f "$PROJECT_PATH/$MANIFEST" ]]; then
        while IFS= read -r name; do
            link="$TARGET_SKILLS_DIR/$name"
            if [[ -L "$link" ]]; then
                run rm "$link"
                echo "  removed symlink: .agents/skills/$name"
            fi
        done < "$PROJECT_PATH/$MANIFEST"
        run rm "$PROJECT_PATH/$MANIFEST"
    fi
    # Remove managed block from AGENTS.md
    if [[ -f "$AGENTS_MD" ]] && grep -q "$BLOCK_BEGIN" "$AGENTS_MD"; then
        run python3 - "$AGENTS_MD" "$BLOCK_BEGIN" "$BLOCK_END" <<'PYEOF'
import sys, pathlib
path, begin, end = sys.argv[1], sys.argv[2], sys.argv[3]
lines = pathlib.Path(path).read_text().splitlines(keepends=True)
out, skip = [], False
for l in lines:
    if begin in l: skip = True
    if not skip: out.append(l)
    if end in l: skip = False
pathlib.Path(path).write_text("".join(out))
PYEOF
        echo "  removed AGENTS.md block"
    fi
    echo "Done."
    exit 0
fi

# ---------- install ----------
echo "Installing PaperAgent skills into: $PROJECT_PATH"
echo "  Skills source: $SKILLS_DIR"
echo ""

run mkdir -p "$TARGET_SKILLS_DIR"

INSTALLED=()
for skill_dir in "$SKILLS_DIR"/*/; do
    name="$(basename "$skill_dir")"
    [[ -f "$skill_dir/SKILL.md" ]] || continue
    link="$TARGET_SKILLS_DIR/$name"
    if [[ -L "$link" ]]; then
        run rm "$link"
    elif [[ -e "$link" ]]; then
        echo "  warning: $link exists and is not a symlink, skipping $name" >&2
        continue
    fi
    run ln -s "$skill_dir" "$link"
    echo "  linked: .agents/skills/$name -> $skill_dir"
    INSTALLED+=("$name")
done

# Write manifest
if ! $DRY_RUN; then
    printf "%s\n" "${INSTALLED[@]}" > "$PROJECT_PATH/$MANIFEST"
fi

# Inject/update AGENTS.md block
BLOCK_CONTENT="$BLOCK_BEGIN
## PaperAgent Skills

> Installed from: $PAPER_AGENT_REPO
> Skills directory: .agents/skills/

| Skill | Invoke | What it does |
|-------|--------|-------------|
| paper-agent | \`/paper-agent \"paper\"\` | Full reproduction pipeline (end-to-end) |
| paper-reader | \`/paper-reader \"pdf or arxiv\"\` | Extract method, arch, datasets → paper_analysis.json |
| code-implementer | \`/code-implementer\` | Implement model, train, eval code from paper_analysis.json |
| env-setup | \`/env-setup\` | Create venv, install deps, download datasets |
| runner | \`/runner\` | Run training + evaluation, save results |

### Common Parameters
\`\`\`
— run_id: YYYY-MM-DD-<paper-name>    # identifies this reproduction run
\`\`\`

### Artifact Contracts
Skills communicate through \`runs/<run_id>/\`:
- \`paper_analysis.json\` — paper-reader → code-implementer, env-setup, runner
- \`code/\` — code-implementer → env-setup, runner
- \`env_report.json\` — env-setup → runner
- \`results/\` — runner → paper-agent
- \`final_report.md\` — paper-agent → user

### Source of Truth
Each skill's full spec: \`.agents/skills/<name>/SKILL.md\`
$BLOCK_END"

if [[ -f "$AGENTS_MD" ]] && grep -q "$BLOCK_BEGIN" "$AGENTS_MD"; then
    # Replace existing block
    if ! $DRY_RUN; then
        python3 - "$AGENTS_MD" "$BLOCK_BEGIN" "$BLOCK_END" "$BLOCK_CONTENT" <<'PYEOF'
import sys, pathlib
path, begin, end, new_block = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
lines = pathlib.Path(path).read_text().splitlines(keepends=True)
out, skip = [], False
for l in lines:
    if begin in l: skip = True; out.append(new_block + "\n"); continue
    if end in l: skip = False; continue
    if not skip: out.append(l)
pathlib.Path(path).write_text("".join(out))
PYEOF
    fi
    echo "  updated: AGENTS.md (replaced existing block)"
else
    # Append block
    if ! $DRY_RUN; then
        printf "\n%s\n" "$BLOCK_CONTENT" >> "$AGENTS_MD"
    fi
    echo "  updated: AGENTS.md (appended block)"
fi

echo ""
echo "Done. Installed ${#INSTALLED[@]} skills: ${INSTALLED[*]}"
echo ""
echo "To use in any project:"
echo "  cd your-project && codex     # then: /paper-agent \"arxiv-link\""
echo "  cd your-project && claude    # then: /paper-agent \"arxiv-link\""
echo ""
echo "To uninstall:"
echo "  bash $PAPER_AGENT_REPO/install.sh $PROJECT_PATH --uninstall"
