# install.ps1 -- APTools 挂载到 Allegro(写 allegro.ilinit)
# ===========================================================================
# 目录结构(本仓库 = 开发):
#     APTools/
#     ├─ core/   APTools_Menu.il(入口) + APTools_Load.il(框架)
#     ├─ tools/  <阶段>/<工具>.il
#     └─ install/install.ps1  ← 本文件
#
# 做的事(只动自己那一块, 不破坏其它内容):
#   在 %HOME%\pcbenv\allegro.ilinit 末尾写入:
#       ; ---- APTools 自建 SKILL 工具集 ----
#       apt_home = "<运行位置>"
#       loadi(strcat(apt_home "/core/APTools_Menu.il"))
#   写入前先备份成 .bak_<时间戳>; 已有旧块则替换该块, 不重复追加。
#
# 为什么写绝对路径而不是环境变量: 实测用户级环境变量对 Allegro 不可见
#   (注册表有值, 但已运行的父进程不会更新自己的环境块, 新进程继承的是旧环境块),
#   getShellEnvVar 返回空 -> loadi 静默失败 -> 菜单完全不出现。
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   powershell ... -File install.ps1 -RunRoot "D:\Aphranda\APTools"
#   powershell ... -File install.ps1 -CadHome "D:\Cadence\SPB_Data"
# ===========================================================================
[CmdletBinding()]
param(
    [string]$RunRoot = '',
    [string]$CadHome = ''
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir          # APTools 仓库根

# 运行位置: 默认与 FanySkill 并排
if (-not $RunRoot) { $RunRoot = 'D:\Aphranda\APTools' }
$RunRoot = $RunRoot.TrimEnd('\')

if (-not $CadHome) { $CadHome = $env:HOME }
if (-not $CadHome) { $CadHome = $env:USERPROFILE }
if (-not $CadHome) { Write-Output '[FATAL] 找不到 Cadence 用户目录, 用 -CadHome 指定'; exit 3 }

$ilinit   = Join-Path (Join-Path $CadHome 'pcbenv') 'allegro.ilinit'
$runPosix = $RunRoot -replace '\\', '/'

Write-Output '==============================================================='
Write-Output "APTools 仓库 : $repoRoot"
Write-Output "运行位置     : $RunRoot"
Write-Output "Cadence HOME : $CadHome"
Write-Output "ilinit       : $ilinit"
Write-Output '==============================================================='

foreach ($f in 'core\APTools_Menu.il', 'core\APTools_Load.il', 'tools') {
    $p = Join-Path $repoRoot $f
    if (-not (Test-Path -LiteralPath $p)) { Write-Output "[FATAL] 缺文件/目录: $p"; exit 3 }
}

$runMenu = Join-Path $RunRoot 'core\APTools_Menu.il'
if (-not (Test-Path -LiteralPath $runMenu)) {
    Write-Output "[warn] 运行位置还没部署: $runMenu"
    Write-Output "       先执行: powershell -File `"$repoRoot\devkit\deploy.ps1`" -RunRoot `"$RunRoot`""
}

$block = @(
    '; ---- APTools 自建 SKILL 工具集 ----'
    ('apt_home = "{0}"' -f $runPosix)
    'loadi(strcat(apt_home "/core/APTools_Menu.il"))'
)

$pcbenv = Split-Path -Parent $ilinit
if (-not (Test-Path -LiteralPath $pcbenv)) { New-Item -ItemType Directory -Force -Path $pcbenv | Out-Null }

if (Test-Path -LiteralPath $ilinit) {
    $bak = "$ilinit.bak_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $ilinit -Destination $bak -Force
    Write-Output "[bak] $bak"

    $lines = [System.IO.File]::ReadAllLines($ilinit, [System.Text.Encoding]::UTF8)
    $keep = @()
    $inBlock = $false
    foreach ($l in $lines) {
        if ($l -match 'APTools 自建 SKILL 工具集') { $inBlock = $true; continue }
        if ($inBlock) {
            if (($l -match '^\s*apt_home\s*=') -or ($l -match 'APTools_Menu\.il')) { continue }
            $inBlock = $false
        }
        $keep += $l
    }
    while ($keep.Count -gt 0 -and $keep[-1].Trim() -eq '') { $keep = $keep[0..($keep.Count - 2)] }
    $out = @($keep) + @('') + $block
    [System.IO.File]::WriteAllLines($ilinit, $out, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output '[ok] 已写入/更新 APTools 挂载块'
} else {
    [System.IO.File]::WriteAllLines($ilinit, $block, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output '[ok] 新建 allegro.ilinit'
}

Write-Output ''
Write-Output '---- 现在 ilinit 的内容 ----'
Get-Content -LiteralPath $ilinit -Encoding UTF8 | ForEach-Object { Write-Output $_ }
Write-Output ''
Write-Output '完成, 重启 Allegro 生效。'
exit 0
