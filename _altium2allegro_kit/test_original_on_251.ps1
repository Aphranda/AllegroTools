# test_original_on_251.ps1 - 实验: 用 SPB_25.1 导入"原始未修复"文件
# 目的: 验证新版 Allegro 是否已修复空封装元件的 upperCase nil 崩溃。
$ErrorActionPreference = 'Continue'
$root = 'F:\1.Hardware\GTS_PPA1\06.SYNC_TRIG'
$kit  = Join-Path $root '_altium2allegro_kit'
$wd   = Join-Path $root '_auto_run\test251'
New-Item -ItemType Directory -Force -Path $wd | Out-Null
Get-ChildItem $wd -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$in   = Join-Path $root 'CTL-SYNCTRIG4F4-HASL-ASCII.pcbdoc'   # 原始文件(含 T1-T4 空封装)
$tpl  = Get-Content (Join-Path $kit 'run_import.scr.template') -Raw
($tpl -replace '__PCB__', ($in -replace '\\', '/')) | Set-Content (Join-Path $wd 'run_import.scr') -Encoding Ascii
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit 'allegro_watchdog.ps1') `
    -WorkDir $wd -ScrName 'run_import.scr' -AllegroRoot 'D:\Cadence\SPB_25.1' -Minutes 6
Write-Output '=== test251 done ==='
