# =============================================================================
# llama.cpp — Build from Source (Windows)
#
# Usage (PowerShell):
#   powershell -ExecutionPolicy Bypass -File ./build/scripts/build.ps1
#   .\build\scripts\build.ps1                    # If execution policy allows
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
$SourceBuild = Resolve-Path (Join-Path $ScriptDir "..")
$LLAMACPP_REPO = Join-Path $SourceBuild "llama.cpp"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$Config = @{}
Get-Content (Join-Path $ProjectRoot "config\build.env") |
ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $Value = $matches[2].Trim() -replace '^["'']|["'']$', ''
        $Config[$matches[1]] = $Value
    }
}

$INSTALL_DIR = $Config["INSTALL_DIR_WINDOWS"]
$BUILD_TYPE = $Config["BUILD_TYPE"]
$CUDA_ARCH = $Config["CUDA_ARCH"]

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Log {
    param([string]$Message)
    Write-Host "[agentx build] $Message" -ForegroundColor Cyan
}

function Warn {
    param([string]$Message)
    Write-Host "[agentx build] WARNING: $Message" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if (-not (Test-Path (Join-Path $LLAMACPP_REPO "CMakeLists.txt"))) {
    throw "Error: llama.cpp source tree not found at $LLAMACPP_REPO"
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "Error: cmake not found. Install cmake first."
}

New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null

Log "Project root : $ProjectRoot"
Log "Source       : $LLAMACPP_REPO"
Log "Install dir  : $INSTALL_DIR"
Log "CUDA archs   : $CUDA_ARCH"
Log "Build type   : $BUILD_TYPE"

# ---------------------------------------------------------------------------
# Configure & Build
# ---------------------------------------------------------------------------
Push-Location $LLAMACPP_REPO

Log "Configuring build..."

cmake -B build `
    -DGGML_CUDA=ON `
    -DGGML_CUDA_BLAS=ON `
    -DGGML_CUDA_BLAS_VENDOR=OpenBLAS `
    -DGGML_CUDA_NCCL=ON `
    -DGGML_NATIVE=OFF `
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" `
    -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" `
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"

Log "Building (this may take a while)..."

cmake --build build --config "$BUILD_TYPE" --parallel

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
Log "Installing to $INSTALL_DIR..."

cmake --install build --config "$BUILD_TYPE"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
if ($Config["KEEP_BUILD_DIR"] -ne "true") {
    Log "Cleaning build directory..."
    Remove-Item -Recurse -Force .\build
}

Pop-Location

Log "Build complete. Binaries installed to $INSTALL_DIR"
