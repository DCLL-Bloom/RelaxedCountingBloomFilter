<#
.SYNOPSIS
    Sets up MCP (Model Context Protocol) servers for the Relaxed Concurrent
    Counting Bloom Filter research project.

.DESCRIPTION
    Installs and configures MCP servers used by the Copilot agent system.
    Generates .vscode/mcp.json with the appropriate server configurations.

    Servers installed:
      - papersflow-mcp    (Semantic Scholar + OpenAlex literature search)
      - mcp-dblp          (DBLP CS bibliography search)
      - mcp-simple-arxiv  (arXiv paper search and reading)
      - OneCite           (BibTeX citation generation)
      - arxiv-latex-mcp   (arXiv LaTeX source extraction)
      - latex-mcp-server  (LaTeX compilation and figure management)
      - github-mcp-server (GitHub repo/PR/issue management)
      - mcp-fetch         (Web content fetching)
      - mcp-sequentialthinking (Multi-step reasoning)

.PARAMETER SkipInstall
    Skip package installation, only generate config.

.PARAMETER GithubToken
    GitHub personal access token for the GitHub MCP server.
    Can also be set via GITHUB_TOKEN environment variable.

.EXAMPLE
    .\setup-mcp.ps1
    .\setup-mcp.ps1 -GithubToken "ghp_xxxx"
    .\setup-mcp.ps1 -SkipInstall
#>

