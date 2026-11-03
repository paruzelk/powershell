#requires -Version 5.1
# BW4k7n LIVE forensic read-only diagnostics for the already-moved fresh test mail.
# No Move/Save/SetProperty/journal/Claim. The original BW4k7l and BW4k7m files are immutable.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$FixtureId='d1a68868-acf5-4c70-860d-5521e1ce2836',
    [string]$ExpectedEvidenceSha256='36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29',
    [string]$ExpectedClaimSha256='6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58',
    [string]$ExpectedDestinationEntryId='00000000E88584FF275FEE45B531E472CF338A8A24002000',
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7n requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7nProviderSizeFlagDiagnostics265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7mFreshOneShotGuard265.ps1')
$pins=Get-OPA265BW4k7nPins
if($FixtureId -cne [string]$pins.FixtureId -or
   $ExpectedEvidenceSha256 -cne [string]$pins.OriginalEvidenceSha256 -or
   $ExpectedClaimSha256 -cne [string]$pins.IrreversibleClaimSha256 -or
   $ExpectedDestinationEntryId -cne [string]$pins.DestinationEntryId -or
   $ExpectedProfileName -cne 'Outlook'){
    throw 'BW4k7n ONLY pinned BW4k7m archived fixture/evidence/Claim/EntryID permitted.'
}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7n.WhatIf.1'
        Status='WhatIfNoOutlookReadNoPstOrEvidenceWrite'
        FixtureId=$FixtureId
        OutlookMoveExecuted=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
