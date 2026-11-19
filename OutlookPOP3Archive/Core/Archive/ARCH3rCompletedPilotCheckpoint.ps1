#requires -Version 5.1
# ARCH3r immutable historical checkpoint of the operator-completed REAL
# ARCH3o original Move + ARCH3p original verifier + ARCH3q journal/index.
# Read-only; no new Outlook calls, no transaction/index mutations.
. (Join-Path $PSScriptRoot 'ARCH3qVerifiedJournalIndexCommit.ps1')

function Assert-OPA265ARCH3rRealCheckpointPins {
    [CmdletBinding()]
    param([string]$RunId,[string]$IntentSha256,[string]$JournalSha256,
          [string]$ReviewSha256,[string]$CommitClaimSha256,[string]$CommitSealSha256)
    $pins=[ordered]@{
        RunId='9d276dc4-a0e6-4e74-891f-81502fafe7db'
        IntentSha256='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
        JournalSha256='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
        ReviewSha256='3c455f4da4ee32fd9f0d046ac5e36cc3d013c0913cf86ddee69d359f700831c3'
        CommitClaimSha256='fc0e51d828d3b82fb3e46b22bdca6ff50f54f86366d1f9ec5ff5c937e221527a'
        CommitSealSha256='0fa26ba60ebe9685a6b13c5f989b1c5a840f54d5bc8302f87679b4e7dc6e67f0'
    }
    foreach($key in $pins.Keys){
        if([string](Get-Variable -Name $key -ValueOnly) -cne [string]$pins[$key]){
            throw ('ARCH3r operator accepted completed-pilot SHA pin mismatch: '+$key)
        }
    }
}

