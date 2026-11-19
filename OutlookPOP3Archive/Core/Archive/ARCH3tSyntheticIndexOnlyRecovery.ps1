#requires -Version 5.1
# ARCH3t. Repair ONLY missing ORIGINAL DuplicateIndex JSONL rows in a
# verified ARCH3s/ARCH3r OS TEMP fake transaction. No Outlook, no PST, no Move.
. (Join-Path $PSScriptRoot 'ARCH3sTenOriginalVerifierIntegration.ps1')

function Assert-OPA265ARCH3tWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Workspace)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $full=[IO.Path]::GetFullPath($Workspace).TrimEnd([char]92,[char]47)
    if(-not $full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       -not [IO.Directory]::Exists($full)){
        throw 'ARCH3t accepts only existing synthetic workspace under OS TEMP.'
    }
    $info=New-Object IO.DirectoryInfo($full)
    if($info.Name -cnotmatch '^OPA265-ARCH3r-SYNTH-[a-f0-9]{32}$' -or
       $null -eq $info.Parent -or
       $info.Parent.Name -cnotmatch '^OPA265-ARCH3s-FAKE-[a-f0-9]{32}$'){
        throw 'ARCH3t requires nested ARCH3s/ARCH3r fake workspace, never a real journal.'
    }
    $walk=$info
    while($null -ne $walk -and $walk.FullName.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){
        if(($walk.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'ARCH3t rejects reparse-point workspace and parents.'
        }
        $walk=$walk.Parent
    }
    return $full
}

function Assert-OPA265ARCH3tRegularFile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not [IO.File]::Exists($Path) -or
       (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw ('ARCH3t missing/reparse file: '+$Path)
    }
}

