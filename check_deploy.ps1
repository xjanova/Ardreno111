<#
.SYNOPSIS
    Check GitHub Actions deploy status — used by Claude to diagnose errors autonomously.

.USAGE
    .\check_deploy.ps1                # Latest run status + summary
    .\check_deploy.ps1 -Full          # Full log of latest run
    .\check_deploy.ps1 -RunId 12345   # Check specific run
    .\check_deploy.ps1 -List 5        # List last 5 runs
    .\check_deploy.ps1 -Artifacts     # Download debug artifacts from latest failed run
    .\check_deploy.ps1 -Watch         # Watch live until current run finishes
#>

param(
    [switch]$Full,
    [switch]$Artifacts,
    [switch]$Watch,
    [int]$List = 0,
    [string]$RunId = ""
)

$ErrorActionPreference = "Stop"
$Repo = "xjanova/Ardreno111"

# ── Check gh CLI ─────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: GitHub CLI (gh) not installed. Run install_runner.ps1 first." -ForegroundColor Red
    exit 1
}

# ── List mode ────────────────────────────────────────────────
if ($List -gt 0) {
    Write-Host "Last $List workflow runs:" -ForegroundColor Cyan
    gh run list --repo $Repo --workflow arduino-deploy.yml --limit $List
    exit 0
}

# ── Get target run ───────────────────────────────────────────
if (-not $RunId) {
    # Get latest run
    $runsJson = gh run list --repo $Repo --workflow arduino-deploy.yml --limit 1 --json databaseId,status,conclusion,headBranch,createdAt,displayTitle 2>$null
    $runs = $runsJson | ConvertFrom-Json
    if (-not $runs -or $runs.Count -eq 0) {
        Write-Host "No workflow runs found." -ForegroundColor Yellow
        Write-Host "Push a change to sketches/ to trigger a run."
        exit 0
    }
    $RunId = $runs[0].databaseId
    $runStatus     = $runs[0].status
    $runConclusion = $runs[0].conclusion
    $runBranch     = $runs[0].headBranch
    $runTitle      = $runs[0].displayTitle
    $runCreated    = $runs[0].createdAt
}

# ── Watch mode ───────────────────────────────────────────────
if ($Watch) {
    Write-Host "Watching run $RunId..." -ForegroundColor Cyan
    gh run watch $RunId --repo $Repo
    Write-Host ""
    Write-Host "Run finished. Getting results..."
    # Fall through to show results
}

# ── Show run details ─────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Deploy Status Report" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Run overview
gh run view $RunId --repo $Repo

Write-Host ""

# ── Full log mode ────────────────────────────────────────────
if ($Full) {
    Write-Host "======== FULL LOG ========" -ForegroundColor Yellow
    gh run view $RunId --repo $Repo --log
    exit 0
}

# ── Show failed step logs ────────────────────────────────────
$runJson = gh run view $RunId --repo $Repo --json conclusion 2>$null | ConvertFrom-Json
if ($runJson.conclusion -eq "failure") {
    Write-Host "======== FAILED STEP LOGS ========" -ForegroundColor Red
    gh run view $RunId --repo $Repo --log-failed
    Write-Host ""

    # ── Artifacts mode ───────────────────────────────────────
    if ($Artifacts) {
        Write-Host "======== DOWNLOADING ARTIFACTS ========" -ForegroundColor Yellow
        $artifactDir = "deploy-logs-run-$RunId"
        gh run download $RunId --repo $Repo --dir $artifactDir 2>$null
        if (Test-Path $artifactDir) {
            Write-Host "Artifacts saved to: $artifactDir/" -ForegroundColor Green
            Get-ChildItem -Recurse $artifactDir | ForEach-Object {
                Write-Host "  $($_.FullName)"
            }

            # Auto-display key files
            $boardFile = Get-ChildItem -Path $artifactDir -Filter "board-list.txt" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($boardFile) {
                Write-Host ""
                Write-Host "--- board-list.txt ---" -ForegroundColor Yellow
                Get-Content $boardFile.FullName
            }

            $runnerFile = Get-ChildItem -Path $artifactDir -Filter "runner-info.txt" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($runnerFile) {
                Write-Host ""
                Write-Host "--- runner-info.txt ---" -ForegroundColor Yellow
                Get-Content $runnerFile.FullName
            }
        } else {
            Write-Host "No artifacts available for this run." -ForegroundColor Yellow
        }
    } else {
        Write-Host "TIP: Run with -Artifacts to download debug logs" -ForegroundColor Yellow
        Write-Host "     .\check_deploy.ps1 -Artifacts" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "======== QUICK COMMANDS ========" -ForegroundColor Cyan
Write-Host "  .\check_deploy.ps1 -Full         # Full log"
Write-Host "  .\check_deploy.ps1 -Artifacts    # Download debug files"
Write-Host "  .\check_deploy.ps1 -List 10      # Last 10 runs"
Write-Host "  .\check_deploy.ps1 -Watch        # Watch live"
Write-Host ""
Write-Host "  GitHub UI: https://github.com/$Repo/actions" -ForegroundColor Yellow
Write-Host ""
