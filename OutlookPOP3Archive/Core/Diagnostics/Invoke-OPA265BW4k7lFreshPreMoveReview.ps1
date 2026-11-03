#requires -Version 5.1
# BW4k7l: NEW disposable Outlook POP3 Inbox fixture, PRE-MOVE only.
# Review: no persistent writes. Capture: one immutable JSON evidence file only.
# No MailItem.Move, Save, Delete, Send, journal/claim modification.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Review','Capture')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$FixtureId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [Parameter(Mandatory=$true)][string]$ExpectedDestinationFolderEntryId,
    [string]$ExpectedProfileName='Outlook',
    [switch]$ConfirmImmutableCapture,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7l requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7lFreshPreMoveMapiWitness265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
[void](Assert-OPA265BW4k7lFixtureId -FixtureId $FixtureId)
if($ExpectedProfileName -cne 'Outlook' -or
   $ExpectedDestinationFolderEntryId -cnotmatch '^[a-fA-F0-9]{40,512}$' -or
   $SourcePst -eq $DestinationPst){
    throw 'BW4k7l strict Outlook/unique PST/destination-folder pins required.'
}
if($Mode -ceq 'Review' -and ($ConfirmImmutableCapture -or $ApprovalText)){
    throw 'BW4k7l Review refuses any Capture approval.'
}
if($Mode -ceq 'Capture' -and
   (-not $ConfirmImmutableCapture -or
    $ApprovalText -cne ('CAPTURE NEW BW4K7L PREMOVE '+$FixtureId))){
    throw 'BW4k7l Capture requires explicit exact approval for this NEW fixture.'
}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7l.WhatIf.1'
        Status='WhatIfNoOutlookAccessNoEvidenceNoMove'
        EvidenceWritten=$false;OutlookMoveExecuted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
