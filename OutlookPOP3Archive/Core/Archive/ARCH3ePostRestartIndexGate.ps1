#requires -Version 5.1
# ARCH3e: original ArchiveVerifier + original OperationJournal + original
# DuplicateIndex. SYNTHETIC ONLY: never open an existing PST or real COM.
# No automatic Move replay and no permission for Archive/Resume/Auto.

function Assert-OPA265ARCH3eSyntheticContext {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Operation,
          [Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$SourceFolder,
          [Parameter(Mandatory=$true)][object]$ArchiveStore)
    if([string]$Operation.Schema -cne '2.6.5-ARCH3d.BeforeDestination.1' -or
       -not [bool]$Operation.SyntheticOnly -or [bool]$Operation.WriterPermit -or
       [string]$Operation.TransactionId -cnotmatch '^ARCH3D-SYNTHETIC-[A-Za-z0-9-]{1,64}$'){
        throw 'ARCH3e rejects non-synthetic or forged ARCH3d operation.'
    }
    $source=[IO.Path]::GetFullPath([string]$Operation.SourcePst)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $directory=[IO.Path]::GetDirectoryName($source)
    if(-not ($directory+[IO.Path]::DirectorySeparatorChar).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($directory) -cne [string]$Operation.TransactionId -or
       [IO.Path]::GetFileName($source) -cne 'info@stios.ru.pst' -or
       [IO.File]::Exists($source)){
        throw 'ARCH3e source must remain a missing POP3 PST in a synthetic TEMP directory.'
    }
    foreach($obj in @($Namespace,$SourceFolder,$ArchiveStore)){
        if($null -eq $obj -or $obj.GetType().FullName -cne 'System.Management.Automation.PSCustomObject'){
            throw 'ARCH3e refuses real Outlook COM: fake PSCustomObject test doubles only.'
        }
    }
    if([string]$SourceFolder.FolderPath -cne [string]$Operation.FolderPath -or
       -not [IO.Directory]::Exists([string]$Operation.Root)){
        throw 'ARCH3e synthetic original source folder/operation mismatch.'
    }
    if([IO.File]::Exists([string]$ArchiveStore.FilePath)){
        throw 'ARCH3e refuses even an existing archive PST in TEMP.'
    }
    $archive=[IO.Path]::GetFullPath([string]$ArchiveStore.FilePath)
    if(-not $archive.StartsWith(($directory+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
        throw 'ARCH3e archive path outside synthetic TEMP.'
    }
    $partValid=$false
    foreach($part in 1..16){
        if($archive -ieq (Get-OPAArchivePartPath -SourcePst $source -Year ([int]$Operation.Year) -Part $part)){
            $partValid=$true;break
        }
    }
    if(-not $partValid){throw 'ARCH3e destination does not match ORIGINAL year/part naming.'}
    return $true
}
function Get-OPA265ARCH3ePinnedReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Operation,
          [Parameter(Mandatory=$true)][string]$ReceiptSha256,
          [Parameter(Mandatory=$true)][object]$SourceSemanticWitness)
    if($ReceiptSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH3e externally pinned MoveReturned SHA256 required.'}
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $SourceSemanticWitness)){
        throw 'ARCH3e original ARCH2b full semantic witness missing or incomplete.'
    }
    $review=Test-OPA265ARCH3dSyntheticBoundary -Operation $Operation -ExternallyPinnedReceiptSha256 $ReceiptSha256
    if([string]$review.Status -cne 'OriginalMailMoverSyntheticMoveReturnedReceiptPinnedIndependentReviewRequired' -or
       @($review.Issues).Count -ne 0 -or
       -not [bool]$review.ReceiptExternallyPinned -or
       [IO.File]::Exists((Join-Path ([string]$Operation.Root) 'MoveIndeterminate.json'))){
        throw 'ARCH3e original operation receipt is unpinned, incomplete or COM-indeterminate.'
    }
    $root=[string]$Operation.Root
    $witnessPath=Join-Path $root 'SourceWitnessAnchored.json'
    $witnessRecord=Read-OPA265ARCH3cPinnedJson -Path $witnessPath -ExpectedSha256 ((Get-FileHash -LiteralPath $witnessPath -Algorithm SHA256).Hash.ToLowerInvariant())
    $receipt=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $root 'MoveReturned.json') -ExpectedSha256 $ReceiptSha256
    $sha=Get-OPA265ARCH3dOriginalWitnessHash -Witness $SourceSemanticWitness
    if([string]$witnessRecord.SourceWitnessSha256 -cne $sha -or
       [string]$receipt.SourceWitnessSha256 -cne $sha -or
       [string]$receipt.OperationId -cne [string]$Operation.OperationId -or
       [string]$receipt.EntryId -cne [string]$Operation.EntryId -or
       [string]$receipt.DestinationEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$'){
        throw 'ARCH3e source semantic SHA or original destination receipt mismatch.'
    }
    return $receipt
}
function Test-OPA265ARCH3eOriginalVerifierGate {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Operation,
          [Parameter(Mandatory=$true)][string]$ReceiptSha256,
          [Parameter(Mandatory=$true)][object]$SourceSemanticWitness,
          [Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$SourceFolder,
          [Parameter(Mandatory=$true)][object]$ArchiveStore,
          [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$OriginalProcessId,
          [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$ReopenedProcessId,
          [Parameter(Mandatory=$true)][string]$ExpectedSubject)
    [void](Assert-OPA265ARCH3eSyntheticContext -Operation $Operation -Namespace $Namespace -SourceFolder $SourceFolder -ArchiveStore $ArchiveStore)
    $receipt=Get-OPA265ARCH3ePinnedReceipt -Operation $Operation -ReceiptSha256 $ReceiptSha256 -SourceSemanticWitness $SourceSemanticWitness
    if($OriginalProcessId -eq $ReopenedProcessId){throw 'ARCH3e fake restart process IDs cannot match.'}
    if([string]$receipt.ArchivePst -cne [string]$ArchiveStore.FilePath){
        throw 'ARCH3e fake archive Store path differs from pinned receipt.'
    }
    if(-not [string]$receipt.TargetFolderPath.EndsWith(('\' + [string]$Operation.TargetFolderPath),[StringComparison]::OrdinalIgnoreCase)){
        throw 'ARCH3e original target folder mismatch.'
    }
    # Call ORIGINAL verifier, never copy its semantic comparison.
    $expected=[pscustomobject]@{
        SourceEntryId=[string]$Operation.EntryId
        ArchiveEntryId=[string]$receipt.DestinationEntryId
        SourceFolderPath=[string]$Operation.FolderPath
        ArchivePst=[string]$receipt.ArchivePst
        TargetFolderPath=[string]$receipt.TargetFolderPath
        SourceSemanticWitness=$SourceSemanticWitness
        Subject=$ExpectedSubject
        Sender=''
        InternetMessageId=''
    }
    $verified=Test-OPAArchiveMoves -Namespace $Namespace -SourceFolder @($SourceFolder) -ArchiveStores @($ArchiveStore) -ExpectedMoved 1 -ExpectedMoves @($expected) -RequireSemanticWitness
    # One isolated synthetic mail in an otherwise empty destination folder.
    # This check closes a uniqueness gap of the original direct-EntryID path:
    # success by EntryID need not mean there are no other target-folder items.
    $ok=([bool]$verified.Verified -and [bool]$verified.EntryIdsVerified -and
         [bool]$verified.SemanticWitnessRequired -and
         [bool]$verified.AllRequiredOriginalSemanticWitnessesPresent -and
         @($verified.MissingEntryIds).Count -eq 0 -and
         [int]$verified.TargetCount -eq 1 -and
         [int]$verified.ObservedSourceCount -eq 0 -and
         [int]$verified.ExpectedEntryIdsChecked -eq 1)
    if(-not $ok){throw 'ARCH3e original ArchiveVerifier did not prove source-zero, archive-one, semantic match, and no unknown items.'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3e.OriginalVerifierGate.1'
        Status='SyntheticOriginalVerifierSemanticMatchNotLiveCertified'
        OperationId=[string]$Operation.OperationId
        ReceiptSha256=$ReceiptSha256
        OriginalArchiveVerifierUsed=$true
        SourceMatches=0
        ArchiveFolderItemCount=1
        AllOriginalSemanticsMatched=$true
        OriginalProcessId=$OriginalProcessId
        ReopenedProcessId=$ReopenedProcessId
        RestartIsSyntheticOnly=$true
        ReadyForSyntheticIndexCommit=$true
        RealOutlookRestartProven=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Operation,
          [Parameter(Mandatory=$true)][string]$ReceiptSha256,
          [Parameter(Mandatory=$true)][object]$SourceSemanticWitness,
          [Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$SourceFolder,
          [Parameter(Mandatory=$true)][object]$ArchiveStore,
          [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$OriginalProcessId,
          [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$ReopenedProcessId,
          [Parameter(Mandatory=$true)][string]$ExpectedSubject,
          [switch]$ConfirmSyntheticIndexWrite)
    if(-not $ConfirmSyntheticIndexWrite){throw 'ARCH3e explicit synthetic index-write approval required.'}
    $params=@{Operation=$Operation;ReceiptSha256=$ReceiptSha256;SourceSemanticWitness=$SourceSemanticWitness;
       Namespace=$Namespace;SourceFolder=$SourceFolder;ArchiveStore=$ArchiveStore;
       OriginalProcessId=$OriginalProcessId;ReopenedProcessId=$ReopenedProcessId;ExpectedSubject=$ExpectedSubject}
    $proof=Test-OPA265ARCH3eOriginalVerifierGate @params
    $root=[string]$Operation.Root
    $proofFile=Join-Path $root 'ARCH3e-IndependentSyntheticReview.json'
    $indexSealFile=Join-Path $root 'ARCH3e-IndexCommitted.json'
    if([IO.File]::Exists($proofFile) -or [IO.File]::Exists($indexSealFile)){
        throw 'ARCH3e independent review or commit already exists: no replay.'
    }
    $receipt=Get-OPA265ARCH3ePinnedReceipt -Operation $Operation -ReceiptSha256 $ReceiptSha256 -SourceSemanticWitness $SourceSemanticWitness
    $originalEvents=Read-OPAOperationJournal -Path (Join-Path $root 'original-operation-journal.jsonl')
    $resolved=Resolve-OPAOperationRecovery -Journal $originalEvents
    if(@($originalEvents.Events).Count -ne 1 -or [string]$originalEvents.Events[0].Phase -cne 'Intent' -or
       [string]$originalEvents.Events[0].OperationId -cne [string]$Operation.OperationId -or
       [bool]$resolved.TrailingPartial){
        throw 'ARCH3e original journal not exactly at safe Intent (no replay or index mutation).'
    }
    $proofRecord=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3e.SyntheticIndependentReview.1'
        OperationId=[string]$Operation.OperationId
        ReceiptSha256=$ReceiptSha256
        SourceWitnessSha256=(Get-OPA265ARCH3dOriginalWitnessHash -Witness $SourceSemanticWitness)
        ArchivePst=[string]$receipt.ArchivePst
        ArchiveEntryId=[string]$receipt.DestinationEntryId
        OriginalProcessId=$OriginalProcessId
        ReopenedProcessId=$ReopenedProcessId
        OriginalVerifierUsed=$true
        OriginalSemanticMatch=$true
        SourceCount=0
        ArchiveFolderItemCount=1
        FakeRestartOnly=$true
        RealOutlookCertified=$false
    }
    # Immutable reviewed witness BEFORE original journal terminal transition.
    $proofSha=Write-OPA265ARCH3cJsonOnce -Path $proofFile -Record $proofRecord
    $journal=Join-Path $root 'original-operation-journal.jsonl'
    $journalParams=@{Path=$journal;TransactionId=[string]$Operation.TransactionId;
       OperationId=[string]$Operation.OperationId;Sequence=[long]2;Phase='Reconciled';
       SourceEntryId=[string]$Operation.EntryId;ArchiveEntryId=[string]$receipt.DestinationEntryId;
       ArchivePst=[string]$receipt.ArchivePst;SourceStoreId=[string]$Operation.FakeStoreId;
       SourceFolderPath=[string]$Operation.FolderPath;TargetFolderPath=[string]$receipt.TargetFolderPath;
       Message=('ARCH3e SYNTHETIC ONLY original verifier proof SHA='+$proofSha)}
    [void](Write-OPAOperationJournalEvent @journalParams)
    $resolvedAfter=Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $journal)
    if(@($resolvedAfter.Resolved).Count -ne 1 -or [string]$resolvedAfter.Resolved[0].Status -cne 'Reconciled'){
        throw 'ARCH3e original journal failed readback; index commit forbidden.'
    }
    # ORIGINAL DuplicateIndex append and readback in OS TEMP; fake PST absent.
    $index=Import-OPADuplicateIndex -ArchivePst ([string]$receipt.ArchivePst)
    if(Test-OPADuplicateEntry -Index $index -SourceEntryId ([string]$Operation.EntryId)){
        throw 'ARCH3e source already in original DuplicateIndex; no automatic replay.'
    }
    $indexParams=@{Index=$index;SourceEntryId=[string]$Operation.EntryId;ArchiveEntryId=[string]$receipt.DestinationEntryId;
       SourceFolderPath=[string]$Operation.FolderPath;TargetFolderPath=[string]$receipt.TargetFolderPath;
       TransactionId=[string]$Operation.TransactionId;ArchiveGrouping=[string]$Operation.ArchiveGrouping;
       SourcePst=[string]$Operation.SourcePst;ArchivePst=[string]$receipt.ArchivePst;Subject=$ExpectedSubject}
    Add-OPADuplicateEntry @indexParams
    $loaded=Import-OPADuplicateIndex -ArchivePst ([string]$receipt.ArchivePst)
    $entry=Test-OPADuplicateEntry -Index $loaded -SourceEntryId ([string]$Operation.EntryId)
    if($null -eq $entry -or [string]$entry.ArchiveEntryId -cne [string]$receipt.DestinationEntryId){
        throw 'ARCH3e original DuplicateIndex did not retain verified receipt identity.'
    }
    $indexPath=Get-OPADuplicateIndexJournalPath -ArchivePst ([string]$receipt.ArchivePst)
    if(-not [IO.File]::Exists($indexPath)){throw 'ARCH3e original DuplicateIndex journal absent.'}
    $indexSha=(Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $journalSha=(Get-FileHash -LiteralPath $journal -Algorithm SHA256).Hash.ToLowerInvariant()
    $seal=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3e.SyntheticIndexCommit.1'
        OperationId=[string]$Operation.OperationId
        ReceiptSha256=$ReceiptSha256
        IndependentSyntheticReviewSha256=$proofSha
        OriginalOperationJournalSha256=$journalSha
        OriginalDuplicateIndexJournalSha256=$indexSha
        SourceEntryId=[string]$Operation.EntryId
        ArchiveEntryId=[string]$receipt.DestinationEntryId
        OriginalVerifierUsed=$true
        FakeRestartOnly=$true
        WriterPermit=$false
        ProductionReady=$false
    }
    $finalSha=Write-OPA265ARCH3cJsonOnce -Path $indexSealFile -Record $seal
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3e.SyntheticCommitReturned.1'
        Status='OriginalVerifierThenOriginalOperationJournalAndDuplicateIndexSyntheticLinkedNoLiveCertification'
        OperationId=[string]$Operation.OperationId
        ReceiptSha256=$ReceiptSha256
        IndependentSyntheticReviewSha256=$proofSha
        FinalIndexSealSha256=$finalSha
        OriginalDuplicateIndexJournalSha256=$indexSha
        OriginalOperationJournalSha256=$journalSha
        OriginalVerifierUsed=$true
        DuplicateIndexCommitAfterVerification=$true
        SyntheticRestartOnly=$true
        LiveOutlookVerified=$false
        LiveMailMoved=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
