#requires -Version 5.1
# BW3g: ONE explicit human size-deviation acceptance, separate immutable JSON.
# Never executes Outlook COM, Move, or any journal/claim write.
function Get-OPA265BW3gPinnedAcceptance {
    [CmdletBinding()]
    param()
    $p=Get-OPA265BW3ePinnedTailEvidence
    return [pscustomobject]@{
        RunId=[string]$p.RunId
        OperationId=[string]$p.OperationId
        WorkerRequestId=[string]$p.WorkerRequestId
        SourcePst=[string]$p.SourcePst
        JournalSha256=[string]$p.JournalSha256
        DestinationEntryId=[string]$p.ArchiveEntryId
        BodyUtf8Sha256=[string]$p.ExpectedBodySha256
        IntentSizeBytes=1436L
        ObservedArchiveSizeBytes=1444L
        AcceptedDifferenceBytes=8L
        RecordFileName='bw3g-manual-size-acceptance.json'
        ExactAcknowledgment=('ACCEPT-SYNTHETIC-8-BYTES-'+[string]$p.RunId+'-NO-JOURNAL-CHANGE')
    }
}
function Assert-OPA265BW3gReviewDossier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Dossier,
          [Parameter(Mandatory=$true)][object]$Pinned)
    $original=Get-OPA265BW3gPinnedAcceptance
    foreach($name in @('RunId','OperationId','WorkerRequestId','SourcePst',
        'JournalSha256','DestinationEntryId','BodyUtf8Sha256',
        'RecordFileName','ExactAcknowledgment')) {
        if ([string]$Pinned.$name -cne [string]$original.$name) {
            throw ('BW3g changed pinned identity '+$name)
        }
    }
    if ([long]$Pinned.IntentSizeBytes -ne 1436 -or
        [long]$Pinned.ObservedArchiveSizeBytes -ne 1444 -or
        [long]$Pinned.AcceptedDifferenceBytes -ne 8) {
        throw 'BW3g wrong pinned size delta.'
    }
    if ($null -eq $Dossier -or $Dossier -is [array] -or $Dossier -is [string] -or
        [string]$Dossier.Schema -cne '2.6.5-BW3f.ManualSizeDecisionDossier.1' -or
        [string]$Dossier.Status -cne 'EvidenceDossierReadyHumanDecisionPending' -or
        [string]$Dossier.Decision -cne 'DeferJournalResolutionUntilSeparateExplicitAuthorization' -or
        [string]$Dossier.RunId -cne [string]$Pinned.RunId -or
        [string]$Dossier.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Dossier.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Dossier.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Dossier.DestinationEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$Dossier.ArchivedBodyUtf8Sha256 -cne [string]$Pinned.BodyUtf8Sha256 -or
        [string]$Dossier.PriorBw3eStatus -cne 'SyntheticBodyTailSpaceCrLfConfirmed' -or
        [long]$Dossier.IntentSizeBytes -ne 1436 -or
        [long]$Dossier.ArchivedSizeBytes -ne 1444 -or
        [long]$Dossier.UnapprovedSizeDifferenceBytes -ne 8 -or
        [int]$Dossier.SourceItemCount -ne 0 -or
        [int]$Dossier.ArchiveItemCount -ne 1 -or
        [int]$Dossier.AttachmentsCount -ne 0 -or
        [string]$Dossier.HumanSizeDecisionValue -cne 'Unrecorded' -or
        [string]$Dossier.NextAction -cne 'PreserveOriginalEvidenceAndObtainSeparateExplicitManualSizeDecision') {
        throw 'BW3g rejects inconsistent BW3f historical evidence.'
    }
    foreach($name in @('WorkerMoveIdentityObserved','ClaimsCorrelated',
        'BodySuffixConfirmed','ProviderSizeCrossCheckMatches',
        'AdditionalExplicitOperatorConsentRequired',
        'OnlyRunScopedSyntheticFoldersInspected')) {
        if ($Dossier.PSObject.Properties.Name -cnotcontains $name -or
            $Dossier.$name -isnot [bool] -or -not [bool]$Dossier.$name) {
            throw ('BW3g missing positive proof '+$name)
        }
    }
    foreach($name in @('BeforeMoveActualBodyHashCaptured','TimingOfBodySuffixEstablished',
        'CauseOfMAPIByteSizeDriftEstablished','MAPIStreamOrFullItemByteEqualityVerified',
        'SizeDifferenceAcceptableAutomatically','SizeDifferenceApproved',
        'HumanSizeDecisionRecorded','ManualJournalDecisionAuthorized',
        'WriteableReconciliationPermitIssued','EvidencePacketPersisted',
        'OutlookMoveExecuted','JournalChanged','JournalCompleted',
        'JournalReconciled','AutomaticRetryAllowed','ProductionReady')) {
        if ($Dossier.PSObject.Properties.Name -cnotcontains $name -or
            $Dossier.$name -isnot [bool] -or [bool]$Dossier.$name) {
            throw ('BW3g fabricated waiver/journal state '+$name)
        }
    }
    if ($Dossier.BodyTailCodeUnits -isnot [array] -or
        @($Dossier.BodyTailCodeUnits).Count -ne 3 -or
        [int]$Dossier.BodyTailCodeUnits[0] -ne 32 -or
        [int]$Dossier.BodyTailCodeUnits[1] -ne 13 -or
        [int]$Dossier.BodyTailCodeUnits[2] -ne 10) {
        throw 'BW3g wrong Body suffix.'
    }
    return $true
}
function Get-OPA265BW3gRecordPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths)
    $p=Get-OPA265BW3gPinnedAcceptance
    if ([string]$Paths.RunId -cne [string]$p.RunId -or
        [string]$Paths.SourcePst -cne [string]$p.SourcePst -or
        -not [IO.Directory]::Exists([string]$Paths.Directory) -or
        (([IO.File]::GetAttributes([string]$Paths.Directory)) -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3g refuses writing outside original regular synthetic fixture directory.'
    }
    return (Join-Path ([string]$Paths.Directory) ([string]$p.RecordFileName))
}
function Get-OPA265BW3gEvidenceFileHashes {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Extra)
    $map=[ordered]@{
        Journal=[string]$Paths.JournalPath
        Request=[string]$Paths.RequestPath
        Scope=[string]$Paths.ScopePath
        MoveAttemptClaim=[string]$Paths.ClaimPath
        DispatchClaim=[string]$Extra.DispatchClaimPath
        ControllerResult=[string]$Extra.ControllerResultPath
    }
    $result=[ordered]@{}
    foreach($name in $map.Keys) {
        $file=[string]$map[$name]
        if (-not [IO.File]::Exists($file) -or
            (([IO.File]::GetAttributes($file)) -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('BW3g missing historical evidence file '+$name)
        }
        $result[$name]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $p=Get-OPA265BW3gPinnedAcceptance
    if ([string]$result['Journal'] -cne [string]$p.JournalSha256) {
        throw 'BW3g original Intent journal SHA256 changed.'
    }
    return [pscustomobject]$result
}
function Assert-OPA265BW3gHashesUnchanged {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Previous,
          [Parameter(Mandatory=$true)][object]$Current)
    $keys=@('Journal','Request','Scope','MoveAttemptClaim','DispatchClaim','ControllerResult')
    if (@($Previous.PSObject.Properties.Name).Count -ne 6 -or
        @($Current.PSObject.Properties.Name).Count -ne 6) {
        throw 'BW3g unexpected evidence file hash map schema.'
    }
    foreach($key in $keys) {
        if ($Previous.PSObject.Properties.Name -cnotcontains $key -or
            $Current.PSObject.Properties.Name -cnotcontains $key -or
            [string]$Previous.$key -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$Previous.$key -cne [string]$Current.$key) {
            throw ('BW3g durable evidence changed '+$key)
        }
    }
    return $true
}
function Get-OPA265BW3gDossierFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Dossier,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3gReviewDossier -Dossier $Dossier -Pinned $Pinned)
    $values=@([string]$Dossier.Schema,[string]$Dossier.Status,
        [string]$Dossier.RunId,[string]$Dossier.OperationId,
        [string]$Dossier.WorkerRequestId,[string]$Dossier.JournalSha256,
        [string]$Dossier.DestinationEntryId,[string]$Dossier.ArchivedBodyUtf8Sha256,
        [string]$Dossier.IntentSizeBytes,[string]$Dossier.ArchivedSizeBytes,
        [string]$Dossier.UnapprovedSizeDifferenceBytes)
    return (Get-OPA265BW3dUtf8TextSha256 -Text ($values -join [char]10))
}
function New-OPA265BW3gManualAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Dossier,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$EvidenceHashes,
          [Parameter(Mandatory=$true)][string]$Acknowledgment)
    [void](Assert-OPA265BW3gReviewDossier -Dossier $Dossier -Pinned $Pinned)
    if ($Acknowledgment -cne [string]$Pinned.ExactAcknowledgment) {
        throw 'BW3g requires exact manual acknowledgement for THIS synthetic +8 bytes.'
    }
    [void](Assert-OPA265BW3gHashesUnchanged -Previous $EvidenceHashes -Current $EvidenceHashes)
    if ([string]$EvidenceHashes.Journal -cne [string]$Pinned.JournalSha256) {
        throw 'BW3g cannot record changed Intent.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3g.ManualSyntheticSizeAcceptance.1'
        Status='ManualSyntheticSizeDeviationAcceptedOnly'
        RecordId=[guid]::NewGuid().ToString('D')
        RecordedUtc=[datetime]::UtcNow.ToString('o')
        DecisionOrigin='ExplicitOperatorLocalCommand'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        SourcePst=[string]$Pinned.SourcePst
        JournalSha256=[string]$Pinned.JournalSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        BodyUtf8Sha256=[string]$Pinned.BodyUtf8Sha256
        IntentSizeBytes=1436L
        ObservedArchiveSizeBytes=1444L
        AcceptedDifferenceBytes=8L
        ApprovalScope='ThisOneHistoricalSyntheticMailOnly'
        UncertaintyAcknowledged='MAPI size cause and pre-Move byte equality unknown'
        EvidenceDossierSha256=(Get-OPA265BW3gDossierFingerprint -Dossier $Dossier -Pinned $Pinned)
        EvidenceFileSha256=[pscustomobject][ordered]@{
            Journal=[string]$EvidenceHashes.Journal
            Request=[string]$EvidenceHashes.Request
            Scope=[string]$EvidenceHashes.Scope
            MoveAttemptClaim=[string]$EvidenceHashes.MoveAttemptClaim
            DispatchClaim=[string]$EvidenceHashes.DispatchClaim
            ControllerResult=[string]$EvidenceHashes.ControllerResult
        }
        ManualSizeAcceptanceRecorded=$true
        FullContentByteEqualityVerified=$false
        JournalReconciliationAuthorized=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        MailMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW3gManualAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Record,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$EvidenceHashes,
          [Parameter(Mandatory=$true)][string]$DossierFingerprint)
    $keys=@('Schema','Status','RecordId','RecordedUtc','DecisionOrigin',
        'RunId','OperationId','WorkerRequestId','SourcePst','JournalSha256',
        'DestinationEntryId','BodyUtf8Sha256','IntentSizeBytes',
        'ObservedArchiveSizeBytes','AcceptedDifferenceBytes','ApprovalScope',
        'UncertaintyAcknowledged','EvidenceDossierSha256','EvidenceFileSha256',
        'ManualSizeAcceptanceRecorded','FullContentByteEqualityVerified',
        'JournalReconciliationAuthorized','JournalChanged','JournalCompleted',
        'JournalReconciled','MailMoveExecuted','AutomaticRetryAllowed',
        'ProductionReady')
    if ($null -eq $Record -or $Record -is [string] -or
        $Record -is [array] -or
        @($Record.PSObject.Properties.Name).Count -ne $keys.Count) {
        throw 'BW3g acceptance record has invalid schema field count.'
    }
    foreach($key in $keys) {
        if ($Record.PSObject.Properties.Name -cnotcontains $key) {
            throw ('BW3g missing acceptance field '+$key)
        }
    }
    $rid=[guid]::Empty;$date=[datetimeoffset]::MinValue
    if (-not [guid]::TryParse([string]$Record.RecordId,[ref]$rid) -or
        $rid -eq [guid]::Empty -or
        -not [datetimeoffset]::TryParse([string]$Record.RecordedUtc,[ref]$date) -or
        [string]$Record.Schema -cne '2.6.5-BW3g.ManualSyntheticSizeAcceptance.1' -or
        [string]$Record.Status -cne 'ManualSyntheticSizeDeviationAcceptedOnly' -or
        [string]$Record.DecisionOrigin -cne 'ExplicitOperatorLocalCommand' -or
        [string]$Record.RunId -cne [string]$Pinned.RunId -or
        [string]$Record.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Record.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Record.SourcePst -cne [string]$Pinned.SourcePst -or
        [string]$Record.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Record.DestinationEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$Record.BodyUtf8Sha256 -cne [string]$Pinned.BodyUtf8Sha256 -or
        [long]$Record.IntentSizeBytes -ne 1436 -or
        [long]$Record.ObservedArchiveSizeBytes -ne 1444 -or
        [long]$Record.AcceptedDifferenceBytes -ne 8 -or
        [string]$Record.ApprovalScope -cne 'ThisOneHistoricalSyntheticMailOnly' -or
        [string]$Record.UncertaintyAcknowledged -cne 'MAPI size cause and pre-Move byte equality unknown' -or
        [string]$Record.EvidenceDossierSha256 -cne $DossierFingerprint) {
        throw 'BW3g recorded size decision no longer matches historical scope.'
    }
    foreach($key in @('ManualSizeAcceptanceRecorded','FullContentByteEqualityVerified',
        'JournalReconciliationAuthorized','JournalChanged','JournalCompleted',
        'JournalReconciled','MailMoveExecuted','AutomaticRetryAllowed',
        'ProductionReady')) {
        $expected=($key -ceq 'ManualSizeAcceptanceRecorded')
        if ($Record.$key -isnot [bool] -or [bool]$Record.$key -ne $expected) {
            throw ('BW3g unsafe Boolean record field '+$key)
        }
    }
    [void](Assert-OPA265BW3gHashesUnchanged -Previous $EvidenceHashes -Current $Record.EvidenceFileSha256)
    return $true
}
function Write-OPA265BW3gCreateNewRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Record)
    $path=Get-OPA265BW3gRecordPath -Paths $Paths
    if ([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) {
        throw 'BW3g acceptance file already exists: never overwrite/retry.'
    }
    # BOM is required for PS CODE, not JSON data.
    $data=[Text.UTF8Encoding]::new($false,$true).GetBytes(
        (ConvertTo-Json -InputObject $Record -Depth 10 -Compress))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($data,0,$data.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) {$stream.Dispose()}
    }
    # If write/readback fails the file MUST remain, with NO retry.
    $after=[IO.File]::ReadAllBytes($path)
    if ([Convert]::ToBase64String($data) -cne [Convert]::ToBase64String($after)) {
        throw 'BW3g size acceptance persisted incompletely. Preserve it; never retry.'
    }
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=([BitConverter]::ToString($sha.ComputeHash($after))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [pscustomobject]@{Path=$path;Sha256=$hash;Length=$after.Length}
}
function Read-OPA265BW3gOriginalRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$EvidenceHashes,
          [Parameter(Mandatory=$true)][string]$DossierFingerprint)
    $path=Get-OPA265BW3gRecordPath -Paths $Paths
    if (-not [IO.File]::Exists($path)) {return $null}
    if ((([IO.File]::GetAttributes($path)) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3g existing record is a reparse point.'
    }
    $bytes=[IO.File]::ReadAllBytes($path)
    if ($bytes.Length -eq 0 -or $bytes.Length -gt 65536 -or
        ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) {
        throw 'BW3g acceptance JSON invalid length or BOM.'
    }
    $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $record=ConvertFrom-Json -InputObject $json -ErrorAction Stop
    [void](Assert-OPA265BW3gManualAcceptance -Record $record -Pinned $Pinned -EvidenceHashes $EvidenceHashes -DossierFingerprint $DossierFingerprint)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [pscustomobject]@{Record=$record;Path=$path;Sha256=$hash}
}
