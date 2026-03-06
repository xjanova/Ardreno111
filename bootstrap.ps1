#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-line bootstrap: installs Git if missing, clones repo, runs full installer.

.DESCRIPTION
    This is the FIRST script the engineer runs. It handles everything:
    1. Checks if Git is installed — if not, downloads and installs silently
    2. Clones the repo from GitHub
    3. Launches install_runner.ps1 (which does the rest)

    The engineer only needs to paste ONE command into Admin PowerShell.

.USAGE
    # ===== COPY THIS ONE LINE INTO POWERSHELL (ADMIN) =====
    irm https://raw.githubusercontent.com/xjanova/Ardreno111/main/bootstrap.ps1 | iex
#>

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoUrl   = "https://github.com/xjanova/Ardreno111.git"
$InstallTo = "D:\Code\Ardrino111"

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "   [OK] $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "   [X] $msg" -ForegroundColor Red }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Arduino Auto-Deploy — Bootstrap" -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

# ── 1. CHECK / INSTALL GIT ──────────────────────────────────
Write-Step "Checking Git..."

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-OK "Git already installed: $(git --version)"
} else {
    Write-Host "   Git not found. Installing..." -ForegroundColor Yellow

    # Try winget first (built into Windows 11)
    $useWinget = Get-Command winget -ErrorAction SilentlyContinue
    if ($useWinget) {
        Write-Host "   Installing via winget..."
        winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        Refresh-Path
    }

    # Check again
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        # Fallback: direct download
        Write-Host "   Downloading Git installer..."
        $gitUrl = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.47.1-64-bit.exe"
        $gitInstaller = "$env:TEMP\git-installer.exe"

        # Get actual latest redirect URL
        try {
            $latestUrl = "https://github.com/git-for-windows/git/releases/latest"
            $response = Invoke-WebRequest -Uri $latestUrl -MaximumRedirection 0 -ErrorAction SilentlyContinue 2>$null
        } catch {
            if ($_.Exception.Response.Headers.Location) {
                $tag = ($_.Exception.Response.Headers.Location -split '/')[-1]
                $ver = $tag -replace '^v', '' -replace '\.windows\.\d+$', ''
                $gitUrl = "https://github.com/git-for-windows/git/releases/download/$tag/Git-$ver-64-bit.exe"
            }
        }

        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing

        Write-Host "   Running silent install (this takes ~1 minute)..."
        Start-Process -FilePath $gitInstaller -ArgumentList `
            "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", `
            "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS", `
            "/COMPONENTS=ext,ext\shellhere,ext\guihere,gitlfs,assoc,assoc_sh" `
            -Wait -NoNewWindow

        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
        Refresh-Path

        # Also add common Git paths manually
        @(
            "C:\Program Files\Git\cmd",
            "C:\Program Files\Git\bin",
            "C:\Program Files (x86)\Git\cmd"
        ) | ForEach-Object {
            if ((Test-Path $_) -and $env:Path -notlike "*$_*") {
                $env:Path += ";$_"
            }
        }
    }

    # Final check
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-OK "Git installed: $(git --version)"
    } else {
        Write-Fail "Git installation failed!"
        Write-Host ""
        Write-Host "   Please install Git manually:" -ForegroundColor Yellow
        Write-Host "   https://git-scm.com/download/win" -ForegroundColor Yellow
        Write-Host "   Then re-run this script." -ForegroundColor Yellow
        exit 1
    }
}

# ── 2. CLONE REPO ───────────────────────────────────────────
Write-Step "Cloning repository..."

if (Test-Path "$InstallTo\.git") {
    Write-OK "Repo already exists at $InstallTo"
    Push-Location $InstallTo
    Write-Host "   Pulling latest changes..."
    git pull origin main 2>&1
    Pop-Location
} else {
    # Create parent directory
    $parentDir = Split-Path -Parent $InstallTo
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }

    git clone $RepoUrl $InstallTo 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Clone failed!"
        Write-Host "   Check internet connection and try again." -ForegroundColor Yellow
        exit 1
    }
    Write-OK "Cloned to $InstallTo"
}

# ── 3. RUN MAIN INSTALLER ──────────────────────────────────
Write-Step "Launching main installer..."
Write-Host ""

Set-Location $InstallTo

if (Test-Path "install_runner.ps1") {
    & ".\install_runner.ps1"
} else {
    Write-Fail "install_runner.ps1 not found in $InstallTo"
    exit 1
}
