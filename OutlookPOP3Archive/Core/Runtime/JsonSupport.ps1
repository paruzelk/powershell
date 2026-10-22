function Read-OPAJsonFile {
    <#
    .SYNOPSIS
        Reads a JSON file with retry/backoff. JSON sidecars (transaction
        checkpoints, DuplicateIndex) can be transiently locked by antivirus
        or indexing; a single-shot read turns that into a spurious failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [ValidateRange(0,10)][int]$Retries = 3,
        [ValidateRange(10,60000)][int]$BaseDelayMs = 200
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file was not found: $Path"
    }

    $lastError = $null
    for ($attempt = 0; $attempt -le $Retries; $attempt++) {
        try {
            $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            if ([string]::IsNullOrWhiteSpace($text)) { throw 'JSON file is empty.' }
            $obj = $text | ConvertFrom-Json
            if ($null -eq $obj) { throw 'JSON document is null.' }
            return $obj
        }
        catch {
            $lastError = $_
            if ($attempt -lt $Retries) {
                Start-Sleep -Milliseconds ([int]($BaseDelayMs * [math]::Pow(2, $attempt)))
            }
        }
    }

    throw "Unable to read JSON file '$Path' after $($Retries + 1) attempt(s): $($lastError.Exception.Message)"
}

function Read-OPAJsonlEntries {
    <#
    .SYNOPSIS
        Shared streaming reader for append-only JSONL journals. At most two
        lines are held in memory at any moment: the current line plus a
        one-line lookahead used only to classify the line as middle vs last.
        Tail mode keeps a bounded ring of the newest entries. Malformed
        middle line is a hard error; malformed last line is tolerated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [long]$FromOffset = 0,
        [int]$TailCount = 0,
        [string]$Context = 'JSONL journal'
    )

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $fs = $null; $reader = $null
    try {
        $fs = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        if ($FromOffset -gt 0 -and $FromOffset -lt $fs.Length) { $fs.Position = $FromOffset }
        $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)

        $list = $null
        $ring = $null
        if ($TailCount -gt 0) {
            $ring = New-Object 'System.Collections.Generic.Queue[object]'
        }
        else {
            $list = New-Object System.Collections.Generic.List[object]
        }

        $lineNo = 0
        $pending = $reader.ReadLine()
        while ($null -ne $pending) {
            $lineNo++
            $next = $reader.ReadLine()
            $isLast = ($null -eq $next)

            $raw = $pending
            $pending = $next

            if ([string]::IsNullOrWhiteSpace($raw)) { continue }

            $parsed = $null
            try { $parsed = ConvertFrom-Json -InputObject $raw }
            catch {
                if ($isLast) {
                    Write-Warning ("{0} '{1}': last line is malformed ({2} chars), skipping." -f $Context, $Path, $raw.Length)
                    continue
                }
                $preview = if ($raw.Length -gt 120) { $raw.Substring(0,120) + '...' } else { $raw }
                throw ("{0} '{1}' is corrupted at line {2}. Malformed JSON: {3}" -f $Context, $Path, $lineNo, $preview)
            }
            if ($null -eq $parsed) { continue }

            if ($null -ne $ring) {
                foreach ($el in @($parsed)) {
                    if ($null -ne $el) { [void]$ring.Enqueue($el) }
                    while ($ring.Count -gt $TailCount) { [void]$ring.Dequeue() }
                }
            }
            else {
                if ($parsed -is [System.Array]) {
                    foreach ($el in $parsed) { if ($null -ne $el) { $list.Add($el) | Out-Null } }
                }
                else {
                    $list.Add($parsed) | Out-Null
                }
            }
        }

        if ($null -ne $ring) {
            $arr = New-Object System.Collections.Generic.List[object]
            foreach ($el in $ring) { $arr.Add($el) | Out-Null }
            return $arr.ToArray()
        }
        return $list.ToArray()
    }
    finally {
        if ($reader) { try { $reader.Dispose() } catch {} }
        if ($fs)     { try { $fs.Dispose() } catch {} }
    }
}
