#requires -Version 5.1
# BW3d: pure read-only synthetic size-drift evidence. No Outlook COM here.
# No automatic consent, no journal mutation, no production activation.
function Get-OPA265BW3dPinnedSizeReview {
    [CmdletBinding()]
    param()
    $pinned=Get-OPA265BW3bPinnedIdentity
    return [pscustomobject]@{
        RunId=[string]$pinned.RunId
        OperationId=[string]$pinned.OperationId
        WorkerRequestId=[string]$pinned.WorkerRequestId
        SourcePst=[string]$pinned.SourcePst
        ArchiveEntryId=[string]$pinned.ArchiveEntryId
        JournalSha256=[string]$pinned.JournalSha256
        IntentSizeBytes=1436L
        PinnedObservedArchiveSizeBytes=1444L
        PinnedDifferenceBytes=8L
        FixtureBody='Synthetic LIVE3 diagnostic email; no user content.'
        ExpectedAttachmentCount=0
        ExpectedMessageClass='IPM.Note'
    }
}
function Get-OPA265BW3dUtf8TextSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Assert-OPA265BW3dPinnedBw3bAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Previous,
          [Parameter(Mandatory=$true)][object]$Pinned)
    if ([string]$Pinned.RunId -cne 'a7b51427-7494-43f4-bc96-64915f6bee7e' -or
        [string]$Pinned.OperationId -cne '9bd83da2-d47e-404f-a4fd-792852b58dec' -or
        [string]$Pinned.WorkerRequestId -cne '24553e9c-fa09-497f-b42d-4329ebe27021' -or
        [string]$Pinned.JournalSha256 -cne '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648' -or
        [string]$Pinned.ArchiveEntryId -cne '00000000953C628FC9EAC24E97DBE040019A969924002000' -or
        [string]$Pinned.SourcePst -cne [string](Get-OPA265BW3bPinnedIdentity).SourcePst -or
        [long]$Pinned.IntentSizeBytes -ne 1436 -or
        [long]$Pinned.PinnedObservedArchiveSizeBytes -ne 1444 -or
        [long]$Pinned.PinnedDifferenceBytes -ne 8 -or
        [string]$Pinned.FixtureBody -cne 'Synthetic LIVE3 diagnostic email; no user content.' -or
        [int]$Pinned.ExpectedAttachmentCount -ne 0 -or
        [string]$Pinned.ExpectedMessageClass -cne 'IPM.Note') {
        throw 'BW3d pinned synthetic run, fixed fixture body or observed size changed.'
    }
    if ([string]$Previous.Schema -cne '2.6.5-BW3b.IndependentPostMoveAudit.1' -or
        [string]$Previous.Status -cne 'IndependentPostMoveAuditPassed' -or
        [string]$Previous.Decision -cne 'MoveConfirmedByEntryIdAndSyntheticIdentity' -or
        [string]$Previous.RunId -cne [string]$Pinned.RunId -or
        [string]$Previous.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Previous.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Previous.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Previous.WorkerDestinationEntryId -cne [string]$Pinned.ArchiveEntryId -or
        [string]$Previous.ObservedArchiveEntryId -cne [string]$Pinned.ArchiveEntryId -or
        -not [bool]$Previous.ArchiveEntryIdMatchesWorker -or
        -not [bool]$Previous.ClaimsCorrelated -or
        [int]$Previous.SourceItemCount -ne 0 -or
        [int]$Previous.ArchiveItemCount -ne 1 -or
        [int]$Previous.SyntheticSourceMatches -ne 0 -or
        [int]$Previous.SyntheticArchiveMatches -ne 1 -or
        [long]$Previous.IntentSizeBytes -ne [long]$Pinned.IntentSizeBytes -or
        [long]$Previous.ObservedArchiveSizeBytes -ne [long]$Pinned.PinnedObservedArchiveSizeBytes -or
        [long]$Previous.ArchiveSizeDifferenceBytes -ne [long]$Pinned.PinnedDifferenceBytes -or
        [bool]$Previous.ArchiveSizeMatchesIntent -or
        [bool]$Previous.ArchiveSizeDifferenceApproved -or
        [bool]$Previous.ContentByteEqualityVerified -or
        -not [bool]$Previous.RequiresManualSizeReview -or
        -not [bool]$Previous.OnlySyntheticFoldersInspected -or
        [bool]$Previous.OutlookMoveExecuted -or
        [bool]$Previous.JournalChanged -or
        [bool]$Previous.JournalCompleted -or
        [bool]$Previous.JournalReconciled -or
        [bool]$Previous.AutomaticRetryAllowed -or
        [bool]$Previous.ProductionReady -or
        [string]$Previous.NextAction -cne 'StopBeforeManualJournalDecision') {
        throw 'BW3d refuses mismatched, incomplete or auto-approved BW3b evidence.'
    }
    return $true
}
function Assert-OPA265BW3dObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [Parameter(Mandatory=$true)][object]$Pinned)
    $required=@('RunId','OperationId','ArchiveEntryId','ArchiveStoreId',
        'ArchiveFolderEntryId','ArchiveFolderPath','Subject','InternetMessageId',
        'MailClass','MessageClass','SourceItemCount','ArchiveItemCount',
        'AttachmentsCount','BodyText','MailItemSizeBytes','PrMessageSizeAvailable',
        'PrMessageSizeBytes','PrMessageSizeReadError')
    $fields=@($Evidence.PSObject.Properties.Name)
    if ($fields.Count -ne $required.Count) {
        throw 'BW3d unexpected Outlook observation schema/field count.'
    }
    foreach($name in $required) {
        if ($fields -cnotcontains $name) {throw ('BW3d missing Outlook field: '+$name)}
    }
    $expectedSubject='OPA264 LIVE3 synthetic '+[string]$Pinned.RunId
    $expectedMessageId='<opa264-live3-'+[string]$Pinned.RunId+'@example.invalid>'
    if ([string]$Evidence.RunId -cne [string]$Pinned.RunId -or
        [string]$Evidence.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Evidence.ArchiveEntryId -cne [string]$Pinned.ArchiveEntryId -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.ArchiveStoreId) -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.ArchiveFolderEntryId) -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.ArchiveFolderPath) -or
        [string]$Evidence.Subject -cne $expectedSubject -or
        [string]$Evidence.InternetMessageId -cne $expectedMessageId -or
        [int]$Evidence.MailClass -ne 43 -or
        [string]$Evidence.MessageClass -cne [string]$Pinned.ExpectedMessageClass -or
        [int]$Evidence.SourceItemCount -ne 0 -or
        [int]$Evidence.ArchiveItemCount -ne 1 -or
        [int]$Evidence.AttachmentsCount -lt 0 -or
        [long]$Evidence.MailItemSizeBytes -ne [long]$Pinned.PinnedObservedArchiveSizeBytes -or
        ($Evidence.BodyText -isnot [string]) -or
        ($Evidence.PrMessageSizeAvailable -isnot [bool])) {
        throw 'BW3d synthetic archived MailItem identity or pinned MAPI size mismatch.'
    }
    if ([bool]$Evidence.PrMessageSizeAvailable) {
        if ([long]$Evidence.PrMessageSizeBytes -le 0 -or
            -not [string]::IsNullOrWhiteSpace([string]$Evidence.PrMessageSizeReadError)) {
            throw 'BW3d PR_MESSAGE_SIZE flag contradicts observation.'
        }
    } else {
        if ([long]$Evidence.PrMessageSizeBytes -ne 0 -or
            [string]::IsNullOrWhiteSpace([string]$Evidence.PrMessageSizeReadError)) {
            throw 'BW3d PR_MESSAGE_SIZE unavailability is not explicitly documented.'
        }
    }
    return $true
}
function Get-OPA265BW3dSizeEvidenceVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Previous,
          [Parameter(Mandatory=$true)][object]$Observation,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3dPinnedBw3bAudit -Previous $Previous -Pinned $Pinned)
    [void](Assert-OPA265BW3dObservation -Evidence $Observation -Pinned $Pinned)
    $rawBody=[string]$Observation.BodyText
    $baseline=[string]$Pinned.FixtureBody
    $exact=[string]::Equals($rawBody,$baseline,[StringComparison]::Ordinal)
    # Outlook may append CR or LF to Body. ONLY trim trailing CR/LF for
    # a diagnostic comparison; do not normalize/change stored content.
    $normalized=$rawBody.TrimEnd([char[]]@([char]13,[char]10))
    $trailingNewlinesOnly=[string]::Equals($normalized,$baseline,[StringComparison]::Ordinal)
    $attachmentsOk=([int]$Observation.AttachmentsCount -eq 0)
    $prAvailable=[bool]$Observation.PrMessageSizeAvailable
    $prMatches=($prAvailable -and
        [long]$Observation.PrMessageSizeBytes -eq [long]$Observation.MailItemSizeBytes)
    $structural=($trailingNewlinesOnly -and $attachmentsOk)
    return [pscustomobject]@{
        Schema='2.6.5-BW3d.SyntheticSizeReadOnlyEvidence.1'
        Status=$(if ($structural) {'SizeDriftStructureConsistentManualReviewPending'}
            else {'UnexpectedSyntheticContentStopAndInvestigate'})
        Decision='SizeDifferenceUnapprovedManualDecisionRequired'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        JournalSha256=[string]$Pinned.JournalSha256
        ArchiveEntryIdMatchesWorker=$true
        IntentSizeBytes=[long]$Pinned.IntentSizeBytes
        ObservedArchiveSizeBytes=[long]$Observation.MailItemSizeBytes
        SizeDifferenceBytes=([long]$Observation.MailItemSizeBytes - [long]$Pinned.IntentSizeBytes)
        PinnedEightByteDriftObserved=$true
        ExpectedSyntheticBodyUtf8Sha256=(Get-OPA265BW3dUtf8TextSha256 -Text $baseline)
        ObservedBodyUtf8Sha256=(Get-OPA265BW3dUtf8TextSha256 -Text $rawBody)
        BodyTextMatchesFixtureExactly=$exact
        BodyTextMatchesAfterTrailingCrLfTrim=$trailingNewlinesOnly
        ExpectedAttachmentCount=[int]$Pinned.ExpectedAttachmentCount
        ObservedAttachmentCount=[int]$Observation.AttachmentsCount
        AttachmentsCountMatchesFixture=$attachmentsOk
        MessageClassMatchesFixture=$true
        PrMessageSizeAvailable=$prAvailable
        PrMessageSizeBytes=$(if ($prAvailable) {[long]$Observation.PrMessageSizeBytes} else {$null})
        PrMessageSizeMatchesMailItemSize=$prMatches
        PrMessageSizeReadError=$(if ($prAvailable) {''} else {[string]$Observation.PrMessageSizeReadError})
        EvidenceSufficientForIdentityOnly=$true
        EvidenceSufficientForContentByteEquality=$false
        EvidenceSufficientForAutomaticSizeApproval=$false
        ArchiveSizeDifferenceApproved=$false
        RequiresManualSizeReview=$true
        ManualJournalDecisionAuthorized=$false
        OnlySyntheticFoldersInspected=$true
        OutlookReadOnlyInspectionExecuted=$true
        OutlookMoveExecuted=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='PreserveIntentClaimsAndRequestIndependentSizeDecision'
    }
}
