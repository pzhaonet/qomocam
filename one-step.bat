<# :
@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: ================= 配置区域 =================
:: 源文件夹 A (图片来源)
set "SRC_DIR=E:\DataPKU\zf-gkj1-camera"
:: 目标文件夹 B (项目里的图片目录，建议直接设为项目下的某个目录)
set "DST_DIR=%~dp0"
:: ===========================================

echo ======================================
echo   第一步：挑选最新图片并添加水印
echo ======================================

:: 调用本文件中的 PowerShell 代码块
powershell -noprofile -executionpolicy bypass -command "IEX ([System.IO.File]::ReadAllText('%~f0'))"

if %errorlevel% neq 0 (
    echo [错误] 图片处理失败，请检查 ImageMagick 是否安装或路径是否正确。
    pause
    exit /b
)

echo.
echo ======================================
echo   第二步：提交变更并推送至 GitHub
echo ======================================

:: 检查是否有文件变动
git status -s | findstr /r "." >nul
if %errorlevel% neq 0 (
    echo [提示] 没有检测到任何文件变化，跳过推送。
    pause
    exit /b
)

git add .

:: 自动生成提交信息
set "commit_msg=Auto-update images: %date% %time%"

echo 正在提交: "%commit_msg%"
git commit -m "%commit_msg%"

echo 正在推送至远程仓库...
git push

if %errorlevel% equ 0 (
    echo.
    echo [成功] 所有操作已完成！
) else (
    echo.
    echo [错误] 推送失败，请检查网络或 Token 配置。
)

pause
exit /b
#>

# --- 这里开始是 PowerShell 代码 (不要修改下面的逻辑) ---
$src = $env:SRC_DIR
$dst = $env:DST_DIR

if (!(Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }

# 查找最新的两张图片
$images = Get-ChildItem -Path $src -Recurse -File -Include *.jpg, *.jpeg, *.png | ForEach-Object {
    if ($_.BaseName -match '(\d{14})$') {
        [PSCustomObject]@{ FullName = $_.FullName; Timestamp = $matches[1] }
    }
} | Sort-Object Timestamp -Descending | Select-Object -First 2

if (!$images) {
    Write-Error "未能在源文件夹中找到符合日期命名的图片。"
    exit 1
}

$idx = 1
foreach ($img in $images) {
    $ts = $img.Timestamp
    # 格式化时间 20260130163042 -> 2026-01-30 16:30:42
    $displayTS = "{0}-{1}-{2} {3}:{4}:{5}" -f $ts.Substring(0,4), $ts.Substring(4,2), $ts.Substring(6,2), $ts.Substring(8,2), $ts.Substring(10,2), $ts.Substring(12,2)
    
    $outPath = Join-Path $dst "$idx.jpg"
    
    Write-Host "正在处理: $($img.FullName) -> $idx.jpg"
    
    # 调用 ImageMagick
    & magick "$($img.FullName)" -gravity South -pointsize 50 -fill white -undercolor "#00000080" -annotate +0+10 " $displayTS " "$outPath"
    
    $idx++
}