function Get-OPA265ARCH3rCompletedRealCheckpoint {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Plan','Audit')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256,
          [Parameter(Mandatory=$true)][string]$ReviewSha256,
          [Parameter(Mandatory=$true)][string]$CommitClaimSha256,
          [Parameter(Mandatory=$true)][string]$CommitSealSha256)
    $pinArgs=@{RunId=$RunId;IntentSha256=$IntentSha256;JournalSha256=$JournalSha256;ReviewSha256=$ReviewSha256;CommitClaimSha256=$CommitClaimSha256;CommitSealSha256=$CommitSealSha256}
    [void](Assert-OPA265ARCH3rRealCheckpointPins @pinArgs)
    $state=Get-OPA265ARCH3qState -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    if([string]$state.JournalPhase -cne 'Reconciled' -or
       [int]$state.IndexCount -ne 501 -or
       -not [bool]$state.ProofExists -or -not [bool]$state.ClaimExists -or
       -not [bool]$state.SealExists){
        throw 'ARCH3r real completed pilot is not original Reconciled with 501 index entries.'
    }
    if([string]$state.JournalSha256 -cne '6c0a0fc58935fe2bb1b5350b1e9d21400cbaccebcdfe40722aa95a3fa08d7d58'){
        throw 'ARCH3r historical ORIGINAL OperationJournal SHA changed.'
    }
    $indexPath=Get-OPADuplicateIndexJournalPath -ArchivePst ([string]$state.Intent.ExistingArchivePart1)
    if(-not [IO.File]::Exists($indexPath) -or
       (([IO.File]::GetAttributes($indexPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3r historical original shared DuplicateIndex JSONL unsafe.'
    }
    $indexSha=(Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($indexSha -cne '5ada35eb30f34ff60dc4b89f23aa071b72cc0b98e5ff57299d61f1714b13d7ae'){
        throw 'ARCH3r historical ORIGINAL shared DuplicateIndex SHA changed.'
    }
    [void](Assert-OPA265ARCH3qOriginalJournalReconciled -State $state)
    $result=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3r.RealCompletedPilotCheckpoint.1'
        Status=if($Mode -ceq 'Plan'){'OriginalRealCompletedPilotCheckpointPlanVerifiedReadOnly'}else{'OriginalRealCompletedPilotJournalIndexAndSemanticEvidenceIndependentlyAudited'}
        Mode=$Mode;RunId=$RunId
        SourceEntryId=[string]$state.Intent.SourceEntryId
        ArchiveEntryId='00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'
        OriginalFullWitnessSha256=[string]$state.Intent.FullOriginalWitnessSha256
        OriginalIntentSha256=$IntentSha256;OriginalIntentJournalSha256=$JournalSha256
        ProtectedIndependentReviewSha256=$ReviewSha256
        OriginalCommitClaimSha256=$CommitClaimSha256;OriginalCommitSealSha256=$CommitSealSha256
        OriginalOperationJournalSha256=[string]$state.JournalSha256
        OriginalSharedIndexSha256=$indexSha
        JournalPhase='Reconciled';OriginalSharedIndexEntryCount=501
        LiveOutlookContacted=$false;RealPstWritten=$false
        OriginalJournalOrIndexWritten=$false;AutomaticMoveRetryAllowed=$false
        ArchiveResumeAutoRemainClosed=$true;WriterPermit=$false;ProductionReady=$false
    }
    if($Mode -ceq 'Audit'){
        # ORIGINAL archived postcommit review remains read-only and verifies
        # both durable original journal and shared index file via SHA readback.
        $verified=Invoke-OPA265ARCH3qCommit -Mode Review @pinArgs
        if([string]$verified.Schema -cne '2.6.5-ARCH3q.FinalReadback.1' -or
           [string]$verified.Status -cne 'OriginalReconciledSharedIndex501SealedReadbackConfirmed' -or
           [string]$verified.OriginalJournalSha256 -cne [string]$result.OriginalOperationJournalSha256 -or
           [string]$verified.OriginalSharedIndexSha256 -cne [string]$result.OriginalSharedIndexSha256 -or
           [int]$verified.IndexEntryCount -ne 501){
            throw 'ARCH3r original independent ARCH3q final readback differs.'
        }
        $seal=Read-OPA265ARCH3cPinnedJson -Path ([string]$state.SealPath) -ExpectedSha256 $CommitSealSha256
        if([string]$seal.Schema -cne '2.6.5-ARCH3q.OriginalVerifiedCommit.1' -or
           [string]$seal.ReviewSha256 -cne $ReviewSha256 -or
           [string]$seal.CommitClaimSha256 -cne $CommitClaimSha256 -or
           [string]$seal.OriginalJournalSha256 -cne [string]$result.OriginalOperationJournalSha256 -or
           [string]$seal.OriginalSharedIndexSha256 -cne [string]$result.OriginalSharedIndexSha256 -or
           [int]$seal.IndexEntryCount -ne 501 -or
           -not [bool]$seal.OriginalJournalReconciled -or
           -not [bool]$seal.OriginalArchiveVerifierUsed -or
           -not [bool]$seal.IndependentReadbackPassed){
            throw 'ARCH3r final original verified commit seal is not independently valid.'
        }
        # Recheck archived original full semantic evidence and ARCH3o
        # immutable provider SHA, not trusting DuplicateIndex alone.
        $proof=Get-OPA265ARCH3qReviewSeal -State $state -ReviewSha256 $ReviewSha256
        if(-not [bool]$proof.Review.RealOutlookRestartConfirmed -or
           -not [bool]$proof.Review.OriginalVerifierSemanticMatch -or
           -not [bool]$proof.Review.OriginalVerifierSourceIdAbsent -or
           [int]$proof.Review.OriginalVerifierDestinationCount -ne 1){
            throw 'ARCH3r original real semantic postrestart evidence invalid.'
        }
        $result | Add-Member -NotePropertyName OriginalArchiveVerifierEvidencePresent -NotePropertyValue $true
        $result | Add-Member -NotePropertyName OriginalPostRestartSourceAbsentArchiveOne -NotePropertyValue $true
        $result | Add-Member -NotePropertyName OriginalFullSemanticWitnessVerified -NotePropertyValue $true
        $result | Add-Member -NotePropertyName OriginalIndependentIndexReadback -NotePropertyValue $true
    }
    return $result
}
