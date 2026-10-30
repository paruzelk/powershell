#requires -Version 5.1
# BW4j: independent suite plan and multi-format read-only witnesses.
# NEVER calls Send, Move, copies customer messages, edits PST or operation journal.
function Get-OPA265BW4jSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-OPA265BW4jTextHash {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Value)
    Get-OPA265BW4jSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($Value))
}
function Get-OPA265BW4jPlanPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,[string]$LocalAppData=$env:LOCALAPPDATA)
    $g=[guid]::Empty
    if (-not [guid]::TryParse($SuiteId,[ref]$g) -or
        $g -eq [guid]::Empty -or $SuiteId -cne $g.ToString('D') -or
        [string]::IsNullOrWhiteSpace($LocalAppData) -or
        -not [IO.Path]::IsPathRooted($LocalAppData)) {
        throw 'BW4j invalid canonical SuiteId or local AppData.'
    }
    Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4j-Suites') ('suite-'+$SuiteId+'.json')
}
function New-OPA265BW4jPlan {
    [CmdletBinding()]
    param()
    $suite=[guid]::NewGuid().ToString('D')
    $cases=New-Object 'System.Collections.Generic.List[object]'
    foreach($name in @('PlainSmall','UnicodePlain','HtmlBody','Attachment1K','Attachment256K')) {
        $tid=[guid]::NewGuid().ToString('D')
        $expectedAttachments=if ($name -like 'Attachment*') {1} else {0}
        $minAttachmentSize=if ($name -eq 'Attachment256K') {262144} elseif($name -eq 'Attachment1K'){1024}else{0}
        $cases.Add([pscustomobject][ordered]@{
            Name=$name
            TestId=$tid
            Subject=('OPA265 BW4j '+$name+' '+$tid)
            Marker=('OPA265 BW4j disposable synthetic test. TestId: '+$tid)
            MinimumAttachmentBytes=[int]$minAttachmentSize
            ExpectedAttachmentCount=[int]$expectedAttachments
        })
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j.SyntheticSuitePlan.1'
        SuiteId=$suite
        CreatedUtc=[datetime]::UtcNow.ToString('o')
        Cases=@($cases.ToArray())
        OnlySynthetic=$true
        AutomaticSendAllowed=$false
        AutomaticMoveAllowed=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4jPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Plan)
    if($Plan -isnot [pscustomobject] -or
        @($Plan.PSObject.Properties.Name).Count -ne 7 -or
        $Plan.Schema -cne '2.6.5-BW4j.SyntheticSuitePlan.1' -or
        $Plan.OnlySynthetic -isnot [bool] -or -not $Plan.OnlySynthetic -or
        $Plan.AutomaticSendAllowed -isnot [bool] -or $Plan.AutomaticSendAllowed -or
        $Plan.AutomaticMoveAllowed -isnot [bool] -or $Plan.AutomaticMoveAllowed -or
        $Plan.ProductionReady -isnot [bool] -or $Plan.ProductionReady) {
        throw 'BW4j invalid exact synthetic suite schema or unsafe capability flag.'
    }
    [void](Get-OPA265BW4jPlanPath -SuiteId ([string]$Plan.SuiteId) -LocalAppData 'C:\Temp')
    $dt=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Plan.CreatedUtc,[ref]$dt)){
        throw 'BW4j plan timestamp invalid.'
    }
    $expected=@('PlainSmall','UnicodePlain','HtmlBody','Attachment1K','Attachment256K')
    $cases=@($Plan.Cases)
    if($cases.Count -ne $expected.Count){throw 'BW4j requires five distinct planned cases.'}
    $ids=@{}
    for($i=0;$i -lt $expected.Count;$i++) {
        $item=$cases[$i]
        $g=[guid]::Empty
        if($item -isnot [pscustomobject] -or
            @($item.PSObject.Properties.Name).Count -ne 6 -or
            $item.Name -cne $expected[$i] -or
            -not [guid]::TryParse([string]$item.TestId,[ref]$g) -or $g -eq [guid]::Empty -or
            [string]$item.TestId -cne $g.ToString('D') -or
            [string]$item.Subject -cne ('OPA265 BW4j '+$expected[$i]+' '+$g.ToString('D')) -or
            [string]$item.Marker -cne ('OPA265 BW4j disposable synthetic test. TestId: '+$g.ToString('D')) -or
            $ids.ContainsKey([string]$item.TestId) -or
            [int]$item.ExpectedAttachmentCount -ne $(if($i -ge 3){1}else{0}) -or
            [int]$item.MinimumAttachmentBytes -ne $(if($i -eq 3){1024}elseif($i -eq 4){262144}else{0})) {
            throw ('BW4j invalid or repeated fixture at index '+$i)
        }
        $ids[[string]$item.TestId]=$true
    }
    return $true
}
function Write-OPA265BW4jOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Object,
          [Parameter(Mandatory=$true)][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or
        $Path.StartsWith('\\',[StringComparison]::Ordinal)) {
        throw 'BW4j requires exact local absolute evidence path.'
    }
    $folder=[IO.Path]::GetDirectoryName($Path)
    if(-not [IO.Directory]::Exists($folder)){[void][IO.Directory]::CreateDirectory($folder)}
    if (([IO.File]::GetAttributes($folder) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW4j evidence parent is a reparse point.'
    }
    $encoding=New-Object Text.UTF8Encoding($true)
    $data=$encoding.GetBytes((ConvertTo-Json -InputObject $Object -Depth 9))
    $bom=$encoding.GetPreamble()
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bom,0,$bom.Length)
        $stream.Write($data,0,$data.Length)
        $stream.Flush($true)
    } finally {if($null -ne $stream){$stream.Dispose()}}
    return $Path
}
function Write-OPA265BW4jPlanOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Plan)
    [void](Assert-OPA265BW4jPlan -Plan $Plan)
    $path=Get-OPA265BW4jPlanPath -SuiteId ([string]$Plan.SuiteId)
    $written=Write-OPA265BW4jOnce -Object $Plan -Path $path
    return [pscustomobject]@{
        Status='SuitePlanCreatedNoMailSentOrMoved'
        SuiteId=$Plan.SuiteId
        PlanPath=$written
        PlanSha256=(Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash.ToLowerInvariant()
        Cases=@($Plan.Cases)
        ProductionReady=$false
    }
}
function Get-OPA265BW4jEvidencePath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $p=Get-OPA265BW4jPlanPath -SuiteId $SuiteId -LocalAppData $LocalAppData
    $g=[guid]::Empty
    if(-not [guid]::TryParse($TestId,[ref]$g) -or $g -eq [guid]::Empty -or
        $TestId -cne $g.ToString('D')) {
        throw 'BW4j evidence needs canonical TestId.'
    }
    Join-Path (Join-Path ([IO.Path]::GetDirectoryName($p)) ('evidence-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}
function Assert-OPA265BW4jFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Case,
          [AllowEmptyString()][string]$Subject,
          [AllowEmptyString()][string]$Body,
          [AllowEmptyString()][string]$HtmlBody,
          [Parameter(Mandatory=$true)][int]$AttachmentCount)
    if($Subject -cne [string]$Case.Subject -or
        $Body -cnotlike ('*'+[string]$Case.Marker+'*') -or
        $AttachmentCount -ne [int]$Case.ExpectedAttachmentCount) {
        throw 'BW4j fixture subject, marker or attachment count differs from exact suite plan.'
    }
    if($Case.Name -ceq 'UnicodePlain' -and $Body -cnotmatch '[\u0400-\u04FF]'){
        throw 'BW4j UnicodePlain missing Cyrillic test content.'
    }
    if($Case.Name -ceq 'HtmlBody' -and
        $HtmlBody -cnotmatch '(?i)<html\b|<body\b') {
        throw 'BW4j HtmlBody fixture missing HTML representation.'
    }
    return $true
}
