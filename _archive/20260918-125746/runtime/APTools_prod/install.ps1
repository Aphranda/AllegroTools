# install.ps1 -- APTools 安装: 设环境变量 + 挂 allegro.ilinit
# ===========================================================================
# 只做两件事, 都不破坏已有配置:
#   1) 设用户级环境变量 APTools = 本目录
#   2) 在 %HOME%\pcbenv\allegro.ilinit 末尾追加一行 loadi
#      * 追加前先备份成 allegro.ilinit.bak_<时间戳>
#      * 已存在则跳过, 不重复加
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   powershell ... -File install.ps1 -CadHome "D:\Cadence\SPB_Data"
# ===========================================================================
[CmdletBinding()]
param(
    [string]$CadHome = ''
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $CadHome) { $CadHome = $env:HOME }
if (-not $CadHome) { $CadHome = $env:USERPROFILE }
if (-not $CadHome) { Write-Output '[FATAL] 找不到 Cadence 用户目录, 用 -CadHome 指定'; exit 3 }

$pcbenv = Join-Path $CadHome 'pcbenv'
$ilinit = Join-Path $pcbenv 'allegro.ilinit'

Write-Output '==============================================================='
Write-Output "APTools root : $root"
Write-Output "CadHome      : $CadHome"
Write-Output "ilinit       : $ilinit"
Write-Output '==============================================================='

# 自检: 必需文件在不在
foreach ($f in 'skill\APTools_Menu.il', 'skill\APTools_Load.il', 'SkillCode') {
    $p = Join-Path $root $f
    if (-not (Test-Path -LiteralPath $p)) { Write-Output "[FATAL] 缺文件/目录: $p"; exit 3 }
}

# --- 1) 环境变量 -----------------------------------------------------------
[Environment]::SetEnvironmentVariable('APTools', $root, 'User')
$env:APTools = $root
Write-Output ("[ok] 环境变量 APTools(User) = " + [Environment]::GetEnvironmentVariable('APTools', 'User'))

# --- 2) ilinit -------------------------------------------------------------
if (-not (Test-Path -LiteralPath $pcbenv)) {
    Write-Output "[warn] $pcbenv 不存在, 创建"
    New-Item -ItemType Directory -Force -Path $pcbenv | Out-Null
}

$line = 'loadi(strcat(getShellEnvVar("APTools") "\\skill\\APTools_Menu.il"))'

if (Test-Path -LiteralPath $ilinit) {
    $txt = [System.IO.File]::ReadAllText($ilinit, [System.Text.Encoding]::UTF8)
    if ($txt -match 'APTools_Menu\.il') {
        Write-Output '[skip] allegro.ilinit 里已有 APTools 加载行, 不重复追加'
    } else {
        $bak = "$ilinit.bak_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $ilinit -Destination $bak -Force
        Write-Output "[bak] $bak"
        $add = "`r`n; ---- APTools 自建 SKILL 工具集 ----`r`n$line`r`n"
        [System.IO.File]::AppendAllText($ilinit, $add, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output '[ok] 已追加加载行'
    }
} else {
    $add = "; ---- APTools 自建 SKILL 工具集 ----`r`n$line`r`n"
    [System.IO.File]::WriteAllText($ilinit, $add, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output '[ok] 新建 allegro.ilinit'
}

Write-Output ''
Write-Output '---- 现在 ilinit 的内容 ----'
Get-Content -LiteralPath $ilinit -Encoding UTF8 | ForEach-Object { Write-Output $_ }
Write-Output ''
Write-Output '安装完成, 重启 Allegro 生效。'
Write-Output '启动后命令行应出现 [APTools] ... 字样, menubar 右端会出现 APTools 菜单。'
exit 0
