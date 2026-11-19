#requires -Version 5.1
# ARCH3s ORIGINAL ArchiveVerifier + ORIGINAL ARCH2b full SHA witness,
# followed only on PASS by original ARCH3r journal/index TEMP simulation.
# Zero real Outlook/PST/file writer paths. No MailItem.Move or batch permit.
. (Join-Path $PSScriptRoot 'ARCH3sFakeOutlookTenObjects.ps1')

function Invoke-OPA265ARCH3sOriginalVerifierTen {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Fixture)
    if(@($Fixture.ExpectedMoves).Count -ne 10 -or
       [IO.File]::Exists([string]$Fixture.ArchivePst)){
        throw 'ARCH3s fake Outlook fixture missing ten original witnesses or fake PST collision.'
    }
    # Call UNMODIFIED ORIGINAL Test-OPAArchiveMoves -> original
    # Test-OPAArchiveItemFingerprint -> ORIGINAL ARCH2b witness builder
    # with private TEMP SaveAsFile payload-byte SHA256.
    $args=@{
        Namespace=$Fixture.Namespace
        SourceFolder=@($Fixture.SourceFolder)
        ArchiveStores=@($Fixture.ArchiveStore)
        ExpectedMoved=10
        ExpectedMoves=@($Fixture.ExpectedMoves)
        RequireSemanticWitness=$true
    }
    $v=Test-OPAArchiveMoves @args
    $missing=@($v.MissingEntryIds)
    $warnings=@($v.WarningEntryIds)
    $unsafeWarnings=@($warnings | Where-Object {
        $_ -notlike 'STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT:*'
    })
    $accepted=([bool]$v.Verified -and [bool]$v.EntryIdsVerified -and
        [bool]$v.SemanticWitnessRequired -and
        [bool]$v.AllRequiredOriginalSemanticWitnessesPresent -and
        [int]$v.ExpectedMoved -eq 10 -and
        [int]$v.ExpectedEntryIdsChecked -eq 10 -and
        [int]$v.TargetCount -eq 10 -and
        [int]$v.ObservedSourceCount -eq 0 -and
        $missing.Count -eq 0 -and $unsafeWarnings.Count -eq 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3s.OriginalArchiveVerifierFakeTen.1'
        Status=if($accepted){'OriginalArchiveVerifierTenFakeMailItemsFullSemanticContentMatched'}else{'OriginalArchiveVerifierRejectedTenFakeMailItemsNoJournalIndexCommit'}
        OriginalArchiveVerifierPassed=[bool]$accepted
        OriginalArchiveVerifierUsed=$true
        OriginalArchiveVerifierImplementationReplaced=$false
        OriginalARCH2bFullSemanticWitnessReaderUsed=$true
        OriginalAttachmentSaveAsFileByteSha256Used=$true
        ExpectedMoved=10
        ExpectedEntryIdsChecked=[int]$v.ExpectedEntryIdsChecked
        ObservedSourceCount=[int]$v.ObservedSourceCount
        ObservedArchiveFolderCount=[int]$v.TargetCount
        MissingCodes=$missing
        WarningCodes=$warnings
        FakeOutlookOnly=$true
        RealOutlookContacted=$false
        RealPstOpenedOrWritten=$false
        RealMailMovePerformed=$false
        RealOriginalJournalOrIndexWritten=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3sTen {
    [CmdletBinding()]
    param(
        [ValidateSet('VerifierOnly','Integration')][string]$Mode='VerifierOnly',
        [ValidateSet('None','SourceStillPresent','DestinationMissing','ExtraDestination',
           'HtmlDrift','BodyDrift','RecipientDrift','AttachmentDrift','MissingOriginalWitness',
           'DuplicateSourceSelector','DuplicateArchiveSelector','WrongTargetFolder',
           'StaleArchiveIdUnique','StaleArchiveIdAmbiguous')][string]$VerifierFault='None',
        [ValidateSet('None','AfterJournalReconciled','AfterIndexAppend')][string]$JournalFault='None',
        [ValidateRange(1,10)][int]$FaultAt=4,
        [string]$SyntheticTempRoot=[IO.Path]::GetTempPath()
    )
    if($Mode -eq 'VerifierOnly' -and $JournalFault -ne 'None'){
        throw 'ARCH3s journal/index simulation requires Integration mode.'
    }
    if($JournalFault -ne 'None' -and $VerifierFault -ne 'None'){
        throw 'ARCH3s only one synthetic fault permitted at once.'
    }
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $base=[IO.Path]::GetFullPath($SyntheticTempRoot)
    if(-not $base.EndsWith([IO.Path]::DirectorySeparatorChar)){$base += [IO.Path]::DirectorySeparatorChar}
    $isOsTemp=([string]::Equals($base.TrimEnd([char]92,[char]47),
        $temp.TrimEnd([char]92,[char]47),[StringComparison]::OrdinalIgnoreCase))
    if(-not ($isOsTemp -or $base.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) -or
       -not [IO.Directory]::Exists($base) -or
       (([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3s requires pre-existing OS TEMP subdirectory, never real PST paths.'
    }
    $workspace=Join-Path $base ('OPA265-ARCH3s-FAKE-'+[guid]::NewGuid().ToString('N'))
    if([IO.Directory]::Exists($workspace) -or [IO.File]::Exists($workspace)){
        throw 'ARCH3s synthetic workspace collides; no retries.'
    }
    [void][IO.Directory]::CreateDirectory($workspace)
    $fixture=New-OPA265ARCH3sFakeOutlook -VerifierFault $VerifierFault -FaultAt $FaultAt -Workspace $workspace
    $r=Invoke-OPA265ARCH3sOriginalVerifierTen -Fixture $fixture
    $r | Add-Member -NotePropertyName Mode -NotePropertyValue $Mode
    $r | Add-Member -NotePropertyName VerifierFault -NotePropertyValue $VerifierFault
    $r | Add-Member -NotePropertyName JournalFault -NotePropertyValue $JournalFault
    $r | Add-Member -NotePropertyName SyntheticWorkspace -NotePropertyValue $workspace
    $r | Add-Member -NotePropertyName OriginalJournalIndexIntegrationExecuted -NotePropertyValue $false
    $r | Add-Member -NotePropertyName OriginalJournalReconciledCount -NotePropertyValue 0
    $r | Add-Member -NotePropertyName OriginalSharedIndexEntryCount -NotePropertyValue 0
    if(-not [bool]$r.OriginalArchiveVerifierPassed -or $Mode -ceq 'VerifierOnly'){
        return $r
    }
    # Exact separation of assertions: fake original verifier first,
    # independent ARCH3r TEMP journal/index model only after its PASS.
    $next=Invoke-OPA265ARCH3rSyntheticTen -InjectFault $JournalFault -FaultAt $FaultAt -SyntheticTempRoot $workspace
    if([int]$next.SyntheticMoveClaims -ne 10 -or
       [int]$next.SyntheticFullSemanticComparisons -ne 10 -or
       -not [bool]$next.OriginalJournalFunctionsUsed -or
       -not [bool]$next.OriginalDuplicateIndexFunctionsUsed){
        throw 'ARCH3s TEMP-only original journal/index model incomplete after verifier.'
    }
    $r.OriginalJournalIndexIntegrationExecuted=$true
    $r.OriginalJournalReconciledCount=[int]$next.OriginalOperationJournalReconciledCount
    $r.OriginalSharedIndexEntryCount=[int]$next.OriginalSharedIndexEntryCount
    $r | Add-Member -NotePropertyName OriginalJournalEventCount -NotePropertyValue ([int]$next.OriginalOperationJournalEventCount)
    $r | Add-Member -NotePropertyName OriginalJournalIndeterminateCount -NotePropertyValue ([int]$next.OriginalOperationJournalIndeterminateCount)
    $r | Add-Member -NotePropertyName OriginalJournalSha256 -NotePropertyValue ([string]$next.OriginalOperationJournalSha256)
    $r | Add-Member -NotePropertyName OriginalSharedIndexSha256 -NotePropertyValue ([string]$next.OriginalSharedIndexSha256)
    $r | Add-Member -NotePropertyName OriginalJournalWorkspace -NotePropertyValue ([string]$next.SyntheticWorkspace)
    if($JournalFault -eq 'None'){
        if([int]$r.OriginalJournalEventCount -ne 20 -or
           [int]$r.OriginalJournalReconciledCount -ne 10 -or
           [int]$r.OriginalSharedIndexEntryCount -ne 10 -or
           [int]$r.OriginalJournalIndeterminateCount -ne 0){
            throw 'ARCH3s original verifier PASS but original journal/index ten readback failed.'
        }
        $r.Status='OriginalArchiveVerifierTenThenOriginalJournalIndexTenFullReadbackNoLiveWriter'
    }else{
        if($JournalFault -eq 'AfterJournalReconciled' -and
           ($r.OriginalSharedIndexEntryCount -ne 0 -or $r.OriginalJournalReconciledCount -ne $FaultAt)){
            throw 'ARCH3s partial Reconciled failpoint did not stop at intended boundary.'
        }
        if($JournalFault -eq 'AfterIndexAppend' -and
           ($r.OriginalSharedIndexEntryCount -ne $FaultAt -or $r.OriginalJournalReconciledCount -ne 10)){
            throw 'ARCH3s partial index append failpoint did not stop at intended boundary.'
        }
        $r.Status='OriginalArchiveVerifierTenThenSyntheticPartialJournalIndexCommitStoppedNoAutoRetry'
    }
    return $r
}