$stage='Exact new fixture and source/destination paths'
$app=$null;$ns=$null;$source=$null;$destination=$null;$folder=$null;$mail=$null
try{
    $sourceCanonical=[IO.Path]::GetFullPath($SourcePst)
    $destinationCanonical=[IO.Path]::GetFullPath($DestinationPst)
    if(-not [IO.File]::Exists($sourceCanonical) -or
       -not [IO.File]::Exists($destinationCanonical) -or
       [IO.Path]::GetExtension($destinationCanonical) -ine '.pst' -or
       -not [IO.Path]::IsPathRooted($DestinationPst) -or
       $destinationCanonical.StartsWith('\\',[StringComparison]::Ordinal) -or
       [string]::Equals($sourceCanonical,$destinationCanonical,[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k7l both local PST files must exist and be different.'
    }
    if(([IO.File]::GetAttributes($destinationCanonical) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7l destination PST is a reparse point.'
    }
    $evidencePath=Get-OPA265BW4k7lEvidencePath -FixtureId $FixtureId
    if([IO.File]::Exists($evidencePath)){throw 'BW4k7l existing pre-Move evidence: no recapture/rebaseline.'}
    foreach($p in @(
        (Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$FixtureId+'.json')),
        (Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4k1-Claims') ('fixture-'+$FixtureId+'.json'))
    )){
        if([IO.File]::Exists($p)){throw 'BW4k7l prior fixture attempt/Claim detected. NEVER RETRY.'}
    }
    $stage='Outlook exact POP3 DeliveryStore and selected NEW Inbox item'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){throw 'BW4k7l Outlook profile mismatch.'}
    $source=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $sourceCanonical
    $inbox=$source.Store.GetDefaultFolder(6)
    if($null -eq $inbox -or
       [string]$inbox.StoreID -cne [string]$source.StoreId){
        throw 'BW4k7l exact POP3 Inbox unavailable.'
    }
    $explorer=$app.ActiveExplorer()
    if($null -eq $explorer -or [int]$explorer.Selection.Count -ne 1){
        throw 'BW4k7l select exactly one NEW synthetic mail in the POP3 Inbox.'
    }
    $selected=$explorer.Selection.Item(1)
    $entry=[string]$selected.EntryID
    if([int]$selected.Class -ne 43 -or
       [string]$selected.Parent.EntryID -cne [string]$inbox.EntryID -or
       [string]$selected.Parent.StoreID -cne [string]$source.StoreId -or
       $entry -cnotmatch '^[a-fA-F0-9]{40,512}$'){
        throw 'BW4k7l selection is not the exact source POP3 Inbox MailItem.'
    }
    $stage='Uniquely mounted separate test destination PST with exact empty fixture folder'
    $hit=0;$storeCount=[int]$ns.Stores.Count
    if($storeCount -lt 2 -or $storeCount -gt 128){throw 'BW4k7l unsafe store count.'}
    for($i=1;$i -le $storeCount;$i++){
        $s=$ns.Stores.Item($i);$fp=''
        try{$fp=[string]$s.FilePath}catch{continue}
        if($fp -and [string]::Equals([IO.Path]::GetFullPath($fp),
          $destinationCanonical,[StringComparison]::OrdinalIgnoreCase)){
            $destination=$s;$hit++
        }
    }
    if($hit -ne 1 -or $null -eq $destination){
        throw 'BW4k7l new destination PST not uniquely mounted.'
    }
    $folder=$ns.GetFolderFromID($ExpectedDestinationFolderEntryId,[string]$destination.StoreID)
    if($null -eq $folder -or
       [string]$folder.EntryID -cne $ExpectedDestinationFolderEntryId -or
       [string]$folder.StoreID -cne [string]$destination.StoreID -or
       [string]$folder.Parent.EntryID -cne [string]$destination.GetRootFolder().EntryID -or
       [string]$folder.Name -cne ('OPA265-BW4k7l-'+$FixtureId) -or
       [int]$folder.Items.Count -ne 0){
        throw 'BW4k7l test archive folder must be exact and initially EMPTY.'
    }
    $stage='Two independent pre-Move reads of full synthetic 1K content and separate MAPI tags'
    $args=@{
        FixtureId=$FixtureId;ExpectedEntryId=$entry
        ExpectedFolderId=[string]$inbox.EntryID
        ExpectedStoreId=[string]$source.StoreId
    }
    $a=Get-OPA265BW4k7lFreshMailWitness -Mail $selected @args
    $mail=$ns.GetItemFromID($entry,[string]$source.StoreId)
    $b=Get-OPA265BW4k7lFreshMailWitness -Mail $mail @args
    [void](Assert-OPA265BW4k7lStableFreshWitness -First $a -Second $b)
    if([int]$folder.Items.Count -ne 0 -or
       [string]$mail.Parent.EntryID -cne [string]$inbox.EntryID){
        throw 'BW4k7l source/empty destination changed during read-only capture.'
    }
    $record=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7l.ImmutablePreMoveEvidence.1'
        FixtureId=$FixtureId
        OutlookProfile='Outlook'
        SourcePst=$sourceCanonical
        DestinationPst=$destinationCanonical
        DestinationStoreIdSha256=(Get-OPA265BW4k7lStringSha -Value ([string]$destination.StoreID))
        DestinationFolderEntryId=$ExpectedDestinationFolderEntryId
        DestinationFolderItems=0
        SourceWitness=$b
        IndependentSourceReads=2
        PriorBW4k7gClaimMustRemainUntouched='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        Original0x00010000MeaningEstablished=$false
        OriginalBW4k7gFlagMismatchWaived=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
    if($Mode -ceq 'Review'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7l.FreshPreMoveReview.1'
            Status='FreshExactDisposableSourceAndEmptyArchiveReviewedNoMove'
            FixtureId=$FixtureId
            SourceEntryId=$entry
            SourceRawPrMessageFlags=[int]$b.RawPrMessageFlags
            SourcePrMessageStatusAvailable=[bool]$b.PrMessageStatusAvailable
            SourcePrMessageStatus=$b.PrMessageStatus
            SourcePrHasAttach=[bool]$b.PrHasAttach
            SourceRawFlag0x00010000=[bool]$b.RawFlag0x00010000BeforeMove
            AttachmentBytesSha256=[string]$b.AttachmentBytesSha256
            RecipientDigestSha256=[string]$b.RecipientDigestSha256
            SourceMessageIdSha256=[string]$b.InternetMessageIdSha256
            IndependentSourceReads=2
            EmptyDestinationFolderVerified=$true
            EvidenceWritten=$false;OutlookMoveExecuted=$false
            WriterPermit=$false;AutomaticRetryAllowed=$false;ProductionReady=$false
            NextAction='Run separately approved Capture after reviewing source MAPI values;NeverMoveInBW4k7l'
        }
    }
    $stage='Operator-approved immutable CreateNew/Flush evidence JSON (no Outlook/PST write)'
    if(-not $PSCmdlet.ShouldProcess($evidencePath,
        'Write one immutable pre-Move JSON, not a Move or Claim')){
        throw 'BW4k7l operator declined immutable evidence capture.'
    }
    $write=Write-OPA265BW4k7lEvidenceOnce -Record $record
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7l.FreshPreMoveCapture.1'
        Status='FreshOriginalMapiAndContentWitnessSealedNoMove'
        FixtureId=$FixtureId
        EvidencePath=[string]$write.EvidencePath
        EvidenceSha256=[string]$write.EvidenceSha256
        SourceRawPrMessageFlags=[int]$b.RawPrMessageFlags
        SourcePrMessageStatusAvailable=[bool]$b.PrMessageStatusAvailable
        SourcePrMessageStatus=$b.PrMessageStatus
        SourceRawFlag0x00010000=[bool]$b.RawFlag0x00010000BeforeMove
        IndependentSourceReads=2
        EvidenceWritten=$true
        OutlookMoveExecuted=$false;AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
        NextAction='STOP;PreserveOriginalEvidenceAndSourceMail;DoNotMoveUntilSeparatelyTestedOneShotStage'
    }
}catch{
    throw ('BW4k7l STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Outlook MailItem.Move. No automatic retry or production permission.')
}finally{
    foreach($o in @($mail,$folder,$destination,$ns,$app)){
        if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)
        }
    }
}
