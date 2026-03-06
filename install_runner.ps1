#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Zero-config installer: GitHub Actions Runner + Arduino CLI + Everything.
    Run once in elevated PowerShell. It handles EVERYTHING automatically.

.DESCRIPTION
    This script will:
    1. Install Chocolatey, Git, GitHub CLI, Arduino CLI
    2. Auto-detect your Arduino board and install the correct core
    3. Download and register GitHub Actions self-hosted runner
    4. Install runner as Windows Service (runs 24/7 without terminal)
    5. Initialize git repo, commit, and push to GitHub

    The ONLY thing you need to do: log in to GitHub when the browser opens.

.USAGE
    # Open PowerShell as Administrator, then:
    .\install_runner.ps1

    # Or with custom repo:
    .\install_runner.ps1 -RepoOwner "myuser" -RepoName "myrepo"
#>

param(
    [string]$RepoOwner = "xjanova",
    [string]$RepoName  = "Ardreno111",
    [string]$RunnerDir = "C:\actions-runner",
    [string]$ArduinoDir = "C:\arduino-cli"
)

# ============================================================
#  CONFIG
# ============================================================
$RepoUrl  = "https://github.com/$RepoOwner/$RepoName"
$RepoPath = "$RepoOwner/$RepoName"
$RunnerName   = "arduino-$($env:COMPUTERNAME.ToLower())"
$RunnerLabels = "self-hosted,windows,arduino-windows"
$ProjectDir   = Split-Path -Parent $MyInvocation.MyCommand.Path

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================================
#  HELPERS
# ============================================================
function Write-Banner($text) {
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Magenta
    Write-Host "  $text" -ForegroundColor Magenta
    Write-Host ("=" * 50) -ForegroundColor Magenta
}
function Write-Step($text)  { Write-Host "`n>> $text" -ForegroundColor Cyan }
function Write-OK($text)    { Write-Host "   [OK] $text" -ForegroundColor Green }
function Write-Warn($text)  { Write-Host "   [!] $text" -ForegroundColor Yellow }
function Write-Fail($text)  { Write-Host "   [X] $text" -ForegroundColor Red }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Ensure-Command($name, $chocoPackage) {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
        Write-OK "$name already installed"
        return $true
    }
    Write-Host "   Installing $chocoPackage..."
    choco install $chocoPackage -y --no-progress | Out-Null
    Refresh-Path
    if (Get-Command $name -ErrorAction SilentlyContinue) {
        Write-OK "$name installed"
        return $true
    }
    Write-Fail "Failed to install $name"
    return $false
}

# ============================================================
#  AUTO-DETECT ARDUINO BOARD (reusable function)
# ============================================================
function Detect-ArduinoBoard {
    $result = @{ Port = $null; Fqbn = $null; BoardName = $null }
    try {
        $raw  = arduino-cli board list --format json 2>$null
        $json = $raw | ConvertFrom-Json

        # New format (arduino-cli 0.35+)
        if ($json.detected_ports) {
            $found = $json.detected_ports |
                Where-Object { $_.matching_boards -and $_.matching_boards.Count -gt 0 } |
                Select-Object -First 1
            if ($found) {
                $result.Port      = $found.port.address
                $result.Fqbn      = $found.matching_boards[0].fqbn
                $result.BoardName = $found.matching_boards[0].name
            }
        }
        # Old format (flat array)
        elseif ($json -is [array]) {
            $found = $json |
                Where-Object { $_.boards -and $_.boards.Count -gt 0 } |
                Select-Object -First 1
            if ($found) {
                $result.Port      = $found.address
                $result.Fqbn      = $found.boards[0].fqbn
                $result.BoardName = $found.boards[0].name
            }
        }
    } catch {}
    return $result
}

# ============================================================
#  START
# ============================================================
Write-Banner "Arduino + GitHub Actions Runner Installer"
Write-Host "  Repo:    $RepoUrl" -ForegroundColor White
Write-Host "  Runner:  $RunnerName" -ForegroundColor White
Write-Host "  Project: $ProjectDir" -ForegroundColor White

