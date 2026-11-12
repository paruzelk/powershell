#requires -Version 5.1
# ARCH3b read-only bridge over ORIGINAL ArchiveSelector/Grouping/MailMover.
# No independent routing algorithm, COM, PST mount, writer or journal.
. (Join-Path $PSScriptRoot '../Archive/ArchiveGrouping.ps1')
. (Join-Path $PSScriptRoot '../Archive/ArchiveSelector.ps1')
. (Join-Path $PSScriptRoot '../Archive/MailMover.ps1')

function Get-OPA265ARCH3bDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Parts)
    $sb=New-Object Text.StringBuilder
    foreach($p in $Parts){
        if($null -eq $p){throw 'ARCH3b canonical parts contain null.'}
        $v=[string]$p
        [void]$sb.Append($v.Length)
        [void]$sb.Append(':')
        [void]$sb.Append($v)
    }
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($sb.ToString())
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
    }finally{$sha.Dispose()}
}
function New-OPA265ARCH3bOperationContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Candidate,
        [Parameter(Mandatory=$true)][string]$TransactionId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$SourceStoreId,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='Year',
        [ValidateRange(1,9999)][int]$ArchivePart=1
    )
    if($TransactionId -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$'){throw 'ARCH3b invalid transaction identifier.'}
    if([string]::IsNullOrWhiteSpace($SourceStoreId) -or $SourceStoreId.Length -gt 2048){throw 'ARCH3b original StoreID required.'}
    foreach($p in @('EntryID','ArchiveDate','SourceFolderPath','FolderName')){
        if($null -eq $Candidate -or $Candidate.PSObject.Properties.Name -notcontains $p){throw ('ARCH3b missing original ArchiveSelector row member: '+$p)}
    }
    $id=[string]$Candidate.EntryID
    $path=[string]$Candidate.SourceFolderPath
    $name=[string]$Candidate.FolderName
    if($id -cnotmatch '^[a-fA-F0-9]{16,1024}$'){throw 'ARCH3b original EntryID malformed.'}
    if([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($path) -or -not $path.StartsWith('\')){throw 'ARCH3b original source FolderPath missing.'}
    $source=[IO.Path]::GetFullPath($SourcePst)
    if($source.StartsWith('\\') -or [IO.Path]::GetExtension($source) -ine '.pst'){throw 'ARCH3b expected absolute local original PST.'}
    try{$date=[datetime]$Candidate.ArchiveDate}catch{throw 'ARCH3b invalid original ArchiveDate.'}
    if($date.Year -lt 1900 -or $date.Year -gt 2100){throw 'ARCH3b source date out of supported range.'}
    # ORIGINAL functionality is called, never replicated.
    $archivePst=Get-OPAArchivePartPath -SourcePst $source -Year $date.Year -Part $ArchivePart
    $target=Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderName $name -SourceFolderPath $path -Grouping $ArchiveGrouping
    if([string]::IsNullOrWhiteSpace($target)){throw 'ARCH3b empty original target.'}
    $dateUtc=$date.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
    $parts=@('2.6.5-ARCH3b.OperationContract.1',$TransactionId,$source,$SourceStoreId,$id.ToUpperInvariant(),$path,$name,$dateUtc,$ArchiveGrouping,[string]$ArchivePart,[string]$archivePst,[string]$target)
    $hash=Get-OPA265ARCH3bDigest -Parts $parts
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3b.OperationContract.1'
        TransactionId=$TransactionId
        OperationId=('ARCH3b-'+$hash)
        ContractSha256=$hash
        SourcePst=$source
        SourceStoreId=$SourceStoreId
        SourceEntryId=$id
        SourceFolderPath=$path
        SourceFolderName=$name
        ArchiveDateUtc=$dateUtc
        ArchiveYear=$date.Year
        ArchiveGrouping=$ArchiveGrouping
        ArchivePart=$ArchivePart
        PlannedArchivePst=[string]$archivePst
        PlannedTargetFolderPath=[string]$target
        DestinationSelectionUsesOriginalFunctions=$true
        DestinationNotYetOpenedOrCreated=$true
        OriginalSourceWitnessStillRequired=$true
        DurablePrepareIntentStillRequired=$true
        IndependentReconcileStillRequired=$true
        OutlookContacted=$false
        PstOpened=$false
        JsonWritten=$false
        WriterPermit=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
function Assert-OPA265ARCH3bOperationContract {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Contract,[Parameter(Mandatory=$true)][object]$Candidate)
    if([string]$Contract.Schema -cne '2.6.5-ARCH3b.OperationContract.1' -or [string]$Contract.ContractSha256 -cnotmatch '^[a-f0-9]{64}$' -or [string]$Contract.OperationId -cne ('ARCH3b-'+[string]$Contract.ContractSha256)){
        throw 'ARCH3b forged/invalid operation identity.'
    }
    $again=New-OPA265ARCH3bOperationContract -Candidate $Candidate -TransactionId ([string]$Contract.TransactionId) -SourcePst ([string]$Contract.SourcePst) -SourceStoreId ([string]$Contract.SourceStoreId) -ArchiveGrouping ([string]$Contract.ArchiveGrouping) -ArchivePart ([int]$Contract.ArchivePart)
    foreach($key in @('ContractSha256','OperationId','SourcePst','SourceStoreId','SourceEntryId','SourceFolderPath','SourceFolderName','ArchiveDateUtc','ArchiveYear','ArchiveGrouping','ArchivePart','PlannedArchivePst','PlannedTargetFolderPath')){
        if([string]$Contract.$key -cne [string]$again.$key){throw ('ARCH3b source row or destination provenance drift: '+$key)}
    }
    if([bool]$Contract.WriterPermit -or [bool]$Contract.ProductionReady -or [bool]$Contract.AutomaticRetryAllowed){throw 'ARCH3b contract does not grant writer/retry permission.'}
    return $true
}
function New-OPA265ARCH3bBatchPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Candidates,
        [Parameter(Mandatory=$true)][string]$TransactionId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$SourceStoreId,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='Year',
        [ValidateRange(1,9999)][int]$ArchivePart=1)
    if($Candidates.Count -gt 10000){throw 'ARCH3b bounded offline preview exceeds 10000 originals.'}
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $ops=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($c in $Candidates){
        $x=New-OPA265ARCH3bOperationContract -Candidate $c -TransactionId $TransactionId -SourcePst $SourcePst -SourceStoreId $SourceStoreId -ArchiveGrouping $ArchiveGrouping -ArchivePart $ArchivePart
        if(-not $ids.Add([string]$x.SourceEntryId) -or -not $ops.Add([string]$x.OperationId)){throw 'ARCH3b duplicate original EntryID or operation identity.'}
        [void]$rows.Add($x)
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3b.OriginalCandidateBatchPreview.1'
        Status='OriginalLegacyCandidateAndRoutingContractReadOnlyNoMove'
        TransactionId=$TransactionId
        PlannedItems=$rows.Count
        Grouping=$ArchiveGrouping
        YearCounts=@($rows.ToArray()|Group-Object ArchiveYear|Sort-Object Name|ForEach-Object{[pscustomobject]@{Year=[int]$_.Name;Count=[int]$_.Count}})
        Items=@($rows.ToArray())
        LegacyDestinationModulesReused=$true
        FullOriginalSourceWitnessesCaptured=$false
        OutlookContacted=$false
        PstOpened=$false
        JsonWritten=$false
        WriterPermit=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
function Test-OPA265ARCH3bPhaseEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Contract,
          [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][object[]]$Events)
    # Hypothetical policy simulation only. Never enables a live Move.
    $allowed=@('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned','IndependentContentVerified','IndexCommitted')
    $next=0
    $issues=New-Object 'System.Collections.Generic.List[string]'
    $unknown=$false
    # Classify null as invalid evidence instead of failing parameter binding.
    foreach($event in @($Events)){
        if($null -eq $event){[void]$issues.Add('NullEvidence');continue}
        if([string]$event.OperationId -cne [string]$Contract.OperationId -or [string]$event.TransactionId -cne [string]$Contract.TransactionId){
            [void]$issues.Add('IdentityMismatch');continue
        }
        $phase=[string]$event.Phase
        if($phase -ceq 'MoveIndeterminate'){
            if($next -ne 4 -or $unknown){[void]$issues.Add('IndeterminateOutOfOrder')}
            $unknown=$true;continue
        }
        if($unknown){[void]$issues.Add('EvidenceAfterIndeterminateMove');continue}
        if($next -ge $allowed.Count -or $phase -cne $allowed[$next]){
            [void]$issues.Add('PhaseMissingDuplicateOrOutOfOrder');continue
        }
        if($phase -ceq 'SourceWitnessAnchored' -and [string]$event.SourceWitnessSha256 -cnotmatch '^[a-f0-9]{64}$'){
            [void]$issues.Add('SourceWitnessNotAnchored');continue
        }
        if($phase -ceq 'MoveClaimed' -and -not [bool]$event.DurablyFlushedBeforeMove){
            [void]$issues.Add('MoveClaimWithoutDurableFlush');continue
        }
        if($phase -ceq 'MoveReturned' -and [string]$event.DestinationEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$'){
            [void]$issues.Add('InvalidDestinationEntryID');continue
        }
        if($phase -ceq 'IndependentContentVerified' -and (-not [bool]$event.FullSemanticMatch -or -not [bool]$event.OutlookRestartConfirmed)){
            [void]$issues.Add('IndependentReconcileNotConfirmed');continue
        }
        if($phase -ceq 'IndexCommitted' -and -not [bool]$event.IndexMatchesReceipt){
            [void]$issues.Add('IndexNotLinkedToVerifiedReceipt');continue
        }
        $next++
    }
    $status=if($issues.Count -gt 0){'InvalidEvidenceManualReviewNoRetry'}
        elseif($unknown){'IndeterminateMoveManualReviewNoRetry'}
        elseif($next -eq $allowed.Count){'HypotheticalVerifiedAndIndexedNotLiveCertified'}
        elseif($next -ge 5){'MoveReturnedIndependentVerificationPending'}
        elseif($next -eq 4){'OneShotMoveClaimPresentOutcomeUnconfirmed'}
        else{'BeforeMoveContractOnlyNoWriterPermit'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3b.PhasePolicyReview.1'
        OperationId=[string]$Contract.OperationId
        Status=$status
        AcceptedPhaseCount=$next
        IssueCodes=@($issues.ToArray())
        IndeterminateMoveObserved=$unknown
        OriginalSourceWitnessRequired=$true
        DurableClaimsActuallyWritten=$false
        OutlookMoveActuallyAttempted=$false
        IndependentRuntimeContentVerified=$false
        WriterPermit=$false
        AutomaticMoveRetryAllowed=$false
        ProductionReady=$false
    }
}
