# probe.ps1 -- 启动一次 Allegro(-nograph, 无窗口) 自检 APTools 是否挂上
# ===========================================================================
# 只读检查, 不修改任何库文件, 也不会结束任何已有的 Allegro 进程。
# 做三件事:
#   1. 用一个 .scr 让 Allegro 打印/导出: apt_home、工具加载结果、菜单结构
#   2. 把菜单 dump 到文件 (axlUIMenuDump)
#   3. 读回结果, 判断 APTools 是否注册成功、菜单文字是否正常(GBK)
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File probe.ps1
# ===========================================================================
[CmdletBinding()]
param(
    [int]$TimeoutSec = 120,
    [switch]$Gui        # 用有窗口模式跑。axlUIMenuDump 在 -nograph 下拿不到菜单, 只会返回 nil
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir

# 运行位置: 从 ilinit 里读, 读不到就用默认
$cadHome = $env:HOME
if (-not $cadHome) { $cadHome = $env:USERPROFILE }
$ilinit = Join-Path (Join-Path $cadHome 'pcbenv') 'allegro.ilinit'
$runRoot = 'D:\Aphranda\APTools'
if (Test-Path -LiteralPath $ilinit) {
    $m = Select-String -Path $ilinit -Pattern '^\s*apt_home\s*=\s*"([^"]+)"' -Encoding UTF8 | Select-Object -First 1
    if ($m) { $runRoot = $m.Matches[0].Groups[1].Value }
}
$runRootWin = $runRoot -replace '/', '\'

$tmp = Join-Path $runRoot 'Temp'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$probeTxt = Join-Path $tmp 'probe.txt'
$dumpTxt  = Join-Path $tmp ('menudump_' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$scr      = Join-Path $tmp 'probe.scr'
$probePosix = ($probeTxt -replace '\\', '/')
$dumpPosix  = ($dumpTxt  -replace '\\', '/')

$allegro = 'D:\Cadence\SPB_25.1\tools\bin\allegro.exe'
if (-not (Test-Path -LiteralPath $allegro)) {
    Write-Output "[FATAL] 找不到 allegro.exe: $allegro"
    exit 3
}

Set-Content -LiteralPath $scr -Encoding ASCII -Value @(
    ('skill (let (p) (setq p (outfile "{0}" "w")) (when p (fprintf p "apt_home=%L\n" (errset apt_home t)) (fprintf p "workDir=%L\n" (errset (getWorkingDir) t)) (fprintf p "design=%L\n" (errset (axlCurrentDesign) t)) (fprintf p "apt_menuTree=%L\n" (errset (if apt_menuTree t nil) t)) (fprintf p "cmd_apt_scan=%L\n" (errset (axlUIMenuFind nil "apt_scan") t)) (fprintf p "loadAll=%L\n" (errset (apt_loadAll) t)) (close p)))' -f $probePosix),
    ('skill (axlUIMenuDump "{0}")' -f $dumpPosix),
    'exit'
)

Write-Output "运行位置 : $runRootWin"
Write-Output "模式     : $(if ($Gui) { '有窗口(可 dump 菜单)' } else { 'nograph(无窗口, 只看加载)' })"
$before = @(Get-Process allegro -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$argl = @('-readonly', '-s', ('"' + $scr + '"'))
if (-not $Gui) { $argl = @('-nograph') + $argl }
Start-Process -FilePath $allegro -ArgumentList $argl -WorkingDirectory $tmp | Out-Null
for ($i = 0; $i -lt $TimeoutSec; $i++) {
    Start-Sleep -Seconds 1
    if (-not (Get-Process allegro -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Id })) { break }
}
Start-Sleep -Seconds 2

Write-Output ''
Write-Output '=== 加载状态 ==='
if (Test-Path -LiteralPath $probeTxt) { Get-Content -LiteralPath $probeTxt -Encoding UTF8 | ForEach-Object { Write-Output $_ } }
else { Write-Output '(未生成 —— 说明 ilinit 那条链没跑起来)' }

Write-Output ''
Write-Output '=== menubar 里的 APTools (按 GBK 读 = Allegro 实际渲染编码) ==='
if (Test-Path -LiteralPath $dumpTxt) {
    $gbk = [System.Text.Encoding]::GetEncoding(936)
    $lines = [System.IO.File]::ReadAllLines($dumpTxt, $gbk)
    $hit = $lines | Select-String -Pattern 'APTools' -Context 0, 14 | Select-Object -First 1
    if ($hit) {
        Write-Output ('  ' + $hit.Line)
        $hit.Context.PostContext | ForEach-Object { Write-Output ('  ' + $_) }
    } else { Write-Output '  没有 APTools —— 菜单未注册' }
} else { Write-Output '(未生成 menudump)' }

Write-Output ''
Write-Output "提示: 临时文件在 $tmp (probe.scr / probe.txt / menudump.txt)"
exit 0
