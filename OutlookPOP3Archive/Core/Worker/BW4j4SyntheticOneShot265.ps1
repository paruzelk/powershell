#requires -Version 5.1
# BW4j4 isolated on-disk SYNTHETIC ONLY. No Outlook COM, PST, Send or MailItem.Move.
. (Join-Path $PSScriptRoot 'BW4jSuitePlan265.ps1')
function Assert-OPA265BW4j4SandboxRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot,
          [switch]$AllowCreate)
    if(-not [IO.Path]::IsPathRooted($SandboxRoot) -or
        $SandboxRoot.StartsWith('\\',[StringComparison]::Ordinal)) {
        throw 'BW4j4 sandbox must be a local absolute path.'
    }
    $root=[IO.Path]::GetFullPath($SandboxRoot).TrimEnd([char[]]@('\','/'))
    if([IO.Path]::GetFileName($root) -cnotmatch '^OPA265-BW4j6-SYNTH-[a-f0-9]{32}$' -or
        $root -match '(?i)[\\/]Файлы Outlook[\\/]|[\\/]OutlookPOP3Archive-BW4g-Claims[\\/]' -or
        $root -match '(?i)\.pst([\\/]|$)') {
        throw 'BW4j4 requires isolated specifically named synthetic-only directory.'
    }
    $parent=[IO.Path]::GetDirectoryName($root)
    if(-not [IO.Directory]::Exists($parent) -or
       (([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'BW4j4 sandbox parent must be real local directory, not a junction.'
    }
    if([IO.Directory]::Exists($root)){
        if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'BW4j4 sandbox itself cannot be junction/symlink.'
        }
    } elseif(-not $AllowCreate){throw 'BW4j4 sandbox not initialized.'}
    return $root
}
function Write-OPA265BW4j4JsonOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][object]$Value)
    if([IO.File]::Exists($Path)){throw 'BW4j4 immutable evidence already exists.'}
    $encoding=New-Object Text.UTF8Encoding($true)
    $bytes=$encoding.GetBytes((ConvertTo-Json -InputObject $Value -Depth 12))
    $bom=$encoding.GetPreamble()
    $stream=$null
    try{
        $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bom,0,$bom.Length)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }finally{if($null -ne $stream){$stream.Dispose()}}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-OPA265BW4j4FileSha {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not [IO.File]::Exists($Path) -or
       (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'BW4j4 required synthetic evidence file absent or symlinked.'
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-OPA265BW4j4Paths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root,
          [Parameter(Mandatory=$true)][string]$TestId)
    $g=[guid]::Empty
    if(-not [guid]::TryParse($TestId,[ref]$g) -or
       $g -eq [guid]::Empty -or $TestId -cne $g.ToString('D')) {
        throw 'BW4j4 requires canonical TestId.'
    }
    [pscustomobject]@{
        Source=(Join-Path (Join-Path $Root 'source') ($TestId+'.json'))
        Target=(Join-Path (Join-Path $Root 'destination') ($TestId+'.json'))
        Claim=(Join-Path (Join-Path $Root 'claims') ($TestId+'.json'))
        Receipt=(Join-Path (Join-Path $Root 'receipts') ($TestId+'.json'))
    }
}
function New-OPA265BW4j4Fixture {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][string]$SuiteId)
    $body=[string]$Case.Marker+' -- synthetic no customer data'
    if($Case.Name -ceq 'UnicodePlain'){$body+=' Привет мир — проверка Unicode.'}
    $html=if($Case.Name -ceq 'HtmlBody'){'<html><body><strong>'+[string]$Case.Marker+'</strong></body></html>'}else{'<html><body>'+[string]$Case.Marker+'</body></html>'}
    $attachments=New-Object 'System.Collections.Generic.List[object]'
    if([int]$Case.ExpectedAttachmentCount -eq 1){
        $n=[int]$Case.MinimumAttachmentBytes
        if($n -gt 262144 -or $n -lt 1024){throw 'BW4j4 unexpected attachment size.'}
        $bytes=New-Object byte[] $n
        for($i=0;$i -lt $n;$i++){$bytes[$i]=[byte](($i*31+17) % 256)}
        $attachments.Add([pscustomobject][ordered]@{
            FileName=([string]$Case.Name+'.bin')
            BytesBase64=[Convert]::ToBase64String($bytes)
            ByteCount=$n
            Sha256=(Get-OPA265BW4jSha256 -Bytes $bytes)
        })
    }
    $index=@('PlainSmall','UnicodePlain','HtmlBody','Attachment1K','Attachment256K').IndexOf([string]$Case.Name)
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j4.IndependentSyntheticMail.1'
        SuiteId=$SuiteId
        TestId=[string]$Case.TestId
        CaseName=[string]$Case.Name
        SourceEntryId='SYNTH-SRC-'+[string]$Case.TestId
        DestinationEntryId='SYNTH-DEST-'+[string]$Case.TestId
        InternetMessageId=('<'+$Case.TestId+'@bw4j.synthetic.invalid>')
        Subject=[string]$Case.Subject
        SenderEmailAddress='synthetic@bw4j.invalid'
        Body=$body
        HtmlBody=$html
        ReceivedUtcTicks=[long](639289630550000000 + $index*10000000)
        SourceSize=[long](8760 + $index*4096)
        InjectedDestinationSizeDelta=[long]38
        Attachments=@($attachments.ToArray())
        SyntheticOnly=$true
        ProductionReady=$false
    }
}
function Assert-OPA265BW4j4Fixture {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][string]$SuiteId)
    $expected=New-OPA265BW4j4Fixture -Case $Case -SuiteId $SuiteId
    # SHA, full JSON and deterministic binary data must match the plan. No user message admitted.
    $got=ConvertTo-Json -InputObject $Mail -Depth 12 -Compress
    $correct=ConvertTo-Json -InputObject $expected -Depth 12 -Compress
    if($got -cne $correct -or $Mail.SyntheticOnly -isnot [bool] -or
        -not $Mail.SyntheticOnly -or $Mail.ProductionReady -isnot [bool] -or
        $Mail.ProductionReady) {
        throw 'BW4j4 synthetic mail differs from immutable deterministic fixture.'
    }
    return $true
}
function New-OPA265BW4j4Sandbox {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot)
    $root=Assert-OPA265BW4j4SandboxRoot -SandboxRoot $SandboxRoot -AllowCreate
    if([IO.Directory]::Exists($root)){throw 'BW4j4 never replaces an existing sandbox.'}
    [void][IO.Directory]::CreateDirectory($root)
    foreach($dir in @('source','destination','claims','receipts')){
        [void][IO.Directory]::CreateDirectory((Join-Path $root $dir))
    }
    $plan=New-OPA265BW4jPlan
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    $fixtures=New-Object 'System.Collections.Generic.List[object]'
    foreach($case in @($plan.Cases)){
        $mail=New-OPA265BW4j4Fixture -Case $case -SuiteId $plan.SuiteId
        $paths=Get-OPA265BW4j4Paths -Root $root -TestId $case.TestId
        $fileSha=Write-OPA265BW4j4JsonOnce -Path $paths.Source -Value $mail
        $fixtures.Add([pscustomobject][ordered]@{
            CaseName=[string]$case.Name
            TestId=[string]$case.TestId
            SourceJsonSha256=$fileSha
            ExpectedSourceSize=[long]$mail.SourceSize
            ExpectedSyntheticDestinationDelta=[long]38
        })
    }
    $manifest=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4j4.IsolatedSyntheticManifest.1'
        Plan=$plan
        Fixtures=@($fixtures.ToArray())
        SyntheticOnly=$true
        OutlookCOMAllowed=$false
        PstAccessAllowed=$false
        ProductionReady=$false
    }
    $manifestFile=Join-Path $root 'manifest.json'
    $sha=Write-OPA265BW4j4JsonOnce -Path $manifestFile -Value $manifest
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j4.NewSandbox.1'
        Status='FiveSyntheticCasesInitializedNoMove'
        SandboxRoot=$root
        SuiteId=$plan.SuiteId
        ManifestSha256=$sha
        FixtureCount=5
        ProductionReady=$false
    }
}
function Get-OPA265BW4j4Manifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256)
    $root=Assert-OPA265BW4j4SandboxRoot -SandboxRoot $SandboxRoot
    if($ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4j4 independently pinned manifest SHA256 required.'
    }
    $path=Join-Path $root 'manifest.json'
    if((Get-OPA265BW4j4FileSha -Path $path) -cne $ExpectedManifestSha256){
        throw 'BW4j4 immutable sandbox manifest hash differs.'
    }
    if((Get-Item -LiteralPath $path).Length -gt 16384){throw 'BW4j4 oversized manifest.'}
    $m=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if($m.Schema -cne '2.6.5-BW4j4.IsolatedSyntheticManifest.1' -or
       @($m.Fixtures).Count -ne 5 -or
       $m.SyntheticOnly -isnot [bool] -or -not $m.SyntheticOnly -or
       $m.OutlookCOMAllowed -isnot [bool] -or $m.OutlookCOMAllowed -or
       $m.PstAccessAllowed -isnot [bool] -or $m.PstAccessAllowed -or
       $m.ProductionReady -isnot [bool] -or $m.ProductionReady){
        throw 'BW4j4 manifest schema/unsafe synthetic switches.'
    }
    [void](Assert-OPA265BW4jPlan -Plan $m.Plan)
    for($i=0;$i -lt 5;$i++){
        $row=$m.Fixtures[$i]
        if($row.TestId -cne $m.Plan.Cases[$i].TestId -or
           $row.CaseName -cne $m.Plan.Cases[$i].Name -or
           $row.SourceJsonSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [long]$row.ExpectedSyntheticDestinationDelta -ne 38) {
            throw 'BW4j4 synthetic fixture seal differs.'
        }
    }
    return $m
}
function Get-OPA265BW4j4FixtureRow {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][string]$TestId)
    for($i=0;$i -lt 5;$i++){
        if([string]$Manifest.Plan.Cases[$i].TestId -ceq $TestId){
            return [pscustomobject]@{Case=$Manifest.Plan.Cases[$i];Seal=$Manifest.Fixtures[$i]}
        }
    }
    throw 'BW4j4 unknown synthetic TestId; no production data accepted.'
}
function Get-OPA265BW4j4State {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
          [Parameter(Mandatory=$true)][string]$TestId)
    $m=Get-OPA265BW4j4Manifest -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256
    $row=Get-OPA265BW4j4FixtureRow -Manifest $m -TestId $TestId
    $root=Assert-OPA265BW4j4SandboxRoot -SandboxRoot $SandboxRoot
    $p=Get-OPA265BW4j4Paths -Root $root -TestId $TestId
    $s=[IO.File]::Exists($p.Source);$d=[IO.File]::Exists($p.Target)
    $c=[IO.File]::Exists($p.Claim);$r=[IO.File]::Exists($p.Receipt)
    if($s -and $d){$state='BLOCKED_DuplicateSourceAndDestination'}
    elseif(-not $s -and -not $d){$state='BLOCKED_MissingSourceAndDestination'}
    elseif($r -and (-not $c -or $s -or -not $d)){$state='BLOCKED_InconsistentReceipt'}
    elseif(-not $c -and $d){$state='BLOCKED_UnclaimedMove'}
    elseif(-not $c){$state='PendingUnclaimed'}
    elseif($s){$state='ClaimedSourceStillPresentNeverRetry'}
    elseif($r){$state='ReceiptExistsReadOnlyVerify'}
    else{$state='MoveObservedAwaitIndependentReconciliation'}
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j4.SyntheticCrashRecoveryState.1'
        TestId=$TestId
        State=$state
        SourceExists=$s
        DestinationExists=$d
        ClaimExists=$c
        ReceiptExists=$r
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
    }
}
function Invoke-OPA265BW4j4OneShotSyntheticMove {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][switch]$ConfirmIsolatedSyntheticOneShot,
          [ValidateSet('None','AfterClaim','AfterMove')][string]$CrashPoint='None')
    if(-not $ConfirmIsolatedSyntheticOneShot){throw 'BW4j4 explicit isolated synthetic confirmation required.'}
    $state=Get-OPA265BW4j4State -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256 -TestId $TestId
    if($state.State -cne 'PendingUnclaimed'){throw ('BW4j4 NEVER retry or overwrite: '+$state.State)}
    $m=Get-OPA265BW4j4Manifest -SandboxRoot $SandboxRoot -ExpectedManifestSha256 $ExpectedManifestSha256
    $row=Get-OPA265BW4j4FixtureRow -Manifest $m -TestId $TestId
    $root=Assert-OPA265BW4j4SandboxRoot -SandboxRoot $SandboxRoot
    $p=Get-OPA265BW4j4Paths -Root $root -TestId $TestId
    $preSha=Get-OPA265BW4j4FileSha -Path $p.Source
    if($preSha -cne [string]$row.Seal.SourceJsonSha256){
        throw 'BW4j4 original source witness hash differs BEFORE claim.'
    }
    $mail=Get-Content -LiteralPath $p.Source -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4j4Fixture -Mail $mail -Case $row.Case -SuiteId $m.Plan.SuiteId)
    # Always DURABLY claim one irreversible attempt BEFORE atomic file rename.
    $claim=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4j4.IrreversibleSyntheticAttemptClaim.1'
        SuiteId=$m.Plan.SuiteId
        TestId=$TestId
        OriginalSourceSha256=$preSha
        OriginalManifestSha256=$ExpectedManifestSha256
        ClaimedUtc=[datetime]::UtcNow.ToString('o')
        OneAttemptOnly=$true
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
    $claimHash=Write-OPA265BW4j4JsonOnce -Path $p.Claim -Value $claim
    if($CrashPoint -ceq 'AfterClaim'){
        throw 'BW4j4 INJECTED CRASH after durable claim BEFORE synthetic move. NEVER RETRY.'
    }
    # File.Move is the simulation's atomic "move" on the same local filesystem.
    # This is NOT an Outlook/MAPI move and does not predict real PST behavior.
    [IO.File]::Move($p.Source,$p.Target)
    if($CrashPoint -ceq 'AfterMove'){
        throw 'BW4j4 INJECTED CRASH after atomic synthetic move BEFORE receipt. NEVER RETRY.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j4.SyntheticOneShotMoveReturned.1'
        Status='SyntheticFileMovedRequiresIndependentReconciliation'
        TestId=$TestId
        ClaimSha256=$claimHash
        SourceJsonSha256=$preSha
        MoveAttempts=1
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
}
