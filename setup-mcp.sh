#!/usr/bin/env bash
#
# setup-mcp.sh — Install and configure MCP servers for the Relaxed Concurrent
# Counting Bloom Filter research project.
#
# Usage:
#   ./setup-mcp.sh                        # Full install + config
#   ./setup-mcp.sh --skip-install         # Config only
#   GITHUB_TOKEN=ghp_xxx ./setup-mcp.sh   # With GitHub token
#
# Servers configured:
#   papersflow-mcp, mcp-dblp, mcp-simple-arxiv, OneCite, arxiv-latex-mcp,
#   latex-mcp-server, github-mcp-server, mcp-fetch, mcp-sequentialthinking

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; GRAY='\033[0;90m'; NC='\033[0m'

step()  { printf "\n${CYAN}>> %s${NC}\n" "$1"; }
ok()    { printf "   ${GREEN}[OK]${NC} %s\n" "$1"; }
skip()  { printf "   ${YELLOW}[SKIP]${NC} %s\n" "$1"; }
err()   { printf "   ${RED}[ERR]${NC} %s\n" "$1"; }
info()  { printf "   ${GRAY}%s${NC}\n" "$1"; }

has_cmd() { command -v "$1" &>/dev/null; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

SKIP_INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --skip-install) SKIP_INSTALL=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-install]"
            echo "  Set GITHUB_TOKEN env var for GitHub MCP server."
            exit 0 ;;
        *) err "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

step "Checking prerequisites"

prereq_ok=true

for cmd in node npm npx; do
    if ! has_cmd "$cmd"; then
        err "'$cmd' is required but not found. Install Node.js: https://nodejs.org/"
        prereq_ok=false
    fi
done

has_python=false
has_pip=false
has_uvx=false

if has_cmd python3; then
    has_python=true
    PYTHON=python3
elif has_cmd python; then
    has_python=true
    PYTHON=python
else
    skip "Python not found — Python-based MCP servers will be skipped."
fi

if $has_python; then
    if $PYTHON -m pip --version &>/dev/null; then
        has_pip=true
    else
        skip "pip not found — Python MCP servers require manual install."
    fi
fi

if has_cmd uvx; then
    has_uvx=true
    ok "uvx available"
elif $has_python; then
    skip "uvx not found — will fall back to pip + python for Python servers."
fi

if ! $prereq_ok; then
    err "Missing required prerequisites. Install them and re-run."
    exit 1
fi

ok "Node.js $(node --version)"
if $has_python; then ok "Python $($PYTHON --version 2>&1 | sed 's/Python //')"; fi

# ---------------------------------------------------------------------------
# Resolve GitHub token
# ---------------------------------------------------------------------------

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
has_github_token=false
if [[ -n "$GITHUB_TOKEN" ]]; then
    has_github_token=true
    ok "GitHub token found"
else
    skip "No GITHUB_TOKEN set — GitHub MCP server will use empty token."
    info "Set GITHUB_TOKEN env var to enable."
fi

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------

if ! $SKIP_INSTALL; then
    step "Pre-caching npm MCP packages"

    npm_servers=(
        "@anthropic/mcp-fetch"
        "@modelcontextprotocol/server-sequential-thinking"
        "@github/mcp-server"
    )

    for pkg in "${npm_servers[@]}"; do
        printf "   Caching %s ..." "$pkg"
        if npm cache add "$pkg" &>/dev/null; then
            printf " ${GREEN}done${NC}\n"
        else
            printf " ${YELLOW}(will download on first use)${NC}\n"
        fi
    done

    if $has_python && $has_pip; then
        step "Installing Python MCP packages"

        pip_servers=(
            papersflow-mcp
            mcp-simple-arxiv
            mcp-dblp
            oncite
            arxiv-latex-mcp
            latex-mcp-server
        )

        for pkg in "${pip_servers[@]}"; do
            printf "   Installing %s ..." "$pkg"
            if $PYTHON -m pip install "$pkg" --quiet 2>/dev/null; then
                printf " ${GREEN}done${NC}\n"
            else
                printf " ${YELLOW}skipped (install manually: pip install %s)${NC}\n" "$pkg"
            fi
        done
    fi
fi

# ---------------------------------------------------------------------------
# Generate .vscode/mcp.json
# ---------------------------------------------------------------------------

step "Generating .vscode/mcp.json"

vscode_dir="$SCRIPT_DIR/.vscode"
mkdir -p "$vscode_dir"

config_path="$vscode_dir/mcp.json"

# Determine Python server command
if $has_uvx; then
    py_runner="uvx"
    py_papersflow='["papersflow-mcp"]'
    py_arxiv='["mcp-simple-arxiv"]'
    py_dblp='["mcp-dblp"]'
    py_oncite='["oncite"]'
    py_arxiv_latex='["arxiv-latex-mcp"]'
    py_latex='["latex-mcp-server"]'
elif $has_python; then
    py_runner="$PYTHON"
    py_papersflow='["-m", "papersflow_mcp"]'
    py_arxiv='["-m", "mcp_simple_arxiv"]'
    py_dblp='["-m", "mcp_dblp"]'
    py_oncite='["-m", "oncite"]'
    py_arxiv_latex='["-m", "arxiv_latex_mcp"]'
    py_latex='["-m", "latex_mcp_server"]'
else
    py_runner=""
fi

# Build JSON — using heredoc for reliability over jq dependency
{
    cat <<HEADER
{
  "servers": {
    "fetch": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-fetch"]
    },
    "sequential-thinking": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }
HEADER

    # GitHub server (conditional)
    if $has_github_token; then
        cat <<GITHUB
    ,
    "github": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@github/mcp-server"],
      "env": {
        "GITHUB_TOKEN": "\${GITHUB_TOKEN}"
      }
    }
GITHUB
    fi

    # Python servers (conditional)
    if [[ -n "$py_runner" ]]; then
        cat <<PYSERVERS
    ,
    "papersflow": {
      "type": "stdio",
      "command": "$py_runner",
      "args": $py_papersflow
    },
    "arxiv": {
      "type": "stdio",
      "command": "$py_runner",
      "args": $py_arxiv
    },
    "dblp": {
      "type": "stdio",
      "command": "$py_runner",
      "args": $py_dblp
    },
    "oncite": {
      "type": "stdio",
      "command": "$py_runner",
      "args": $py_oncite
    },
    "arxiv-latex": {
      "type": "stdio",
      "command": "$py_runner",
      "args": $py_arxiv_latex
    },
    "latex": {
      "type": "stdio",
      "command": "$py_runner",
      "args": $py_latex
    }
PYSERVERS
    fi

    echo "  }"
    echo "}"
} > "$config_path"

ok "Created $config_path"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

step "Setup complete"
echo ""
echo "   Configured MCP servers:"

# List what was configured
for name in fetch sequential-thinking; do
    info "  - $name (npx)"
done
$has_github_token && info "  - github (npx)"
if [[ -n "$py_runner" ]]; then
    for name in papersflow arxiv dblp oncite arxiv-latex latex; do
        info "  - $name ($py_runner)"
    done
fi

echo ""
echo "   Next steps:"
info "  1. Reload VS Code window (Cmd+Shift+P / Ctrl+Shift+P > 'Reload Window')"
info "  2. MCP servers start automatically when agents use them"
if ! $has_github_token; then
    printf "   ${YELLOW}3. Set GITHUB_TOKEN env var and re-run to enable GitHub MCP${NC}\n"
fi
echo ""
