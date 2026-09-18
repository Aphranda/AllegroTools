# run_locator_holes.ps1 -- 批量还原 Allegro 封装库里的连接器"定位孔"
# ===========================================================================
# 问题
#   嘉立创(EasyEDA) -> AD -> Allegro 之后, 连接器的机械定位孔(定位柱孔)不是焊盘,
#   而是画在 DOCUMENT_LAYER 上的一圈闭合线, 结果被搬成了
#       PACKAGE GEOMETRY/DOCUMENT_LAYER 上的 path 图形
#   钻孔/铣槽文件里因此没有这些孔 —— 表现为"封装没有定位孔"。
#
# 识别规则(两根信号同时满足才认定)
#   A. DOCUMENT 类图层上有一圈"闭合且近似圆"的线;
#   B. 同一圆心处有 ROUTE KEEPOUT/ALL。
#
# 处理动作
#   取闭合线的"外轮廓"(中心线 + 半个线宽, 即 Z-Copy 的 enlarge 语义)作为
#   BOARD GEOMETRY/CUTOUT 上的圆形 shape。
#
# 用法
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_locator_holes.ps1
#   powershell ... -File run_locator_holes.ps1 -Action fix
#   powershell ... -File run_locator_holes.ps1 -Action fix -Only "rj45*"
#
# 安全
#   * scan 不写任何库文件
#   * fix 默认先整库复制一份到 <repo>\Allegro\_lib_backup_<时间戳>\ (-NoBackup 可关)
#   * 只结束"本次自己启动"的 Allegro 进程, 不会动用户已打开的 Allegro
# ===========================================================================
[CmdletBinding()]
param(
    [ValidateSet('scan', 'fix')][string]$Action = 'scan',
    [string]$LibDir = '',
    [string]$AllegroRoot = '',
    [string]$Targets = 'DOCUMENT',
    [string]$KeepoutPat = 'KEEPOUT',
    [string]$OutLayer = 'BOARD GEOMETRY/CUTOUT',
    [double]$MinDiaMM = 0.3,
    [double]$MaxDiaMM = 8.0,
    [string]$Only = '*',
    [switch]$DeleteOriginal,
    [switch]$NoKeepoutRequired,
    [switch]$NoBackup,
    [switch]$NoCreateSym,
    [switch]$InSession,
    [switch]$NoGraph,
    [int]$MinutesPerFile = 3,
    [int]$MinutesTotal = 40
)

$ErrorActionPreference = 'Continue'
$kitDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo   = Split-Path -Parent (Split-Path -Parent $kitDir)

if (-not $LibDir) { $LibDir = Join-Path $repo 'Allegro\lib' }
$LibDir = (Resolve-Path -LiteralPath $LibDir).Path
$ilFile = Join-Path $kitDir 'alt2a_locator_hole.il'
if (-not (Test-Path -LiteralPath $ilFile)) { Write-Output "[FATAL] 找不到 $ilFile"; exit 3 }

# ---------------------------------------------------------------- 探测 Allegro
if (-not $AllegroRoot) {
    $envJson = Join-Path $kitDir '_locatorhole_env.json'
    try {
        & (Join-Path $kitDir 'find_allegro.ps1') -OutJson $envJson | Out-Null
        if (Test-Path $envJson) {
            $info = Get-Content $envJson -Raw | ConvertFrom-Json
            if ($info.found) { $AllegroRoot = [string]$info.root }
        }
    } catch { }
}
if (-not $AllegroRoot) { Write-Output '[FATAL] 没找到 Allegro 环境 (用 -AllegroRoot 指定)'; exit 3 }
$allegroExe = Join-Path $AllegroRoot 'tools\bin\allegro.exe'
$createSym  = Join-Path $AllegroRoot 'tools\bin\create_sym.exe'
if (-not (Test-Path -LiteralPath $allegroExe)) { Write-Output "[FATAL] 缺 allegro.exe: $allegroExe"; exit 3 }

function ToPosix([string]$p) { return ($p -replace '\\', '/') }

Write-Output '==============================================================='
Write-Output "LibDir      : $LibDir"
Write-Output "Allegro     : $AllegroRoot"
Write-Output "Action      : $Action"
Write-Output "Targets     : $Targets     Keepout: $KeepoutPat     Out: $OutLayer"
Write-Output "Dia         : $MinDiaMM ~ $MaxDiaMM mm     Only: $Only"
Write-Output '==============================================================='

