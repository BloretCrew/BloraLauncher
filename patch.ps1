$ErrorActionPreference = "Stop"

# ============================================================
# 读取项目版本号
# ============================================================

$WorkDir = (Get-Location).Path

$VersionFile = Join-Path $WorkDir "lib\services\update_manager.dart"

if (-not (Test-Path $VersionFile -PathType Leaf)) {
    Write-Host "[ERROR] 找不到版本文件:" -ForegroundColor Red
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
    Write-Host "[ERROR] 无法从 update_manager.dart 中找到 currentVersion。" -ForegroundColor Red
    Write-Host '期望格式: const currentVersion = "0.0.6";' -ForegroundColor Yellow
    exit 1
}

$Version = $VersionMatch.Groups[1].Value

Write-Host "[INFO] 当前版本: $Version" -ForegroundColor Cyan

# ============================================================
# 基础路径
# ============================================================

$RunnerDir = Join-Path $WorkDir "build\windows\x64\runner"

$ReleaseDir = Join-Path $RunnerDir "Release"
$OldReleaseDir = Join-Path $RunnerDir "OldRelease"

$ReleasePackDir = Join-Path $RunnerDir "ReleasePack"
$PatchDir = Join-Path $RunnerDir "Patch"

# 临时 ZIP 目录
$TempDir = Join-Path $RunnerDir ".pack_temp"

# ============================================================
# 输出函数
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

function Format-Size {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }

    if ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }

    return "$Bytes B"
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath)
    $full = [System.IO.Path]::GetFullPath($FullPath)

    if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $base += [System.IO.Path]::DirectorySeparatorChar
    }

    return [System.IO.Path]::GetRelativePath($base, $full)
}

# ============================================================
# 开始
# ============================================================

Write-Host ""
Write-Host "==============================================" -ForegroundColor DarkCyan
Write-Host "       Windows Release / Patch Packer         " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor DarkCyan
Write-Host ""

Write-Info "版本: $Version"
Write-Info "工作目录: $WorkDir"
Write-Info "Release: $ReleaseDir"
Write-Info "OldRelease: $OldReleaseDir"
Write-Host ""

# ============================================================
# 检查 Release
# ============================================================

if (-not (Test-Path $ReleaseDir -PathType Container)) {
    Write-ErrorMessage "找不到 Release 目录:"
    Write-Host $ReleaseDir -ForegroundColor Yellow
    exit 1
}

# ============================================================
# 检查 OldRelease
# ============================================================

if (-not (Test-Path $OldReleaseDir -PathType Container)) {
    Write-WarningMessage "OldRelease 不存在，本次不进行打包。"
    Write-Host ""
    exit 0
}

Write-Success "Release 和 OldRelease 均存在"

# ============================================================
# 清理旧的临时目录
# ============================================================

Write-Host ""
Write-Info "清理旧的打包目录..."

