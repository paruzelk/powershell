#requires -Version 5.1
# ARCH3j: prepare a REAL operator-designated test-PST one-shot original
# operation with a durable original OperationJournal Intent. NO PST opens,
# target PST creation, MailItem.Move, MoveClaimed, or DuplicateIndex writes.
# PREPARE stops before any irreversible Outlook provider action.
. (Join-Path $PSScriptRoot 'ARCH3iSealedFullOriginalWitness.ps1')
. (Join-Path $PSScriptRoot 'ARCH3bOriginalMoverContract.ps1')
# Original DuplicateIndex depends on the original JSON/JSONL readers, which
# are normally loaded by the full legacy entrypoint. ARCH3j is standalone.
if(-not (Get-Command Read-OPAJsonFile -ErrorAction SilentlyContinue) -or
   -not (Get-Command Read-OPAJsonlEntries -ErrorAction SilentlyContinue)){
    . (Join-Path $PSScriptRoot '../Runtime/JsonSupport.ps1')
}
. (Join-Path $PSScriptRoot 'DuplicateIndex.ps1')

function Get-OPA265ARCH3jLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $base=Get-OPA265ARCH3iEvidenceLayout -RunId $RunId -LocalAppData $LocalAppData
    $dir=Join-Path ([string]$base.LocalAppData) ('OPA265-ARCH3j-'+$RunId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3j.Layout.1'
        RunId=$RunId
        Root=$dir
        IntentPath=(Join-Path $dir 'original-prepare-intent.json')
        JournalPath=(Join-Path $dir 'original-operation-journal.jsonl')
    }
}

function Get-OPA265ARCH3jSealedSource {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SealRunId,
          [Parameter(Mandatory=$true)][string]$SealSha256)
    $sealedLayout=Get-OPA265ARCH3iEvidenceLayout -RunId $SealRunId
    $review=Test-OPA265ARCH3iReadback -Layout $sealedLayout -SealSha256 $SealSha256
    if(-not [bool]$review.IndependentReadbackPassed -or
       [bool]$review.WriterPermit -or
       [bool]$review.LiveMovePerformed -or
       [string]$review.FullWitnessSchema -cne '2.6.5-ARCH2b.MailSemanticWitness.1'){
        throw 'ARCH3j original ARCH3i witness did not pass independent Review.'
    }
    $obj=Read-OPA265ARCH3cPinnedJson -Path ([string]$sealedLayout.WitnessPath) -ExpectedSha256 $SealSha256
    if([string]$obj.Schema -cne '2.6.5-ARCH3i.OriginalFullWitnessEnvelope.1' -or
       [string]$obj.RunId -cne $SealRunId -or
       [string]$obj.SourceEntryId -cne [string]$review.SourceEntryId -or
       [string]$obj.OriginalWitnessSha256 -cne [string]$review.OriginalWitnessSha256 -or
       [bool]$obj.FutureLiveWriterAuthorized -or [bool]$obj.WriterPermit){
        throw 'ARCH3j sealed original witness envelope conflicts with independent Review.'
    }
    [void](Assert-OPA265ARCH3fRealTestSource -SourcePst ([string]$obj.SourcePst) -RequireExisting)
    return $obj
}

