#requires -Version 5.1
# BW4k7k: no mutation, no MailItem.Move, no evidence or Claim writes.
# Examine PR_MESSAGE_FLAGS, PR_MESSAGE_STATUS and PR_HASATTACH separately
# in the original exact archived PST. Never infer one property from another.
[CmdletBinding(SupportsShouldProcess=$true)]
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
    throw 'BW4k7k requires native Windows PowerShell 5.1 STA.'
}
if($WhatIfPreference){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7k.ReadOnlyWhatIf.1'
        Status='WhatIfNoOutlookAccessNoMutation'
        OutlookMoveExecuted=$false;WriterPermit=$false
        ProductionReady=$false;AutomaticRetryAllowed=$false
    }
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7kProviderPropertyContext265.ps1')
$app=$null;$ns=$null;$archive=$null;$folder=$null;$mail=$null
$stage='Repeat exact original BW4k7j restarted-Outlook and source-zero/destination-one audit'
try {
    $args=@{
        SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        ExpectedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
        ExpectedDecisionSha256=$ExpectedDecisionSha256
        ExpectedSemanticSnapshotSha256=$ExpectedSemanticSnapshotSha256
        ExpectedClaimSha256=$ExpectedClaimSha256
        ExpectedDestinationEntryId=$ExpectedDestinationEntryId
        ExpectedDestinationFolderEntryId=$ExpectedDestinationFolderEntryId
        SourcePst=$SourcePst;DestinationPst=$DestinationPst
        ExpectedBaselineSha256=$ExpectedBaselineSha256
        ExpectedProfileName=$ExpectedProfileName
    }
    $prior=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7jFlagPolicyReview.ps1') @args
    if([string]$prior.Schema -cne '2.6.5-BW4k7j.IndependentDocumentedMessageFlagReview.1' -or
       [string]$prior.Status -cne 'ReopenedArchiveStableDocumentedUnmodifiedAndUnknown0x00010000RequireSeparateReview' -or
       [string]$prior.OriginalOneShotClaimSha256 -cne '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c' -or
       [string]$prior.VerifiedImmutableReopenBaselineSha256 -cne 'f75594047529cca19bbeb8d2a52db5412187325a39db4d659dc85b4b41d44399' -or
       [int]$prior.SourceMessageIdMatches -ne 0 -or
       [int]$prior.DestinationMessageIdMatches -ne 1 -or
       [int]$prior.OriginalRawPrMessageFlags -ne 65555 -or
       [int]$prior.DestinationRawPrMessageFlags -ne 17 -or
       -not [bool]$prior.ActualNewOutlookProcessObserved -or
       -not [bool]$prior.ArchiveContentRecipientAttachmentShaStable -or
       -not [bool]$prior.AllCapturedUserFieldsStable -or
       [bool]$prior.ChangedBit0x00010000Waived -or
       [bool]$prior.WriterPermit -or [bool]$prior.ProductionReady){
        throw 'BW4k7k exact historical BW4k7j read-only proof changed.'
    }
    $stage='Open existing Outlook instance and uniquely mounted exact destination PST'
    $outlookBefore=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($outlookBefore.Count -ne 1){throw 'BW4k7k requires exactly one OUTLOOK.EXE.'}
    $outlookPid=[int]$outlookBefore[0].Id
    $outlookStartTicks=[long]$outlookBefore[0].StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName -or $ExpectedProfileName -cne 'Outlook'){
        throw 'BW4k7k unexpected Outlook profile.'
    }
    $count=[int]$ns.Stores.Count
    if($count -lt 2 -or $count -gt 128){throw 'BW4k7k unsafe Outlook store count.'}
    $found=0
    for($i=1;$i -le $count;$i++){
        $store=$ns.Stores.Item($i);$path=''
        try {$path=[string]$store.FilePath} catch {continue}
        if($path -and [string]::Equals([IO.Path]::GetFullPath($path),
           [IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
            $archive=$store;$found++
        }
    }
    if($found -ne 1 -or $null -eq $archive){
        throw 'BW4k7k archived PST must be mounted exactly once.'
    }
    if($ExpectedDestinationEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B24002000' -or
       $ExpectedDestinationFolderEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B82800000'){
        throw 'BW4k7k historical target EntryIDs differ.'
    }
    $folder=$ns.GetFolderFromID($ExpectedDestinationFolderEntryId,[string]$archive.StoreID)
    if([string]$folder.EntryID -cne $ExpectedDestinationFolderEntryId -or
       [string]$folder.StoreID -cne [string]$archive.StoreID -or
       [string]$folder.Name -cne 'OPA265-BW4j-87e72fd09e774098a403cbe99870b9e7' -or
       [int]$folder.Items.Count -ne 1){
        throw 'BW4k7k target folder identity/count mismatch.'
    }
    $mail=$ns.GetItemFromID($ExpectedDestinationEntryId,[string]$archive.StoreID)
    if($null -eq $mail -or
       [string]$mail.EntryID -cne $ExpectedDestinationEntryId -or
       [string]$mail.Parent.EntryID -cne $ExpectedDestinationFolderEntryId -or
       [string]$mail.Parent.StoreID -cne [string]$archive.StoreID -or
       [int]$mail.Class -ne 43){
        throw 'BW4k7k archived MailItem identity mismatch.'
    }
    $stage='Read independent raw MAPI property tags twice from original archived object'
    $samples=@()
    for($round=0;$round -lt 2;$round++){
        $accessor=$mail.PropertyAccessor
        $flags=[int]$accessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E070003')
        $attach=$accessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E1B000B')
        if($attach -isnot [bool]){throw 'BW4k7k PR_HASATTACH is not Boolean.'}
        $available=$true;$messageStatus=$null
        try {
            $messageStatus=[int]$accessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E170003')
        } catch {
            # A missing optional property is evidence of absence, not a zero value.
            # Any other failure is ambiguous and must STOP.
            $exception=$_.Exception
            $hresults=@()
            while($null -ne $exception){
                $hresults+=([int]$exception.HResult)
                $exception=$exception.InnerException
            }
            if($hresults -notcontains -2147221233){
                throw 'BW4k7k PR_MESSAGE_STATUS read failed for a reason other than MAPI_E_NOT_FOUND.'
            }
            $available=$false
        }
        $samples+=,[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7k.RawProviderPropertySample.1'
            MessageFlagsTag='0x0E070003'
            MessageFlags=$flags
            MessageStatusTag='0x0E170003'
            MessageStatusAvailable=[bool]$available
            MessageStatus=$messageStatus
            HasAttachmentsTag='0x0E1B000B'
            HasAttachments=[bool]$attach
            AttachmentCount=[int]$mail.Attachments.Count
            UnRead=[bool]$mail.UnRead
            PstStorePathMatched=$true
            ExactDestinationEntryIdMatched=$true
            PropertyOrigin='ArchivedMailItem.PropertyAccessor'
        }
    }
    $result=Compare-OPA265BW4k7kPropertySamples -First $samples[0] -Second $samples[1]
    $stage='Verify same Outlook process and historical immutable baseline after live reads'
    $outlookAfter=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($outlookAfter.Count -ne 1 -or
       [int]$outlookAfter[0].Id -ne $outlookPid -or
       [long]$outlookAfter[0].StartTime.ToUniversalTime().Ticks -ne $outlookStartTicks){
        throw 'BW4k7k Outlook process changed during independent MAPI reads.'
    }
    $baseline=Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4k7i-ReopenBaselines\suite-74912f94-d523-4856-9efd-d5528a92426f\fixture-87e72fd0-9e77-4098-a403-cbe99870b9e7.json'
    if(-not [IO.File]::Exists($baseline) -or
       (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedBaselineSha256){
        throw 'BW4k7k original BW4k7i immutable baseline SHA drifted.'
    }
    $result | Add-Member -NotePropertyName SuiteId -NotePropertyValue $SuiteId
    $result | Add-Member -NotePropertyName TestId -NotePropertyValue $TestId
    $result | Add-Member -NotePropertyName OriginalOneShotClaimSha256 -NotePropertyValue $ExpectedClaimSha256
    $result | Add-Member -NotePropertyName VerifiedImmutableReopenBaselineSha256 -NotePropertyValue $ExpectedBaselineSha256
    $result | Add-Member -NotePropertyName ActualReopenedOutlookProcessVerified -NotePropertyValue $true
    $result | Add-Member -NotePropertyName SourceMessageIdMatches -NotePropertyValue 0
    $result | Add-Member -NotePropertyName DestinationMessageIdMatches -NotePropertyValue 1
    $result | Add-Member -NotePropertyName DestinationEntryId -NotePropertyValue $ExpectedDestinationEntryId
    return $result
}catch{
    throw ('BW4k7k STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No new Move, no Claim/journal modification and no production approval. NEVER RETRY.')
}finally{
    foreach($obj in @($mail,$folder,$archive,$ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}
