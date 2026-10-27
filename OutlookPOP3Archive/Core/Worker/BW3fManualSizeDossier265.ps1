#requires -Version 5.1
# BW3f: pure human-decision DOSSIER classification of an independently
# observed BW3e synthetic BODY tail, not an approval or journal operation.
# This file contains NO Outlook COM, persistence, or production entry point.
function Assert-OPA265BW3fExactBoolean {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [Parameter(Mandatory=$true)][string]$Field,
          [Parameter(Mandatory=$true)][bool]$Expected)
    if ($Evidence.PSObject.Properties.Name -cnotcontains $Field -or
        $Evidence.$Field -isnot [bool] -or
        $Evidence.$Field -ne $Expected) {
        throw ('BW3f rejects missing, non-Boolean or mismatched '+$Field)
    }
    return $true
}
function Assert-OPA265BW3fExactTailArray {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [Parameter(Mandatory=$true)][string]$Field)
    if ($Evidence.PSObject.Properties.Name -cnotcontains $Field -or
        $Evidence.$Field -isnot [array]) {
        throw ('BW3f rejects absent or non-array Unicode evidence: '+$Field)
    }
    $a=@($Evidence.$Field)
    if ($a.Count -ne 3) {
        throw ('BW3f expected exactly three Unicode units in '+$Field)
    }
    foreach($i in 0..2) {
        if ($a[$i] -isnot [int] -and $a[$i] -isnot [long]) {
            throw ('BW3f Unicode code unit must be numeric in '+$Field)
        }
    }
    if ([int]$a[0] -ne 32 -or [int]$a[1] -ne 13 -or [int]$a[2] -ne 10) {
        throw ('BW3f rejects different Unicode suffix in '+$Field)
    }
    return $true
}
function Assert-OPA265BW3fHistoricalAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Audit,
          [Parameter(Mandatory=$true)][object]$Pinned)
    $original=Get-OPA265BW3ePinnedTailEvidence
    if ($null -eq $Audit -or $Audit -is [array] -or $Audit -is [string] -or
        $null -eq $Pinned -or
        [string]$Pinned.RunId -cne [string]$original.RunId -or
        [string]$Pinned.OperationId -cne [string]$original.OperationId -or
        [string]$Pinned.WorkerRequestId -cne [string]$original.WorkerRequestId -or
        [string]$Pinned.JournalSha256 -cne [string]$original.JournalSha256 -or
        [string]$Pinned.ArchiveEntryId -cne [string]$original.ArchiveEntryId -or
        [string]$Pinned.SourcePst -cne [string]$original.SourcePst -or
        [long]$Pinned.IntentSizeBytes -ne 1436 -or
        [long]$Pinned.ArchiveSizeBytes -ne 1444 -or
        [long]$Pinned.SizeDifferenceBytes -ne 8 -or
        [string]$Pinned.ExpectedBodySha256 -cne [string]$original.ExpectedBodySha256 -or
        [string]$Pinned.FixtureBody -cne [string]$original.FixtureBody) {
        throw 'BW3f is pinned to one historical synthetic evidence set only.'
    }
    # Fixed expected schema prevents a synthetic "success" object with an
    # arbitrary extra waiver/approval field from being interpreted as proof.
    $expectedFields=@('Schema','Status','Decision','RunId','OperationId',
        'WorkerRequestId','JournalSha256','ArchivedMailEntryId',
        'ExpectedBaselineBodyLength','ObservedBodyLength','ExpectedBodyLength',
        'ObservedTailUnicodeCodeUnits','ExpectedTailUnicodeCodeUnits',
        'ExpectedTailUtf8Bytes','ObservedBodyUtf8Sha256',
        'ExpectedObservedBodyUtf8Sha256','BodyTextMatchesExactBaselinePlusSpaceCrLf',
        'TailSpaceCrLfConfirmed',
        'NormalizedByRemovingExactlyThreeSuffixCharsMatchesBaseline',
        'TrailingSpaceBeforeCrLfObserved','IntentSizeBytes','ArchivedSizeBytes',
        'UnapprovedSizeDifferenceBytes','PrMessageSizeMatchedMailItemSize',
        'SourceItemCount','ArchiveItemCount','AttachmentsCount',
        'ArchiveEntryIdMatchesWorker','ClaimsCorrelated',
        'BeforeMoveActualBodyHashAvailable',
        'WhenTailWasIntroducedEstablished','SizeDifferenceCauseEstablished',
        'ContentByteEqualityVerified','ArchiveSizeDifferenceApproved',
        'ManualJournalDecisionAuthorized','RequiresManualSizeReview',
        'OutlookMoveExecuted','JournalChanged','JournalCompleted',
        'JournalReconciled','AutomaticRetryAllowed','ProductionReady',
        'NextAction')
    $actualFields=@($Audit.PSObject.Properties.Name)
    if ($actualFields.Count -ne $expectedFields.Count) {
        throw 'BW3f rejects unexpected BW3e audit field count.'
    }
    foreach($f in $expectedFields) {
        if ($actualFields -cnotcontains $f) {
            throw ('BW3f missing audited evidence field: '+$f)
        }
    }
    if ([string]$Audit.Schema -cne '2.6.5-BW3e.SyntheticBodyTailReadOnlyEvidence.1' -or
        [string]$Audit.Status -cne 'SyntheticBodyTailSpaceCrLfConfirmed' -or
        [string]$Audit.Decision -cne 'BodyTailEvidenceOnlySizeDifferenceStillUnapproved' -or
        [string]$Audit.RunId -cne [string]$Pinned.RunId -or
        [string]$Audit.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Audit.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Audit.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Audit.ArchivedMailEntryId -cne [string]$Pinned.ArchiveEntryId -or
        [int]$Audit.ExpectedBaselineBodyLength -ne 50 -or
        [int]$Audit.ObservedBodyLength -ne 53 -or
        [int]$Audit.ExpectedBodyLength -ne 53 -or
        [string]$Audit.ObservedBodyUtf8Sha256 -cne [string]$Pinned.ExpectedBodySha256 -or
        [string]$Audit.ExpectedObservedBodyUtf8Sha256 -cne [string]$Pinned.ExpectedBodySha256 -or
        [long]$Audit.IntentSizeBytes -ne 1436 -or
        [long]$Audit.ArchivedSizeBytes -ne 1444 -or
        [long]$Audit.UnapprovedSizeDifferenceBytes -ne 8 -or
        [int]$Audit.SourceItemCount -ne 0 -or
        [int]$Audit.ArchiveItemCount -ne 1 -or
        [int]$Audit.AttachmentsCount -ne 0 -or
        [string]$Audit.NextAction -cne 'PreserveIntentClaimsAndAwaitExplicitIndependentSizeDecision') {
        throw 'BW3f cannot verify exact BW3e operation or +8-byte evidence.'
    }
    [void](Assert-OPA265BW3fExactTailArray -Evidence $Audit -Field 'ObservedTailUnicodeCodeUnits')
    [void](Assert-OPA265BW3fExactTailArray -Evidence $Audit -Field 'ExpectedTailUnicodeCodeUnits')
    [void](Assert-OPA265BW3fExactTailArray -Evidence $Audit -Field 'ExpectedTailUtf8Bytes')
    foreach($name in @(
        'PrMessageSizeMatchedMailItemSize','BodyTextMatchesExactBaselinePlusSpaceCrLf',
        'TailSpaceCrLfConfirmed','NormalizedByRemovingExactlyThreeSuffixCharsMatchesBaseline',
        'TrailingSpaceBeforeCrLfObserved','ArchiveEntryIdMatchesWorker','ClaimsCorrelated',
        'RequiresManualSizeReview')) {
        [void](Assert-OPA265BW3fExactBoolean -Evidence $Audit -Field $name -Expected $true)
    }
    foreach($name in @(
        'BeforeMoveActualBodyHashAvailable','WhenTailWasIntroducedEstablished',
        'SizeDifferenceCauseEstablished','ContentByteEqualityVerified',
        'ArchiveSizeDifferenceApproved','ManualJournalDecisionAuthorized',
        'OutlookMoveExecuted','JournalChanged','JournalCompleted',
        'JournalReconciled','AutomaticRetryAllowed','ProductionReady')) {
        [void](Assert-OPA265BW3fExactBoolean -Evidence $Audit -Field $name -Expected $false)
    }
    return $true
}
function Get-OPA265BW3fDecisionDossier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Audit,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3fHistoricalAudit -Audit $Audit -Pinned $Pinned)
    # An audit is factual evidence, NOT an operator consent. This verdict
    # has no writable output path and cannot authorize a LIVE6a executor.
    return [pscustomobject]@{
        Schema='2.6.5-BW3f.ManualSizeDecisionDossier.1'
        Status='EvidenceDossierReadyHumanDecisionPending'
        Decision='DeferJournalResolutionUntilSeparateExplicitAuthorization'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        JournalSha256=[string]$Pinned.JournalSha256
        DestinationEntryId=[string]$Pinned.ArchiveEntryId
        PriorBw3eStatus=[string]$Audit.Status
        WorkerMoveIdentityObserved=$true
        SourceItemCount=0
        ArchiveItemCount=1
        ClaimsCorrelated=$true
        BodySuffixConfirmed=$true
        BodyTailCodeUnits=[int[]]@(32,13,10)
        BodyLengthBeforeFixtureNormalization=53
        FixtureBaselineBodyLength=50
        ArchivedBodyUtf8Sha256=[string]$Audit.ObservedBodyUtf8Sha256
        AttachmentsCount=0
        ProviderSizeCrossCheckMatches=$true
        IntentSizeBytes=1436L
        ArchivedSizeBytes=1444L
        UnapprovedSizeDifferenceBytes=8L
        BeforeMoveActualBodyHashCaptured=$false
        TimingOfBodySuffixEstablished=$false
        CauseOfMAPIByteSizeDriftEstablished=$false
        MAPIStreamOrFullItemByteEqualityVerified=$false
        SizeDifferenceAcceptableAutomatically=$false
        SizeDifferenceApproved=$false
        HumanSizeDecisionRecorded=$false
        HumanSizeDecisionValue='Unrecorded'
        AdditionalExplicitOperatorConsentRequired=$true
        ManualJournalDecisionAuthorized=$false
        WriteableReconciliationPermitIssued=$false
        EvidencePacketPersisted=$false
        OnlyRunScopedSyntheticFoldersInspected=$true
        OutlookMoveExecuted=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='PreserveOriginalEvidenceAndObtainSeparateExplicitManualSizeDecision'
    }
}