# ---------------------------------------------------------------- 工作目录
$work = Join-Path $repo 'AllegroTools\Temp\locatorhole_run'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $work | Out-Null
$reportTxt = Join-Path $work 'report.txt'
$reportCsv = Join-Path $work 'report.csv'
$modified  = Join-Path $work 'modified.txt'
$doneFile  = Join-Path $work 'done.txt'
$scr       = Join-Path $work 'run_one.scr'

# ---------------------------------------------------------------- 备份
if ($Action -eq 'fix' -and -not $NoBackup) {
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bakDir = Join-Path $repo ("Allegro\_lib_backup_$stamp")
    Write-Output "[bak] 备份 $LibDir -> $bakDir"
    New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
    Copy-Item -Path (Join-Path $LibDir '*') -Destination $bakDir -Recurse -Force -ErrorAction Continue
    Write-Output ("[bak] 完成, " + (Get-ChildItem $bakDir -Recurse -File | Measure-Object).Count + ' 个文件')
}

# ---------------------------------------------------------------- .scr (只生成一次)
# 最后一个 skill 表达式写一个"完成标记"文件; 驱动靠它判断本次 Allegro 是否跑完
# (allegro.exe 会重新拉起子进程, 单靠 PID 判断不可靠)
Set-Content -LiteralPath $scr -Encoding ASCII -Value @(
    ('skill load("{0}")'                          -f (ToPosix $ilFile)),
    ('skill alt2a_cfgset(''targets (list "{0}"))' -f $Targets),
    ('skill alt2a_cfgset(''keepoutPat "{0}")'     -f $KeepoutPat),
    ('skill alt2a_cfgset(''outLayer "{0}")'       -f $OutLayer),
    ('skill alt2a_cfgset(''requireKeepout {0})'   -f $(if ($NoKeepoutRequired) { 'nil' } else { 't' })),
    ('skill alt2a_cfgset(''minDiaMM {0})'         -f $MinDiaMM),
    ('skill alt2a_cfgset(''maxDiaMM {0})'         -f $MaxDiaMM),
    ('skill alt2a_cfgset(''deleteOriginal {0})'   -f $(if ($DeleteOriginal) { 't' } else { 'nil' })),
    ('skill alt2a_cfgset(''report "{0}")'         -f (ToPosix $reportTxt)),
    ('skill alt2a_cfgset(''csv "{0}")'            -f (ToPosix $reportCsv)),
    ('skill alt2a_cfgset(''modified "{0}")'       -f (ToPosix $modified)),
    ('skill (alt2a_run "{0}")'                    -f $Action),
    ('skill (let (p) (setq p (outfile "{0}" "w")) (when p (fprintf p "ok\n") (close p)))' -f (ToPosix $doneFile)),
    'exit'
)
Write-Output "[scr] $scr"

# ---------------------------------------------------------------- 环境
$env:CDSROOT = $AllegroRoot
$env:PATH    = (Join-Path $AllegroRoot 'tools\bin') + ';' + $env:PATH
$env:PADPATH = $LibDir + ';' + $env:PADPATH
$env:PSMPATH = $LibDir + ';' + $env:PSMPATH

