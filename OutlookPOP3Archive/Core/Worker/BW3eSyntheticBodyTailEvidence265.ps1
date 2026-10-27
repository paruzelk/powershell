#requires -Version 5.1
# BW3e pure read-only body-tail proof for ONE historical synthetic Move.
# No Outlook COM, file writes, retry, size consent or journal resolution.
function Get-OPA265BW3ePinnedTailEvidence {
    [CmdletBinding()]
    param()
    $p=Get-OPA265BW3dPinnedSizeReview
    return [pscustomobject]@{
        RunId=[string]$p.RunId
        OperationId=[string]$p.OperationId
        WorkerRequestId=[string]$p.WorkerRequestId
        SourcePst=[string]$p.SourcePst
        ArchiveEntryId=[string]$p.ArchiveEntryId
        JournalSha256=[string]$p.JournalSha256
        IntentSizeBytes=1436L
        ArchiveSizeBytes=1444L
        SizeDifferenceBytes=8L
        FixtureBody=[string]$p.FixtureBody
        ExpectedBodySha256='82d1b1508ec29fab365b819df44c5ef24ba2dd9a68612579d474daa4949ff29e'
        ExpectedTailUnicodeCodeUnits=@(32,13,10)
        ExpectedTailUtf8Bytes=@(32,13,10)
    }
}
function Assert-OPA265BW3ePriorSizeEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Previous,
          [Parameter(Mandatory=$true)][object]$Pinned)
    $expected=Get-OPA265BW3ePinnedTailEvidence
    if ([string]$Pinned.RunId -cne [string]$expected.RunId -or
        [string]$Pinned.OperationId -cne [string]$expected.OperationId -or
        [string]$Pinned.WorkerRequestId -cne [string]$expected.WorkerRequestId -or
        [string]$Pinned.SourcePst -cne [string]$expected.SourcePst -or
        [string]$Pinned.ArchiveEntryId -cne [string]$expected.ArchiveEntryId -or
        [string]$Pinned.JournalSha256 -cne [string]$expected.JournalSha256 -or
        [string]$Pinned.FixtureBody -cne [string]$expected.FixtureBody -or
        [string]$Pinned.ExpectedBodySha256 -cne [string]$expected.ExpectedBodySha256 -or
        [long]$Pinned.IntentSizeBytes -ne 1436 -or
        [long]$Pinned.ArchiveSizeBytes -ne 1444 -or
        [long]$Pinned.SizeDifferenceBytes -ne 8) {
        throw 'BW3e rejects modified pinned historical synthetic evidence.'
    }
    if ([string]$Previous.Schema -cne '2.6.5-BW3d.SyntheticSizeReadOnlyEvidence.1' -or
        [string]$Previous.Status -cne 'UnexpectedSyntheticContentStopAndInvestigate' -or
        [string]$Previous.Decision -cne 'SizeDifferenceUnapprovedManualDecisionRequired' -or
        [string]$Previous.RunId -cne [string]$Pinned.RunId -or
        [string]$Previous.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Previous.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Previous.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        -not [bool]$Previous.ArchiveEntryIdMatchesWorker -or
        [long]$Previous.IntentSizeBytes -ne 1436 -or
        [long]$Previous.ObservedArchiveSizeBytes -ne 1444 -or
        [long]$Previous.SizeDifferenceBytes -ne 8 -or
        -not [bool]$Previous.PinnedEightByteDriftObserved -or
        [string]$Previous.ExpectedSyntheticBodyUtf8Sha256 -cne
            (Get-OPA265BW3dUtf8TextSha256 -Text ([string]$Pinned.FixtureBody)) -or
        [string]$Previous.ObservedBodyUtf8Sha256 -cne [string]$Pinned.ExpectedBodySha256 -or
        [bool]$Previous.BodyTextMatchesFixtureExactly -or
        [bool]$Previous.BodyTextMatchesAfterTrailingCrLfTrim -or
        [int]$Previous.ExpectedAttachmentCount -ne 0 -or
        [int]$Previous.ObservedAttachmentCount -ne 0 -or
        -not [bool]$Previous.AttachmentsCountMatchesFixture -or
        -not [bool]$Previous.MessageClassMatchesFixture -or
        -not [bool]$Previous.PrMessageSizeAvailable -or
        [long]$Previous.PrMessageSizeBytes -ne 1444 -or
        -not [bool]$Previous.PrMessageSizeMatchesMailItemSize -or
        [bool]$Previous.EvidenceSufficientForContentByteEquality -or
        [bool]$Previous.EvidenceSufficientForAutomaticSizeApproval -or
        [bool]$Previous.ArchiveSizeDifferenceApproved -or
        -not [bool]$Previous.RequiresManualSizeReview -or
        [bool]$Previous.ManualJournalDecisionAuthorized -or
        -not [bool]$Previous.OnlySyntheticFoldersInspected -or
        -not [bool]$Previous.OutlookReadOnlyInspectionExecuted -or
        [bool]$Previous.OutlookMoveExecuted -or
        [bool]$Previous.JournalChanged -or
        [bool]$Previous.JournalCompleted -or
        [bool]$Previous.JournalReconciled -or
        [bool]$Previous.AutomaticRetryAllowed -or
        [bool]$Previous.ProductionReady -or
        [string]$Previous.NextAction -cne 'PreserveIntentClaimsAndRequestIndependentSizeDecision') {
        throw 'BW3e requires exact unresolved read-only BW3d size evidence.'
    }
    return $true
}
function Get-OPA265BW3eTailCodeUnits {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
          [ValidateRange(1,16)][int]$Count=3)
    $start=[Math]::Max(0,$Text.Length-$Count)
    $units=New-Object 'System.Collections.Generic.List[int]'
    for($i=$start;$i -lt $Text.Length;$i++) {
        [void]$units.Add([int][char]$Text[$i])
    }
    return ,([int[]]$units.ToArray())
}
function Get-OPA265BW3eTailVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$BodyText,
          [Parameter(Mandatory=$true)][object]$Previous,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3ePriorSizeEvidence -Previous $Previous -Pinned $Pinned)
    $candidate=[string]$Pinned.FixtureBody+[char]32+[char]13+[char]10
    $expectedHash=Get-OPA265BW3dUtf8TextSha256 -Text $candidate
    if ([string]$expectedHash -cne [string]$Pinned.ExpectedBodySha256) {
        throw 'BW3e candidate body SHA256 does not match the observed pinned digest.'
    }
    $observedHash=Get-OPA265BW3dUtf8TextSha256 -Text $BodyText
    $actualUnits=@(Get-OPA265BW3eTailCodeUnits -Text $BodyText -Count 3)
    $observedMatches=[string]::Equals($BodyText,$candidate,[StringComparison]::Ordinal)
    $tailMatches=($actualUnits.Count -eq 3 -and
        $actualUnits[0] -eq 32 -and $actualUnits[1] -eq 13 -and
        $actualUnits[2] -eq 10)
    # Positive verdict needs BOTH full-body exact match and pinned SHA256.
    $confirmed=($observedMatches -and $tailMatches -and
        [string]$observedHash -ceq [string]$Pinned.ExpectedBodySha256)
    return [pscustomobject]@{
        Schema='2.6.5-BW3e.SyntheticBodyTailReadOnlyEvidence.1'
        Status=$(if($confirmed){'SyntheticBodyTailSpaceCrLfConfirmed'}else{'UnexpectedBodyTailStopAndInvestigate'})
        Decision='BodyTailEvidenceOnlySizeDifferenceStillUnapproved'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        JournalSha256=[string]$Pinned.JournalSha256
        ArchivedMailEntryId=[string]$Pinned.ArchiveEntryId
        ExpectedBaselineBodyLength=[int]([string]$Pinned.FixtureBody).Length
        ObservedBodyLength=[int]$BodyText.Length
        ExpectedBodyLength=[int]$candidate.Length
        ObservedTailUnicodeCodeUnits=[int[]]$actualUnits
        ExpectedTailUnicodeCodeUnits=[int[]]@(32,13,10)
        ExpectedTailUtf8Bytes=[int[]]@(32,13,10)
        ObservedBodyUtf8Sha256=[string]$observedHash
        ExpectedObservedBodyUtf8Sha256=[string]$Pinned.ExpectedBodySha256
        BodyTextMatchesExactBaselinePlusSpaceCrLf=$confirmed
        TailSpaceCrLfConfirmed=$confirmed
        NormalizedByRemovingExactlyThreeSuffixCharsMatchesBaseline=$confirmed
        TrailingSpaceBeforeCrLfObserved=$confirmed
        IntentSizeBytes=[long]$Pinned.IntentSizeBytes
        ArchivedSizeBytes=[long]$Pinned.ArchiveSizeBytes
        UnapprovedSizeDifferenceBytes=[long]$Pinned.SizeDifferenceBytes
        PrMessageSizeMatchedMailItemSize=$true
        SourceItemCount=0
        ArchiveItemCount=1
        AttachmentsCount=0
        ArchiveEntryIdMatchesWorker=$true
        ClaimsCorrelated=$true
        BeforeMoveActualBodyHashAvailable=$false
        WhenTailWasIntroducedEstablished=$false
        SizeDifferenceCauseEstablished=$false
        ContentByteEqualityVerified=$false
        ArchiveSizeDifferenceApproved=$false
        ManualJournalDecisionAuthorized=$false
        RequiresManualSizeReview=$true
        OutlookMoveExecuted=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='PreserveIntentClaimsAndAwaitExplicitIndependentSizeDecision'
    }
}
