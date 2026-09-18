# uninstall.ps1 -- 卸载 APTools 的"自启动"部分(工具集目录本身保留)
# ===========================================================================
# 做两件事:
#   1) 从 %HOME%\pcbenv\allegro.ilinit 里删掉 APTools 那段(先备份)
#   2) 删掉用户级环境变量 APTools
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
# ===========================================================================
[CmdletBinding()]
param(
    [string]$CadHome = ''
)

$ErrorActionPreference = 'Continue'

if (-not $CadHome) { $CadHome = $env:HOME }
if (-not $CadHome) { $CadHome = $env:USERPROFILE }
if (-not $CadHome) { Write-Output '[FATAL] 找不到 Cadence 用户目录, 用 -CadHome 指定'; exit 3 }

$ilinit = Join-Path (Join-Path $CadHome 'pcbenv') 'allegro.ilinit'

if (Test-Path -LiteralPath $ilinit) {
    $bak = "$ilinit.bak_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $ilinit -Destination $bak -Force
    Write-Output "[bak] $bak"

    $lines = [System.IO.File]::ReadAllLines($ilinit, [System.Text.Encoding]::UTF8)
    $keep = @()
    $skip = $false
    foreach ($l in $lines) {
        if ($l -match 'APTools 自建 SKILL 工具集') { $skip = $true; continue }
        if ($skip -and ($l -match 'APTools_Menu\.il')) { $skip = $false; continue }
        $skip = $false
        $keep += $l
    }
    # 去掉尾部多余空行
    while ($keep.Count -gt 0 -and $keep[-1].Trim() -eq '') { $keep = $keep[0..($keep.Count - 2)] }
    [System.IO.File]::WriteAllLines($ilinit, $keep, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output '[ok] 已移除 APTools 加载行'
} else {
    Write-Output "[skip] 没有 $ilinit"
}

[Environment]::SetEnvironmentVariable('APTools', $null, 'User')
Write-Output '[ok] 已删除用户环境变量 APTools'
Write-Output ''
Write-Output '---- 现在 ilinit 的内容 ----'
if (Test-Path -LiteralPath $ilinit) { Get-Content -LiteralPath $ilinit -Encoding UTF8 | ForEach-Object { Write-Output $_ } }
Write-Output ''
Write-Output '卸载完成(工具集目录本身未删除)。'
exit 0
