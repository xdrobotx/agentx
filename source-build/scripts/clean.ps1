# =============================================================================
# llama.cpp — Clean Build Artifacts (Windows)
#
# Usage (PowerShell):
#   powershell -ExecutionPolicy Bypass -File ./source-build/scripts/clean.ps1
#   .\source-build\scripts\clean.ps1 --native
#   .\source-build\scripts\clean.ps1 --artifacts
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$LLAMACPP_REPO = Join-Path $ProjectRoot "llama.cpp"
$ArtifactsDir = Join-Path $ProjectRoot "source-build\artifacts"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Log {
    param([string]$Message)
    Write-Host "[agentx clean] $Message" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
$CleanNative = $true
$CleanArtifacts = $true

foreach ($arg in $args) {
    switch ($arg) {
        "--native" {
            $CleanArtifacts = $false
        }
        "--artifacts" {
            $CleanNative = $false
        }
        default {
            Write-Host "Unknown flag: $arg" -ForegroundColor Yellow
            exit 1
        }
    }
}

# ---------------------------------------------------------------------------
# Clean native build
# ---------------------------------------------------------------------------
if ($CleanNative) {
    $BuildDir = Join-Path $LLAMACPP_REPO "build"
    if (Test-Path $BuildDir) {
        Log "Removing $BuildDir..."
        Remove-Item -Recurse -Force $BuildDir
    } else {
        Log "No native build directory to clean."
    }
}

# ---------------------------------------------------------------------------
# Clean artifacts
# ---------------------------------------------------------------------------
if ($CleanArtifacts) {
    if (Test-Path $ArtifactsDir) {
        Log "Cleaning artifacts directory..."
        Get-ChildItem -Path $ArtifactsDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Log "No artifacts directory to clean."
    }
}

Log "Clean complete."
