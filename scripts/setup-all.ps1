# ==============================================================================
# DevOps Git Hooks - Setup All Repositories (PowerShell)
#
# Scans sibling directories for git repositories and installs hooks in each.
# Run this after cloning goplay-devops.
#
# Usage:
#   cd goplay-devops\scripts
#   .\setup-all.ps1
#
# Compatible: Windows PowerShell 5.1+, PowerShell 7+
# ==============================================================================

$ErrorActionPreference = "Continue"

# Locate paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DevOpsRoot = Split-Path -Parent $ScriptDir
$WorkspaceRoot = Split-Path -Parent $DevOpsRoot

Write-Host ""
Write-Host "  DevOps Git Hooks - Setup All Repositories" -ForegroundColor Cyan
Write-Host "  Workspace: $WorkspaceRoot" -ForegroundColor Green
Write-Host ""

# Counters
$Total = 0
$Installed = 0
$Skipped = 0
$Failed = 0

# Skip list
$SkipDirs = @("goplay-devops", "devops-java", "DevOps-Java")

# Find all sibling git repositories
Get-ChildItem -Path $WorkspaceRoot -Directory | ForEach-Object {
    $dir = $_.FullName
    $dirname = $_.Name

    # Skip devops repos
    if ($SkipDirs -contains $dirname) { return }

    # Must be a git repository
    if (-not (Test-Path (Join-Path $dir ".git"))) { return }

    $Total++
    Write-Host "  Setting up $dirname... " -NoNewline

    # Check if setup-hooks.sh exists
    $SetupScript = Join-Path $ScriptDir "setup-hooks.sh"
    if (-not (Test-Path $SetupScript)) {
        Write-Host "FAILED (setup-hooks.sh not found)" -ForegroundColor Red
        $Failed++
        return
    }

    # Run setup-hooks.sh via git bash
    $gitBash = $null
    $gitBashPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )

    foreach ($path in $gitBashPaths) {
        if (Test-Path $path) {
            $gitBash = $path
            break
        }
    }

    # Try PATH if not found in standard locations
    if (-not $gitBash) {
        $gitBash = Get-Command bash -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    }

    if (-not $gitBash) {
        Write-Host "FAILED (bash not found - install Git for Windows)" -ForegroundColor Red
        $Failed++
        return
    }

    try {
        Push-Location $dir
        $output = & $gitBash $SetupScript 2>&1
        if ($LASTEXITCODE -eq 0) {
            $Installed++
            Write-Host "OK" -ForegroundColor Green
        } else {
            $Failed++
            Write-Host "FAILED" -ForegroundColor Red
            $output | Select-Object -Last 3 | ForEach-Object { Write-Host "    $_" }
        }
    } catch {
        $Failed++
        Write-Host "FAILED ($_)" -ForegroundColor Red
    } finally {
        Pop-Location
    }
}

# Summary
Write-Host ""
Write-Host "  Total repositories:  $Total"
Write-Host "  Installed/Updated:   $Installed" -ForegroundColor Green
if ($Skipped -gt 0) { Write-Host "  Skipped:             $Skipped" -ForegroundColor Yellow }
if ($Failed -gt 0) { Write-Host "  Failed:              $Failed" -ForegroundColor Red }
Write-Host ""

if ($Failed -gt 0) {
    Write-Host "  Some repositories failed. Run setup-hooks.sh manually in those repos." -ForegroundColor Yellow
    exit 1
}