[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [string]$GithubToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step { param([string]$Message) Write-Host "`n>> $Message" -ForegroundColor Cyan }
function Write-OK   { param([string]$Message) Write-Host "   [OK] $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "   [SKIP] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "   [ERR] $Message" -ForegroundColor Red }

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Assert-Prerequisite {
    param([string]$Command, [string]$InstallHint)
    if (-not (Test-Command $Command)) {
        Write-Err "'$Command' is required but not found."
        Write-Host "   Install: $InstallHint" -ForegroundColor Yellow
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

Write-Step "Checking prerequisites"

$prereqOk = $true

if (-not (Assert-Prerequisite "node" "https://nodejs.org/")) { $prereqOk = $false }
if (-not (Assert-Prerequisite "npm"  "Comes with Node.js"))  { $prereqOk = $false }
if (-not (Assert-Prerequisite "npx"  "Comes with Node.js"))  { $prereqOk = $false }

# Python is optional — only needed for some servers
$hasPython = Test-Command "python"
$hasPip = Test-Command "pip"
if (-not $hasPython) {
    Write-Skip "Python not found — Python-based MCP servers will be skipped."
}

# uvx is optional — preferred runner for some Python servers
$hasUvx = Test-Command "uvx"
if (-not $hasUvx -and $hasPython) {
    Write-Skip "uvx not found — will fall back to pip + python for Python servers."
}

if (-not $prereqOk) {
    Write-Err "Missing required prerequisites. Install them and re-run."
    exit 1
}

$nodeVersion = (node --version) 2>$null
Write-OK "Node.js $nodeVersion"
if ($hasPython) {
    $pyVersion = (python --version 2>&1) -replace 'Python\s*', ''
    Write-OK "Python $pyVersion"
}
if ($hasUvx) { Write-OK "uvx available" }

# ---------------------------------------------------------------------------
# Resolve GitHub token
# ---------------------------------------------------------------------------

if (-not $GithubToken) {
    $GithubToken = $env:GITHUB_TOKEN
}
$hasGithubToken = [bool]$GithubToken
if (-not $hasGithubToken) {
    Write-Skip "No GitHub token provided — GitHub MCP server will use empty token."
    Write-Host "   Set GITHUB_TOKEN env var or pass -GithubToken to enable." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Install npm-based MCP servers (global installs via npx at runtime — no
# global pollution; npx caches automatically)
# ---------------------------------------------------------------------------

# We don't globally install npm packages. The VS Code MCP config uses npx
# which auto-downloads on first run. We just verify npx works.

if (-not $SkipInstall) {
    Write-Step "Pre-caching npm MCP packages (npx -y)"

    $npmServers = @(
        "@anthropic/mcp-fetch"
        "@modelcontextprotocol/server-sequential-thinking"
        "@github/mcp-server"
    )

    foreach ($pkg in $npmServers) {
        Write-Host "   Caching $pkg ..." -NoNewline
        try {
            $null = npm cache add $pkg 2>&1
            Write-Host " done" -ForegroundColor Green
        } catch {
            Write-Host " (will download on first use)" -ForegroundColor Yellow
        }
    }

    # Python-based servers: install via pip/uvx if available
    if ($hasPython -and $hasPip) {
        Write-Step "Installing Python MCP packages"

        $pipServers = @(
            "papersflow-mcp"
            "mcp-simple-arxiv"
            "mcp-dblp"
        )

        foreach ($pkg in $pipServers) {
            Write-Host "   Installing $pkg ..." -NoNewline
            try {
                $output = pip install $pkg 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw $output }
                Write-Host " done" -ForegroundColor Green
            } catch {
                Write-Host " failed" -ForegroundColor Red
                Write-Err "  $($_.Exception.Message)"
            }
        }
    }

    if ($hasPython -and $hasPip) {
        # These may need special install methods
        $specialPip = @(
            @{ Name = "oncite";         Pkg = "oncite" }
            @{ Name = "arxiv-latex-mcp"; Pkg = "arxiv-latex-mcp" }
            @{ Name = "latex-mcp-server"; Pkg = "latex-mcp-server" }
        )

        foreach ($entry in $specialPip) {
            Write-Host "   Installing $($entry.Name) ..." -NoNewline
            try {
                $output = pip install $entry.Pkg 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw $output }
                Write-Host " done" -ForegroundColor Green
            } catch {
                Write-Host " skipped (install manually: pip install $($entry.Pkg))" -ForegroundColor Yellow
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Generate .vscode/mcp.json
# ---------------------------------------------------------------------------

Write-Step "Generating .vscode/mcp.json"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$vscodeDir = Join-Path $projectRoot ".vscode"

if (-not (Test-Path $vscodeDir)) {
    New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
}

# Build server configs conditionally
$servers = [ordered]@{}

# --- npm / npx-based servers ---

$servers["fetch"] = @{
    type = "stdio"
    command = "npx"
    args = @("-y", "@anthropic/mcp-fetch")
}

$servers["sequential-thinking"] = @{
    type = "stdio"
    command = "npx"
    args = @("-y", "@modelcontextprotocol/server-sequential-thinking")
}

if ($hasGithubToken) {
    $servers["github"] = @{
        type = "stdio"
        command = "npx"
        args = @("-y", "@github/mcp-server")
        env = @{
            GITHUB_TOKEN = "`${GITHUB_TOKEN}"
        }
    }
}

# --- Python-based servers (uvx preferred, fallback to python -m) ---

if ($hasUvx) {
    $servers["papersflow"] = @{
        type = "stdio"
        command = "uvx"
        args = @("papersflow-mcp")
    }
    $servers["arxiv"] = @{
        type = "stdio"
        command = "uvx"
        args = @("mcp-simple-arxiv")
    }
    $servers["dblp"] = @{
        type = "stdio"
        command = "uvx"
        args = @("mcp-dblp")
    }
    $servers["oncite"] = @{
        type = "stdio"
        command = "uvx"
        args = @("oncite")
    }
    $servers["arxiv-latex"] = @{
        type = "stdio"
        command = "uvx"
        args = @("arxiv-latex-mcp")
    }
    $servers["latex"] = @{
        type = "stdio"
        command = "uvx"
        args = @("latex-mcp-server")
    }
} elseif ($hasPython) {
    $servers["papersflow"] = @{
        type = "stdio"
        command = "python"
        args = @("-m", "papersflow_mcp")
    }
    $servers["arxiv"] = @{
        type = "stdio"
        command = "python"
        args = @("-m", "mcp_simple_arxiv")
    }
    $servers["dblp"] = @{
        type = "stdio"
        command = "python"
        args = @("-m", "mcp_dblp")
    }
    $servers["oncite"] = @{
        type = "stdio"
        command = "python"
        args = @("-m", "oncite")
    }
    $servers["arxiv-latex"] = @{
        type = "stdio"
        command = "python"
        args = @("-m", "arxiv_latex_mcp")
    }
    $servers["latex"] = @{
        type = "stdio"
        command = "python"
        args = @("-m", "latex_mcp_server")
    }
}

$mcpConfig = @{ servers = $servers }

$configPath = Join-Path $vscodeDir "mcp.json"

# Serialize with proper depth to capture nested objects
$json = $mcpConfig | ConvertTo-Json -Depth 5

# Write UTF-8 without BOM
[System.IO.File]::WriteAllText($configPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-OK "Created $configPath"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Step "Setup complete"
Write-Host ""
Write-Host "   Configured MCP servers:" -ForegroundColor White

$servers.Keys | ForEach-Object {
    $cmd = $servers[$_].command
    Write-Host "     - $_ ($cmd)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "   Next steps:" -ForegroundColor White
Write-Host "     1. Reload VS Code window (Ctrl+Shift+P > 'Reload Window')" -ForegroundColor Gray
Write-Host "     2. MCP servers start automatically when agents use them" -ForegroundColor Gray
if (-not $hasGithubToken) {
    Write-Host "     3. Set GITHUB_TOKEN env var and re-run to enable GitHub MCP" -ForegroundColor Yellow
}
Write-Host ""
