#requires -Version 5.1
# BW4k7m strictly independent, READ-ONLY after one fresh Move attempt.
# Reads original sealed pre-Move evidence and irrevocable Claim. No Move/retry/waiver.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$FixtureId,
    [Parameter(Mandatory=$true)][string]$ExpectedEvidenceSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedClaimSha256,
    [string]$ExpectedDestinationEntryId='',
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7m independent read-only audit requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7mFreshOneShotGuard265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$pins=Get-OPA265BW4k7mPins
if($FixtureId -cne [string]$pins.FixtureId -or
   $ExpectedEvidenceSha256 -cne [string]$pins.EvidenceSha256 -or
   $ExpectedClaimSha256 -cnotmatch '^[a-f0-9]{64}$' -or
   $ExpectedProfileName -cne 'Outlook' -or
   ($ExpectedDestinationEntryId -ne '' -and
    $ExpectedDestinationEntryId -cnotmatch '^[a-fA-F0-9]{40,512}$')){
    throw 'BW4k7m audit exact fixture SHA/Claim SHA/optional destination EntryID pins mismatch.'
}
$stage='Verify original immutable BW4k7l SHA and irreversible new Claim SHA'
$app=$null;$ns=$null;$source=$null;$destination=$null;$folder=$null;$moved=$null
try{
    $sealed=Read-OPA265BW4k7mSealedEvidence -FixtureId $FixtureId -ExpectedEvidenceSha256 $ExpectedEvidenceSha256
    $e=$sealed.Record;$w=$e.SourceWitness
    $claimPath=Get-OPA265BW4k7mClaimPath -FixtureId $FixtureId
    if(-not [IO.File]::Exists($claimPath) -or
       (([IO.File]::GetAttributes($claimPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $claimPath).Length -gt 32768){
        throw 'BW4k7m expected irreversible Claim absent/invalid. No Move allowed.'
    }
    $claimHash=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($claimHash -cne $ExpectedClaimSha256){throw 'BW4k7m original Claim SHA mismatch. STOP.'}
    $claim=Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$claim.Schema -cne '2.6.5-BW4k7m.OneIrreversibleFreshAttachment1KClaim.1' -or
       [string]$claim.FixtureId -cne $FixtureId -or
       [string]$claim.EvidenceSha256 -cne $ExpectedEvidenceSha256 -or
       [string]$claim.SourceEntryId -cne [string]$pins.SourceEntryId -or
       [string]$claim.DestinationFolderEntryId -cne [string]$pins.DestinationFolderEntryId -or
       [string]$claim.InternetMessageId -cne [string]$w.InternetMessageId -or
       [string]$claim.SourcePst -cne [string]$e.SourcePst -or
       [string]$claim.DestinationPst -cne [string]$e.DestinationPst -or
       -not [bool]$claim.OneIrreversibleMoveAttemptClaimed -or
       [bool]$claim.AllowAutomaticRetry -or
       [bool]$claim.AllowJournalWrite -or
       [bool]$claim.HistoricalFlagMismatchWaived -or
       [bool]$claim.ProductionReady){
        throw 'BW4k7m historical Claim contents violate pinned one-attempt schema.'
    }
    $stage='Validate exact POP3 source store, test PST, empty source/one target MessageId'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){throw 'BW4k7m wrong Outlook profile.'}
    $source=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst ([string]$e.SourcePst)
    if((Get-OPA265BW4k7lStringSha -Value ([string]$source.StoreId)) -cne
        [string]$w.SourceStoreIdSha256){
        throw 'BW4k7m source POP3 StoreId SHA differs from sealed evidence.'
    }
    $inbox=$source.Store.GetDefaultFolder(6)
    if([string]$inbox.EntryID -cne [string]$w.SourceFolderEntryId){
        throw 'BW4k7m source Inbox EntryID changed.'
    }
    $storeCount=[int]$ns.Stores.Count;$hits=0
    if($storeCount -lt 2 -or $storeCount -gt 128){throw 'BW4k7m unsafe archive store inventory.'}
    for($i=1;$i -le $storeCount;$i++){
        $s=$ns.Stores.Item($i);$p=''
        try{$p=[string]$s.FilePath}catch{continue}
        if($p -and [string]::Equals([IO.Path]::GetFullPath($p),
           [IO.Path]::GetFullPath([string]$e.DestinationPst),
           [StringComparison]::OrdinalIgnoreCase)){
            $destination=$s;$hits++
        }
    }
    if($hits -ne 1 -or $null -eq $destination -or
       (Get-OPA265BW4k7lStringSha -Value ([string]$destination.StoreID)) -cne
         [string]$e.DestinationStoreIdSha256){
        throw 'BW4k7m archived PST is not uniquely mounted with original StoreID.'
    }
    $folder=$ns.GetFolderFromID([string]$pins.DestinationFolderEntryId,[string]$destination.StoreID)
    if($null -eq $folder -or
       [string]$folder.EntryID -cne [string]$pins.DestinationFolderEntryId -or
       [string]$folder.StoreID -cne [string]$destination.StoreID -or
       [string]$folder.Name -cne ('OPA265-BW4k7l-'+$FixtureId) -or
       [string]$folder.Parent.EntryID -cne [string]$destination.GetRootFolder().EntryID){
        throw 'BW4k7m archived folder is not the sealed direct child of test PST root.'
    }
    $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+
        "'"+[string]$w.InternetMessageId+"'"
    $srcItems=$inbox.Items.Restrict($filter)
    $destItems=$folder.Items.Restrict($filter)
    if([int]$srcItems.Count -ne 0 -or
       [int]$destItems.Count -ne 1 -or
       [int]$folder.Items.Count -ne 1){
        throw 'BW4k7m independent exact reconciliation is not source zero / destination one.'
    }
    $moved=$destItems.Item(1)
    $destEntry=[string]$moved.EntryID
    if($destEntry -cnotmatch '^[a-fA-F0-9]{40,512}$' -or
       ($ExpectedDestinationEntryId -ne '' -and
        $ExpectedDestinationEntryId -cne $destEntry)){
        throw 'BW4k7m moved EntryID missing or differs from operator-pinned return value.'
    }
    $stage='Two independent archive read paths; full semantic/attachment and separate raw MAPI context'
    $args=@{
        FixtureId=$FixtureId
        ExpectedEntryId=$destEntry
        ExpectedFolderId=[string]$pins.DestinationFolderEntryId
        ExpectedStoreId=[string]$destination.StoreID
    }
    $first=Get-OPA265BW4k7lFreshMailWitness -Mail $moved @args
    $direct=$ns.GetItemFromID($destEntry,[string]$destination.StoreID)
    $second=Get-OPA265BW4k7lFreshMailWitness -Mail $direct @args
    [void](Assert-OPA265BW4k7lStableFreshWitness -First $first -Second $second)
    if([int]$inbox.Items.Restrict($filter).Count -ne 0 -or
       [int]$folder.Items.Restrict($filter).Count -ne 1){
        throw 'BW4k7m source/destination count changed during independent audit.'
    }
    $comparison=Get-OPA265BW4k7mContentComparison -Original $w -Destination $second
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7m.IndependentRealPostMoveAudit.1'
        Status=[string]$comparison.Status
        FixtureId=$FixtureId
        VerifiedOriginalEvidenceSha256=[string]$sealed.Sha256
        VerifiedOriginalIrreversibleClaimSha256=$claimHash
        SourceMessageIdMatches=0
        DestinationMessageIdMatches=1
        DestinationEntryId=$destEntry
        DestinationEntryIdExplicitlyPinned=($ExpectedDestinationEntryId -ne '')
        IndependentDestinationReadPaths=2
        FullSemanticContentMatch=[bool]$comparison.FullSemanticContentMatch
        SemanticFieldMismatchCount=[int]$comparison.SemanticFieldMismatchCount
        SemanticFieldMismatches=@($comparison.SemanticFieldMismatches)
        SourceRawPrMessageFlags=[int]$comparison.OriginalRawPrMessageFlags
        DestinationRawPrMessageFlags=[int]$comparison.DestinationRawPrMessageFlags
        ChangedMaskHex=[string]$comparison.ChangedMaskHex
        Unknown0x00010000Changed=[bool]$comparison.Unresolved0x00010000Changed
        SourcePrMessageStatus=$comparison.OriginalPrMessageStatus
        DestinationPrMessageStatus=$comparison.DestinationPrMessageStatus
        PrMessageStatusEqual=[bool]$comparison.SeparatePrMessageStatusEqual
        SourceDiagnosticMessageSize=[long]$comparison.OriginalDiagnosticMessageSize
        DestinationDiagnosticMessageSize=[long]$comparison.DestinationDiagnosticMessageSize
        ProviderMessageSizeDrift=[bool]$comparison.ProviderMessageSizeDrift
        OriginalHistoricBW4k7gClaimRewritten=$false
        HistoricRawFlag0x00010000MeaningEstablished=$false
        HistoricalRawStateMismatchWaived=$false
        OutlookMoveExecutedByThisAudit=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='PreserveEvidenceAndClaim;DoNotRetry;Unknown0x00010000StillBlocked;SeparateOutlookRestartAudit'
    }
}catch{
    throw ('BW4k7m independent read-only audit STOP at ['+$stage+']: '+
        [string]$_.Exception.Message+'. NEVER RETRY Move or rewrite immutable Claim.')
}finally{
    foreach($com in @($moved,$folder,$destination,$ns,$app)){
        if($null -ne $com -and [Runtime.InteropServices.Marshal]::IsComObject($com)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($com)
        }
    }
}