foreach ($dir in @(
    $ReleasePackDir,
    $PatchDir,
    $TempDir
)) {
    if (Test-Path $dir) {
        Remove-Item `
            -Path $dir `
            -Recurse `
            -Force
    }
}

New-Item `
    -ItemType Directory `
    -Path $ReleasePackDir `
    -Force | Out-Null

New-Item `
    -ItemType Directory `
    -Path $PatchDir `
    -Force | Out-Null

New-Item `
    -ItemType Directory `
    -Path $TempDir `
    -Force | Out-Null

Write-Success "临时目录准备完成"

# ============================================================
# 第一部分
# 创建 ReleasePack
#
# 只复制：
# *.exe
# *.dll
# *.exp
# *.lib
# data\
# ============================================================

Write-Host ""
Write-Host "========== 创建 ReleasePack ==========" -ForegroundColor Cyan
Write-Host ""

$releaseFiles = Get-ChildItem `
    -Path $ReleaseDir `
    -File `
    -ErrorAction Stop |
    Where-Object {
        $_.Extension.ToLowerInvariant() -in @(
            ".exe",
            ".dll",
            ".exp",
            ".lib"
        )
    }

$releaseFileCount = 0
$releaseTotalSize = 0

foreach ($file in $releaseFiles) {

    $destination = Join-Path `
        $ReleasePackDir `
        $file.Name

    Copy-Item `
        -Path $file.FullName `
        -Destination $destination `
        -Force

    $releaseFileCount++
    $releaseTotalSize += $file.Length

    Write-Host "  + $($file.Name)" -ForegroundColor Gray
}

# ------------------------------------------------------------
# data
# ------------------------------------------------------------

$releaseDataDir = Join-Path $ReleaseDir "data"

if (Test-Path $releaseDataDir -PathType Container) {

    Write-Info "复制 data 文件夹..."

    Copy-Item `
        -Path $releaseDataDir `
        -Destination $ReleasePackDir `
        -Recurse `
        -Force

    $dataFiles = Get-ChildItem `
        -Path $releaseDataDir `
        -File `
        -Recurse

    foreach ($file in $dataFiles) {
        $releaseTotalSize += $file.Length
    }

    Write-Success "data: $($dataFiles.Count) 个文件"
}
else {
    Write-WarningMessage "Release 中不存在 data 文件夹"
}

Write-Host ""

Write-Success "ReleasePack 创建完成"

Write-Host "  根目录文件: $releaseFileCount"
Write-Host "  原始大小: $(Format-Size $releaseTotalSize)"

# ============================================================
# 第二部分
# 打包完整 Release
# ============================================================

Write-Host ""
Write-Host "========== 打包完整 Release ==========" -ForegroundColor Cyan
Write-Host ""

$releaseZipTemp = Join-Path `
    $TempDir `
    "ReleasePack.zip"

if (Test-Path $releaseZipTemp) {
    Remove-Item `
        -Path $releaseZipTemp `
        -Force
}

# 只压缩 ReleasePack 的内容
# 不把 ReleasePack 这一层目录放进 ZIP
Compress-Archive `
    -Path (Join-Path $ReleasePackDir "*") `
    -DestinationPath $releaseZipTemp `
    -CompressionLevel Optimal `
    -Force

# ------------------------------------------------------------
# SHA256
# ------------------------------------------------------------

$releaseHash = (
    Get-FileHash `
        -Path $releaseZipTemp `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$releaseFinalName = "release_$Version`_$releaseHash.zip"

$releaseFinalPath = Join-Path `
    $RunnerDir `
    $releaseFinalName

if (Test-Path $releaseFinalPath) {
    Remove-Item `
        -Path $releaseFinalPath `
        -Force
}

Move-Item `
    -Path $releaseZipTemp `
    -Destination $releaseFinalPath

$releaseZipSize = (
    Get-Item $releaseFinalPath
).Length

Write-Success "完整 Release 包生成成功"

Write-Host "  文件名: " -NoNewline
Write-Host $releaseFinalName -ForegroundColor Yellow

Write-Host "  大小: $(Format-Size $releaseZipSize)"

# ============================================================
# 第三部分
# 建立 OldRelease Hash 索引
# ============================================================

Write-Host ""
Write-Host "========== 分析 Release 差异 ==========" -ForegroundColor Cyan
Write-Host ""

$oldFiles = @{}
$currentFiles = @{}

# ------------------------------------------------------------
# OldRelease
# ------------------------------------------------------------

Write-Info "扫描 OldRelease..."

$oldFileList = Get-ChildItem `
    -Path $OldReleaseDir `
    -File `
    -Recurse

$oldIndex = 0

foreach ($file in $oldFileList) {

    $oldIndex++

    $relative = Get-RelativePath `
        -BasePath $OldReleaseDir `
        -FullPath $file.FullName

    $relative = $relative.Replace("\", "/")

    $hash = (
        Get-FileHash `
            -Path $file.FullName `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    $oldFiles[$relative] = $hash
}

Write-Success "OldRelease: $($oldFiles.Count) 个文件"

# ------------------------------------------------------------
# 当前 Release
# ------------------------------------------------------------

Write-Info "扫描当前 Release..."

$currentFileList = Get-ChildItem `
    -Path $ReleasePackDir `
    -File `
    -Recurse

foreach ($file in $currentFileList) {

    $relative = Get-RelativePath `
        -BasePath $ReleasePackDir `
        -FullPath $file.FullName

    $relative = $relative.Replace("\", "/")

    $hash = (
        Get-FileHash `
            -Path $file.FullName `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    $currentFiles[$relative] = $hash
}

Write-Success "当前 Release: $($currentFiles.Count) 个文件"

# ============================================================
# 第四部分
# 找新增 / 修改文件
# ============================================================

Write-Host ""
Write-Host "---------- 新增 / 修改 ----------" -ForegroundColor DarkCyan

$addedCount = 0
$modifiedCount = 0
$unchangedCount = 0
$deletedCount = 0

foreach ($relative in $currentFiles.Keys) {

    $source = Join-Path `
        $ReleasePackDir `
        ($relative.Replace("/", "\"))

    $destination = Join-Path `
        $PatchDir `
        ($relative.Replace("/", "\"))

    # --------------------------------------------------------
    # 新文件
    # --------------------------------------------------------

    if (-not $oldFiles.ContainsKey($relative)) {

        $parent = Split-Path `
            $destination `
            -Parent

        if (-not (Test-Path $parent)) {
            New-Item `
                -ItemType Directory `
                -Path $parent `
                -Force | Out-Null
        }

        Copy-Item `
            -Path $source `
            -Destination $destination `
            -Force

        $addedCount++

        Write-Host "  [+] $relative" -ForegroundColor Green

        continue
    }

    # --------------------------------------------------------
    # Hash 相同
    # --------------------------------------------------------

    if ($currentFiles[$relative] -eq $oldFiles[$relative]) {

        $unchangedCount++

        continue
    }

    # --------------------------------------------------------
    # Hash 不同
    # --------------------------------------------------------

    $parent = Split-Path `
        $destination `
        -Parent

    if (-not (Test-Path $parent)) {
        New-Item `
            -ItemType Directory `
            -Path $parent `
            -Force | Out-Null
    }

    Copy-Item `
        -Path $source `
        -Destination $destination `
        -Force

    $modifiedCount++

    Write-Host "  [M] $relative" -ForegroundColor Yellow
}

# ============================================================
# 第五部分
# 找被删除的文件
# ============================================================

Write-Host ""
Write-Host "---------- 删除文件 ----------" -ForegroundColor DarkCyan

foreach ($relative in $oldFiles.Keys) {

    # 当前仍然存在
    if ($currentFiles.ContainsKey($relative)) {
        continue
    }

    $deletedPath = Join-Path `
        $PatchDir `
        ($relative.Replace("/", "\"))

    # --------------------------------------------------------
    # foo.dll
    #
    # ↓
    #
    # foo.dll.deleted
    # --------------------------------------------------------

    $deletedPath = "$deletedPath.deleted"

    $parent = Split-Path `
        $deletedPath `
        -Parent

    if (-not (Test-Path $parent)) {
        New-Item `
            -ItemType Directory `
            -Path $parent `
            -Force | Out-Null
    }

    # 创建 0 字节文件
    New-Item `
        -ItemType File `
        -Path $deletedPath `
        -Force | Out-Null

    $deletedCount++

    Write-Host "  [-] $relative" -ForegroundColor Red
}

# ============================================================
# 差异统计
# ============================================================

$totalPatchFiles =
    $addedCount +
    $modifiedCount +
    $deletedCount

Write-Host ""
Write-Host "==============================================" -ForegroundColor DarkGray

Write-Host "新增:   " -NoNewline
Write-Host $addedCount -ForegroundColor Green

Write-Host "修改:   " -NoNewline
Write-Host $modifiedCount -ForegroundColor Yellow

Write-Host "删除:   " -NoNewline
Write-Host $deletedCount -ForegroundColor Red

Write-Host "未变化: " -NoNewline
Write-Host $unchangedCount -ForegroundColor Gray

Write-Host "Patch 文件: $totalPatchFiles"

Write-Host "==============================================" -ForegroundColor DarkGray

# ============================================================
# 第六部分
# 打包 Patch
# ============================================================

Write-Host ""
Write-Host "========== 打包 Patch ==========" -ForegroundColor Cyan
Write-Host ""

$patchZipTemp = Join-Path `
    $TempDir `
    "Patch.zip"

if (Test-Path $patchZipTemp) {
    Remove-Item `
        -Path $patchZipTemp `
        -Force
}

# ------------------------------------------------------------
# 即使没有变化，也创建 ZIP
# ------------------------------------------------------------

if ($totalPatchFiles -eq 0) {

    Write-WarningMessage "没有检测到任何文件变化。"

    # Compress-Archive 对完全空目录无法直接创建 ZIP，
    # 所以创建一个临时占位文件，然后删除它。
    $emptyFile = Join-Path `
        $PatchDir `
        ".empty"

    New-Item `
        -ItemType File `
        -Path $emptyFile `
        -Force | Out-Null

    Compress-Archive `
        -Path $emptyFile `
        -DestinationPath $patchZipTemp `
        -CompressionLevel Optimal `
        -Force

    Remove-Item `
        -Path $emptyFile `
        -Force
}
else {

    Compress-Archive `
        -Path (Join-Path $PatchDir "*") `
        -DestinationPath $patchZipTemp `
        -CompressionLevel Optimal `
        -Force
}

# ============================================================
# Patch SHA256
# ============================================================

$patchHash = (
    Get-FileHash `
        -Path $patchZipTemp `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

$patchFinalName = "patch_$Version`_$patchHash.zip"

$patchFinalPath = Join-Path `
    $RunnerDir `
    $patchFinalName

if (Test-Path $patchFinalPath) {
    Remove-Item `
        -Path $patchFinalPath `
        -Force
}

Move-Item `
    -Path $patchZipTemp `
    -Destination $patchFinalPath

$patchZipSize = (
    Get-Item $patchFinalPath
).Length

Write-Success "Patch 包生成成功"

Write-Host "  文件名: " -NoNewline
Write-Host $patchFinalName -ForegroundColor Yellow

Write-Host "  大小: $(Format-Size $patchZipSize)"

# ============================================================
# 第七部分
# 清理临时目录
# ============================================================

Write-Host ""
Write-Info "清理临时文件..."

if (Test-Path $TempDir) {
    Remove-Item `
        -Path $TempDir `
        -Recurse `
        -Force
}

# ============================================================
# 完成
# ============================================================

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "                 打包完成                     " -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""

Write-Host "完整包:" -ForegroundColor Cyan
Write-Host "  $releaseFinalPath" -ForegroundColor Yellow
Write-Host "  $(Format-Size $releaseZipSize)"
Write-Host ""

Write-Host "补丁包:" -ForegroundColor Cyan
Write-Host "  $patchFinalPath" -ForegroundColor Yellow
Write-Host "  $(Format-Size $patchZipSize)"
Write-Host ""

Write-Host "变化统计:" -ForegroundColor Cyan
Write-Host "  新增   $addedCount"
Write-Host "  修改   $modifiedCount"
Write-Host "  删除   $deletedCount"
Write-Host "  未变化 $unchangedCount"
Write-Host ""

Write-Success "全部任务完成"