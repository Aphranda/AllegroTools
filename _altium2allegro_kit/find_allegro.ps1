# find_allegro.ps1 - auto-discover a usable Allegro/SPB installation on this PC
# ============================================================================
# Search order:
#   1. explicit -AllegroRoot or env CDSROOT / CDS_INST_DIR / SPB_ROOT / ALLEGRO_ROOT
#   2. allegro.exe found on PATH (walk up to installation root)
#   3. registry HKLM Cadence Design Systems SPB_* entries
#   4. shallow drive scan for SPB_* / Cadence\SPB_* directories
# Every candidate must contain:
#   tools\bin\allegro.exe, share\pcb\etc\context\64bit\translators.cxt,
#   share\pcb\translators\config\altium2pcb.ini  (needed for Altium import)
# Output markers: [ALLEGRO-ROOT] [EXE] [CTX] [INI] [VERDICT]; use -OutJson to
# write a machine readable result for pipeline scripts.
# ============================================================================
param(
    [string]$AllegroRoot = '',
    [string]$OutJson = '',
    [switch]$ListAll
)
$ErrorActionPreference = 'SilentlyContinue'

function Test-Root([string]$root) {
    if (-not $root) { return $null }
    $root = $root.TrimEnd('\')
    $exe = Join-Path $root 'tools\bin\allegro.exe'
    $cxt = Join-Path $root 'share\pcb\etc\context\64bit\translators.cxt'
    $ini = Join-Path $root 'share\pcb\translators\config\altium2pcb.ini'
    if ((Test-Path $exe) -and (Test-Path $cxt) -and (Test-Path $ini)) {
        return [pscustomobject]@{ Root = $root; Exe = $exe; Cxt = $cxt; Ini = $ini; Ok = $true }
    }
    return $null
}

$candidates = [System.Collections.Generic.List[string]]::new()

# 1) explicit / environment
if ($AllegroRoot) { $candidates.Add($AllegroRoot) }
foreach ($v in @('CDSROOT', 'CDS_INST_DIR', 'SPB_ROOT', 'ALLEGRO_ROOT')) {
    $val = [Environment]::GetEnvironmentVariable($v)
    if ($val) { $candidates.Add($val) }
}

# 2) PATH (walk up two levels from tools\bin)
$cmd = Get-Command allegro.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd -and $cmd.Source) {
    $dir = Split-Path (Split-Path $cmd.Source -Parent) -Parent
    $candidates.Add($dir)
}

# 3) registry
$regPaths = @(
    'HKLM:\SOFTWARE\Cadence Design Systems',
    'HKLM:\SOFTWARE\WOW6432Node\Cadence Design Systems'
)
foreach ($rp in $regPaths) {
    if (Test-Path $rp) {
        Get-ChildItem $rp | Where-Object { $_.PSChildName -like 'SPB_*' } | ForEach-Object {
            $val = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            foreach ($p in @($val.InstallPath, $val.INSTDIR, $val.CDSROOT, $val.'Install Dir')) {
                if ($p) { $candidates.Add([string]$p) }
            }
        }
    }
}

# 4) drive scan (shallow)
foreach ($drive in @('D:\', 'C:\', 'E:\', 'F:\')) {
    if (-not (Test-Path $drive)) { continue }
    Get-ChildItem $drive -Directory -Filter 'SPB_*' -ErrorAction SilentlyContinue |
        ForEach-Object { $candidates.Add($_.FullName) }
    foreach ($sub in @('Cadence', 'Cadence Design Systems')) {
        $sp = Join-Path $drive $sub
        if (Test-Path $sp) {
            Get-ChildItem $sp -Directory -Filter 'SPB_*' -ErrorAction SilentlyContinue |
                ForEach-Object { $candidates.Add($_.FullName) }
        }
    }
}

# dedupe + verify
$seen = @{}
$results = @()
foreach ($c in $candidates) {
    if (-not $c) { continue }
    $key = $c.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $r = Test-Root $c
    if ($r) { $results += $r }
}

# order by version (newest first) so the default pick is deterministic
$results = @($results | Sort-Object -Property @{
        Expression = {
            if ($_.Root -match 'SPB_(\d+)\.(\d+)') {
                return [int]$matches[1] * 10000 + [int]$matches[2]
            }
            return 0
        }
    } -Descending)

if ($results.Count -eq 0) {
    Write-Output '[VERDICT] no usable Allegro root found'
    $checked = (($candidates | Select-Object -Unique) -join ' ; ')
    Write-Output ('checked: ' + $checked)
    if ($OutJson) {
        @{ found = $false; candidates = @($candidates | Select-Object -Unique) } |
            ConvertTo-Json -Depth 4 | Set-Content $OutJson
    }
    exit 1
}
foreach ($r in $results) {
    Write-Output ('[ALLEGRO-ROOT] ' + $r.Root)
    Write-Output ('[EXE] ' + $r.Exe)
    Write-Output ('[CTX] ' + $r.Cxt)
    Write-Output ('[INI] ' + $r.Ini)
    Write-Output ("[LIC-ENV] CDS_LIC_FILE='" + $env:CDS_LIC_FILE + "' CDS_LIC_QUEUE='" + $env:CDS_LIC_QUEUE + "'")
}
if ($ListAll) {
    Write-Output ('[VERDICT] found ' + $results.Count + ' candidate(s)')
} else {
    Write-Output ('[VERDICT] ok => ' + $results[0].Root)
}
if ($OutJson) {
    @{
        found = $true
        root  = $results[0].Root
        exe   = $results[0].Exe
        cxt   = $results[0].Cxt
        ini   = $results[0].Ini
        all   = @($results | ForEach-Object { $_.Root })
    } | ConvertTo-Json -Depth 4 | Set-Content $OutJson
}
exit 0
