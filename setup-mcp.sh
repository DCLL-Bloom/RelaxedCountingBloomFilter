#!/usr/bin/env bash
#
# setup-mcp.sh — Install and configure MCP servers for the Relaxed Concurrent
# Counting Bloom Filter research project.
#
# Uses GitHub CLI browser-based OAuth for GitHub MCP authentication.
#
# Usage:
#   ./setup-mcp.sh                  # Full install + config
#   ./setup-mcp.sh --skip-install   # Config only

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
            echo "  Uses GitHub CLI (gh) for browser-based GitHub authentication."
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

if ! $prereq_ok; then
    err "Missing required prerequisites. Install them and re-run."
    exit 1
fi

ok "Node.js $(node --version)"

has_python=false
has_pip=false
has_uvx=false
PYTHON=""

if has_cmd python3; then
    has_python=true
    PYTHON=python3
elif has_cmd python; then
    has_python=true
    PYTHON=python
else
    skip "Python not found. Python-based MCP servers will be skipped."
fi

if $has_python; then
    ok "Python $($PYTHON --version 2>&1 | sed 's/Python //')"
    if $PYTHON -m pip --version &>/dev/null; then
        has_pip=true
    else
        skip "pip not found. Python MCP servers require manual install."
    fi
fi

if has_cmd uvx; then
    has_uvx=true
    ok "uvx available"
elif $has_python; then
    skip "uvx not found. Will fall back to pip + python for Python servers."
fi

# ---------------------------------------------------------------------------
# GitHub CLI browser authentication
# ---------------------------------------------------------------------------

step "Configuring GitHub authentication (browser login)"

has_github_auth=false

if ! has_cmd gh; then
    skip "GitHub CLI (gh) not found. GitHub MCP server will be skipped."
    info "Install: https://cli.github.com/"
else
    if gh auth status &>/dev/null; then
        ok "Already authenticated with GitHub CLI"
        has_github_auth=true
    else
        info "Launching browser login..."
        if gh auth login --web --scopes 'repo,read:org'; then
            ok "GitHub browser login successful"
            has_github_auth=true
        else
            err "GitHub browser login failed. GitHub MCP server will be skipped."
        fi
    fi
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
        "mcp-languagetool"
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
py_runner=""
if $has_uvx; then
    py_runner="uvx"
elif $has_python; then
    py_runner="$PYTHON"
fi

# Build JSON via heredoc
{
    printf '{\n  "servers": {\n'
    printf '    "fetch": {\n'
    printf '      "type": "stdio",\n'
    printf '      "command": "npx",\n'
    printf '      "args": ["-y", "@anthropic/mcp-fetch"]\n'
    printf '    },\n'
    printf '    "sequential-thinking": {\n'
    printf '      "type": "stdio",\n'
    printf '      "command": "npx",\n'
    printf '      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]\n'
    printf '    },\n'
    printf '    "languagetool": {\n'
    printf '      "type": "stdio",\n'
    printf '      "command": "npx",\n'
    printf '      "args": ["-y", "mcp-languagetool"]\n'
    printf '    }'

    # GitHub server
    if $has_github_auth; then
        printf ',\n'
        printf '    "github": {\n'
        printf '      "type": "stdio",\n'
        printf '      "command": "npx",\n'
        printf '      "args": ["-y", "@github/mcp-server"],\n'
        printf '      "env": {\n'
        printf '        "GITHUB_TOKEN": "${command:github.copilot.chat.ghtoken}"\n'
        printf '      }\n'
        printf '    }'
    fi

    # Python servers
    if [[ -n "$py_runner" ]]; then
        if $has_uvx; then
            servers=("papersflow:papersflow-mcp" "arxiv:mcp-simple-arxiv" "dblp:mcp-dblp" "oncite:oncite" "arxiv-latex:arxiv-latex-mcp" "latex:latex-mcp-server")
        else
            servers=("papersflow:-m:papersflow_mcp" "arxiv:-m:mcp_simple_arxiv" "dblp:-m:mcp_dblp" "oncite:-m:oncite" "arxiv-latex:-m:arxiv_latex_mcp" "latex:-m:latex_mcp_server")
        fi

        for entry in "${servers[@]}"; do
            IFS=':' read -r name arg1 arg2 <<< "$entry"
            printf ',\n'
            printf '    "%s": {\n' "$name"
            printf '      "type": "stdio",\n'
            printf '      "command": "%s",\n' "$py_runner"
            if [[ -z "$arg2" ]]; then
                printf '      "args": ["%s"]\n' "$arg1"
            else
                printf '      "args": ["%s", "%s"]\n' "$arg1" "$arg2"
            fi
            printf '    }'
        done
    fi

    printf '\n  }\n}\n'
} > "$config_path"

ok "Created $config_path"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

step "Setup complete"
echo ""
echo "   Configured MCP servers:"

for name in fetch sequential-thinking languagetool; do
    info "  - $name (npx)"
done
if $has_github_auth; then info "  - github (npx)"; fi
if [[ -n "$py_runner" ]]; then
    for name in papersflow arxiv dblp oncite arxiv-latex latex; do
        info "  - $name ($py_runner)"
    done
fi

echo ""
echo "   Next steps:"
info "  1. Reload VS Code window (Cmd+Shift+P / Ctrl+Shift+P > Reload Window)"
info "  2. MCP servers start automatically when agents use them"
if ! $has_github_auth; then
    printf "   ${YELLOW}3. Install GitHub CLI (https://cli.github.com/) and re-run for GitHub MCP${NC}\n"
fi
echo ""