function Get-OPA265ARCH3jOriginalRoutePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Sealed,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SourceStoreId)
    $path=Assert-OPA265ARCH3fRealTestSource -SourcePst ([string]$Sealed.SourcePst) -RequireExisting
    if([string]$Sealed.SourceEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$' -or
       [string]$Sealed.SourceStoreIdSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [int]$Sealed.SourceArchiveYear -ne 2020 -or
       [long]$Sealed.ExistingArchivePart1LengthBytes -ne 271360 -or
       [string]$Sealed.OriginalWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'){
        throw 'ARCH3j one-shot requires the EXACT operator-proven 2020/ARCH3h original witness.'
    }
    $storeSha=Get-OPA265ARCH2bTextSha256 -Text $SourceStoreId
    if($storeSha -cne [string]$Sealed.SourceStoreIdSha256){
        throw 'ARCH3j original StoreID not identical to pinned ARCH3i evidence.'
    }
    Clear-OPAArchivePartCache -SourcePst $path
    $parts=@(Get-OPAArchivePstPartsOnDisk -SourcePst $path -Year 2020)
    $part1=Get-OPAArchivePartPath -SourcePst $path -Year 2020 -Part 1
    $part2=Get-OPAArchivePartPath -SourcePst $path -Year 2020 -Part 2
    if($parts.Count -ne 1 -or [int]$parts[0].Part -ne 1 -or
       -not [string]::Equals([string]$parts[0].Path,$part1,[StringComparison]::OrdinalIgnoreCase) -or
       -not [IO.File]::Exists($part1) -or
       [int64]([IO.FileInfo]::new($part1)).Length -ne [long]$Sealed.ExistingArchivePart1LengthBytes -or
       [IO.File]::Exists($part2) -or
       [IO.Directory]::Exists($part2)){
        throw 'ARCH3j original 2020 archive collision topology changed; no preparation.'
    }
    if((([IO.File]::GetAttributes($part1)) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH3j existing archive is a reparse point.'
    }
    $date=[datetime]::new([long]$Sealed.ArchiveDateLocalTicks)
    if($date.Year -ne 2020){throw 'ARCH3j sealed original DateTime year drift.'}
    $candidate=[pscustomobject]@{
        EntryID=[string]$Sealed.SourceEntryId
        ArchiveDate=$date
        SourceFolderPath='\\info@stios.ru\Входящие'
        FolderName='Входящие'
    }
    $contract=New-OPA265ARCH3bOperationContract -Candidate $candidate -TransactionId ('ARCH3j-'+$RunId) -SourcePst $path -SourceStoreId $SourceStoreId -ArchiveGrouping Year -ArchivePart 2
    if([string]$contract.PlannedArchivePst -cne $part2 -or
       [string]$contract.PlannedTargetFolderPath -cne '2020\Входящие' -or
       [bool]$contract.WriterPermit){
        throw 'ARCH3j original MailMover route failed exact canonical one-shot pin.'
    }
    return $contract
}

