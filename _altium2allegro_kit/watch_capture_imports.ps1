# watch_capture_imports.ps1 - monitor/validate manual per-sheet Altium->OrCAD X imports
# ================================================================================
# Context: OrCAD X "Altium Schematic Translator" is GUI-only (no CLI). You import
# each ASCII .SchDoc manually; this helper watches the output folder, validates
# each produced .DSN, tracks progress and writes a report.
#
# Expected per sheet: <SheetName>.DSN in -OutDir (plus shared ORCAD_LIBRARY.OLB).
#
# Usage:
#   powershell -File watch_capture_imports.ps1 -OneShot                       # scan once, print status
#   powershell -File watch_capture_imports.ps1 -Interval 15 -Minutes 120      # watch 2h
#   powershell -File watch_capture_imports.ps1 -OneShot -JsonReport state.json
# ================================================================================
param(
    [string]$SchDir = 'F:\1.Hardware\GTS_PPA1\06.SYNC_TRIG\Altium_RP2350-PICO-BaseBoard_2026-09-08\RP2350-PICO-BaseBoard\CTL-SYNCTRIG4F4-HASL\CTL-SYNCTRIG4F4-HASL',
    [string]$OutDir = '',
    [int]$Interval = 10,
    [int]$Minutes = 0,
    [switch]$OneShot,
    [string]$StateFile = '',
    [string]$JsonReport = ''
)
$ErrorActionPreference = 'Continue'
if (-not $OutDir) { $OutDir = Join-Path $SchDir 'out' }
if (-not $StateFile) { $StateFile = Join-Path $SchDir 'capture_import_state.json' }

$expected = @(Get-ChildItem $SchDir -Filter '*.schdoc' -File -ErrorAction SilentlyContinue |
    ForEach-Object { $_.BaseName } | Sort-Object)
$done = @{}
if (Test-Path $StateFile) {
    try {
        $prev = Get-Content $StateFile -Raw | ConvertFrom-Json
        foreach ($n in @($prev.done)) { $done[$n] = $true }
    } catch { }
}
function Save-State {
    $all = @()
    foreach ($e in $expected) { if ($done.ContainsKey($e)) { $all += $e } }
    $missing = @($expected | Where-Object { -not $done.ContainsKey($_) })
    $obj = @{ total = $expected.Count; done = $all; remaining = $missing;
              outdir = $OutDir; updated = (Get-Date).ToString('s') }
    $obj | ConvertTo-Json -Depth 3 | Set-Content $StateFile
    if ($JsonReport) { $obj | ConvertTo-Json -Depth 3 | Set-Content $JsonReport }
    return $obj
}
function Show-Status {
    $obj = Save-State
    Write-Output ("[STATUS] done=" + $obj.done.Count + "/" + $obj.total)
    if ($obj.done.Count -gt 0) { Write-Output ("[DONE]   " + ($obj.done -join ', ')) }
    Write-Output ("[TODO]   " + ($obj.remaining -join ', '))
    return $obj
}

$deadline = if ($Minutes -gt 0) { (Get-Date).AddMinutes($Minutes) } else { $null }
$lastSig = ''
$changed = $false
do {
    $changed = $false
    foreach ($s in $expected) {
        if ($done.ContainsKey($s)) { continue }
        $dsn = Join-Path $OutDir ($s + '.DSN')
        if (Test-Path $dsn) {
            $len = (Get-Item $dsn).Length
            if ($len -gt 0) {
                $done[$s] = $true
                $changed = $true
                Write-Output ("[NEW] " + $s + ".DSN  " + $len + " bytes @" + (Get-Date).ToString('HH:mm:ss'))
            }
        }
    }
    if ($changed) { Show-Status | Out-Null }
    if ($OneShot) { break }
    Start-Sleep -Seconds $Interval
} while (-not $deadline -or (Get-Date) -lt $deadline)

$obj = Show-Status
Write-Output ("[STATE] " + $StateFile)
if ($obj.remaining.Count -eq 0) { Write-Output '[ALL-DONE] every schematic page has a .DSN output' }
