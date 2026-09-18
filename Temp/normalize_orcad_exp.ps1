param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath
)

if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($InputPath),
        ([System.IO.Path]::GetFileNameWithoutExtension($InputPath) + '_normalized.EXP')
    )
}

$encoding = [System.Text.Encoding]::Default
$lines = [System.IO.File]::ReadAllLines($InputPath, $encoding)
if ($lines.Count -lt 2) {
    throw 'The EXP file does not contain a header.'
}

function Get-Fields([string]$line) {
    return $line.Split([char]9)
}

function Get-Value([string]$field) {
    if ($field.Length -ge 2 -and $field[0] -eq '"' -and $field[$field.Length - 1] -eq '"') {
        return $field.Substring(1, $field.Length - 2).Replace('""', '"')
    }
    return $field
}

function Set-Value([string]$value) {
    if ($null -eq $value) {
        $value = ''
    }
    return '"' + $value.Replace('"', '""') + '"'
}

$headers = Get-Fields $lines[1] | ForEach-Object { Get-Value $_ }
$index = @{}
for ($i = 0; $i -lt $headers.Count; $i++) {
    if (-not $index.ContainsKey($headers[$i])) {
        $index[$headers[$i]] = $i
    }
}

foreach ($required in @('Device', 'Source Library', 'Source Package', 'Source Part')) {
    if (-not $index.ContainsKey($required)) {
        throw "Required column not found: $required"
    }
}

$deviceIndex = $index['Device']
$libraryIndex = $index['Source Library']
$packageIndex = $index['Source Package']
$partIndex = $index['Source Part']
$canonical = @{}
$output = New-Object System.Collections.Generic.List[string]
$output.Add($lines[0])
$output.Add($lines[1])
$changed = 0
$skipped = 0

for ($lineNumber = 2; $lineNumber -lt $lines.Count; $lineNumber++) {
    $fields = Get-Fields $lines[$lineNumber]
    if ($fields.Count -ne $headers.Count) {
        $skipped++
        $output.Add($lines[$lineNumber])
        continue
    }

    $device = Get-Value $fields[$deviceIndex]
    $library = Get-Value $fields[$libraryIndex]
    $sourcePackage = Get-Value $fields[$packageIndex]
    $sourcePart = Get-Value $fields[$partIndex]

    if ([string]::IsNullOrWhiteSpace($device) -or $device -eq '<null>' -or
        [string]::IsNullOrWhiteSpace($sourcePart) -or $sourcePart -eq '<null>') {
        $output.Add($lines[$lineNumber])
        continue
    }

    $key = $device + "`0" + $library
    if (-not $canonical.ContainsKey($key)) {
        $canonical[$key] = [pscustomobject]@{
            Package = $sourcePackage
            Part = $sourcePart
        }
    }
    else {
        $reference = $canonical[$key]
        if ($sourcePart -ne $reference.Part -or $sourcePackage -ne $reference.Package) {
            $fields[$packageIndex] = Set-Value $reference.Package
            $fields[$partIndex] = Set-Value $reference.Part
            $changed++
        }
    }

    $output.Add(($fields -join [char]9))
}

[System.IO.File]::WriteAllLines($OutputPath, $output, $encoding)
Write-Output "Output: $OutputPath"
Write-Output "Groups: $($canonical.Count)"
Write-Output "Rows changed: $changed"
Write-Output "Rows skipped due to field count: $skipped"
