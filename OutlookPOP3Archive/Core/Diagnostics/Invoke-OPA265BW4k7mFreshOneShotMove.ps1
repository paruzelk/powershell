#requires -Version 5.1
# BW4k7m EXACT NEW fixture only. Explicitly approved durable Claim then ONE MailItem.Move.
# Review and -WhatIf are read-only (no Claim/Move). NO automatic retries.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Review','Execute')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$FixtureId,
    [Parameter(Mandatory=$true)][string]$ExpectedEvidenceSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [Parameter(Mandatory=$true)][string]$ExpectedDestinationFolderEntryId,
    [string]$ExpectedProfileName='Outlook',
    [switch]$ConfirmOneShotFreshMove,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7m requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7mFreshOneShotGuard265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$pins=Get-OPA265BW4k7mPins
if($FixtureId -cne [string]$pins.FixtureId -or
   $ExpectedEvidenceSha256 -cne [string]$pins.EvidenceSha256 -or
   $ExpectedDestinationFolderEntryId -cne [string]$pins.DestinationFolderEntryId -or
   $ExpectedProfileName -cne 'Outlook'){
    throw 'BW4k7m: new operator FixtureId/EvidenceSha256/FolderEntryId/Profile pins mismatch.'
}
if($Mode -ceq 'Review' -and ($ConfirmOneShotFreshMove -or $ApprovalText)){
    throw 'BW4k7m Review refuses execution approval.'
}
if(-not $dry -and $Mode -ceq 'Execute' -and
   (-not $ConfirmOneShotFreshMove -or
    $ApprovalText -cne ('MOVE EXACT ONE BW4K7M '+$FixtureId))){
    throw 'BW4k7m Execute requires separate exact one-shot operator approval.'
}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7m.WhatIf.1'
        Status='WhatIfNoOutlookAccessNoClaimNoMove'
        FixtureId=$FixtureId
        AttemptClaimWritten=$false;OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}
