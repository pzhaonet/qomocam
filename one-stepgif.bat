<# :
@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: ================= 配置区域 =================
:: 源文件夹 A
set "SRC_DIR=E:\DataPKU\zf-gkj1-camera"
:: 目标文件夹 B (项目里的图片目录，建议直接设为项目下的某个目录)
set "DST_DIR=%~dp0"
:: GIF 帧数
set "FRAME_COUNT=36"
:: ===========================================

if not exist "%DST_DIR%" mkdir "%DST_DIR%"

echo ======================================
echo   第一步：处理图片并生成 GIF 动画
echo ======================================

:: 调用本文件中的 PowerShell 代码块
powershell -noprofile -executionpolicy bypass -command "IEX ([System.IO.File]::ReadAllText('%~f0'))"

if %errorlevel% neq 0 (
    echo [错误] 处理失败。
    pause
    exit /b
)

:: echo.
:: echo ======================================
:: echo   第二步：提交变更并推送至 GitHub
:: echo ======================================
:: 
:: git add .
:: set "commit_msg=Auto-update GIFs: %date% %time%"
:: git commit -m "%commit_msg%"
:: git push
:: 
:: if %errorlevel% equ 0 (
::     echo.
::     echo [成功] 1.gif 和 2.gif 已更新并推送！
:: ) else (
::     echo.
::     echo [错误] 推送失败。
:: )
:: 
pause
exit /b
#>

# --- PowerShell 代码区 ---
$src = $env:SRC_DIR
$dst = $env:DST_DIR
$limit = [int]$env:FRAME_COUNT

# 定义处理函数
function Create-Gif($filePattern, $outputName, $regex) {
    Write-Host "正在搜索组 $outputName ($filePattern)..." -ForegroundColor Cyan
    
    # 1. 扫描并获取最新的 36 张图
    $allFiles = Get-ChildItem -Path $src -Recurse -File -Include "*.jpg" | Where-Object { $_.BaseName -match $regex }
    
    if ($allFiles.Count -eq 0) {
        Write-Host "未找到符合 $filePattern 的图片" -ForegroundColor Yellow
        return
    }

    # 排序并取前 36 张 (最新)
    $latestFiles = $allFiles | ForEach-Object {
        $ts = $matches[1]
        [PSCustomObject]@{ Path = $_.FullName; TS = $ts }
    } | Sort-Object TS -Descending | Select-Object -First $limit
    
    # 将这 36 张按时间重新正向排序 (从旧到新，这样 GIF 才是正序播放)
    $gifFrames = $latestFiles | Sort-Object TS Ascending

    Write-Host "正在处理 $($gifFrames.Count) 帧图像..." -ForegroundColor Gray

    # 2. 构建 ImageMagick 命令
    # -delay 20: 帧间隔 20/100s = 0.2秒一帧
    # -resize: 建议稍微缩小尺寸，减小 GIF 体积
    $magickArgs = @("-delay", "20", "-loop", "0")
    
    foreach ($frame in $gifFrames) {
        $ts = $frame.TS
        $displayTS = "{0}-{1}-{2} {3}:{4}:{5}" -f $ts.Substring(0,4), $ts.Substring(4,2), $ts.Substring(6,2), $ts.Substring(8,2), $ts.Substring(10,2), $ts.Substring(12,2)
        
        # 将每一帧转换参数加入数组
        # 注意：这里使用了 ImageMagick 的括号语法来实时处理每一帧的水印
        $magickArgs += "("
        $magickArgs += $frame.Path
        # $magickArgs += "-resize"
        # $magickArgs += "1024x"   # 限制宽度为 1024px，防止 GIF 过大
        $magickArgs += "-gravity"
        $magickArgs += "South"
        $magickArgs += "-pointsize"
        $magickArgs += "40"
        $magickArgs += "-fill"
        $magickArgs += "white"
        $magickArgs += "-undercolor"
        $magickArgs += "#00000080"
        $magickArgs += "-annotate"
        $magickArgs += "+0+5"
        $magickArgs += " $displayTS "
        $magickArgs += ")"
    }
    
    $outputPath = Join-Path $dst $outputName
    $magickArgs += $outputPath

    # 3. 执行合并
    & magick $magickArgs
    Write-Host "生成完毕: $outputName" -ForegroundColor Green
}

# 执行两次处理
# 组 1: photo2026... (排除 photo_2_)
Create-Gif "photo*.jpg" "1.gif" "^photo(\d{14})$"

# 组 2: photo_2_2026...
Create-Gif "photo_2_*.jpg" "2.gif" "^photo_2_(\d{14})$"