# ── PHASE 1: Package Manager ────────────────────────────────
Write-Step "Phase 1: Package Manager"
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-OK "Chocolatey already installed"
} else {
    Write-Host "   Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    Refresh-Path
    Write-OK "Chocolatey installed"
}

# ── PHASE 2: Prerequisites ──────────────────────────────────
Write-Step "Phase 2: Prerequisites (git, gh CLI)"
Ensure-Command "git"  "git"
Ensure-Command "gh"   "gh"

# ── PHASE 3: GitHub Authentication ──────────────────────────
Write-Step "Phase 3: GitHub Authentication"
$ghStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Not logged in to GitHub. Opening browser..."
    Write-Host ""
    Write-Host "   >>> A browser window will open." -ForegroundColor Yellow
    Write-Host "   >>> Log in to GitHub and authorize the CLI." -ForegroundColor Yellow
    Write-Host ""
    gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "GitHub login failed!"
        Write-Host "   Try manually: gh auth login"
        exit 1
    }
}
Write-OK "GitHub authenticated"

# ── PHASE 4: Ensure GitHub Repo Exists ──────────────────────
Write-Step "Phase 4: Verify GitHub Repository"
$repoCheck = gh repo view $RepoPath 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Repo '$RepoPath' not found. Creating it..."
    gh repo create $RepoPath --public --description "Arduino Auto-Deploy via GitHub Actions"
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to create repo. Create it manually at: $RepoUrl"
        exit 1
    }
    Write-OK "Repo created: $RepoUrl"
} else {
    Write-OK "Repo exists: $RepoUrl"
}

# ── PHASE 5: Arduino CLI ────────────────────────────────────
Write-Step "Phase 5: Arduino CLI"
if (Get-Command arduino-cli -ErrorAction SilentlyContinue) {
    Write-OK "Arduino CLI already installed: $(arduino-cli version 2>$null)"
} else {
    Write-Host "   Downloading Arduino CLI..."
    New-Item -ItemType Directory -Force -Path $ArduinoDir | Out-Null

    $zipPath = "$env:TEMP\arduino-cli.zip"
    $dlUrl   = "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_64bit.zip"
    Invoke-WebRequest -Uri $dlUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $ArduinoDir -Force
    Remove-Item $zipPath -Force

    # Add to system PATH permanently
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$ArduinoDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$ArduinoDir", "Machine")
    }
    Refresh-Path
    Write-OK "Arduino CLI installed to $ArduinoDir"
}

# Add ESP32 board manager URL
Write-Host "   Adding ESP32 board support..."
arduino-cli config init 2>$null
arduino-cli config add board_manager.additional_urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json 2>$null
Write-OK "ESP32 board URL added"

# Update board index
Write-Host "   Updating board index..."
arduino-cli core update-index 2>&1 | Out-Null
Write-OK "Board index updated"

# ── PHASE 6: Detect Board & Install Core ────────────────────
Write-Step "Phase 6: Detect Arduino Board"
Write-Host "   Connected devices:"
arduino-cli board list

$board = Detect-ArduinoBoard

if ($board.Port -and $board.Fqbn) {
    Write-OK "Detected: $($board.BoardName) ($($board.Fqbn)) on $($board.Port)"

    # Install the matching core
    $coreName = ($board.Fqbn -split ':')[0..1] -join ':'
    Write-Host "   Installing core: $coreName..."
    arduino-cli core install $coreName 2>&1 | Out-Null
    Write-OK "Core '$coreName' installed"
} else {
    Write-Warn "No board detected right now."
    Write-Warn "Installing common cores as fallback..."
    arduino-cli core install arduino:avr 2>&1 | Out-Null
    arduino-cli core install esp32:esp32 2>&1 | Out-Null
    Write-OK "Cores installed: arduino:avr + esp32:esp32"
    Write-Host ""
    Write-Host "   Plug in your board and the system will auto-detect it" -ForegroundColor Yellow
    Write-Host "   when the workflow runs." -ForegroundColor Yellow
}