function Get-OPA265ARCH3jIndexSafety {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Part1,
          [Parameter(Mandatory=$true)][string]$SourceEntryId)
    $indexDir=Join-Path ([IO.Path]::GetDirectoryName($Part1)) 'OutlookPOP3Archive-Transactions'
    $json=Join-Path $indexDir 'DuplicateIndex.json'
    $jsonl=Join-Path $indexDir 'DuplicateIndex.jsonl'
    if(-not [IO.Directory]::Exists($indexDir)){
        return [pscustomobject]@{Approved=$false;Reason='OriginalSharedDuplicateIndexDirectoryMissing';EntryCount=0;IndexReadOnly=$true}
    }
    if((([IO.File]::GetAttributes($indexDir)) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH3j original shared index directory is a reparse point.'
    }
    if(-not [IO.File]::Exists($json) -and -not [IO.File]::Exists($jsonl)){
        return [pscustomobject]@{Approved=$false;Reason='OriginalSharedDuplicateIndexFilesMissing';EntryCount=0;IndexReadOnly=$true}
    }
    foreach($f in @($json,$jsonl)){
        if([IO.File]::Exists($f) -and
           (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3j original index file is a reparse point.'
        }
    }
    if([IO.File]::Exists($jsonl)){
        $stream=$null
        try{
            $stream=[IO.File]::Open($jsonl,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            if($stream.Length -lt 2){throw 'ARCH3j original index JSONL empty/truncated.'}
            [void]$stream.Seek(-1,[IO.SeekOrigin]::End)
            if($stream.ReadByte() -ne 10){throw 'ARCH3j original index JSONL unterminated tail.'}
        }finally{if($null -ne $stream){$stream.Dispose()}}
    }
    # Original importer is read-only only because directory EXISTENCE is
    # checked before calling its Get-OPADuplicateIndexPath helpers.
    $index=Import-OPADuplicateIndex -ArchivePst $Part1
    $duplicate=Test-OPADuplicateEntry -Index $index -SourceEntryId $SourceEntryId
    return [pscustomobject]@{
        Approved=($null -eq $duplicate)
        Reason=if($null -eq $duplicate){'OriginalSharedDuplicateIndexReadOnlyNoEntryMatch'}else{'SourceAlreadyInOriginalSharedDuplicateIndex'}
        EntryCount=@($index.Entries).Count
        IndexReadOnly=$true
    }
}

function Test-OPA265ARCH3jPreparedIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256)
    if([string]$IntentSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$JournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [IO.Directory]::Exists([string]$Layout.Root) -or
       (([IO.File]::GetAttributes([string]$Layout.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3j PrepareIntent review requires sealed immutable evidence and canonical SHA.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$Layout.Root))
    if(@([IO.Directory]::GetFileSystemEntries([string]$Layout.Root)).Count -ne 2){
        throw 'ARCH3j prepared directory must contain exact sealed Intent and original journal only.'
    }
    $intent=Read-OPA265ARCH3cPinnedJson -Path ([string]$Layout.IntentPath) -ExpectedSha256 $IntentSha256
    $events=Read-OPAOperationJournal -Path ([string]$Layout.JournalPath)
    if((Get-FileHash -LiteralPath ([string]$Layout.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $JournalSha256 -or
       [bool]$events.TrailingPartial -or @($events.Events).Count -ne 1 -or
       [string]$intent.Schema -cne '2.6.5-ARCH3j.RealTestPstPrepareIntent.1' -or
       [string]$intent.RunId -cne [string]$Layout.RunId -or
       [string]$events.Events[0].Phase -cne 'Intent' -or
       [string]$events.Events[0].TransactionId -cne ('ARCH3j-'+[string]$Layout.RunId) -or
       [string]$events.Events[0].OperationId -cne [string]$intent.OperationId -or
       [string]$events.Events[0].ArchivePst -cne [string]$intent.NewArchivePst -or
       [string]$events.Events[0].SourceEntryId -cne [string]$intent.SourceEntryId -or
       [string]$intent.FullOriginalWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c' -or
       [bool]$intent.WriterPermit -or [bool]$intent.LiveMovePerformed){
        throw 'ARCH3j original Journal Intent and sealed record mismatch; no writer.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3j.PreparedReview.1'
        Status='OriginalOperationJournalRealTestPstPrepareIntentIndependentlyVerifiedNoMove'
        RunId=[string]$Layout.RunId
        OriginalWitnessSha256=[string]$intent.FullOriginalWitnessSha256
        SealedSourceRunId=[string]$intent.SourceSealRunId
        SealedSourceFileSha256=[string]$intent.SourceSealSha256
        NewArchivePst=[string]$intent.NewArchivePst
        ExistingArchivePart1Preserved=$true
        OriginalYearRoutingUsed=$true
        OriginalOperationJournalIntentWritten=$true
        IntentSha256=$IntentSha256
        JournalSha256=$JournalSha256
        MoveClaimed=$false
        LiveMovePerformed=$false
        ArchivePstOpenedOrCreated=$false
        DuplicateIndexWritten=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3jRealOneShotPrepare {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Prepare','Review')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$RunId,
          [string]$SealRunId,
          [string]$SealSha256,
          [string]$IntentSha256,
          [string]$JournalSha256,
          [switch]$ConfirmPrepareIntent)
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3j requires Windows PowerShell 5.1.'
    }
    $layout=Get-OPA265ARCH3jLayout -RunId $RunId
    if($Mode -ceq 'Review'){
        if($ConfirmPrepareIntent){throw 'ARCH3j Review cannot request preparation.'}
        return (Test-OPA265ARCH3jPreparedIntent -Layout $layout -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256)
    }
    if([string]$SealRunId -cnotmatch '^[a-f0-9-]{36}$' -or [string]$SealSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3j needs the exact existing ARCH3i sealed RunId and SHA256.'
    }
    if([string]::Equals($RunId,$SealRunId,[StringComparison]::OrdinalIgnoreCase)){
        throw 'ARCH3j new RunId must differ from existing ARCH3i evidence RunId.'
    }
    $sealed=Get-OPA265ARCH3jSealedSource -SealRunId $SealRunId -SealSha256 $SealSha256
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst ([string]$sealed.SourcePst) -RequireExisting
    $part1=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 1
    $part2=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 2
    if([IO.Directory]::Exists([string]$layout.Root) -or [IO.File]::Exists([string]$layout.Root)){
        throw 'ARCH3j RunId already has durable evidence; never replay PrepareIntent.'
    }
    if(-not [IO.File]::Exists($part1) -or
       ([IO.FileInfo]::new($part1)).Length -ne [long]$sealed.ExistingArchivePart1LengthBytes -or
       [IO.File]::Exists($part2)){
        throw 'ARCH3j old archive changed or new part occupied. STOP.'
    }
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3j.Plan.1'
            Status='SealedRealOneShotOriginalYearRoutePlanNoOutlookNoWrites'
            RunId=$RunId
            SourceSealRunId=$SealRunId
            SourceSealSha256=$SealSha256
            SourceEntryId=[string]$sealed.SourceEntryId
            ExistingArchivePart1=$part1
            ProposedUnusedYearPart2=$part2
            NoOriginalIndexMutation=$true
            OriginalOperationJournalIntentWritten=$false
            OutlookContacted=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3j Audit and Prepare require Windows PowerShell 5.1 -STA.'
    }
    if($Mode -ceq 'Prepare' -and -not $ConfirmPrepareIntent){
        throw 'ARCH3j Prepare requires explicit -ConfirmPrepareIntent; no PST write authorization.'
    }
    if($Mode -ceq 'Prepare' -and -not $PSCmdlet.ShouldProcess([string]$layout.IntentPath,'Write evidence-only original real PrepareIntent before any PST writer')){
        return [pscustomobject]@{Schema='2.6.5-ARCH3j.WhatIf.1';Status='PrepareIntentWhatIfNoOutlookNoWrites';WriterPermit=$false;ProductionReady=$false}
    }
    $session=$null;$mail=$null;$parent=$null
    try{
        $arch2layout=Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
        $session=Open-OPA265ARCH2dSession -Layout $arch2layout -SourcePst $source
        if(-not [bool]$session.Scope.Approved){throw 'ARCH3j original POP3 session scope not approved.'}
        $storeId=[string]$session.SourceStore.StoreID
        if((Get-OPA265ARCH2bTextSha256 -Text $storeId) -cne [string]$sealed.SourceStoreIdSha256){
            throw 'ARCH3j source StoreID changed since immutable ARCH3i seal.'
        }
        $mail=$session.Namespace.GetItemFromID([string]$sealed.SourceEntryId,$storeId)
        if($null -eq $mail -or [int]$mail.Class -ne 43 -or
           [string]$mail.EntryID -cne [string]$sealed.SourceEntryId){
            throw 'ARCH3j real exact source MailItem not present.'
        }
        $parent=$mail.Parent
        if($null -eq $parent -or
           [string]$parent.EntryID -cne [string]$sealed.SourceFolderEntryId -or
           [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
           [string]$parent.StoreID -cne $storeId){
            throw 'ARCH3j real source MailItem left approved POP3 Inbox.'
        }
        $date=Get-OPAArchiveItemDate -Item $mail
        if($null -eq $date -or ([datetime]$date).Ticks -ne [long]$sealed.ArchiveDateLocalTicks){
            throw 'ARCH3j source ArchiveDate changed from sealed witness.'
        }
        $witness=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $witness -ExpectedOriginalWitnessSha256 ([string]$sealed.OriginalWitnessSha256))
        $contract=Get-OPA265ARCH3jOriginalRoutePlan -Sealed $sealed -RunId $RunId -SourceStoreId $storeId
        if([string]$parent.FolderPath -cne [string]$contract.SourceFolderPath){
            throw 'ARCH3j original source folder routing drift.'
        }
        $index=Get-OPA265ARCH3jIndexSafety -Part1 $part1 -SourceEntryId ([string]$sealed.SourceEntryId)
        if(-not [bool]$index.Approved){
            # No write at all: existing shared index is unsafe or incomplete.
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH3j.IndexAudit.1'
                Status='ExistingOriginalDuplicateIndexBlocksNewRealOneShotPreparation'
                RunId=$RunId
                IndexReason=[string]$index.Reason
                IndexEntryCount=[int]$index.EntryCount
                IndexReadOnly=$true
                OriginalArchiveRoute=[string]$contract.PlannedArchivePst
                ExactSourceSemanticWitnessMatchesSeal=$true
                OriginalOperationJournalIntentWritten=$false
                LiveMovePerformed=$false
                WriterPermit=$false;ProductionReady=$false
            }
        }
        $audit=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3j.ReadOnlyOneShotAudit.1'
            Status='OriginalArchiveIndexAndSealedSourcePermitEvidenceOnlyPrepareIntent'
            RunId=$RunId
            SourceSealRunId=$SealRunId
            SealSha256=$SealSha256
            SourceEntryId=[string]$sealed.SourceEntryId
            SourceStoreIdSha256=[string]$sealed.SourceStoreIdSha256
            SourceFolderEntryId=[string]$sealed.SourceFolderEntryId
            OriginalWitnessSha256=[string]$sealed.OriginalWitnessSha256
            ExistingPart1=$part1
            ExistingPart1LengthBytes=[long]$sealed.ExistingArchivePart1LengthBytes
            NewArchivePart2=[string]$contract.PlannedArchivePst
            NewTargetFolder=[string]$contract.PlannedTargetFolderPath
            OriginalContractSha256=[string]$contract.ContractSha256
            OriginalOperationId=[string]$contract.OperationId
            OriginalDuplicateIndexReadOnly=$true
            OriginalIndexEntryCount=[int]$index.EntryCount
            SourceProcessId=[int]$session.OutlookProcessId
            SourceProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            OriginalOperationJournalIntentWritten=$false
            LiveMovePerformed=$false
            WriterPermit=$false;ProductionReady=$false
        }
        if($Mode -ceq 'Audit'){return $audit}
        # Recheck destination, source, and index immediately before disk intent.
        if([IO.File]::Exists($part2) -or
           [IO.FileInfo]::new($part1).Length -ne [long]$sealed.ExistingArchivePart1LengthBytes -or
           [string]$mail.EntryID -cne [string]$sealed.SourceEntryId -or
           [IO.Directory]::Exists([string]$layout.Root)){
            throw 'ARCH3j source or archive changed before PrepareIntent. STOP.'
        }
        $record=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3j.RealTestPstPrepareIntent.1'
            RunId=$RunId
            SourceSealRunId=$SealRunId
            SourceSealSha256=$SealSha256
            FullOriginalWitnessSha256=[string]$sealed.OriginalWitnessSha256
            SourcePst=$source
            SourceEntryId=[string]$sealed.SourceEntryId
            SourceFolderEntryId=[string]$sealed.SourceFolderEntryId
            SourceStoreIdSha256=[string]$sealed.SourceStoreIdSha256
            OriginalContractSha256=[string]$contract.ContractSha256
            OperationId=[string]$contract.OperationId
            NewArchivePst=[string]$contract.PlannedArchivePst
            PlannedTargetFolderPath=[string]$contract.PlannedTargetFolderPath
            ExistingArchivePart1=$part1
            ExistingArchivePart1LengthBytes=[long]$sealed.ExistingArchivePart1LengthBytes
            OriginalSharedIndexReadOnlyApproved=$true
            OriginalArchivePart2NotCreated=$true
            MoveClaimed=$false
            LiveMovePerformed=$false
            WriterPermit=$false
            ProductionReady=$false
        }
        $intentLayout=[pscustomobject]@{Root=[string]$layout.Root}
        New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $intentLayout
        $intentHash=Write-OPA265ARCH3cJsonOnce -Path ([string]$layout.IntentPath) -Record $record
        # ORIGINAL durable journal. Any failure preserves the half-written
        # run directory forever as a manual-review marker, never replay.
        [void](Write-OPAOperationJournalEvent -Path ([string]$layout.JournalPath) -TransactionId ('ARCH3j-'+$RunId) -OperationId ([string]$contract.OperationId) -Sequence 1 -Phase Intent -SourceEntryId ([string]$sealed.SourceEntryId) -ArchivePst ([string]$contract.PlannedArchivePst) -SourceStoreId $storeId -SourceFolderPath ([string]$contract.SourceFolderPath) -TargetFolderPath ([string]$contract.PlannedTargetFolderPath) -Message ('ARCH3j real TEST PST PREPARE ONLY, original full witness SHA256='+[string]$sealed.OriginalWitnessSha256+'; no PST or COM Move.'))
        $journalHash=(Get-FileHash -LiteralPath ([string]$layout.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant()
        return (Test-OPA265ARCH3jPreparedIntent -Layout $layout -IntentSha256 $intentHash -JournalSha256 $journalHash)
    }finally{
        Release-OPA265ARCH2c4Com -Object $parent
        Release-OPA265ARCH2c4Com -Object $mail
        Close-OPA265ARCH2dSession -Session $session
    }
}
