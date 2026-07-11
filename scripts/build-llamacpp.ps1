$ErrorActionPreference = "Stop"

###############################################################################
# Paths
###############################################################################

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")

$LLAMACPP_REPO = Join-Path $ProjectRoot "llama.cpp"

###############################################################################
# Config
###############################################################################

$Config = @{}

Get-Content "$ProjectRoot\config\build.env" |
ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        # Trim whitespace, then safely strip wrapping single or double quotes
        $Value = $matches[2].Trim() -replace '^["'']|["'']$', ''
        $Config[$matches[1]] = $Value
    }
}

$INSTALL_DIR = $Config["INSTALL_DIR_WINDOWS"]

###############################################################################
# Logging
###############################################################################

function Log {
    param([string]$Message)

    Write-Host "[agentx] $Message" -ForegroundColor Cyan
}

###############################################################################
# Validation
###############################################################################

if (-not (Test-Path "$LLAMACPP_REPO\CMakeLists.txt")) {
    throw "Cannot find llama.cpp source tree."
}

New-Item `
    -ItemType Directory `
    -Force `
    -Path $INSTALL_DIR | Out-Null

###############################################################################
# Submodule
###############################################################################

Log "Updating submodules..."

git submodule update --init --recursive

###############################################################################
# Configure & Build (Executed within the llama.cpp repository)
###############################################################################

# Push-Location saves our starting path so we can return cleanly later
Push-Location $LLAMACPP_REPO

Log "Configuring build..."

cmake -B build `
    -DGGML_CUDA=ON `
    -DGGML_NATIVE=OFF `
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" `
    -DCMAKE_CUDA_ARCHITECTURES="$($Config['CUDA_ARCH'])"

###############################################################################
# Build
###############################################################################

Log "Building..."

cmake --build build `
    --config $Config["BUILD_TYPE"] `
    --parallel

###############################################################################
# Install
###############################################################################

Log "Installing..."

cmake --install build `
    --config $Config["BUILD_TYPE"]

###############################################################################
# Cleanup & Return
###############################################################################

if ($Config["KEEP_BUILD_DIR"] -ne "true") {
    Log "Cleaning build directory..."

    Remove-Item `
        -Recurse `
        -Force `
        .\build
}

# Safely return to the original directory we started the script from
Pop-Location

Log "Done."