# Install required libraries
Write-Step "Phase 6b: Install Arduino Libraries"
Write-Host "   Installing InfluxDB client library..."
arduino-cli lib install "ESP8266 Influxdb" 2>&1 | Out-Null
Write-OK "Library 'ESP8266 Influxdb' installed"

# ── PHASE 7: GitHub Actions Runner ──────────────────────────
Write-Step "Phase 7: GitHub Actions Runner"

if (Test-Path "$RunnerDir\.runner") {
    Write-OK "Runner already configured at $RunnerDir"
} else {
    New-Item -ItemType Directory -Force -Path $RunnerDir | Out-Null

    # Get latest runner version
    Write-Host "   Fetching latest runner version..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest" -UseBasicParsing
    $version = $release.tag_name -replace '^v', ''
    $runnerUrl = "https://github.com/actions/runner/releases/download/v${version}/actions-runner-win-x64-${version}.zip"

    Write-Host "   Downloading runner v${version} (this may take a minute)..."
    $runnerZip = "$env:TEMP\actions-runner.zip"
    Invoke-WebRequest -Uri $runnerUrl -OutFile $runnerZip -UseBasicParsing

    Write-Host "   Extracting..."
    Expand-Archive -Path $runnerZip -DestinationPath $RunnerDir -Force
    Remove-Item $runnerZip -Force
    Write-OK "Runner extracted to $RunnerDir"

    # Get registration token via gh CLI
    Write-Host "   Getting registration token..."
    $tokenResponse = gh api -X POST "repos/$RepoPath/actions/runners/registration-token" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Cannot get runner token. You need admin access to the repo."
        Write-Fail "Error: $tokenResponse"
        exit 1
    }
    $regToken = ($tokenResponse | ConvertFrom-Json).token
    Write-OK "Registration token obtained"

    # Configure runner
    Write-Host "   Configuring runner..."
    Push-Location $RunnerDir
    try {
        $configArgs = @(
            "--url", $RepoUrl,
            "--token", $regToken,
            "--name", $RunnerName,
            "--labels", $RunnerLabels,
            "--work", "_work",
            "--unattended",
            "--replace"
        )
        & cmd /c "config.cmd $($configArgs -join ' ')" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "config.cmd failed" }
        Write-OK "Runner configured: $RunnerName"
    } catch {
        Write-Fail "Runner configuration failed: $_"
        Pop-Location
        exit 1
    }
    Pop-Location
}

# ── PHASE 8: Install Runner as Windows Service ──────────────
Write-Step "Phase 8: Install Runner as Windows Service"

# Check if service already exists
$existingService = Get-Service -Name "actions.runner.*" -ErrorAction SilentlyContinue
if ($existingService) {
    Write-OK "Service already exists: $($existingService.Name)"
    if ($existingService.Status -ne 'Running') {
        Start-Service $existingService.Name
        Write-OK "Service started"
    } else {
        Write-OK "Service is running"
    }
} else {
    Push-Location $RunnerDir

    # Try svc.sh via Git Bash (official method)
    $gitBash = $null
    @(
        "${env:ProgramFiles}\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "C:\Program Files\Git\bin\bash.exe"
    ) | ForEach-Object {
        if ((Test-Path $_) -and -not $gitBash) { $gitBash = $_ }
    }

    if ($gitBash) {
        Write-Host "   Installing service via svc.sh..."
        $runnerDirUnix = ($RunnerDir -replace '\\', '/') -replace '^([A-Za-z]):', '/$1'
        & $gitBash -c "cd '$runnerDirUnix' && ./svc.sh install" 2>&1
        & $gitBash -c "cd '$runnerDirUnix' && ./svc.sh start" 2>&1

        Start-Sleep -Seconds 2
        $svc = Get-Service -Name "actions.runner.*" -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-OK "Service installed and running: $($svc.Name)"
        } else {
            Write-Warn "svc.sh completed but service status unclear"
            Write-Warn "Falling back to Scheduled Task..."
            $gitBash = $null  # trigger fallback
        }
    }

    if (-not $gitBash) {
        # Fallback: Scheduled Task (no password needed, runs at logon)
        Write-Host "   Creating Scheduled Task (fallback)..."

        $taskName = "GitHubActionsRunner-Arduino"

        # Remove old task if exists
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        $action   = New-ScheduledTaskAction -Execute "$RunnerDir\run.cmd" -WorkingDirectory $RunnerDir
        $trigger1 = New-ScheduledTaskTrigger -AtLogon
        $trigger2 = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -DontStopOnIdleEnd `
            -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1)

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger1,$trigger2 `
            -Settings $settings `
            -RunLevel Highest `
            -Force | Out-Null

        Start-ScheduledTask -TaskName $taskName
        Write-OK "Scheduled Task '$taskName' created and started"
    }

    Pop-Location
}

