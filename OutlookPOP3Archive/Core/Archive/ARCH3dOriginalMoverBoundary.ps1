#requires -Version 5.1
# ARCH3d: protected hooks CALLABLE FROM THE ORIGINAL MailMover.ps1.
# The only enabled mode is synthetic injection. Existing user PST and actual
# Outlook COM objects are rejected before the original destination can be
# opened or created. This does not authorize real archiving or Resume.
function Assert-OPA265ARCH3dSyntheticBoundary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$Transaction,
          [Parameter(Mandatory=$true)][object[]]$SourceFolders)
    $id=[string]$Transaction.TransactionId
    $src=[IO.Path]::GetFullPath([string]$Transaction.State.SourcePst)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $root=[IO.Path]::GetDirectoryName($src)
    if($id -cnotmatch '^ARCH3D-SYNTHETIC-[a-zA-Z0-9-]{1,64}$' -or
       -not ($root+[IO.Path]::DirectorySeparatorChar).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($root) -cne $id -or
       [IO.Path]::GetFileName($src) -cne 'info@stios.ru.pst' -or
       [IO.File]::Exists($src)){
        throw 'ARCH3d protected integration accepts only a NONEXISTENT synthetic POP3 source path in its own TEMP directory.'
    }
    # Reject every actual COM wrapper and anything other than a test double.
    $all=@($Namespace)+@($SourceFolders)
    foreach($obj in $all){
        if($null -eq $obj -or $obj -is [System.__ComObject] -or $obj.GetType().FullName -ne 'System.Management.Automation.PSCustomObject'){
            throw 'ARCH3d synthetic boundary refuses real Outlook COM objects.'
        }
    }
    if([string]$Transaction.State.SourceStoreId -cne 'ARCH3D-SYNTHETIC-NOT-REAL-STORE'){
        throw 'ARCH3d accepts only a fake StoreID, never a live account.'
    }
    if([IO.Directory]::Exists($root) -and
       (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3d synthetic root cannot be a reparse point.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3d.ProtectedScope.1'
        Root=$root
        SourcePst=$src
        TransactionId=$id
        FakeStoreId='ARCH3D-SYNTHETIC-NOT-REAL-STORE'
        SyntheticOnly=$true
        RealOutlookObjectAllowed=$false
        OriginalPstAllowed=$false
        ProductionReady=$false
    }
}
function Get-OPA265ARCH3dSha {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($Text)
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
    }finally{$sha.Dispose()}
}
function Get-OPA265ARCH3dOperationIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Scope,
          [Parameter(Mandatory=$true)][object]$Candidate,
          [Parameter(Mandatory=$true)][string]$ArchiveGrouping)
    $id=[string]$Candidate.EntryID
    if($id -cnotmatch '^[a-fA-F0-9]{16,1024}$'){throw 'ARCH3d invalid original candidate EntryID.'}
    $date=[datetime]$Candidate.ArchiveDate
    $sourceFolder=[string]$Candidate.SourceFolderPath
    $sourceName=[string]$Candidate.FolderName
    if([string]::IsNullOrWhiteSpace($sourceFolder) -or [string]::IsNullOrWhiteSpace($sourceName)){
        throw 'ARCH3d original candidate folder identity missing.'
    }
    # Original target path logic, not a second archive planner.
    $target=Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderName $sourceName -SourceFolderPath $sourceFolder -Grouping $ArchiveGrouping
    $values=@('2.6.5-ARCH3d.BeforeDestination.1',
        [string]$Scope.TransactionId,[string]$Scope.SourcePst,[string]$Scope.FakeStoreId,
        $id.ToUpperInvariant(),$sourceFolder,$target,$date.ToUniversalTime().ToString('o'),$ArchiveGrouping)
    $builder=New-Object Text.StringBuilder
    foreach($v in $values){[void]$builder.Append(([string]$v).Length);[void]$builder.Append(':');[void]$builder.Append([string]$v)}
    $hash=Get-OPA265ARCH3dSha -Text $builder.ToString()
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3d.BeforeDestination.1'
        OperationId=('ARCH3d-'+$hash)
        TransactionId=$Scope.TransactionId
        EntryId=$id
        SourcePst=$Scope.SourcePst
        Year=$date.Year
        FolderPath=$sourceFolder
        TargetFolderPath=$target
        ArchiveGrouping=$ArchiveGrouping
        Root=(Join-Path ([string]$Scope.Root) ('evidence-'+$hash))
        FakeStoreId=$Scope.FakeStoreId
        SyntheticOnly=$true
        WriterPermit=$false
    }
}
function Write-OPA265ARCH3dSyntheticBoundary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Operation,
          [Parameter(Mandatory=$true)][ValidateSet('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned','MoveIndeterminate')][string]$Stage,
          [string]$ArchivePst='',[string]$TargetFolderPath='',
          [string]$WitnessSha256='',[string]$ArchiveEntryId='')
    if([string]$Operation.Schema -cne '2.6.5-ARCH3d.BeforeDestination.1' -or
       [bool]$Operation.WriterPermit -or
       -not [bool]$Operation.SyntheticOnly){
        throw 'ARCH3d forged synthetic operation context.'
    }
    $root=[IO.Path]::GetFullPath([string]$Operation.Root)
    $expectedRoot=Join-Path ([IO.Path]::GetDirectoryName([string]$Operation.SourcePst)) ('evidence-'+([string]$Operation.OperationId -replace '^ARCH3d-',''))
    if($root -cne [IO.Path]::GetFullPath($expectedRoot)){throw 'ARCH3d unexpected evidence destination.'}
    if(-not (Get-Command Write-OPA265ARCH3cJsonOnce -ErrorAction SilentlyContinue)){
        throw 'ARCH3d requires existing ARCH3c CreateNew/Flush(true) immutable writer loaded.'
    }
    $sequence=@('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned')
    $ordinal=[array]::IndexOf($sequence,$Stage)
    if($Stage -ceq 'MoveIndeterminate'){$ordinal=4}
    if($ordinal -lt 0){throw 'ARCH3d unknown stage.'}
    if($Stage -ceq 'PrepareIntent'){
        if([IO.Directory]::Exists($root)){throw 'ARCH3d operation directory already exists: never replay.'}
        [void][IO.Directory]::CreateDirectory($root)
    }elseif(-not [IO.Directory]::Exists($root)){
        throw 'ARCH3d no durable PrepareIntent before later stage.'
    }
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH3d reparse evidence directory refused.'
    }
    $previous=''
    if($ordinal -gt 0){
        $prior=Join-Path $root ($sequence[$ordinal-1]+'.json')
        if(-not [IO.File]::Exists($prior)){throw 'ARCH3d prior immutable stage missing.'}
        $previous=(Get-FileHash -LiteralPath $prior -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if($Stage -in @('DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned','MoveIndeterminate')){
        if([string]::IsNullOrWhiteSpace($ArchivePst) -or
           -not ([IO.Path]::GetFullPath($ArchivePst)).StartsWith(([IO.Path]::GetDirectoryName([string]$Operation.SourcePst)+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
            throw 'ARCH3d destination must be a SYNTHETIC archive under original synthetic TEMP root.'
        }
        $validPart=$false
        foreach($part in 1..16){
            $p=Get-OPAArchivePartPath -SourcePst ([string]$Operation.SourcePst) -Year ([int]$Operation.Year) -Part $part
            if([IO.Path]::GetFullPath($p) -ieq [IO.Path]::GetFullPath($ArchivePst)){$validPart=$true;break}
        }
        if(-not $validPart -or $TargetFolderPath -cne [string]$Operation.TargetFolderPath){
            throw 'ARCH3d original year/part/target routing differs from declared plan.'
        }
    }
    if($Stage -in @('SourceWitnessAnchored','MoveClaimed','MoveReturned','MoveIndeterminate') -and
       $WitnessSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3d original semantic witness SHA256 missing.'
    }
    if($Stage -ceq 'MoveReturned' -and $ArchiveEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$'){
        throw 'ARCH3d returned destination EntryID invalid.'
    }
    $record=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3d.SyntheticBoundaryEvidence.1'
        OperationId=[string]$Operation.OperationId
        TransactionId=[string]$Operation.TransactionId
        EntryId=[string]$Operation.EntryId
        Stage=$Stage
        PreviousSha256=$previous
        ArchivePst=$ArchivePst
        TargetFolderPath=$TargetFolderPath
        SourceWitnessSha256=$WitnessSha256
        DestinationEntryId=$ArchiveEntryId
        SyntheticOnly=$true
        OutlookActuallyContacted=$false
        ProductionReady=$false
    }
    $file=Join-Path $root ($Stage+'.json')
    $sha=Write-OPA265ARCH3cJsonOnce -Path $file -Record $record
    if($Stage -ceq 'PrepareIntent'){
        # Original OperationJournal Intent is durably written BEFORE any
        # archive destination is opened by the original GetDestination.
        $journal=Join-Path $root 'original-operation-journal.jsonl'
        [void](Write-OPAOperationJournalEvent -Path $journal -TransactionId ([string]$Operation.TransactionId) -OperationId ([string]$Operation.OperationId) -Sequence 1 -Phase Intent -SourceEntryId ([string]$Operation.EntryId) -ArchivePst '' -SourceStoreId ([string]$Operation.FakeStoreId) -SourceFolderPath ([string]$Operation.FolderPath) -TargetFolderPath ([string]$Operation.TargetFolderPath) -Message 'ARCH3d SYNTHETIC PROTECTED ORIGINAL MAILMOVER - no real Outlook.')
    }
    if($Stage -ceq 'MoveIndeterminate'){
        [void](Write-OPAOperationJournalEvent -Path (Join-Path $root 'original-operation-journal.jsonl') -TransactionId ([string]$Operation.TransactionId) -OperationId ([string]$Operation.OperationId) -Sequence 2 -Phase Indeterminate -SourceEntryId ([string]$Operation.EntryId) -ArchivePst $ArchivePst -SourceStoreId ([string]$Operation.FakeStoreId) -SourceFolderPath ([string]$Operation.FolderPath) -TargetFolderPath ([string]$Operation.TargetFolderPath) -Message 'ARCH3d synthetic COM outcome unknown, NEVER retry.')
    }
    return [pscustomobject]@{Stage=$Stage;Sha256=$sha;Path=$file;OperationId=$Operation.OperationId;WriterPermit=$false}
}
function Get-OPA265ARCH3dOriginalWitnessHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness)
    # This SHA is only a bridge marker: original ARCH2b semantic verifier
    # remains authoritative. Do not treat this as full content proof.
    $json=ConvertTo-Json -InputObject $Witness -Depth 30 -Compress -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($json)){throw 'ARCH3d witness cannot be serialized.'}
    return (Get-OPA265ARCH3dSha -Text $json)
}
function Test-OPA265ARCH3dSyntheticBoundary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Operation,
          [string]$ExternallyPinnedReceiptSha256='')
    $root=[string]$Operation.Root
    $stages=@('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned')
    $seen=New-Object 'System.Collections.Generic.List[string]'
    $issues=New-Object 'System.Collections.Generic.List[string]'
    $prior=''
    $gap=$false
    foreach($stage in $stages){
        $p=Join-Path $root ($stage+'.json')
        if(-not [IO.File]::Exists($p)){$gap=$true;continue}
        if($gap){$issues.Add('NonPrefixStage')|Out-Null}
        try{
            $sha=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
            $item=Read-OPA265ARCH3cPinnedJson -Path $p -ExpectedSha256 $sha
            if([string]$item.Stage -cne $stage -or [string]$item.OperationId -cne [string]$Operation.OperationId -or
               [string]$item.PreviousSha256 -cne $prior -or -not [bool]$item.SyntheticOnly){
                throw 'Invalid stage link.'
            }
            $seen.Add($stage)|Out-Null;$prior=$sha
        }catch{$issues.Add(('InvalidStage:'+ $stage))|Out-Null;$prior='BROKEN'}
    }
    $unknown=[IO.File]::Exists((Join-Path $root 'MoveIndeterminate.json'))
    $returned=($seen.Contains('MoveReturned') -and -not $unknown)
    $pinned=$false
    if($returned -and $ExternallyPinnedReceiptSha256 -cmatch '^[a-f0-9]{64}$'){
        $last=(Get-FileHash -LiteralPath (Join-Path $root 'MoveReturned.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        $pinned=($last -ceq $ExternallyPinnedReceiptSha256)
        if(-not $pinned){$issues.Add('ExternalReceiptShaMismatch')|Out-Null}
    }
    $journalPath=Join-Path $root 'original-operation-journal.jsonl'
    if(-not [IO.File]::Exists($journalPath)){$issues.Add('MissingOriginalJournal')|Out-Null}
    else{
        try{
            $j=Read-OPAOperationJournal -Path $journalPath
            $s=Resolve-OPAOperationRecovery -Journal $j
            if([string]$j.Events[0].OperationId -cne [string]$Operation.OperationId -or
               [string]$j.Events[0].Phase -cne 'Intent' -or
               [bool]$j.TrailingPartial -or @($j.Events).Count -gt 2){throw 'Invalid original operation journal.'}
        }catch{$issues.Add('OriginalOperationJournalInvalid')|Out-Null}
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3d.SyntheticOriginalMoverEvidence.1'
        Status=if($issues.Count -gt 0){'SyntheticBoundaryEvidenceInvalidNoRetry'}
            elseif($unknown){'SyntheticComIndeterminateManualReviewNoRetry'}
            elseif($returned -and $pinned){'OriginalMailMoverSyntheticMoveReturnedReceiptPinnedIndependentReviewRequired'}
            elseif($seen.Contains('MoveClaimed')){'SyntheticOneShotClaimExistsOutcomeUnknownNoRetry'}
            else{'BeforeMoveSyntheticEvidenceOnly'}
        OperationId=[string]$Operation.OperationId
        AcceptedStages=$seen.Count
        ReceiptExternallyPinned=$pinned
        OriginalOperationJournalPath=$journalPath
        Issues=@($issues.ToArray())
        OriginalMailMoverInvoked=$true
        RealOutlookContacted=$false
        LiveMailMoved=$false
        IndependentLivePstVerified=$false
        DuplicateIndexCommitAllowed=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
