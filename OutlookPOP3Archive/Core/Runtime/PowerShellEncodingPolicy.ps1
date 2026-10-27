#requires -Version 5.1
# Technical specification TZ-ENC-001: new/changed PowerShell code MUST have UTF-8 BOM.
# Existing 82 BOM-less files are protected by an immutable whole-set checksum.
function Get-OPAPowerShellEncodingInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    if (-not [IO.Directory]::Exists($ProjectRoot)) {
        throw 'Encoding policy: ProjectRoot does not exist.'
    }
    $root=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]@('\','/'))
    $legacy=New-Object 'System.Collections.Generic.List[string]'
    $total=0
    $withBom=0
    $files=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1') })
    $decoder=[Text.UTF8Encoding]::new($false,$true)
    foreach($file in $files) {
        $total++
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Encoding policy: reparse-point PowerShell file rejected: '+$file.FullName)
        }
        $data=[IO.File]::ReadAllBytes($file.FullName)
        $bom=($data.Length -ge 3 -and $data[0] -eq 0xEF -and
            $data[1] -eq 0xBB -and $data[2] -eq 0xBF)
        if ($bom) {
            # Strictly validate the remaining bytes, not just the BOM signature.
            try { [void]$decoder.GetString($data,3,$data.Length-3) }
            catch { throw ('Encoding policy: invalid UTF-8 after BOM: '+$file.FullName) }
            $withBom++
        } else {
            $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
            $fileHash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$legacy.Add(($relative+[char]9+$fileHash))
        }
    }
    $lines=$legacy.ToArray()
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    # Canonical legacy baseline uses UTF-8 of ASCII paths/hash + LF separators,
    # no final newline. Never relies on filesystem enumeration order.
    $joined=[string]::Join([char]10,$lines)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $digest=([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($joined)))).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
    return [pscustomobject]@{
        Schema='TZ-ENC-001.UTF8BOMInventory.1'
        PowerShellFiles=$total
        Utf8BomFiles=$withBom
        LegacyBomlessFiles=$lines.Length
        LegacyBomlessSha256=$digest
        LegacyBomlessRelativePaths=@($lines | ForEach-Object { ($_ -split [char]9)[0] })
    }
}
function Assert-OPAPowerShellEncodingPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [ValidateRange(0,10000)][int]$LegacyCount=82,
        [string]$LegacySha256='ace042f4ab915f2c1bd274685ea0e041e1f94f05c82418bed5a893ae153967ca'
    )
    if ($LegacySha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Encoding policy: invalid trusted legacy snapshot digest.'
    }
    $inventory=Get-OPAPowerShellEncodingInventory -ProjectRoot $ProjectRoot
    if ($inventory.LegacyBomlessFiles -ne $LegacyCount -or
        [string]$inventory.LegacyBomlessSha256 -cne $LegacySha256) {
        throw ('TZ-ENC-001 FAILED: new/modified PowerShell source without UTF-8 BOM, or legacy migration not reviewed. '+
            'Expected legacy files/hash: '+$LegacyCount+'/'+$LegacySha256+
            '; observed: '+$inventory.LegacyBomlessFiles+'/'+$inventory.LegacyBomlessSha256+
            '. Write new/changed *.ps1/*.psm1/*.psd1 in UTF-8 with BOM (EF BB BF).')
    }
    return $inventory
}
