<#
.SYNOPSIS
    Sets up MCP servers for the Relaxed Concurrent Counting Bloom Filter
    research project.

.DESCRIPTION
    Installs and configures MCP servers used by the Copilot agent system.
    Generates .vscode/mcp.json with the appropriate server configurations.
    Uses GitHub CLI browser-based OAuth for GitHub MCP authentication.

.PARAMETER SkipInstall
    Skip package installation, only generate config.

.EXAMPLE
    .\setup-mcp.ps1
    .\setup-mcp.ps1 -SkipInstall
#>

[CmdletBinding()]
param(
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "   [OK] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "   [SKIP] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "   [ERR] $Message" -ForegroundColor Red
}

function Test-CommandExists {
    param([string]$Name)
    return ($null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue))
}

function Assert-Prerequisite {
    param([string]$Command, [string]$InstallHint)
    if (-not (Test-CommandExists $Command)) {
        Write-Err "'$Command' is required but not found."
        Write-Host "   Install: $InstallHint" -ForegroundColor Yellow
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

Write-Step 'Checking prerequisites'

$prereqOk = $true

if (-not (Assert-Prerequisite 'node' 'https://nodejs.org/')) {
    $prereqOk = $false
}
if (-not (Assert-Prerequisite 'npm' 'Comes with Node.js')) {
    $prereqOk = $false
}
if (-not (Assert-Prerequisite 'npx' 'Comes with Node.js')) {
    $prereqOk = $false
}

if (-not $prereqOk) {
    Write-Err 'Missing required prerequisites. Install them and re-run.'
    exit 1
}

$nodeVersion = node --version 2>$null
Write-OK "Node.js $nodeVersion"

# Python is optional
$hasPython = Test-CommandExists 'python'
$hasPip = $false
if ($hasPython) {
    $hasPip = Test-CommandExists 'pip'
    $pyVersion = python --version 2>&1
    Write-OK "Python $pyVersion"
} else {
    Write-Skip 'Python not found. Python-based MCP servers will be skipped.'
}

# uvx is optional — preferred runner for Python servers
$hasUvx = Test-CommandExists 'uvx'
if ($hasUvx) {
    Write-OK 'uvx available'
} elseif ($hasPython) {
    Write-Skip 'uvx not found. Will fall back to pip + python for Python servers.'
}

# gh CLI — required for GitHub MCP browser auth
$hasGh = Test-CommandExists 'gh'

# ---------------------------------------------------------------------------
# GitHub CLI browser authentication
# ---------------------------------------------------------------------------

Write-Step 'Configuring GitHub authentication (browser login)'

$hasGithubAuth = $false

if (-not $hasGh) {
    Write-Skip 'GitHub CLI (gh) not found. GitHub MCP server will be skipped.'
    Write-Host '   Install: https://cli.github.com/' -ForegroundColor Yellow
} else {
    # Check if already authenticated (gh auth status exits 1 if not logged in)
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $null = gh auth status 2>&1
    $ghExitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevPref

    if ($ghExitCode -eq 0) {
        Write-OK 'Already authenticated with GitHub CLI'
        $hasGithubAuth = $true
    } else {
        Write-Host '   Launching browser login...' -ForegroundColor Gray
        gh auth login --web --scopes 'repo,read:org'
        if ($LASTEXITCODE -eq 0) {
            Write-OK 'GitHub browser login successful'
            $hasGithubAuth = $true
        } else {
            Write-Err 'GitHub browser login failed. GitHub MCP server will be skipped.'
        }
    }
}

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------

if (-not $SkipInstall) {
    Write-Step 'Pre-caching npm MCP packages'

    $npmServers = @(
        '@anthropic/mcp-fetch',
        '@modelcontextprotocol/server-sequential-thinking',
        '@github/mcp-server',
        'mcp-languagetool'
    )

    foreach ($pkg in $npmServers) {
        Write-Host "   Caching $pkg ..." -NoNewline
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $null = npm cache add $pkg 2>&1
            Write-Host ' done' -ForegroundColor Green
        }
        catch {
            Write-Host ' (will download on first use)' -ForegroundColor Yellow
        }
        finally {
            $ErrorActionPreference = $prevPref
        }
    }

    # Python-based servers
    if ($hasPython -and $hasPip) {
        Write-Step 'Installing Python MCP packages'

        $pipServers = @(
            'papersflow-mcp',
            'mcp-simple-arxiv',
            'mcp-dblp',
            'oncite',
            'arxiv-latex-mcp',
            'latex-mcp-server'
        )

        foreach ($pkg in $pipServers) {
            Write-Host "   Installing $pkg ..." -NoNewline
            $prevPref = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = pip install $pkg 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) {
                    throw $output
                }
                Write-Host ' done' -ForegroundColor Green
            }
            catch {
                Write-Host " skipped (install manually: pip install $pkg)" -ForegroundColor Yellow
            }
            finally {
                $ErrorActionPreference = $prevPref
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Generate .vscode/mcp.json
# ---------------------------------------------------------------------------

Write-Step 'Generating .vscode/mcp.json'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$vscodeDir = Join-Path $projectRoot '.vscode'

if (-not (Test-Path $vscodeDir)) {
    New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
}

$servers = [ordered]@{}

# --- npm / npx-based servers ---

$servers['fetch'] = [ordered]@{
    type    = 'stdio'
    command = 'npx'
    args    = @('-y', '@anthropic/mcp-fetch')
}

$servers['sequential-thinking'] = [ordered]@{
    type    = 'stdio'
    command = 'npx'
    args    = @('-y', '@modelcontextprotocol/server-sequential-thinking')
}

$servers['languagetool'] = [ordered]@{
    type    = 'stdio'
    command = 'npx'
    args    = @('-y', 'mcp-languagetool')
}

# GitHub MCP — uses gh auth token for browser-based OAuth
if ($hasGithubAuth) {
    $servers['github'] = [ordered]@{
        type    = 'stdio'
        command = 'npx'
        args    = @('-y', '@github/mcp-server')
        env     = [ordered]@{
            GITHUB_TOKEN = '${command:github.copilot.chat.ghtoken}'
        }
    }
}

# --- Python-based servers ---

if ($hasUvx) {
    $pyCmd = 'uvx'
    $pyArgs = @{
        papersflow   = @('papersflow-mcp')
        arxiv        = @('mcp-simple-arxiv')
        dblp         = @('mcp-dblp')
        oncite       = @('oncite')
        'arxiv-latex' = @('arxiv-latex-mcp')
        latex        = @('latex-mcp-server')
    }
} elseif ($hasPython) {
    $pyCmd = 'python'
    $pyArgs = @{
        papersflow   = @('-m', 'papersflow_mcp')
        arxiv        = @('-m', 'mcp_simple_arxiv')
        dblp         = @('-m', 'mcp_dblp')
        oncite       = @('-m', 'oncite')
        'arxiv-latex' = @('-m', 'arxiv_latex_mcp')
        latex        = @('-m', 'latex_mcp_server')
    }
} else {
    $pyCmd = $null
    $pyArgs = @{}
}

if ($pyCmd) {
    foreach ($name in @('papersflow', 'arxiv', 'dblp', 'oncite', 'arxiv-latex', 'latex')) {
        $servers[$name] = [ordered]@{
            type    = 'stdio'
            command = $pyCmd
            args    = $pyArgs[$name]
        }
    }
}

$mcpConfig = [ordered]@{ servers = $servers }
$configPath = Join-Path $vscodeDir 'mcp.json'

$json = $mcpConfig | ConvertTo-Json -Depth 5

# Write UTF-8 without BOM
[System.IO.File]::WriteAllText($configPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-OK "Created $configPath"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Step 'Setup complete'
Write-Host ''
Write-Host '   Configured MCP servers:' -ForegroundColor White

foreach ($key in $servers.Keys) {
    $cmd = $servers[$key].command
    Write-Host "     - $key ($cmd)" -ForegroundColor Gray
}

Write-Host ''
Write-Host '   Next steps:' -ForegroundColor White
Write-Host '     1. Reload VS Code window (Ctrl+Shift+P > Reload Window)' -ForegroundColor Gray
Write-Host '     2. MCP servers start automatically when agents use them' -ForegroundColor Gray
if (-not $hasGithubAuth) {
    Write-Host '     3. Install GitHub CLI (https://cli.github.com/) and re-run for GitHub MCP' -ForegroundColor Yellow
}
Write-Host ''
