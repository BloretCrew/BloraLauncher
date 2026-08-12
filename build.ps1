$ErrorActionPreference = "Stop"

# ============================================================
# Paths
# ============================================================

$WorkDir = (Get-Location).Path

$RunnerDir = Join-Path $WorkDir "build\windows\x64\runner"

$ReleaseDir = Join-Path $RunnerDir "Release"

$OldReleaseDir = Join-Path $RunnerDir "OldRelease"

# ============================================================
# Output functions
# ============================================================

function Write-Info {
    param([string]$Message)

    Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)

    Write-Host "[ OK ] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-WarningMessage {
    param([string]$Message)

    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-ErrorMessage {
    param([string]$Message)

    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

# ============================================================
# Read version
# ============================================================

$VersionFile = Join-Path `
    $WorkDir `
    "lib\services\update_manager.dart"

if (-not (Test-Path $VersionFile -PathType Leaf)) {

    Write-ErrorMessage "Version file not found:"
    Write-Host $VersionFile -ForegroundColor Yellow

    exit 1
}

$VersionContent = Get-Content `
    -Path $VersionFile `
    -Raw `
    -Encoding UTF8

$VersionMatch = [regex]::Match(
        $VersionContent,
        'const\s+currentVersion\s*=\s*"([^"]+)"'
)

if (-not $VersionMatch.Success) {

    Write-ErrorMessage "currentVersion was not found."

    exit 1
}

$Version = $VersionMatch.Groups[1].Value

# ============================================================
# Banner
# ============================================================

Write-Host ""
Write-Host "==============================================" -ForegroundColor DarkCyan
Write-Host "              Windows Build                   " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor DarkCyan
Write-Host ""

Write-Info ("Version: " + $Version)
Write-Info ("Working directory: " + $WorkDir)

# ============================================================
# Check current Release
# ============================================================

if (-not (Test-Path $ReleaseDir -PathType Container)) {

    Write-ErrorMessage "Current Release directory does not exist:"
    Write-Host $ReleaseDir -ForegroundColor Yellow

    exit 1
}

Write-Success "Current Release found"

# ============================================================
# Step 1
# Delete old OldRelease
# ============================================================

Write-Host ""
Write-Host "========== Preparing OldRelease ==========" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $OldReleaseDir) {

    Write-Info "Removing old OldRelease..."

    Remove-Item `
        -Path $OldReleaseDir `
        -Recurse `
        -Force

    Write-Success "OldRelease removed"
}

New-Item `
    -ItemType Directory `
    -Path $OldReleaseDir `
    -Force | Out-Null

# ============================================================
# Step 2
# Copy selected files from current Release
# to OldRelease
#
# Allowed:
#   *.exe
#   *.dll
#   *.exp
#   *.lib
#   data\
# ============================================================

Write-Host ""
Write-Host "========== Saving Old Release ==========" -ForegroundColor Cyan
Write-Host ""

$AllowedExtensions = @(
    ".exe",
    ".dll",
    ".exp",
    ".lib"
)

$OldFileCount = 0

# ------------------------------------------------------------
# Root files
# ------------------------------------------------------------

$RootFiles = Get-ChildItem `
    -Path $ReleaseDir `
    -File `
    -ErrorAction Stop

foreach ($File in $RootFiles) {

    if ($AllowedExtensions -notcontains $File.Extension.ToLowerInvariant()) {
        continue
    }

    $Destination = Join-Path `
        $OldReleaseDir `
        $File.Name

    Copy-Item `
        -Path $File.FullName `
        -Destination $Destination `
        -Force

    $OldFileCount++

    Write-Host ("  [COPY] " + $File.Name) -ForegroundColor Green
}

# ------------------------------------------------------------
# data directory
# ------------------------------------------------------------

$DataDir = Join-Path `
    $ReleaseDir `
    "data"

if (Test-Path $DataDir -PathType Container) {

    Copy-Item `
        -Path $DataDir `
        -Destination $OldReleaseDir `
        -Recurse `
        -Force

    $DataFiles = Get-ChildItem `
        -Path $DataDir `
        -File `
        -Recurse

    $DataCount = $DataFiles.Count

    Write-Host (
    "  [COPY] data/ (" +
            $DataCount +
            " files)"
    ) -ForegroundColor Green
}
else {

    Write-WarningMessage "Current Release does not contain data/"
}

Write-Success "Old release snapshot created"

# ============================================================
# Step 3
# Flutter Build
# ============================================================

Write-Host ""
Write-Host "========== Flutter Build ==========" -ForegroundColor Cyan
Write-Host ""

Write-Host `
    "flutter build windows --verbose --release --split-debug-info=symbol/ --obfuscate" `
    -ForegroundColor DarkGray

Write-Host ""

flutter build windows `
    --verbose `
    --release `
    --split-debug-info=symbol/ `
    --obfuscate

if ($LASTEXITCODE -ne 0) {

    Write-ErrorMessage "Flutter Windows build failed."

    exit 1
}

Write-Success "Flutter Windows build completed"

# ============================================================
# Check new Release
# ============================================================

if (-not (Test-Path $ReleaseDir -PathType Container)) {

    Write-ErrorMessage "Build completed but Release directory was not found:"
    Write-Host $ReleaseDir -ForegroundColor Yellow

    exit 1
}

# ============================================================
# Done
# ============================================================

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "              BUILD COMPLETE                  " -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""

Write-Host "Version:" -ForegroundColor Cyan
Write-Host $Version -ForegroundColor Yellow

Write-Host ""
Write-Host "Old release snapshot:" -ForegroundColor Cyan
Write-Host $OldReleaseDir

Write-Host ""
Write-Host "New Release:" -ForegroundColor Cyan
Write-Host $ReleaseDir

Write-Host ""
Write-Success "Build process completed"