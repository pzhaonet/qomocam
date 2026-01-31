<# :
@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: ================= 配置区域 =================
:: 源文件夹 A
set "SRC_DIR=E:\DataPKU\zf-gkj1-camera"
:: 目标文件夹 B (项目里的图片目录，建议直接设为项目下的某个目录)
set "DST_DIR=%~dp0"
:: GIF 帧数 (最新 36 张)
set "FRAME_COUNT=36"
:: ===========================================

if not exist "%DST_DIR%" mkdir "%DST_DIR%"

echo ======================================
echo   第一步：处理图片并生成 GIF 动画
echo ======================================

:: 调用本文件中的 PowerShell 代码块
powershell -noprofile -executionpolicy bypass -command "IEX ([System.IO.File]::ReadAllText('%~f0'))"

if %errorlevel% neq 0 (
    echo.
    echo [错误] 图片转换过程中发生错误。
    pause
    exit /b
)

echo.
echo ======================================
echo   第二步：提交变更并推送至 GitHub
echo ======================================

git add .
:: 检查是否有变动需要提交
git diff --cached --quiet
if %errorlevel% neq 0 (
   set "commit_msg=Auto-update GIFs: %date% %time%"
   git commit -m "!commit_msg!"
   git push
   echo [成功] 1.gif 和 2.gif 已更新并推送！
) else (
   echo [提示] 文件没有变化，无需推送。
)
:: pause
exit /b
#>

# --- PowerShell 代码区 ---
$src = $env:SRC_DIR
$dst = $env:DST_DIR
$limit = [int]$env:FRAME_COUNT

# 创建系统临时目录用于存放处理后的单帧
$tempBase = Join-Path $env:TEMP "qomo_gif_work"
if (Test-Path $tempBase) { Remove-Item $tempBase -Recurse -Force }
New-Item -ItemType Directory -Path $tempBase | Out-Null

function Create-Gif($outputName, $regex) {
    Write-Host "正在准备组 $outputName ..." -ForegroundColor Cyan
    
    # 1. 获取图片并根据正则筛选（确保精确匹配）
    $files = Get-ChildItem -Path $src -Recurse -File -Include *.jpg | Where-Object { $_.Name -match $regex }
    
    if ($files.Count -eq 0) {
        Write-Host "未找到匹配 $regex 的文件。" -ForegroundColor Yellow
        return
    }

    # 2. 挑选最新的 36 张 (降序取前N)
    $latest = $files | ForEach-Object {
        # 重新运行匹配以获取捕获组
        if ($_.Name -match $regex) {
            $ts = $matches[1]
            [PSCustomObject]@{ Path = $_.FullName; TS = $ts }
        }
    } | Sort-Object TS -Descending | Select-Object -First $limit
    
    # 3. 按时间升序排列（保证播放顺序）
    $gifFrames = $latest | Sort-Object TS

    # 为本组创建独立的临时文件夹
    $groupTemp = Join-Path $tempBase $outputName
    New-Item -ItemType Directory -Path $groupTemp | Out-Null

    Write-Host "正在为 $($gifFrames.Count) 张图片添加独立水印..." -ForegroundColor Gray

    $frameIdx = 100 # 从100开始编号，方便文件夹排序
    $tempFileList = @()

    foreach ($frame in $gifFrames) {
        $ts = $frame.TS
        $displayTS = "{0}-{1}-{2} {3}:{4}:{5}" -f $ts.Substring(0,4), $ts.Substring(4,2), $ts.Substring(6,2), $ts.Substring(8,2), $ts.Substring(10,2), $ts.Substring(12,2)
        
        $tempImgPath = Join-Path $groupTemp ("frame_$frameIdx.jpg")
        
        # --- 关键步骤：逐张处理并保存 ---
        # 这里直接针对单张图片打水印，不存在变量污染
        & magick "$($frame.Path)" `
            -resize 300x `
            -gravity South `
            -fill white `
            -pointsize 18 `
            -annotate +0+5 " $displayTS " `
            "$tempImgPath"
        
        $tempFileList += "`"$tempImgPath`""
        $frameIdx++
    }

    # 4. 将处理好的临时图片合成 GIF
    Write-Host "正在合成 GIF: $outputName ..." -ForegroundColor Green
    $finalOut = Join-Path $dst $outputName
    
    # 使用处理好的图片列表合成
    & magick -delay 25 -loop 0 $tempFileList $finalOut

    if ($LASTEXITCODE -ne 0) { Write-Error "合成 $outputName 失败" }
}

# 组 1：精确匹配 photo + 14位数字.jpg
Create-Gif "1.gif" "^photo(\d{14})\.jpg$"

# 组 2：精确匹配 photo_2_ + 14位数字.jpg
Create-Gif "2.gif" "^photo_2_(\d{14})\.jpg$"

# 清理临时文件
Remove-Item $tempBase -Recurse -Force
