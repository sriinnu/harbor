#
# Harbor Windows Build Script (PowerShell)
#
# Prerequisites:
# - Windows 10/11 with PowerShell 7+
# - Rust: https://rustup.rs/ (latest stable)
# - Node.js: https://nodejs.org/ 18+ LTS
# - Visual Studio Build Tools 2019+ with C++ workload
#   Download: https://visualstudio.microsoft.com/downloads/
#
# Usage:
#   .\Scripts\build.ps1              # Build debug
#   .\Scripts\build.ps1 release      # Build release
#   .\Scripts\build.ps1 clean        # Clean build artifacts
#   .\Scripts\build.ps1 deps         # Install dependencies
#   .\Scripts\build.ps1 run          # Run in development mode
#

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('debug', 'release', 'clean', 'deps', 'run', 'help')]
    [string]$Mode = 'debug'
)

$ErrorActionPreference = 'Stop'

# Paths
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = Split-Path -Parent $SCRIPT_DIR
$TAURI_DIR = Join-Path $PROJECT_ROOT 'harbor-windows'
$BUILD_DIR = Join-Path $PROJECT_ROOT 'build\windows'
$env:CARGO_TARGET_DIR = Join-Path $BUILD_DIR 'target'

# Colors for output
$GREEN = [char]27 + '[32m'
$YELLOW = [char]27 + '[33m'
$RED = [char]27 + '[31m'
$NC = [char]27 + '[0m'

function Write-Info { Write-Host "${GREEN}ℹ️  $args${NC}" }
function Write-Warn { Write-Host "${YELLOW}⚠️  $args${NC}" }
function Write-Error { Write-Host "${RED}❌  $args${NC}" }

function Show-Help {
    Write-Host @"

Harbor Windows Build Script

Usage: $($MyInvocation.MyCommand) <command>

Commands:
  debug    Build debug version (default)
  release  Build release version (optimized)
  clean    Clean all build artifacts
  deps     Install dependencies
  run      Run in development mode (with hot reload)
  help     Show this help

Build output: $BUILD_DIR

Prerequisites:
- Rust (rustup.rs)
- Node.js 18+
- Visual Studio Build Tools with C++ workload

"@
}

function Test-Prerequisites {
    $missing = @()

    # Check Rust
    if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) {
        $missing += 'Rust (run https://rustup.rs/)'
    }

    # Check Node
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        $missing += 'Node.js (https://nodejs.org/)'
    }

    # Check VS Build Tools
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        $missing += 'Visual Studio Build Tools with C++ workload'
    }

    if ($missing.Count -gt 0) {
        Write-Error "Missing prerequisites:"
        $missing | ForEach-Object { Write-Host "  - $_" }
        exit 1
    }
}

function Install-Dependencies {
    Write-Info "Installing dependencies..."

    if (-not (Test-Path $TAURI_DIR)) {
        Write-Error "Tauri project not found: $TAURI_DIR"
        Write-Info "Note: Run this from the Harbor project root"
        exit 1
    }

    Push-Location $TAURI_DIR

    try {
        # Install Node dependencies
        if (Test-Path 'package.json') {
            Write-Info "Installing Node.js dependencies..."
            npm install
        }

        # Verify Rust toolchain
        rustc --version
        cargo --version

        Write-Info "✅ Dependencies ready"
    }
    finally {
        Pop-Location
    }
}

function Build-Debug {
    Write-Info "Building Harbor Windows (Debug)..."
    Test-Prerequisites

    Push-Location $TAURI_DIR

    try {
        npm run tauri build -- --config debug
        Write-Info "✅ Debug build complete"
    }
    finally {
        Pop-Location
    }
}

function Build-Release {
    Write-Info "Building Harbor Windows (Release)..."
    Test-Prerequisites

    Push-Location $TAURI_DIR

    try {
        npm run tauri build
        Write-Info "✅ Release build complete"
    }
    finally {
        Pop-Location
    }
}

function Clean-Build {
    Write-Info "Cleaning build artifacts..."

    # Clean Tauri build
    if (Test-Path $TAURI_DIR/src-tauri/target) {
        Remove-Item -Recurse -Force $TAURI_DIR/src-tauri/target -ErrorAction SilentlyContinue
    }

    # Clean build directory
    if (Test-Path $BUILD_DIR) {
        Remove-Item -Recurse -Force $BUILD_DIR -ErrorAction SilentlyContinue
    }

    Write-Info "✅ Clean complete"
}

function Run-Dev {
    Write-Info "Running Harbor in development mode..."
    Test-Prerequisites

    Push-Location $TAURI_DIR

    try {
        Write-Info "Starting Tauri dev server (with hot reload)..."
        Write-Info "Press Ctrl+C to stop"
        npm run tauri dev
    }
    finally {
        Pop-Location
    }
}

# Main entry point
switch ($Mode) {
    'help' {
        Show-Help
    }
    'deps' {
        Install-Dependencies
    }
    'debug' {
        Build-Debug
    }
    'release' {
        Build-Release
    }
    'clean' {
        Clean-Build
    }
    'run' {
        Run-Dev
    }
    default {
        Show-Help
    }
}
