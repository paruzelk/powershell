#requires -Version 5.1
# BW4k7j: original Attachment1K ONLY. Cross-validate BW4k7i post-restart
# semantic audit + independent Microsoft MAPI flag classification.
# Read-only. No MailItem.Move, Save, Delete, Claim or evidence writer.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceEvidenceSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedDecisionSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedSemanticSnapshotSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedClaimSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedDestinationEntryId,
    [Parameter(Mandatory=$true)][string]$ExpectedDestinationFolderEntryId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [Parameter(Mandatory=$true)][string]$ExpectedBaselineSha256,
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7j requires native Windows PowerShell 5.1 STA.'
}
if($ExpectedBaselineSha256 -cne 'f75594047529cca19bbeb8d2a52db5412187325a39db4d659dc85b4b41d44399' -or
   $SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
   $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
   $ExpectedClaimSha256 -cne '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c' -or
   $ExpectedSemanticSnapshotSha256 -cne 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac' -or
   $ExpectedDestinationEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B24002000' -or
   $ExpectedDestinationFolderEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B82800000'){
    throw 'BW4k7j exact immutable pre-Move, Claim, and post-restart evidence required.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7jRawMessageFlagPolicy265.ps1')
$stage='Reverify original exact BW4k7i archive baseline and actual Outlook restart'
try{
    $a=@{
        Mode='VerifyAfterReopen'
        SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        ExpectedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
        ExpectedDecisionSha256=$ExpectedDecisionSha256
        ExpectedSemanticSnapshotSha256=$ExpectedSemanticSnapshotSha256
        ExpectedClaimSha256=$ExpectedClaimSha256
        ExpectedDestinationEntryId=$ExpectedDestinationEntryId
        ExpectedDestinationFolderEntryId=$ExpectedDestinationFolderEntryId
        SourcePst=$SourcePst
        DestinationPst=$DestinationPst
        ExpectedBaselineSha256=$ExpectedBaselineSha256
        ExpectedProfileName=$ExpectedProfileName
    }
    $reopened=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7iReopenIntegrityReview.ps1') @a
    if([string]$reopened.Schema -cne '2.6.5-BW4k7i.AfterOutlookRestartSemanticReview.1' -or
       [string]$reopened.Status -cne 'ReopenedOutlookSourceZeroDestinationOneCapturedSemanticsStableUnknownFlagStillBlocked' -or
       [string]$reopened.VerifiedImmutableBaselineSha256 -cne $ExpectedBaselineSha256 -or
       [int]$reopened.SourceMessageIdMatches -ne 0 -or
       [int]$reopened.DestinationMessageIdMatches -ne 1 -or
       [string]$reopened.DestinationEntryId -cne $ExpectedDestinationEntryId -or
       [string]$reopened.DestinationUserStateSha256 -cne '05cceab7d9f7fd7c508d8017f023522a60e4d840a6248726faa2432008f08e25' -or
       -not [bool]$reopened.ActualNewOutlookProcessObserved -or
       -not [bool]$reopened.ArchiveContentRecipientAttachmentShaStable -or
       -not [bool]$reopened.AllCapturedUserFieldsStable -or
       -not [bool]$reopened.RawMapiFlagsStableSinceBaseline -or
       -not [bool]$reopened.OutlookArchiveReadAfterRealProcessRestart -or
       [bool]$reopened.UnknownFlagWaived -or
       [bool]$reopened.HistoricalPostmoveMismatchAutomaticallyReclassified -or
       [bool]$reopened.PhysicalPstDurabilityFullyProven -or
       [bool]$reopened.OriginalClaimOrJournalModified -or
       [bool]$reopened.OutlookMailMoveExecuted -or
       [bool]$reopened.AutomaticRetryAllowed -or
       [bool]$reopened.WriterPermit -or
       [bool]$reopened.ProductionReady){
        throw 'BW4k7j BW4k7i verified archive/restart/read-only evidence changed.'
    }
    $stage='Independently classify ONLY original documented and unknown PidTagMessageFlags bits'
    $flags=Get-OPA265BW4k7jFlagDifference -OriginalFlags 65555 -DestinationFlags 17
    [void](Assert-OPA265BW4k7jExactOriginalClassification -Result $flags)
    $stage='Ensure unmodified immutable BW4k7i proof on disk still matches exact SHA after reread'
    $baseline=Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4k7i-ReopenBaselines\suite-74912f94-d523-4856-9efd-d5528a92426f\fixture-87e72fd0-9e77-4098-a403-cbe99870b9e7.json'
    if(-not [IO.File]::Exists($baseline) -or
       (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedBaselineSha256){
        throw 'BW4k7j original BW4k7i immutable baseline missing or modified.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7j.IndependentDocumentedMessageFlagReview.1'
        Status='ReopenedArchiveStableDocumentedUnmodifiedAndUnknown0x00010000RequireSeparateReview'
        SuiteId=$SuiteId
        TestId=$TestId
        OriginalOneShotClaimSha256=$ExpectedClaimSha256
        VerifiedOriginalRecipientStateSnapshotSha256=$ExpectedSemanticSnapshotSha256
        VerifiedImmutableReopenBaselineSha256=$ExpectedBaselineSha256
        ActualNewOutlookProcessObserved=$true
        SourceMessageIdMatches=0
        DestinationMessageIdMatches=1
        DestinationEntryId=$ExpectedDestinationEntryId
        ArchiveContentRecipientAttachmentShaStable=$true
        AllCapturedUserFieldsStable=$true
        RawMapiFlagsStableSinceReopenBaseline=$true
        OriginalRawPrMessageFlags=[int]$flags.OriginalFlags
        DestinationRawPrMessageFlags=[int]$flags.DestinationFlags
        OriginalRawPrMessageFlagsHex=[string]$flags.OriginalFlagsHex
        DestinationRawPrMessageFlagsHex=[string]$flags.DestinationFlagsHex
        ChangedRawFlagMaskHex=[string]$flags.ChangedMaskHex
        ChangedBitCount=[int]$flags.ChangedBitCount
        ChangedBits=@($flags.ChangedBits)
        DocumentedUnmodifiedBit0x00000002='mfUnmodified;ClearedAfterStoreModification'
        UnknownBit0x00010000='NotDefinedInReviewedMsOxcmsgPidTagMessageFlagsTable'
        SeparateStoreSupportMask0x00010000='STORE_HTML_OK;DifferentProperty;NotEvidenceOfMessageFlagsMeaning'
        SeparateMessageStatusBits0x00010000='DifferentProperty;NotEvidenceOfMessageFlagsMeaning'
        KnownModificationStateChangeCount=[int]$flags.KnownModificationStateChangeCount
        UnspecifiedChangedBitCount=[int]$flags.UnspecifiedChangedBitCount
        ReadAndHasAttachBitsUnchanged=[bool]$flags.ReadAndHasAttachBitsUnchanged
        CrossPropertyConstantNameReused=$false
        OriginalFullRawUserStateShaMismatchAccepted=$false
        ChangedBit0x00010000Waived=$false
        HistoricalPostmoveMismatchAutomaticallyReclassified=$false
        PhysicalPstDurabilityFullyProven=$false
        FullProductionSignificantFlagCoverageProven=$false
        ExistingClaimRewritten=$false
        OriginalEvidenceRewritten=$false
        OutlookMoveExecuted=$false
        WriterPermit=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='Stop;NeverRetryMove;ResearchUnknown0x00010000WithIndependentPstProviderEvidenceBeforeAnySEM001Waiver'
    }
}catch{
    throw ('BW4k7j STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Move, PST/Claim writes or automatic semantic approval. NEVER RETRY original Move.')
}