$stage='Fresh independent BW4k7m exact original evidence SHA and Claim SHA audit'
$app=$null;$ns=$null;$dstStore=$null;$folder=$null;$filteredMail=$null;$directMail=$null
try{
    # An independent existing audit validates both immutable SHA256 files, unique
    # old source ZERO / exact archived target ONE and full semantic attachment content.
    $args=@{
        FixtureId=$FixtureId
        ExpectedEvidenceSha256=$ExpectedEvidenceSha256
        ExpectedClaimSha256=$ExpectedClaimSha256
        ExpectedDestinationEntryId=$ExpectedDestinationEntryId
        ExpectedProfileName=$ExpectedProfileName
    }
    $baseAudit=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7mIndependentPostMoveAudit.ps1') @args
    if($null -eq $baseAudit -or
       [string]$baseAudit.Schema -cne '2.6.5-BW4k7m.IndependentRealPostMoveAudit.1' -or
       [string]$baseAudit.Status -cne 'ContentMatchRawPrMessageFlagsDriftUnclassifiedManualReview' -or
       [int]$baseAudit.SourceMessageIdMatches -ne 0 -or
       [int]$baseAudit.DestinationMessageIdMatches -ne 1 -or
       -not [bool]$baseAudit.FullSemanticContentMatch -or
       [int]$baseAudit.SemanticFieldMismatchCount -ne 0 -or
       [bool]$baseAudit.AutomaticRetryAllowed -or [bool]$baseAudit.ProductionReady){
        throw 'BW4k7n BW4k7m semantic baseline changed. Stop without any write.'
    }
    $stage='Read source immutable evidence and exact archive POP3 test store'
    $sealed=Read-OPA265BW4k7mSealedEvidence -FixtureId $FixtureId -ExpectedEvidenceSha256 $ExpectedEvidenceSha256
    $source=$sealed.Record
    $processes=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($processes.Count -ne 1){throw 'BW4k7n requires exactly one OUTLOOK process.'}
    $pidOutlook=[int]$processes[0].Id
    $ticksOutlook=[long]$processes[0].StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'BW4k7n Outlook profile not equal to pinned profile.'
    }
    $destPath=[IO.Path]::GetFullPath([string]$source.DestinationPst)
    $hits=0;$count=[int]$ns.Stores.Count
    if($count -lt 2 -or $count -gt 128){throw 'BW4k7n invalid store count.'}
    for($i=1;$i -le $count;$i++){
        $s=$ns.Stores.Item($i);$p=''
        try{$p=[string]$s.FilePath}catch{continue}
        if($p -and [string]::Equals([IO.Path]::GetFullPath($p),
            $destPath,[StringComparison]::OrdinalIgnoreCase)){
            $dstStore=$s;$hits++
        }
    }
    if($hits -ne 1 -or $null -eq $dstStore -or
       (Get-OPA265BW4k7lStringSha -Value ([string]$dstStore.StoreID)) -cne
        [string]$source.DestinationStoreIdSha256){
        throw 'BW4k7n exact separate archived PST store not uniquely matched.'
    }
    $folder=$ns.GetFolderFromID([string]$pins.DestinationFolderEntryId,[string]$dstStore.StoreID)
    if($null -eq $folder -or
       [string]$folder.EntryID -cne [string]$pins.DestinationFolderEntryId -or
       [string]$folder.StoreID -cne [string]$dstStore.StoreID -or
       [string]$folder.Name -cne ('OPA265-BW4k7l-'+$FixtureId) -or
       [string]$folder.Parent.EntryID -cne [string]$dstStore.GetRootFolder().EntryID -or
       [int]$folder.Items.Count -ne 1){
        throw 'BW4k7n exact archived folder identity/count changed.'
    }
    $stage='Two independent archive MAPI scalar property reads (bounded only)'
    $originalMessageId=[string]$source.SourceWitness.InternetMessageId
    if($originalMessageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$'){
        throw 'BW4k7n original safe MessageId not present.'
    }
    $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+
        "'"+$originalMessageId+"'"
    $restricted=$folder.Items.Restrict($filter)
    if([int]$restricted.Count -ne 1){throw 'BW4k7n archival MessageId restriction returned 0/duplicates.'}
    $filteredMail=$restricted.Item(1)
    $directMail=$ns.GetItemFromID([string]$pins.DestinationEntryId,[string]$dstStore.StoreID)
    $probeArgs=@{
        StoreId=[string]$dstStore.StoreID
        FolderEntryId=[string]$pins.DestinationFolderEntryId
        EntryId=[string]$pins.DestinationEntryId
    }
    $probeOne=Get-OPA265BW4k7nArchivedProbe -Mail $filteredMail @probeArgs
    $probeTwo=Get-OPA265BW4k7nArchivedProbe -Mail $directMail @probeArgs
    [void](Assert-OPA265BW4k7nStableArchivedProbe -First $probeOne -Second $probeTwo)
    $current=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($current.Count -ne 1 -or
       [int]$current[0].Id -ne $pidOutlook -or
       [long]$current[0].StartTime.ToUniversalTime().Ticks -ne $ticksOutlook -or
       [int]$folder.Items.Restrict($filter).Count -ne 1){
        throw 'BW4k7n Outlook process / archived message changed during probe.'
    }
    $stage='Read-only cross-fixture documentation-grounded size and flag classification'
    $classification=Get-OPA265BW4k7nClassification -ArchivedProbe $probeTwo -IndependentArchiveAudit $baseAudit
    if([bool]$classification.ProductionReady -or [bool]$classification.WriterPermit -or
       [bool]$classification.AutomaticRetryAllowed -or [bool]$classification.ProviderFlagWaiver){
        throw 'BW4k7n classifer may never issue a waiver or production permit.'
    }
    $classification | Add-Member -MemberType NoteProperty -Name OriginalFullBW4k7mSemanticsVerified -Value $true
    $classification | Add-Member -MemberType NoteProperty -Name IndependentArchivePropertyReads -Value 2
    $classification | Add-Member -MemberType NoteProperty -Name CurrentOutlookProcessId -Value $pidOutlook
    $classification | Add-Member -MemberType NoteProperty -Name CurrentOutlookProcessStartUtcTicks -Value $ticksOutlook
    $classification | Add-Member -MemberType NoteProperty -Name IndependentProcessRestartComparisonAvailable -Value $false
    $classification | Add-Member -MemberType NoteProperty -Name OutlookMoveExecutedByThisReview -Value $false
    return $classification
}catch{
    throw ('BW4k7n READ-ONLY STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Move, Claim, rewrite, automatic retry or production waiver.')
}finally{
    foreach($com in @($filteredMail,$directMail,$folder,$dstStore,$ns,$app)){
        if($null -ne $com -and [Runtime.InteropServices.Marshal]::IsComObject($com)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($com)
        }
    }
}