$stage='Read and verify original immutable BW4k7l pre-Move evidence SHA256'
$claimed=$false;$claimPath=Get-OPA265BW4k7mClaimPath -FixtureId $FixtureId
$app=$null;$ns=$null;$selected=$null;$mail=$null;$destinationFolder=$null;$destinationStore=$null
try{
    [void](Assert-OPA265BW4k7mNeverAttempted -FixtureId $FixtureId)
    $sealed=Read-OPA265BW4k7mSealedEvidence -FixtureId $FixtureId -ExpectedEvidenceSha256 $ExpectedEvidenceSha256
    $e=$sealed.Record;$w=$e.SourceWitness
    $sourcePath=[IO.Path]::GetFullPath($SourcePst)
    $destPath=[IO.Path]::GetFullPath($DestinationPst)
    if(-not [IO.Path]::IsPathRooted($SourcePst) -or
       -not [IO.Path]::IsPathRooted($DestinationPst) -or
       $sourcePath.StartsWith('\\',[StringComparison]::Ordinal) -or
       $destPath.StartsWith('\\',[StringComparison]::Ordinal) -or
       -not [string]::Equals($sourcePath,[string]$e.SourcePst,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals($destPath,[string]$e.DestinationPst,[StringComparison]::OrdinalIgnoreCase) -or
       [string]::Equals($sourcePath,$destPath,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals([IO.Path]::GetFileName($destPath),
            ('OPA265-BW4k7l-'+$FixtureId+'.pst'),[StringComparison]::OrdinalIgnoreCase) -or
       -not [IO.File]::Exists($sourcePath) -or
       -not [IO.File]::Exists($destPath) -or
       (([IO.File]::GetAttributes($destPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'BW4k7m source/destination PST path, identity, or existence differs from immutable evidence.'
    }
    $stage='One Outlook 5.1 STA process and exact POP3 delivery-store profile'
    $processes=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($processes.Count -ne 1){throw 'BW4k7m Outlook process must be uniquely identified.'}
    $outlookProcessId=[int]$processes[0].Id
    $outlookStartUtcTicks=[long]$processes[0].StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){throw 'BW4k7m wrong Outlook profile.'}
    $source=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $sourcePath
    if((Get-OPA265BW4k7lStringSha -Value ([string]$source.StoreId)) -cne [string]$w.SourceStoreIdSha256){
        throw 'BW4k7m POP3 source store identity changed from sealed evidence.'
    }
    $inbox=$source.Store.GetDefaultFolder(6)
    if($null -eq $inbox -or
       [string]$inbox.EntryID -cne [string]$w.SourceFolderEntryId -or
       [string]$inbox.StoreID -cne [string]$source.StoreId){
        throw 'BW4k7m original POP3 Inbox identity changed.'
    }
    $stage='Selected exact new source mail, two independent reads vs sealed original content'
    $explorer=$app.ActiveExplorer()
    if($null -eq $explorer -or [int]$explorer.Selection.Count -ne 1){
        throw 'BW4k7m select exactly ONE fresh BW4k7l mail in the source POP3 Inbox.'
    }
    $selected=$explorer.Selection.Item(1)
    if([string]$selected.EntryID -cne [string]$pins.SourceEntryId -or
       [string]$selected.Parent.EntryID -cne [string]$w.SourceFolderEntryId -or
       [string]$selected.Parent.StoreID -cne [string]$source.StoreId){
        throw 'BW4k7m the selected Outlook mail is not the sealed fresh source item.'
    }
    $witnessArgs=@{
        FixtureId=$FixtureId
        ExpectedEntryId=[string]$pins.SourceEntryId
        ExpectedFolderId=[string]$w.SourceFolderEntryId
        ExpectedStoreId=[string]$source.StoreId
    }
    $first=Get-OPA265BW4k7lFreshMailWitness -Mail $selected @witnessArgs
    $mail=$ns.GetItemFromID([string]$pins.SourceEntryId,[string]$source.StoreId)
    $second=Get-OPA265BW4k7lFreshMailWitness -Mail $mail @witnessArgs
    [void](Assert-OPA265BW4k7mSourceEqualsSealed -Original $w -Live $first)
    [void](Assert-OPA265BW4k7mSourceEqualsSealed -Original $w -Live $second)
    [void](Assert-OPA265BW4k7lStableFreshWitness -First $first -Second $second)
    $stage='Unique target PST, exact EMPTY top-level folder and MessageId Restrict'
    $hits=0;$count=[int]$ns.Stores.Count
    if($count -lt 2 -or $count -gt 128){throw 'BW4k7m unsafe store inventory.'}
    for($i=1;$i -le $count;$i++){
        $s=$ns.Stores.Item($i);$fp=''
        try{$fp=[string]$s.FilePath}catch{continue}
        if($fp -and [string]::Equals([IO.Path]::GetFullPath($fp),
             $destPath,[StringComparison]::OrdinalIgnoreCase)){
            $destinationStore=$s;$hits++
        }
    }
    if($hits -ne 1 -or $null -eq $destinationStore -or
       [string]$destinationStore.StoreID -ceq [string]$source.StoreId -or
       (Get-OPA265BW4k7lStringSha -Value ([string]$destinationStore.StoreID)) -cne
        [string]$e.DestinationStoreIdSha256){
        throw 'BW4k7m target PST store absent, duplicated or changed since original Capture.'
    }
    $destinationFolder=$ns.GetFolderFromID(
        $ExpectedDestinationFolderEntryId,[string]$destinationStore.StoreID)
    if($null -eq $destinationFolder -or
       [string]$destinationFolder.EntryID -cne $ExpectedDestinationFolderEntryId -or
       [string]$destinationFolder.StoreID -cne [string]$destinationStore.StoreID -or
       [string]$destinationFolder.Parent.EntryID -cne
        [string]$destinationStore.GetRootFolder().EntryID -or
       [string]$destinationFolder.Name -cne ('OPA265-BW4k7l-'+$FixtureId) -or
       [int]$destinationFolder.Items.Count -ne 0){
        throw 'BW4k7m exact top-level target folder is not empty or changed.'
    }
    $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+
        "'"+[string]$w.InternetMessageId+"'"
    $sourceRestricted=$inbox.Items.Restrict($filter)
    $destinationRestricted=$destinationFolder.Items.Restrict($filter)
    if([int]$sourceRestricted.Count -ne 1 -or
       [string]$sourceRestricted.Item(1).EntryID -cne [string]$pins.SourceEntryId -or
       [int]$destinationRestricted.Count -ne 0){
        throw 'BW4k7m source MessageId not unique or destination already contains a match.'
    }
    $stage='Final second exact source and destination preflight before Claim'
    $third=Get-OPA265BW4k7lFreshMailWitness -Mail $mail @witnessArgs
    [void](Assert-OPA265BW4k7mSourceEqualsSealed -Original $w -Live $third)
    if([int]$destinationFolder.Items.Count -ne 0 -or
       [int]$inbox.Items.Restrict($filter).Count -ne 1 -or
       [int]$destinationFolder.Items.Restrict($filter).Count -ne 0){
        throw 'BW4k7m message counts changed immediately before Claim.'
    }
    $currentProcess=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($currentProcess.Count -ne 1 -or [int]$currentProcess[0].Id -ne $outlookProcessId -or
       [long]$currentProcess[0].StartTime.ToUniversalTime().Ticks -ne $outlookStartUtcTicks){
        throw 'BW4k7m Outlook process was restarted during preflight.'
    }
    [void](Assert-OPA265BW4k7mNeverAttempted -FixtureId $FixtureId)
    if($Mode -ceq 'Review'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7m.FreshOneShotPreflight.1'
            Status='FreshSealedOriginalSourceOneEmptyDestinationReadOnlyReady'
            FixtureId=$FixtureId
            VerifiedOriginalPreMoveEvidenceSha256=[string]$sealed.Sha256
            SourceEntryId=[string]$pins.SourceEntryId
            DestinationFolderEntryId=$ExpectedDestinationFolderEntryId
            SourceMatches=1;DestinationMatches=0
            IndependentPreMoveSourceReads=3
            SourceRawPrMessageFlags=[int]$third.RawPrMessageFlags
            SourcePrMessageStatus=$third.PrMessageStatus
            Source0x00010000Present=[bool]$third.RawFlag0x00010000BeforeMove
            SourceAttachmentBytesSha256=[string]$third.AttachmentBytesSha256
            ClaimPath=$claimPath
            AttemptClaimWritten=$false;OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
            NextAction='STOP;OperatorApprovalRequiresSeparateExecute;DoNotMoveManually'
        }
    }
    $stage='Final explicit ShouldProcess boundary'
    if(-not $PSCmdlet.ShouldProcess(
        ('ONE fresh isolated BW4k7m Attachment1K '+$FixtureId),
        'Durably claim exactly once and invoke exactly ONE MailItem.Move; NEVER RETRY')){
        return [pscustomobject]@{
            Status='WhatIfNoClaimNoMove'
            AttemptClaimWritten=$false;OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
    }
    $stage='CreateNew and flush one irreversible attempt Claim BEFORE Move'
    [void](Assert-OPA265BW4k7mNeverAttempted -FixtureId $FixtureId)
    $claim=New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 $ExpectedEvidenceSha256
    $written=Write-OPA265BW4k7mClaimOnce -Claim $claim
    $claimed=$true
    $stage='Exactly ONE Outlook MailItem.Move; no exception retry'
    $moved=$mail.Move($destinationFolder)
    if($null -eq $moved -or [string]::IsNullOrWhiteSpace([string]$moved.EntryID)){
        throw 'BW4k7m Move returned no destination entry ID; NEVER RETRY.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7m.RealOneShotFreshMoveReturned.1'
        Status='OneFreshAttachment1KMoveReturnedIndependentAuditRequired'
        FixtureId=$FixtureId
        OriginalEvidenceSha256=$ExpectedEvidenceSha256
        ClaimPath=[string]$written.ClaimPath
        ClaimSha256=[string]$written.ClaimSha256
        DestinationEntryId=[string]$moved.EntryID
        DestinationFolderEntryId=$ExpectedDestinationFolderEntryId
        MoveAttempts=1;OutlookMoveReturned=$true
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        NextAction='STOP;NeverRetry;RunIndependentBW4k7mReadOnlyPostMoveAudit'
    }
}catch{
    throw ('BW4k7m STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        $(if($claimed -or [IO.File]::Exists($claimPath)){
           '. Claim exists or may exist: NEVER RETRY; independent read-only audit ONLY.'
        }else{'. No Claim observed; do not automatically retry.'}))
}finally{
    foreach($com in @($mail,$selected,$destinationFolder,$destinationStore,$ns,$app)){
        if($null -ne $com -and [Runtime.InteropServices.Marshal]::IsComObject($com)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($com)
        }
    }
}
