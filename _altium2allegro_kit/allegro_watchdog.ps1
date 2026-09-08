# allegro_watchdog.ps1 - 执行脚本: 启动 Allegro -s 跑导入, 自动收尾并抓错误
# =========================================================================
# 功能:
#   * 未给 -AllegroRoot 时自动调用同目录 find_allegro.ps1 探测安装根
#   * 启动 allegro.exe -s <WorkDir>\<ScrName>, 监视到进程自然退出
#   * 若被"是否保存"等弹窗卡住, 定时补按键 'n' 放行(可 -NoKeys 关闭)
#   * 结束后读 journal: 抓 *Error*/upperCase 错误行、关键进度行、产物 .brd
# 输出标记(供上层流程脚本解析):
#   [VERDICT] FAIL|SUCCESS|UNKNOWN|no allegro|scr missing ...
#   [ERR] ...   [KEY] ...   [BRD] name size
# =========================================================================
param(
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$ScrName = 'run_import.scr',
    [string]$AllegroRoot = '',
    [int]$Minutes = 5,
    [int]$PollSeconds = 12,
    [switch]$NoKeys
)
$ErrorActionPreference = 'Continue'
$kitDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $AllegroRoot) {
    $json = Join-Path $kitDir '_watchdog_env.json'
    & (Join-Path $kitDir 'find_allegro.ps1') -OutJson $json | Out-Null
    if (Test-Path $json) {
        $envInfo = Get-Content $json -Raw | ConvertFrom-Json
        if ($envInfo.found) { $AllegroRoot = [string]$envInfo.root }
    }
}
if (-not $AllegroRoot) { Write-Output '[VERDICT] no allegro environment found'; exit 3 }
$exe = Join-Path $AllegroRoot 'tools\bin\allegro.exe'
if (-not (Test-Path $exe)) { Write-Output ("[VERDICT] allegro.exe missing: " + $exe); exit 3 }

$scr = Join-Path $WorkDir $ScrName
if (-not (Test-Path $scr)) { Write-Output ("[VERDICT] script missing: " + $scr); exit 3 }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Get-ChildItem $WorkDir -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne $ScrName } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$jrl = Join-Path $WorkDir 'allegro.jrl'

$p = Start-Process -FilePath $exe -ArgumentList '-s', ('"' + $scr + '"') -WorkingDirectory $WorkDir -PassThru
Write-Output ("[PID] " + $p.Id)
$maxSec = $Minutes * 60
$elapsed = 0
$prevJrl = -1
$idleStreak = 0
while ($elapsed -lt $maxSec) {
    Start-Sleep -Seconds $PollSeconds
    $elapsed += $PollSeconds
    $alive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    $jrlBytes = 0
    if (Test-Path $jrl) { $jrlBytes = (Get-Item $jrl).Length }
    Write-Output ("[t] " + $elapsed + "s alive=" + [bool]$alive + " jrl=" + $jrlBytes)
    if (-not $alive) { Write-Output '[PROC-EXIT]'; break }
    if ($jrlBytes -eq $prevJrl -and $jrlBytes -gt 0) {
        $idleStreak++
    } else {
        $idleStreak = 0
        $prevJrl = $jrlBytes
    }
    if ($idleStreak -ge 4 -and -not $NoKeys) {
        try {
            $w = New-Object -ComObject WScript.Shell
            $null = $w.AppActivate($p.Id)
            Start-Sleep -Milliseconds 600
            $w.SendKeys('n')
            Start-Sleep -Seconds 6
        } catch { }
        $idleStreak = 0
    }
}
$alive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
if ($alive) { Stop-Process -Id $p.Id -Force; Write-Output '[WATCHDOG-KILL]' }
Start-Sleep -Seconds 2

$errLines = @()
$keyLines = @()
if (Test-Path $jrl) {
    $errLines = @(Select-String -Path $jrl -Pattern '\*Error\*|upperCase' -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
    $keyLines = @(Select-String -Path $jrl -Pattern 'Number of text blocks|Performing DRC|Performing database check' -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
}
foreach ($e in $errLines) { Write-Output ("[ERR] " + $e) }
foreach ($k in $keyLines) { Write-Output ("[KEY] " + $k) }
$brds = Get-ChildItem $WorkDir -Filter '*.brd' -ErrorAction SilentlyContinue | Sort-Object Length -Descending
foreach ($b in $brds) { Write-Output ("[BRD] " + $b.Name + " " + $b.Length) }

if ($errLines.Count -gt 0) { Write-Output '[VERDICT] FAIL'; exit 1 }
$best = $brds | Select-Object -First 1
if ($best -and $best.Length -gt 300000) { Write-Output '[VERDICT] SUCCESS'; exit 0 }
if (Test-Path (Join-Path $WorkDir 'altium2pcb_viewlog.txt')) { Write-Output '[VERDICT] SUCCESS(viewlog)'; exit 0 }
Write-Output '[VERDICT] UNKNOWN'
exit 2
