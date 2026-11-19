#requires -Version 5.1
# ARCH3q: ORIGINAL journal Reconciled then ORIGINAL append-only shared
# DuplicateIndex after independently REAL verified Outlook restart. No Move.
. (Join-Path $PSScriptRoot 'ARCH3qEvidence.ps1')

function Write-OPA265ARCH3qIndexAndSeal {
    [CmdletBinding()]
    param([object]$State,[string]$ReviewSha256,[string]$CommitClaimSha256,[switch]$Recovery)
    if($State.SealExists){throw 'ARCH3q final sealed index already exists.'}
    [void](Assert-OPA265ARCH3qOriginalJournalReconciled -State $State)
    $proof=Get-OPA265ARCH3qReviewSeal -State $State -ReviewSha256 $ReviewSha256
    $claim=Read-OPA265ARCH3cPinnedJson -Path $State.ClaimPath -ExpectedSha256 $CommitClaimSha256
    if([string]$claim.Schema -cne '2.6.5-ARCH3q.OriginalCommitClaim.1' -or
       [string]$claim.RunId -cne [string]$State.Intent.RunId -or
       [string]$claim.ReviewSha256 -cne $ReviewSha256 -or
       [string]$claim.SourceEntryId -cne [string]$State.Intent.SourceEntryId -or
       [string]$claim.ArchiveEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'){
        throw 'ARCH3q independent original index commit claim mismatch.'
    }
    if($State.IndexCount -eq 500){
        if($null -ne $State.ExistingIndexEntry){throw 'ARCH3q source is already in original index.'}
        $sealed=Get-OPA265ARCH3jSealedSource -SealRunId $State.Intent.SourceSealRunId -SealSha256 $State.Intent.SourceSealSha256
        $params=@{
            Index=$State.Index;SourceEntryId=[string]$State.Intent.SourceEntryId
            ArchiveEntryId='00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'
            SourceFolderPath=[string]$State.Journal.Events[0].SourceFolderPath
            TargetFolderPath=[string]$proof.Review.ArchiveFolderPath
            ReceivedTime=[datetime]::new([long]$sealed.ArchiveDateLocalTicks)
            Subject=[string]$State.Journal.Events[0].Subject
            TransactionId=('ARCH3j-'+[string]$State.Intent.RunId)
            TransactionLimit=1;ArchiveGrouping='Year';SourcePst=[string]$State.Intent.SourcePst
            ArchivePst=[string]$State.Intent.NewArchivePst
        }
        $old=$global:OPADurabilityMode
        try{
            $global:OPADurabilityMode='Safe'
            Add-OPADuplicateEntry @params
            Sync-OPADuplicateJournalStreams
        }finally{
            Close-OPADuplicateJournalStreams
            $global:OPADurabilityMode=$old
        }
    }elseif($State.IndexCount -ne 501){throw 'ARCH3q unsafe original 500/501 index state.'}
    # Independent ORIGINAL importer and durable file-hash readback.
    $loaded=Import-OPADuplicateIndex -ArchivePst $State.Intent.ExistingArchivePart1
    $entry=Test-OPADuplicateEntry -Index $loaded -SourceEntryId $State.Intent.SourceEntryId
    if(@($loaded.Entries).Count -ne 501 -or $null -eq $entry -or
       [string]$entry.ArchiveEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000' -or
       [string]$entry.ArchivePst -cne [string]$State.Intent.NewArchivePst -or
       [string]$entry.TransactionId -cne ('ARCH3j-'+[string]$State.Intent.RunId) -or
       [string]$entry.TargetFolderPath -cne [string]$proof.Review.ArchiveFolderPath){
        throw 'ARCH3q ORIGINAL shared DuplicateIndex independent 501 readback failed.'
    }
    $idxPath=Get-OPADuplicateIndexJournalPath -ArchivePst $State.Intent.ExistingArchivePart1
    if(-not [IO.File]::Exists($idxPath)){throw 'ARCH3q shared original JSONL absent.'}
    $indexSha=(Get-FileHash -LiteralPath $idxPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $journalSha=(Get-FileHash -LiteralPath $State.Layout.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $seal=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3q.OriginalVerifiedCommit.1';RunId=[string]$State.Intent.RunId
        ReviewSha256=$ReviewSha256;CommitClaimSha256=$CommitClaimSha256
        OriginalJournalSha256=$journalSha;OriginalSharedIndexSha256=$indexSha
        SourceEntryId=[string]$State.Intent.SourceEntryId
        ArchiveEntryId='00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'
        IndexEntryCount=501;OriginalJournalReconciled=$true
        OriginalArchiveVerifierUsed=$true;IndependentReadbackPassed=$true
        Recovered=$Recovery.IsPresent;AutomaticMoveRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
    $sealSha=Write-OPA265ARCH3cJsonOnce -Path $State.SealPath -Record $seal
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3q.OriginalCommitReturned.1'
        Status='OriginalJournalReconciledAndSharedDuplicateIndex501IndependentReadback'
        RunId=[string]$State.Intent.RunId;ReviewSha256=$ReviewSha256
        CommitClaimSha256=$CommitClaimSha256;CommitSealSha256=$sealSha
        OriginalJournalSha256=$journalSha;OriginalSharedIndexSha256=$indexSha
        OriginalIndexEntries=501;Recovered=$Recovery.IsPresent
        AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3qCommit {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory=$true)][ValidateSet('Plan','Seal','Commit','Recover','Status','Review')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256,
          [string]$ReviewSha256='',
          [string]$CommitClaimSha256='',
          [string]$CommitSealSha256='',
          [switch]$ConfirmSeal,
          [switch]$ConfirmVerifiedCommit,
          [switch]$ConfirmRecovery)
    $s=Get-OPA265ARCH3qState -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    if($Mode -cin @('Plan','Status')){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3q.ReadOnlyStatus.1';Status='OriginalOneShotJournalAndIndexForensicReadOnly'
            RunId=$RunId;OriginalJournalPhase=$s.JournalPhase;OriginalIndexEntryCount=$s.IndexCount
            ReviewSealed=$s.ProofExists;CommitClaimed=$s.ClaimExists;CommitSealed=$s.SealExists
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if($Mode -ceq 'Review'){
        if(-not $s.SealExists -or $s.JournalPhase -cne 'Reconciled' -or $s.IndexCount -ne 501){throw 'ARCH3q commit not complete.'}
        [void](Get-OPA265ARCH3qReviewSeal -State $s -ReviewSha256 $ReviewSha256)
        [void](Assert-OPA265ARCH3qOriginalJournalReconciled -State $s)
        $seal=Read-OPA265ARCH3cPinnedJson -Path $s.SealPath -ExpectedSha256 $CommitSealSha256
        $indexPath=Get-OPADuplicateIndexJournalPath -ArchivePst $s.Intent.ExistingArchivePart1
        $indexSha=(Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if([string]$seal.Schema -cne '2.6.5-ARCH3q.OriginalVerifiedCommit.1' -or
           [string]$seal.ReviewSha256 -cne $ReviewSha256 -or
           [string]$seal.CommitClaimSha256 -cne $CommitClaimSha256 -or
           [string]$seal.OriginalJournalSha256 -cne $s.JournalSha256 -or
           [string]$seal.OriginalSharedIndexSha256 -cne $indexSha -or
           -not [bool]$seal.IndependentReadbackPassed){throw 'ARCH3q immutable final original journal/index SHA drift.'}
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3q.FinalReadback.1'
            Status='OriginalReconciledSharedIndex501SealedReadbackConfirmed'
            RunId=$RunId;JournalPhase='Reconciled';IndexEntryCount=501
            OriginalJournalSha256=[string]$s.JournalSha256;OriginalSharedIndexSha256=$indexSha
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3q writes require native Windows PowerShell 5.1 -STA.'}
    if($Mode -ceq 'Seal'){
        if(-not $ConfirmSeal -or $s.ProofExists -or $s.ClaimExists -or $s.SealExists -or
           $s.JournalPhase -cne 'Intent' -or $s.IndexCount -ne 500){throw 'ARCH3q Seal requires clean original Intent, 500 entries and explicit confirmation.'}
        if(-not $PSCmdlet.ShouldProcess($s.ProofPath,'Seal independent REAL original ArchiveVerifier proof only')){
            return [pscustomobject]@{Schema='2.6.5-ARCH3q.WhatIf.1';Mode='Seal';NoWrites=$true}
        }
        $chain=New-OPA265ARCH3qLiveChain -State $s
        $live=Invoke-OPA265ARCH3pIndependentRestartReview -Chain $chain
        [void](Assert-OPA265ARCH3qLiveReview -Review $live -State $s)
        $again=Get-OPA265ARCH3qState -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
        if($again.ProofExists -or $again.ClaimExists -or $again.JournalPhase -cne 'Intent' -or $again.IndexCount -ne 500){
            throw 'ARCH3q original index or journal drift during real Seal.'
        }
        $record=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3q.IndependentRealReviewSeal.1';RunId=$RunId
            OriginalIntentSha256=$IntentSha256;OriginalJournalIntentSha256=$JournalSha256
            OriginalMoveClaimSha256=[string]$live.OriginalMoveClaimSha256
            Review=$live;OriginalIndexEntries=500
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
        $sha=Write-OPA265ARCH3cJsonOnce -Path $s.ProofPath -Record $record
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3q.ReviewSealed.1'
            Status='IndependentRealOriginalVerifierSealedOriginalJournalAndIndexUnchanged'
            RunId=$RunId;ReviewSha256=$sha;OriginalIndexEntries=500
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if($Mode -ceq 'Commit'){
        if(-not $ConfirmVerifiedCommit -or -not $s.ProofExists -or $s.ClaimExists -or $s.SealExists -or
           $s.JournalPhase -cne 'Intent' -or $s.IndexCount -ne 500){throw 'ARCH3q Commit requires original sealed proof, Intent, index 500 and explicit approval.'}
        $proof=Get-OPA265ARCH3qReviewSeal -State $s -ReviewSha256 $ReviewSha256
        if(-not $PSCmdlet.ShouldProcess($s.Intent.SourceEntryId,'One original Reconciled followed by one original shared index append; NEVER Move')){
            return [pscustomobject]@{Schema='2.6.5-ARCH3q.WhatIf.1';Mode='Commit';NoWrites=$true}
        }
        $chain=New-OPA265ARCH3qLiveChain -State $s
        $live=Invoke-OPA265ARCH3pIndependentRestartReview -Chain $chain
        [void](Assert-OPA265ARCH3qLiveReview -Review $live -State $s)
        if([string]$live.ObservedDestinationEntryId -cne [string]$proof.Review.ObservedDestinationEntryId){throw 'ARCH3q destination changed before original commit.'}
        $now=Get-OPA265ARCH3qState -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
        if($now.ClaimExists -or $now.SealExists -or $now.JournalPhase -cne 'Intent' -or $now.IndexCount -ne 500){throw 'ARCH3q original state changed before commit claim.'}
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3q.OriginalCommitClaim.1';RunId=$RunId
            ReviewSha256=$ReviewSha256;SourceEntryId=[string]$s.Intent.SourceEntryId
            ArchiveEntryId='00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'
            NoSecondReconciledOrMove=$true;WriterPermit=$false;ProductionReady=$false
        }
        $claimSha=Write-OPA265ARCH3cJsonOnce -Path $s.ClaimPath -Record $claim
        $e=$now.Journal.Events[0]
        $args=@{
            Path=[string]$s.Layout.JournalPath;TransactionId=('ARCH3j-'+$RunId)
            OperationId=[string]$s.Intent.OperationId;Sequence=[long]2;Phase='Reconciled'
            SourceEntryId=[string]$s.Intent.SourceEntryId
            ArchiveEntryId='00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'
            ArchivePst=[string]$s.Intent.NewArchivePst
            SourceStoreId=[string]$e.SourceStoreId;SourceFolderPath=[string]$e.SourceFolderPath
            TargetFolderPath=[string]$proof.Review.ArchiveFolderPath
            InternetMessageId=[string]$e.InternetMessageId;Subject=[string]$e.Subject
            Sender=[string]$e.Sender;Size=[long]$e.Size
            Message=('ARCH3q independent real ORIGINAL ArchiveVerifier ReviewSha256='+$ReviewSha256)
        }
        [void](Write-OPAOperationJournalEvent @args)
        $after=Get-OPA265ARCH3qState -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
        [void](Assert-OPA265ARCH3qOriginalJournalReconciled -State $after)
        return (Write-OPA265ARCH3qIndexAndSeal -State $after -ReviewSha256 $ReviewSha256 -CommitClaimSha256 $claimSha)
    }
    if($Mode -ceq 'Recover'){
        if(-not $ConfirmRecovery -or -not $s.ProofExists -or -not $s.ClaimExists -or $s.SealExists -or
           $s.JournalPhase -cne 'Reconciled' -or $s.IndexCount -notin @(500,501)){
            throw 'ARCH3q recovery requires existing Reconciled, unfinished index and explicit approval; never repeat journal or Move.'
        }
        $proof=Get-OPA265ARCH3qReviewSeal -State $s -ReviewSha256 $ReviewSha256
        $claim=Read-OPA265ARCH3cPinnedJson -Path $s.ClaimPath -ExpectedSha256 $CommitClaimSha256
        if([string]$claim.ReviewSha256 -cne $ReviewSha256){throw 'ARCH3q recovery original commit claim drift.'}
        [void](Assert-OPA265ARCH3qOriginalJournalReconciled -State $s)
        if(-not $PSCmdlet.ShouldProcess($s.Intent.SourceEntryId,'Recover only verified original index after existing Reconciled; NEVER Move or repeat Reconciled')){
            return [pscustomobject]@{Schema='2.6.5-ARCH3q.WhatIf.1';Mode='Recover';NoWrites=$true}
        }
        if($s.IndexCount -eq 500){
            $chain=New-OPA265ARCH3qLiveChain -State $s
            $live=Invoke-OPA265ARCH3pIndependentRestartReview -Chain $chain
            [void](Assert-OPA265ARCH3qLiveReview -Review $live -State $s)
            if([string]$live.ObservedDestinationEntryId -cne [string]$proof.Review.ObservedDestinationEntryId){
                throw 'ARCH3q recovery original real verifier mismatch; index not written.'
            }
        }
        $again=Get-OPA265ARCH3qState -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
        if($again.SealExists -or $again.JournalPhase -cne 'Reconciled'){throw 'ARCH3q recovery state changed.'}
        return (Write-OPA265ARCH3qIndexAndSeal -State $again -ReviewSha256 $ReviewSha256 -CommitClaimSha256 $CommitClaimSha256 -Recovery)
    }
}
