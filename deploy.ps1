<#
.SYNOPSIS
    Manual Arduino deploy — auto-detects everything.

.USAGE
    .\deploy.ps1                              # Deploy sketches/blink (auto-detect board)
    .\deploy.ps1 -Sketch sketches/servo       # Deploy specific sketch
    .\deploy.ps1 -Port COM5 -Fqbn arduino:avr:mega   # Override auto-detect
    .\deploy.ps1 -ListBoards                  # Show connected boards
#>

param(
    [string]$Sketch = "sketches/blink",
    [string]$Port = "",
    [string]$Fqbn = "",
    [switch]$ListBoards
)

$ErrorActionPreference = "Stop"

# ── Check arduino-cli ────────────────────────────────────────
if (-not (Get-Command arduino-cli -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: arduino-cli not found!" -ForegroundColor Red
    Write-Host "Run install_runner.ps1 first, or install manually."
    exit 1
}

# ── List boards mode ─────────────────────────────────────────
if ($ListBoards) {
    Write-Host "Connected Arduino boards:" -ForegroundColor Cyan
    arduino-cli board list
    exit 0
}

# ── Auto-detect board ────────────────────────────────────────
Write-Host ""
Write-Host "=== Arduino Manual Deploy ===" -ForegroundColor Cyan
Write-Host ""

if (-not $Port -or -not $Fqbn) {
    Write-Host "Detecting Arduino board..." -ForegroundColor Yellow

    try {
        $raw  = arduino-cli board list --format json 2>$null
        $json = $raw | ConvertFrom-Json

        $detected = $null

        if ($json.detected_ports) {
            $detected = $json.detected_ports |
                Where-Object { $_.matching_boards -and $_.matching_boards.Count -gt 0 } |
                Select-Object -First 1
            if ($detected) {
                if (-not $Port) { $Port = $detected.port.address }
                if (-not $Fqbn) { $Fqbn = $detected.matching_boards[0].fqbn }
                $boardName = $detected.matching_boards[0].name
            }
        }
        elseif ($json -is [array]) {
            $detected = $json |
                Where-Object { $_.boards -and $_.boards.Count -gt 0 } |
                Select-Object -First 1
            if ($detected) {
                if (-not $Port) { $Port = $detected.address }
                if (-not $Fqbn) { $Fqbn = $detected.boards[0].fqbn }
                $boardName = $detected.boards[0].name
            }
        }
    } catch {
        Write-Host "Auto-detect error: $_" -ForegroundColor Yellow
    }

    if (-not $Port -or -not $Fqbn) {
        Write-Host ""
        Write-Host "ERROR: No Arduino board detected!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Connected ports:" -ForegroundColor Yellow
        arduino-cli board list
        Write-Host ""
        Write-Host "Try specifying manually:" -ForegroundColor Yellow
        Write-Host "  .\deploy.ps1 -Port COM3 -Fqbn arduino:avr:uno"
        exit 1
    }
}

# ── Verify sketch exists ─────────────────────────────────────
if (-not (Test-Path "$Sketch\*.ino") -and -not (Test-Path $Sketch -PathType Leaf)) {
    Write-Host "ERROR: Sketch not found: $Sketch" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available sketches:" -ForegroundColor Yellow
    Get-ChildItem -Path sketches -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  sketches/$($_.Name)" }
    exit 1
}

# ── Display info ──────────────────────────────────────────────
Write-Host "  Sketch: $Sketch" -ForegroundColor White
if ($boardName) {
    Write-Host "  Board:  $boardName ($Fqbn)" -ForegroundColor White
} else {
    Write-Host "  Board:  $Fqbn" -ForegroundColor White
}
Write-Host "  Port:   $Port" -ForegroundColor White
Write-Host ""

# ── Compile ───────────────────────────────────────────────────
Write-Host "--- COMPILING ---" -ForegroundColor Yellow
arduino-cli compile --fqbn $Fqbn $Sketch --verbose 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "COMPILE FAILED!" -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "COMPILE OK!" -ForegroundColor Green

# ── Upload with retry ────────────────────────────────────────
$maxAttempts = 2
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    Write-Host ""
    Write-Host "--- UPLOADING (attempt $attempt/$maxAttempts) ---" -ForegroundColor Yellow
    arduino-cli upload -p $Port --fqbn $Fqbn $Sketch --verbose 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  UPLOAD SUCCESS!" -ForegroundColor Green
        Write-Host "  '$Sketch' is now running on Arduino" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        exit 0
    }

    if ($attempt -lt $maxAttempts) {
        Write-Host "Upload failed. Retrying in 3 seconds..." -ForegroundColor Yellow

        # Re-detect port (might have changed)
        Start-Sleep -Seconds 3
        try {
            $raw  = arduino-cli board list --format json 2>$null
            $json = $raw | ConvertFrom-Json
            if ($json.detected_ports) {
                $newBoard = $json.detected_ports |
                    Where-Object { $_.matching_boards -and $_.matching_boards.Count -gt 0 } |
                    Select-Object -First 1
                if ($newBoard -and $newBoard.port.address -ne $Port) {
                    $Port = $newBoard.port.address
                    Write-Host "Port changed to: $Port" -ForegroundColor Yellow
                }
            }
        } catch {}
    }
}

Write-Host ""
Write-Host "UPLOAD FAILED after $maxAttempts attempts!" -ForegroundColor Red
Write-Host ""
Write-Host "Troubleshooting:" -ForegroundColor Yellow
Write-Host "  - Check USB cable connection"
Write-Host "  - Close Serial Monitor / other apps using $Port"
Write-Host "  - Try: .\deploy.ps1 -ListBoards"
Write-Host "  - Try unplugging and replugging the board"
exit 1