# ── PHASE 9: Initialize Git Repo & Push ─────────────────────
Write-Step "Phase 9: Git Repository Setup"

Push-Location $ProjectDir

# Init if needed
if (-not (Test-Path ".git")) {
    git init
    Write-OK "Git repo initialized"
} else {
    Write-OK "Git repo already initialized"
}

# Set remote
$currentRemote = git remote get-url origin 2>$null
if (-not $currentRemote) {
    git remote add origin "$RepoUrl.git"
    Write-OK "Remote added: $RepoUrl"
} elseif ($currentRemote -ne "$RepoUrl.git" -and $currentRemote -ne $RepoUrl) {
    git remote set-url origin "$RepoUrl.git"
    Write-OK "Remote updated: $RepoUrl"
} else {
    Write-OK "Remote already set: $currentRemote"
}

# Set default branch
git branch -M main 2>$null

# Stage and commit
git add -A
$status = git status --porcelain
if ($status) {
    git commit -m "Initial setup: Arduino auto-deploy system

- GitHub Actions workflow for auto compile + upload
- Self-hosted runner installer (install_runner.ps1)
- Manual deploy helper (deploy.ps1)
- Blink test sketch"
    Write-OK "Initial commit created"
} else {
    Write-OK "Nothing new to commit"
}

# Push
Write-Host "   Pushing to GitHub..."
git push -u origin main 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-OK "Pushed to $RepoUrl"
} else {
    # Try force push if repo was empty or has different history
    Write-Warn "Normal push failed, trying with --force (first push)..."
    git push -u origin main --force 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Force pushed to $RepoUrl"
    } else {
        Write-Warn "Push failed. You can push manually: git push -u origin main"
    }
}

Pop-Location

# ── DONE ─────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 50) -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host ("=" * 50) -ForegroundColor Green
Write-Host ""
Write-Host "  Runner:  $RunnerName" -ForegroundColor White
Write-Host "  Labels:  $RunnerLabels" -ForegroundColor White
Write-Host "  Repo:    $RepoUrl" -ForegroundColor White
if ($board.Port) {
    Write-Host "  Board:   $($board.BoardName) on $($board.Port)" -ForegroundColor White
}
Write-Host ""
Write-Host "  HOW IT WORKS:" -ForegroundColor Yellow
Write-Host "  1. Edit any .ino file in sketches/ folder" -ForegroundColor White
Write-Host "  2. git add . && git commit -m 'update' && git push" -ForegroundColor White
Write-Host "  3. GitHub Actions auto-compiles and uploads to Arduino!" -ForegroundColor White
Write-Host ""
Write-Host "  USEFUL COMMANDS:" -ForegroundColor Yellow
Write-Host "  .\deploy.ps1                    # Manual deploy" -ForegroundColor White
Write-Host "  .\deploy.ps1 -Sketch sketches/X # Deploy specific sketch" -ForegroundColor White
Write-Host "  arduino-cli board list           # Check connected boards" -ForegroundColor White
Write-Host ""
Write-Host "  Check runner status:" -ForegroundColor Yellow
Write-Host "  $RepoUrl/settings/actions/runners" -ForegroundColor White
Write-Host ""
