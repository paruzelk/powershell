# Worker protocol 1.0 — standalone, deliberately independent of transaction
# journals and OutlookPOP3Archive.ps1. Compatible with Windows PowerShell 5.1.
$script:OPAWorkerProtocolVersion = '1.0'
$script:OPAWorkerAllowedOperations = @('Ping','Echo','Fail','Crash','Delay','ProbeOutlook','ProbeSyntheticPstReadOnly')

function Assert-OPAWorkerRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)

    if ($null -eq $Request -or $Request -is [string]) { throw 'Worker protocol: request must be a JSON object.' }
    $keys = @($Request.PSObject.Properties.Name)
    foreach ($required in @('ProtocolVersion','RequestId','Operation','Payload','CreatedUtc')) {
        if ($keys -cnotcontains $required) { throw "Worker protocol: required field '$required' is missing." }
    }
    if ([string]$Request.ProtocolVersion -cne $script:OPAWorkerProtocolVersion) {
        throw "Worker protocol: unsupported version '$($Request.ProtocolVersion)'."
    }
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse([string]$Request.RequestId, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw 'Worker protocol: RequestId must be a nonempty GUID.'
    }
    if ([string]$Request.Operation -cnotin $script:OPAWorkerAllowedOperations) {
        throw "Worker protocol: operation '$($Request.Operation)' is not allowed."
    }
    if ($null -eq $Request.Payload -or $Request.Payload -is [string] -or $Request.Payload -is [array]) {
        throw 'Worker protocol: Payload must be a JSON object.'
    }
    $time = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Request.CreatedUtc, [ref]$time)) {
        throw 'Worker protocol: CreatedUtc is invalid.'
    }
    return $true
}

function New-OPAWorkerRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Ping','Echo','Fail','Crash','Delay','ProbeOutlook','ProbeSyntheticPstReadOnly')][string]$Operation,
        [object]$Payload = @{},
        [string]$RequestId = ''
    )
    if ($null -eq $Payload -or $Payload -is [string] -or $Payload -is [array]) {
        throw 'Worker protocol: Payload must be a JSON object.'
    }
    $request = [pscustomobject]@{
        ProtocolVersion = $script:OPAWorkerProtocolVersion
        RequestId       = $(if ([string]::IsNullOrWhiteSpace($RequestId)) { [guid]::NewGuid().ToString('D') } else { $RequestId })
        Operation       = $Operation
        Payload         = $Payload
        CreatedUtc      = [datetime]::UtcNow.ToString('o')
    }
    [void](Assert-OPAWorkerRequest -Request $request)
    return $request
}

function Assert-OPAWorkerResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Response,
        [Parameter(Mandatory=$true)][object]$Request
    )
    $fields = @($Response.PSObject.Properties.Name)
    foreach ($required in @('ProtocolVersion','RequestId','Operation','Status','WorkerProcessId','ApartmentState','Result','Error','StartedUtc','FinishedUtc')) {
        if ($fields -cnotcontains $required) { throw "Worker protocol: response missing '$required'." }
    }
    if ([string]$Response.ProtocolVersion -cne $script:OPAWorkerProtocolVersion) { throw 'Worker protocol: response version mismatch.' }
    if ([string]$Response.RequestId -cne [string]$Request.RequestId) { throw 'Worker protocol: response RequestId mismatch.' }
    if ([string]$Response.Operation -cne [string]$Request.Operation) { throw 'Worker protocol: response Operation mismatch.' }
    if ([string]$Response.Status -cnotin @('Succeeded','Failed')) { throw 'Worker protocol: invalid response Status.' }
    if ([int]$Response.WorkerProcessId -le 0) { throw 'Worker protocol: missing process ID.' }
    if ([string]$Response.ApartmentState -cne 'STA') { throw 'Worker protocol: response apartment must be STA.' }
    $startedAt = [datetime]::MinValue
    $finishedAt = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Response.StartedUtc, [ref]$startedAt) -or
        -not [datetime]::TryParse([string]$Response.FinishedUtc, [ref]$finishedAt) -or
        $finishedAt -lt $startedAt) {
        throw 'Worker protocol: response timestamps are invalid or reversed.'
    }
    if ([string]$Response.Status -ceq 'Failed' -and [string]::IsNullOrWhiteSpace([string]$Response.Error)) {
        throw 'Worker protocol: failed response must include an error.'
    }
    return $true
}

function Write-OPAWorkerJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Value
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Worker protocol: directory does not exist: '$directory'."
    }
    $temporary = $fullPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $json = ConvertTo-Json -InputObject $Value -Depth 12
    try {
        [IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $fullPath) { throw "Worker protocol: output already exists: '$fullPath'." }
        [IO.File]::Move($temporary, $fullPath)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Read-OPAWorkerJson {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Worker protocol: JSON file missing: '$Path'." }
    $text = [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Worker protocol: empty JSON file: '$Path'." }
    try { return ConvertFrom-Json -InputObject $text -ErrorAction Stop }
    catch { throw "Worker protocol: malformed JSON in '$Path': $($_.Exception.Message)" }
}
