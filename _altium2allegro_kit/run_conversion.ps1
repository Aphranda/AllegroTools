# run_conversion.ps1 - 流程管理: Altium ASCII -> 修复 -> 自动导入 -> 校验 -> 产出 .brd
# =========================================================================
# 一键流程(自动探测 Allegro 环境, 无需写死路径):
#   1. 自动发现可用 Allegro(环境变量/PATH/注册表/盘符扫描, 校验 exe+cxt+ini)
#   2. python altium_ascii_tool.py check  -- 体检(打印空封装测试点)
#   3. python altium_ascii_tool.py fix    -- 默认给空封装元件补 PATTERN + 40mil 圆焊盘
#   4. 由 run_import.scr.template 生成 <WorkDir>\run_import.scr
#   5. 调 allegro_watchdog.ps1 跑导入并自动抓错误
#   6. 成功后把产物 .brd 拷贝为 -OutBrd; 失败可 -AutoFallback 自动降级"删除"重试
# 用法示例:
#   powershell -File run_conversion.ps1 -Input CTL-...-HASL-ASCII.pcbdoc `
#       -OutBrd out\CTL-...-HASL.brd -FixMode pad -TpPadDia 40mil
# =========================================================================
param(
    [Parameter(Mandatory = $true)][string]$Input,     # Altium ASCII pcbdoc
    [string]$OutBrd = '',                             # 输出 .brd 路径
    [string]$WorkDir = '',                            # 工作目录(默认 _auto_run\convert)
    [string]$AllegroRoot = '',                        # 显式指定安装根(可选)
    [string]$FixMode = 'pad',                         # pad|remove|fill|none
    [string]$TpPattern = 'TP1PAD',
    [string]$TpPadDia = '40mil',
    [switch]$AutoFallback,                            # pad 失败时自动降级 remove
    [int]$Minutes = 6
)
$ErrorActionPreference = 'Stop'
$kitDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolPy = Join-Path $kitDir 'altium_ascii_tool.py'
$findPs = Join-Path $kitDir 'find_allegro.ps1'
$watchPs = Join-Path $kitDir 'allegro_watchdog.ps1'
$tpl    = Join-Path $kitDir 'run_import.scr.template'

if (-not (Test-Path $Input)) { Write-Error "Input not found: $Input"; exit 4 }
if (-not (Test-Path $toolPy)) { Write-Error "tool not found: $toolPy"; exit 4 }

# ---- 1. 自动发现 Allegro ----
if (-not $AllegroRoot) {
    $envJson = Join-Path $kitDir '_allegro_env.json'
    & $findPs -OutJson $envJson | Out-Null
    if (Test-Path $envJson) {
        $info = Get-Content $envJson -Raw | ConvertFrom-Json
        if ($info.found) { $AllegroRoot = [string]$info.root }
    }
}
if (-not $AllegroRoot) { Write-Error 'No usable Allegro found. Set CDSROOT or pass -AllegroRoot'; exit 4 }
Write-Output ("[ENV] Allegro root: " + $AllegroRoot)

# ---- 2/3. 体检 + 修复 ----
python $toolPy check $Input
$base = [System.IO.Path]::GetFileNameWithoutExtension($Input)
if (-not $WorkDir) { $WorkDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ('..\_auto_run\convert') }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$fixed = Join-Path $WorkDir ($base + '.fixed.pcbdoc')
python $toolPy fix $Input -o $fixed --empty-pattern-action $FixMode --tp-pattern $TpPattern --tp-pad-dia $TpPadDia
if ($LASTEXITCODE -ne 0) { Write-Error 'python fix failed'; exit 5 }

# ---- 4. 生成导入脚本 ----
$tplText = Get-Content $tpl -Raw
$scrPath = Join-Path $WorkDir 'run_import.scr'
$p2 = $fixed -replace '\\', '/'
($tplText -replace '__PCB__', $p2) | Set-Content $scrPath -Encoding Ascii
Write-Output ("[SCR] " + $scrPath)

# ---- 5. 跑导入(看门狗) ----
function Invoke-Watchdog([string]$fixedInput, [string]$tag) {
    $scr = Join-Path $WorkDir ("run_" + $tag + ".scr")
    ((Get-Content $tpl -Raw) -replace '__PCB__', ($fixedInput -replace '\\', '/')) |
        Set-Content $scr -Encoding Ascii
    $outLines = @(& $watchPs -WorkDir $WorkDir -ScrName ("run_" + $tag + ".scr") -AllegroRoot $AllegroRoot -Minutes $Minutes)
    $outLines | ForEach-Object { Write-Output $_ }
    return $outLines
}
$lines = Invoke-Watchdog $fixed 'import'
$verdict = ($lines | Where-Object { $_ -like '[VERDICT]*' } | Select-Object -Last 1)
Write-Output ("[FINAL-VERDICT] " + $verdict)

# ---- 6. 成功则拷贝产物; pad 失败可自动降级 ----
$ok = $verdict -like '*SUCCESS*'
if (-not $ok -and $AutoFallback -and $FixMode -eq 'pad') {
    Write-Output '[AUTO-FALLBACK] pad failed -> retry with remove'
    $fixed2 = Join-Path $WorkDir ($base + '.nopad.pcbdoc')
    python $toolPy fix $Input -o $fixed2 --empty-pattern-action remove
    $lines2 = Invoke-Watchdog $fixed2 'import_remove'
    $lines2 | Where-Object { $_ -like '[VERDICT]*' } | ForEach-Object { Write-Output ("[FINAL-VERDICT] " + $_) }
    $verdict = ($lines2 | Where-Object { $_ -like '[VERDICT]*' } | Select-Object -Last 1)
    $ok = $verdict -like '*SUCCESS*'
    if ($ok) { $fixed = $fixed2 }
}
if ($ok) {
    if ($OutBrd) {
        $brdLine = ($lines | Where-Object { $_ -like '[BRD]*' } | Select-Object -First 1)
        # 优先拷贝与输入同名的 <stem>.brd, 其次最大 .brd
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($fixed)
        $cand = Join-Path $WorkDir ($stem + '.brd')
        if (-not (Test-Path $cand)) {
            $max = Get-ChildItem $WorkDir -Filter '*.brd' | Sort-Object Length -Descending | Select-Object -First 1
            if ($max) { $cand = $max.FullName }
        }
        if (Test-Path $cand) {
            $dirOut = Split-Path -Parent $OutBrd
            if ($dirOut) { New-Item -ItemType Directory -Force -Path $dirOut | Out-Null }
            Copy-Item $cand $OutBrd -Force
            Write-Output ("[OUT] " + $OutBrd)
        }
    }
    Write-Output '[DONE] conversion OK (see [BRD]/[OUT])'
    exit 0
}
Write-Output '[DONE] conversion FAILED (see [ERR]/journal)'
exit 1