function Get-OPA265ARCH3tSyntheticIndexAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Workspace)
    $root=Assert-OPA265ARCH3tWorkspace -Workspace $Workspace
    $rows=@(New-OPA265ARCH3rTenSyntheticPlan)
    $archive=Join-Path $root 'SYNTHETIC-NOT-A-REAL-PST.pst'
    $journalPath=Join-Path $root 'synthetic-original-operation-journal.jsonl'
    $txDir=Join-Path $root 'OutlookPOP3Archive-Transactions'
    $indexPath=Join-Path $txDir 'DuplicateIndex.jsonl'
    $legacyPath=Join-Path $txDir 'DuplicateIndex.json'
    if([IO.File]::Exists($archive) -or -not [IO.Directory]::Exists($txDir) -or
       (([IO.File]::GetAttributes($txDir) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       [IO.File]::Exists($legacyPath)){
        throw 'ARCH3t rejects real PST, missing transaction directory, reparse, or legacy index.'
    }
    Assert-OPA265ARCH3tRegularFile -Path $journalPath
    $j=Read-OPAOperationJournal -Path $journalPath
    $resolved=Resolve-OPAOperationRecovery -Journal $j
    $events=@($j.Events)
    if([bool]$j.TrailingPartial -or $events.Count -ne 20 -or
       @($resolved.Resolved).Count -ne 10 -or
       @($resolved.Indeterminate).Count -ne 0 -or
       [bool]$resolved.BlockAutomaticRetry){
        throw 'ARCH3t refuses incomplete, torn or indeterminate original journal; no index recovery.'
    }
    $run=[string]$resolved.TransactionId
    if($run -cnotmatch '^ARCH3r-SYNTH-[a-f0-9]{32}$'){
        throw 'ARCH3t refuses non-synthetic transaction identity.'
    }
    for($n=1;$n -le 10;$n++){
        $row=$rows[$n-1]
        $intent=$events[$n-1]
        $terminal=$events[$n+9]
        $op=$run+'-'+$n
        if([string]$intent.Phase -cne 'Intent' -or
           [string]$terminal.Phase -cne 'Reconciled' -or
           [long]$intent.Sequence -ne $n -or
           [long]$terminal.Sequence -ne (10+$n) -or
           [string]$intent.OperationId -cne $op -or
           [string]$terminal.OperationId -cne $op -or
           [string]$intent.TransactionId -cne $run -or
           [string]$terminal.TransactionId -cne $run -or
           [string]$intent.SourceEntryId -cne [string]$row.SourceEntryId -or
           [string]$terminal.SourceEntryId -cne [string]$row.SourceEntryId -or
           [string]$terminal.ArchiveEntryId -cne [string]$row.ArchiveEntryId -or
           [string]$intent.ArchivePst -cne $archive -or
           [string]$terminal.ArchivePst -cne $archive -or
           [string]$intent.SourceFolderPath -cne [string]$row.SourceFolderPath -or
           [string]$terminal.SourceFolderPath -cne [string]$row.SourceFolderPath -or
           [string]$intent.TargetFolderPath -cne [string]$row.TargetFolderPath -or
           [string]$terminal.TargetFolderPath -cne [string]$row.TargetFolderPath){
            throw ('ARCH3t original journal transaction/sequence/identity mismatch at '+$n)
        }
        $claimPath=Join-Path $root ('SYNTH-MoveClaim-'+$n+'.json')
        $providerPath=Join-Path $root ('SYNTH-ProviderInvocation-'+$n+'.json')
        Assert-OPA265ARCH3tRegularFile -Path $claimPath
        Assert-OPA265ARCH3tRegularFile -Path $providerPath
        $claim=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($claimPath)) -ErrorAction Stop
        $provider=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($providerPath)) -ErrorAction Stop
        $claimSha=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if([string]$claim.TransactionId -cne $run -or
           [string]$claim.SourceEntryId -cne [string]$row.SourceEntryId -or
           [string]$claim.PlannedArchiveEntryId -cne [string]$row.ArchiveEntryId -or
           [string]$claim.OriginalSemanticWitnessSha256 -cne [string]$row.OriginalSourceWitnessDigest -or
           -not [bool]$claim.SyntheticOnly -or [bool]$claim.WriterPermit -or
           [string]$provider.SourceEntryId -cne [string]$row.SourceEntryId -or
           [string]$provider.MoveClaimSha256 -cne $claimSha -or
           -not [bool]$provider.SyntheticOnly -or [bool]$provider.WriterPermit){
            throw ('ARCH3t synthetic claim/provider evidence mismatch at '+$n)
        }
    }
    $entries=New-Object 'System.Collections.Generic.List[object]'
    $indexSha=''
    if([IO.File]::Exists($indexPath)){
        Assert-OPA265ARCH3tRegularFile -Path $indexPath
        $bytes=[IO.File]::ReadAllBytes($indexPath)
        if($bytes.Length -eq 0 -or $bytes[$bytes.Length-1] -ne 10){
            throw 'ARCH3t refuses empty/truncated index JSONL.'
        }
        $indexSha=(Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()
        foreach($line in [IO.File]::ReadAllLines($indexPath)){
            if([string]::IsNullOrWhiteSpace($line)){throw 'ARCH3t refuses blank index JSONL records.'}
            [void]$entries.Add((ConvertFrom-Json -InputObject $line -ErrorAction Stop))
        }
    }
    if($entries.Count -gt 10){throw 'ARCH3t index has unexpected extra records.'}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($e in $entries){
        $match=@($rows | Where-Object { [string]$_.SourceEntryId -ceq [string]$e.SourceEntryId })
        if($match.Count -ne 1 -or -not $seen.Add([string]$e.SourceEntryId)){
            throw 'ARCH3t index contains unexpected/duplicate source ID; last-wins is forbidden.'
        }
        $row=$match[0]
        if([string]$e.ArchiveEntryId -cne [string]$row.ArchiveEntryId -or
           [string]$e.SourceFolderPath -cne [string]$row.SourceFolderPath -or
           [string]$e.TargetFolderPath -cne [string]$row.TargetFolderPath -or
           [string]$e.TransactionId -cne $run -or
           [string]$e.ArchivePst -cne $archive -or
           [string]$e.ArchiveGrouping -cne 'Year' -or
           [int]$e.TransactionLimit -ne 10){
            throw 'ARCH3t existing index entry conflicts with independently expected identity.'
        }
    }
    $index=Import-OPADuplicateIndex -ArchivePst $archive
    if(@($index.Entries).Count -ne $entries.Count){
        throw 'ARCH3t original index import disagrees with raw append-only entries.'
    }
    $missing=New-Object 'System.Collections.Generic.List[int]'
    for($n=1;$n -le 10;$n++){
        if(-not $seen.Contains([string]$rows[$n-1].SourceEntryId)){[void]$missing.Add($n)}
    }
    # Re-run ORIGINAL Test-OPAArchiveMoves on a new deterministic fake Outlook
    # object model. This proves only synthetic semantics, not real PST durability.
    $fixture=New-OPA265ARCH3sFakeOutlook -Workspace $root
    $verification=Invoke-OPA265ARCH3sOriginalVerifierTen -Fixture $fixture
    if(-not [bool]$verification.OriginalArchiveVerifierPassed -or
       [int]$verification.ObservedSourceCount -ne 0 -or
       [int]$verification.ObservedArchiveFolderCount -ne 10){
        throw 'ARCH3t original fake Outlook verifier failed: index recovery denied.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3t.SyntheticOriginalIndexOnlyRecovery.1'
        Status=if($missing.Count -eq 0){'AlreadyFullyIndexed'}else{'ReadyForSyntheticMissingIndexOnly'}
        Workspace=$root;OriginalJournalPath=$journalPath;OriginalIndexPath=$indexPath
        OriginalJournalSha256=(Get-FileHash -LiteralPath $journalPath -Algorithm SHA256).Hash.ToLowerInvariant()
        OriginalIndexSha256=$indexSha;JournalEventCount=20
        JournalReconciledCount=10;IndexedCount=[int]$entries.Count
        MissingNumbers=@($missing.ToArray())
        TransactionId=$run;OriginalArchiveVerifierPassed=$true
        SyntheticOnly=$true;OriginalJournalWritten=$false;RealPstWritten=$false
        RealOutlookContacted=$false;RealMailMovePerformed=$false
        AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3tIndexOnlyRecovery {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [ValidateSet('Audit','Recover')][string]$Mode='Audit',
        [Parameter(Mandatory=$true)][string]$Workspace,
        [string]$ExpectedJournalSha256='',
        [string]$ExpectedIndexSha256='',
        [switch]$ConfirmSyntheticRecovery
    )
    $state=Get-OPA265ARCH3tSyntheticIndexAudit -Workspace $Workspace
    if($Mode -ceq 'Audit'){return $state}
    if(-not $ConfirmSyntheticRecovery){
        throw 'ARCH3t Recover requires explicit -ConfirmSyntheticRecovery.'
    }
    if($ExpectedJournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$state.OriginalJournalSha256 -cne $ExpectedJournalSha256 -or
       [string]$state.OriginalIndexSha256 -cne $ExpectedIndexSha256){
        throw 'ARCH3t original journal/index SHA pins changed: no recovery.'
    }
    if(@($state.MissingNumbers).Count -eq 0){$state.Status='AlreadyFullyIndexedNoWrites';return $state}
    if(-not $PSCmdlet.ShouldProcess($state.OriginalIndexPath,'Append missing synthetic-only original DuplicateIndex records')){
        $state.Status='WhatIfSyntheticRecoveryNoWrites'
        return $state
    }
    $lockPath=Join-Path $state.Workspace 'ARCH3t-IndexRecovery.lock'
    if([IO.File]::Exists($lockPath) -and
       (([IO.File]::GetAttributes($lockPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3t lock is reparse point.'
    }
    $lease=$null
    $old=$global:OPADurabilityMode
    try {
        $lease=New-Object IO.FileStream($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        # TOCTOU: repeat full original journal, raw index and verifier checks
        # under the exclusive workspace lease before invoking any writer.
        $locked=Get-OPA265ARCH3tSyntheticIndexAudit -Workspace $state.Workspace
        if([string]$locked.OriginalJournalSha256 -cne $ExpectedJournalSha256 -or
           [string]$locked.OriginalIndexSha256 -cne $ExpectedIndexSha256){
            throw 'ARCH3t pinned files changed while acquiring exclusive lease.'
        }
        $index=Import-OPADuplicateIndex -ArchivePst (Join-Path $state.Workspace 'SYNTHETIC-NOT-A-REAL-PST.pst')
        $rows=@(New-OPA265ARCH3rTenSyntheticPlan)
        $global:OPADurabilityMode='Safe'
        foreach($n in @($locked.MissingNumbers)){
            $row=$rows[[int]$n-1]
            if($null -ne (Test-OPADuplicateEntry -Index $index -SourceEntryId ([string]$row.SourceEntryId))){
                throw 'ARCH3t concurrent/double index append detected.'
            }
            Add-OPADuplicateEntry -Index $index -SourceEntryId $row.SourceEntryId -ArchiveEntryId $row.ArchiveEntryId -SourceFolderPath $row.SourceFolderPath -TargetFolderPath $row.TargetFolderPath -ReceivedTime ([datetime]::new(2020,2,1,12,0,0,[DateTimeKind]::Utc).AddDays([int]$n)) -Subject $row.Subject -TransactionId $locked.TransactionId -TransactionLimit 10 -ArchiveGrouping Year -SourcePst (Join-Path $state.Workspace 'SYNTHETIC-NOT-A-REAL-SOURCE.pst') -ArchivePst (Join-Path $state.Workspace 'SYNTHETIC-NOT-A-REAL-PST.pst')
            Sync-OPADuplicateJournalStreams
        }
        Close-OPADuplicateJournalStreams
        $done=Get-OPA265ARCH3tSyntheticIndexAudit -Workspace $state.Workspace
        if($done.IndexedCount -ne 10 -or @($done.MissingNumbers).Count -ne 0 -or
           [string]$done.OriginalJournalSha256 -cne $ExpectedJournalSha256){
            throw 'ARCH3t post-append independent index/journal readback failed.'
        }
        $done.Status='RecoveredMissingSyntheticIndexOnlyNoMove'
        return $done
    }finally{
        Close-OPADuplicateJournalStreams
        $global:OPADurabilityMode=$old
        if($null -ne $lease){$lease.Dispose()}
    }
}