# ---------------------------------------------------------------- 逐个 .dra 处理
$files = @(Get-ChildItem -LiteralPath $LibDir -Filter '*.dra' -File)
if ($Only -ne '*') {
    $pats = @($Only -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($pats.Count -gt 0) {
        $files = @($files | Where-Object {
            $n = $_.Name
            $hit = $false
            foreach ($p in $pats) { if ($n -like $p) { $hit = $true } }
            $hit
        })
    }
}
Write-Output ("[run] 待处理 .dra: " + $files.Count + " 个")

# 把 -Only 的 glob 转成 SKILL 正则列表(单会话模式用; 小写匹配文件名)
$onlySkill = ''
if ($Only -ne '*') {
    $pats = @($Only -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($pats.Count -gt 0) {
        $rx = @($pats | ForEach-Object {
            $s = $_ -replace '([.\\+?^$()\[\]{}|])', '\$1'
            $s = $s -replace '\*', '.*'
            $s.ToLower()
        })
        $onlySkill = (($rx | ForEach-Object { '"' + $_ + '"' }) -join ' ')
        Write-Output ("[run] 单会话过滤 only = " + $onlySkill)
    }
}

$i = 0
$done = 0
$failed = 0

if ($InSession) {
    # ================================================================
    # 单会话模式: 只开一次 Allegro, 在同一个会话里连跑整个库
    #   * 配合 -NoGraph 完全不显示窗口, 不干扰办公
    #   * axlOpenDesign 用 ?mode "wl" + ?ignoreLock t, 不产生 .lck 也不被 .lck 卡住
    # ================================================================
    $scr2 = Join-Path $work 'run_lib.scr'
    Set-Content -LiteralPath $scr2 -Encoding ASCII -Value @(
        ('skill load("{0}")'                          -f (ToPosix $ilFile)),
        ('skill alt2a_cfgset(''targets (list "{0}"))' -f $Targets),
        ('skill alt2a_cfgset(''keepoutPat "{0}")'     -f $KeepoutPat),
        ('skill alt2a_cfgset(''outLayer "{0}")'       -f $OutLayer),
        ('skill alt2a_cfgset(''requireKeepout {0})'   -f $(if ($NoKeepoutRequired) { 'nil' } else { 't' })),
        ('skill alt2a_cfgset(''minDiaMM {0})'         -f $MinDiaMM),
        ('skill alt2a_cfgset(''maxDiaMM {0})'         -f $MaxDiaMM),
        ('skill alt2a_cfgset(''deleteOriginal {0})'   -f $(if ($DeleteOriginal) { 't' } else { 'nil' })),
        ('skill alt2a_cfgset(''report "{0}")'         -f (ToPosix $reportTxt)),
        ('skill alt2a_cfgset(''csv "{0}")'            -f (ToPosix $reportCsv)),
        ('skill alt2a_cfgset(''modified "{0}")'       -f (ToPosix $modified)),
        ('skill alt2a_cfgset(''only {0}))'            -f $(if ($onlySkill) { "(list $onlySkill)" } else { 'nil' })),
        ('skill (alt2a_librun "{0}" "{1}")'           -f (ToPosix $LibDir), $Action),
        ('skill (let (p) (setq p (outfile "{0}" "w")) (when p (fprintf p "ok\n") (close p)))' -f (ToPosix $doneFile)),
        'exit'
    )
    Write-Output "[scr] $scr2"

    $argl = @('-s', ('"' + $scr2 + '"'))
    if ($NoGraph)  { $argl += '-nograph' }
    if ($Action -eq 'scan') { $argl += '-readonly' }

    Remove-Item -LiteralPath $doneFile -Force -ErrorAction SilentlyContinue
    $pre = @(Get-Process allegro -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    Write-Output ("[run] 单会话启动 Allegro (nograph=$($NoGraph.IsPresent), readonly=$($Action -eq 'scan')) ...")
    Start-Process -FilePath $allegroExe -ArgumentList $argl -WorkingDirectory $LibDir | Out-Null

    $maxSec = $MinutesTotal * 60
    $elapsed = 0
    while ($elapsed -lt $maxSec) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        if (Test-Path -LiteralPath $doneFile) { break }
        if (($elapsed % 60) -eq 0) { Write-Output ("[t] ${elapsed}s ...") }
    }
    if (Test-Path -LiteralPath $doneFile) {
        Write-Output ("[run] 单会话完成, 用时约 ${elapsed}s")
        $done = $files.Count
    } else {
        Write-Output "[run] !! 超时(未出现完成标记), 结束本次启动的 Allegro"
        $new = @(Get-Process allegro -ErrorAction SilentlyContinue | Where-Object { $pre -notcontains $_.Id })
        Write-Output "[warn] 超时. 未结束任何 Allegro 进程(避免误杀你自己开的会话), 请自行确认。"
        $failed = 1
    }
} else {

foreach ($f in $files) {
    $i++
    $dra = $f.FullName
    Remove-Item -LiteralPath (Join-Path $LibDir ($f.BaseName + '.dra.lck')) -Force -ErrorAction SilentlyContinue

    Write-Output ("[{0}/{1}] {2}" -f $i, $files.Count, $f.Name)

    Remove-Item -LiteralPath $doneFile -Force -ErrorAction SilentlyContinue
    $pre = @(Get-Process allegro -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    Start-Process -FilePath $allegroExe -ArgumentList '-s', ('"' + $scr + '"'), ('"' + $dra + '"') `
                  -WorkingDirectory $LibDir | Out-Null

    # 等"完成标记"文件出现; 出现即表示这张图已经处理完并 exit
    $maxSec = $MinutesPerFile * 60
    $elapsed = 0
    while ($elapsed -lt $maxSec) {
        Start-Sleep -Seconds 3
        $elapsed += 3
        if (Test-Path -LiteralPath $doneFile) { break }
    }
    if (Test-Path -LiteralPath $doneFile) {
        $done++
    } else {
        Write-Output "        !! 超时(未出现完成标记), 结束本次启动的 Allegro"
        $new = @(Get-Process allegro -ErrorAction SilentlyContinue |
                 Where-Object { $pre -notcontains $_.Id })
        Write-Output "[warn] 超时. 未结束任何 Allegro 进程(避免误杀你自己开的会话), 请自行确认。"
        $failed++
    }
    # 清理本次可能残留的锁
    Remove-Item -LiteralPath (Join-Path $LibDir ($f.BaseName + '.dra.lck')) -Force -ErrorAction SilentlyContinue
}

}   # end of: if ($InSession) { ... } else { 逐文件 }

# ---------------------------------------------------------------- 报告
Write-Output ''
Write-Output '========================= 结果 ========================='
if (Test-Path -LiteralPath $reportTxt) {
    Get-Content -LiteralPath $reportTxt -Encoding UTF8 | ForEach-Object { Write-Output $_ }
} else {
    Write-Output "[warn] 没生成报告: $reportTxt"
}
Write-Output ("处理完成: 正常 " + $done + " 个, 超时/异常 " + $failed + " 个")
if (Test-Path -LiteralPath $reportCsv) { Write-Output "[csv] $reportCsv" }

# ---------------------------------------------------------------- 重编译 .psm
if ($Action -eq 'fix' -and -not $NoCreateSym) {
    Write-Output ''
    Write-Output '===================== create_sym 重编译 .psm ====================='
    $names = @()
    if (Test-Path -LiteralPath $modified) {
        $names = @(Get-Content -LiteralPath $modified | Where-Object { $_.Trim() -ne '' } |
                   ForEach-Object { $_.Trim() } | Select-Object -Unique)
    }
    if ($names.Count -eq 0) {
        Write-Output '[warn] 没有被修改的符号, 跳过 create_sym'
    } else {
        # 等 Allegro 真正退出再编译: 完成标记是在 exit 之前写的, 此时 .dra 可能仍被占用,
        # create_sym 会"静默失败但返回 0"(实测踩过), 所以必须先等进程消失
        $w = 60
        while ($w -gt 0) {
            if (@(Get-Process allegro -ErrorAction SilentlyContinue).Count -eq 0) { break }
            Start-Sleep -Seconds 2
            $w -= 2
        }
        if ($w -le 0) { Write-Output '[warn] Allegro 仍未退出, create_sym 可能失败' }

        $ok = 0; $bad = 0
        foreach ($n in $names) {
            $dra2 = Join-Path $LibDir ($n + '.dra')
            $psm2 = Join-Path $LibDir ($n + '.psm')
            if (-not (Test-Path -LiteralPath $dra2)) { Write-Output "  [skip] 缺文件 $dra2"; $bad++; continue }

            $doneOne = $false
            for ($try = 1; $try -le 2 -and -not $doneOne; $try++) {
                $out = & $createSym '-p' $dra2 2>&1
                Start-Sleep -Milliseconds 500
                # 用"psm 是否比 dra 新"判定真的编译成功, 不能只看退出码
                if ((Test-Path -LiteralPath $psm2) -and
                    ((Get-Item -LiteralPath $psm2).LastWriteTime -ge (Get-Item -LiteralPath $dra2).LastWriteTime)) {
                    Write-Output ("  [ok]   {0}.psm  ({1} bytes)" -f $n, (Get-Item -LiteralPath $psm2).Length)
                    $ok++
                    $doneOne = $true
                } else {
                    Write-Output ("  [retry {0}] {1} : {2}" -f $try, $n, ($out -join ' '))
                    Start-Sleep -Seconds 3
                }
            }
            if (-not $doneOne) { Write-Output "  [fail] $n .psm 未更新"; $bad++ }
        }
        Write-Output "create_sym: 成功 $ok, 失败 $bad"
    }
}

Write-Output ''
Write-Output '提示: 板子已放置的元件需要 Place > Update Symbols 才会带上 CUTOUT。'
exit 0
