# deploy.ps1 -- 把仓库的 core/ + tools/ 同步到运行位置
# ===========================================================================
# 角色分工:
#     仓库 (…\AllegroTools\APTools\ )   = 只负责开发, 唯一真源
#     运行位置 (D:\Aphranda\APTools\ )  = Allegro 实际加载的地方(与 FanySkill 并排)
#
# 本脚本把 core/ 和 tools/ 覆盖到运行位置, 并保证 .il 是 GBK 编码。
# 不会删除运行位置里已有的任何文件(只覆盖同名、新增缺失)。
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File deploy.ps1
#   powershell ... -File deploy.ps1 -RunRoot "D:\Aphranda\APTools" -WhatIfOnly
# ===========================================================================
[CmdletBinding()]
param(
    [string]$RunRoot = '',
    [switch]$WhatIfOnly,
    [switch]$SkipEncodingCheck
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir

if (-not $RunRoot) { $RunRoot = 'D:\Aphranda\APTools' }
$RunRoot = $RunRoot.TrimEnd('\')

$gbk = [System.Text.Encoding]::GetEncoding(936)

Write-Output '==============================================================='
Write-Output "源(仓库)   : $repoRoot"
Write-Output "目标(运行) : $RunRoot"
if ($WhatIfOnly) { Write-Output '模式       : 仅预览(-WhatIfOnly)' }
Write-Output '==============================================================='

# --- 1) 编码体检: 所有 .il 必须是 GBK 可解码且不含 UTF-8 BOM ---
$bad = @()
Get-ChildItem "$repoRoot\core","$repoRoot\tools" -Recurse -Filter '*.il' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        $bad += "$($_.FullName)  (带 UTF-8 BOM)"
    } else {
        # 试按 GBK 解码; 若字节序列非法则说明很可能是 UTF-8 中文
        $dec = [System.Text.Encoding]::GetEncoding(936, [System.Text.EncoderFallback]::ExceptionFallback,
                                                        [System.Text.DecoderFallback]::ExceptionFallback)
        try { $null = $dec.GetString($b) } catch { $bad += "$($_.FullName)  (不是合法 GBK, 可能被存成了 UTF-8)" }
    }
}
if ($bad.Count -gt 0) {
    Write-Output '[!!] 以下 .il 编码不对(菜单中文会乱码):'
    $bad | ForEach-Object { Write-Output "     $_" }
    if (-not $SkipEncodingCheck) {
        Write-Output '     先把它们转成 GBK, 或用 -SkipEncodingCheck 强行继续。'
        exit 2
    }
} else {
    Write-Output '[ok] 编码体检通过: core/ 与 tools/ 下的 .il 都是 GBK'
}

# --- 2) 同步 ---
$n = 0
# core: 整个目录同步
if ($WhatIfOnly) { Write-Output "[plan] $repoRoot\core  ->  $RunRoot\core" }
else {
    New-Item -ItemType Directory -Force -Path "$RunRoot\core" | Out-Null
    Copy-Item -Path "$repoRoot\core\*" -Destination "$RunRoot\core" -Recurse -Force -ErrorAction Continue
    Write-Output "[ok] core  ->  $RunRoot\core"
}
# tools: 只同步阶段目录(两位数字_名字), 排除同目录下的开发辅助文件(.py 等)
$stages = @(Get-ChildItem -LiteralPath "$repoRoot\tools" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d\d_' })
if ($stages.Count -eq 0) { Write-Output '[warn] tools/ 下没有找到阶段目录(^\d\d_)' }
foreach ($st in $stages) {
    if ($WhatIfOnly) { Write-Output "[plan] tools\$($st.Name)  ->  $RunRoot\tools\$($st.Name)"; continue }
    New-Item -ItemType Directory -Force -Path "$RunRoot\tools\$($st.Name)" | Out-Null
    Copy-Item -Path "$($st.FullName)\*" -Destination "$RunRoot\tools\$($st.Name)" -Recurse -Force -ErrorAction Continue
    Write-Output "[ok] tools\$($st.Name)  ->  $RunRoot\tools\$($st.Name)"
}
if (-not $WhatIfOnly) {
    New-Item -ItemType Directory -Force -Path "$RunRoot\Temp" | Out-Null
    $n = (Get-ChildItem "$RunRoot\core","$RunRoot\tools" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Output "[ok] 运行位置现有 $n 个文件"
}

Write-Output ''
Write-Output '部署完成。运行位置的旧目录(skill/ SkillCode/ 等)本脚本不删除, 确认无用后可自行清理。'
Write-Output ('若 ilinit 还没挂, 执行:  powershell -File "{0}\install\install.ps1" -RunRoot "{1}"' -f $repoRoot, $RunRoot)
exit 0
