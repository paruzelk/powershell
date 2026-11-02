#requires -Version 5.1
# BW4k7f: exact Attachment1K source-one/target-zero read-only preflight; never moves mail.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceEvidenceSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedDecisionSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedSemanticSnapshotSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7f requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7fEmptyTargetPreflight265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$app=$null;$ns=$null;$stage='Exact fixture pins and ordinary precreated PSTs'
try{
    $leaf='OPA265-BW4j-74912f94d52348569efdd5528a92426f-87e72fd09e774098a403cbe99870b9e7.pst'
    $destName='OPA265-BW4j-87e72fd09e774098a403cbe99870b9e7'
    $sourceId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
    $sourceFolder='00000000E1878292411BC64291BD506DCEFD2A3582800000'
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       $ExpectedProfileName -cne 'Outlook' -or
       $ExpectedPlanSha256 -cne '6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63' -or
       $ExpectedFiveEvidenceSetSha256 -cne 'ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3' -or
       $ExpectedSourceEvidenceSha256 -cne '0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0' -or
       $ExpectedDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
       $ExpectedSemanticSnapshotSha256 -cne 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac' -or
       -not [IO.Path]::IsPathRooted($SourcePst) -or
       -not [IO.Path]::IsPathRooted($DestinationPst) -or
       $SourcePst.StartsWith('\',[StringComparison]::Ordinal) -or
       $DestinationPst.StartsWith('\',[StringComparison]::Ordinal) -or
       [IO.Path]::GetFileName($DestinationPst) -cne $leaf -or
       -not [IO.File]::Exists($SourcePst) -or
       -not [IO.File]::Exists($DestinationPst) -or
       (([IO.File]::GetAttributes($SourcePst) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (([IO.File]::GetAttributes($DestinationPst) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       [string]::Equals([IO.Path]::GetFullPath($SourcePst),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
        throw 'Exact fixed original witness, profile and existing different ordinary PST paths required.'
    }
    $sourceEvidence=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
    $plan=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    if(-not [IO.File]::Exists($sourceEvidence) -or -not [IO.File]::Exists($plan) -or
       (Get-FileHash -LiteralPath $sourceEvidence -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
       (Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256){
        throw 'Immutable original source evidence or plan altered.'
    }
    $original=Get-Content -LiteralPath $sourceEvidence -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$original.EntryId -cne $sourceId -or
       [string]$original.FolderEntryId -cne $sourceFolder -or
       [string]$original.Attachments[0].Sha256 -cne '8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'){
        throw 'Original MailItem identity or attachment SHA differs.'
    }
    $claim=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId
    $legacy=Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$TestId+'.json')
    if([IO.File]::Exists($claim) -or [IO.File]::Exists($legacy)){
        throw 'Attempt claim already exists; NEVER RETRY.'
    }
    $stage='Repeat full independent prior semantic source and decision verification'
    $argsCheck=@{
        Mode='Verify';SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        ExpectedDecisionSha256=$ExpectedDecisionSha256
        ExpectedSnapshotSha256=$ExpectedSemanticSnapshotSha256
        SourcePst=$SourcePst;ExpectedProfileName=$ExpectedProfileName
    }
    $first=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7eSemanticSourceSnapshot.ps1') @argsCheck
    [void](Assert-OPA265BW4k7fEvidencePins -Verified $first)
    $stage='Uniquely identify original Inbox and one existing, mounted, empty target'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){throw 'Wrong Outlook profile.'}
    $src=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $inbox=$src.Store.GetDefaultFolder(6)
    if(-not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$inbox.EntryID) -Expected $sourceFolder) -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$src.StoreId) -Expected ([string]$original.StoreId))){
        throw 'Original POP3 source store/Inbox mismatch.'
    }
    $mail=$ns.GetItemFromID($sourceId,[string]$src.StoreId)
    if($null -eq $mail -or [int]$mail.Class -ne 43 -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$mail.Parent.EntryID) -Expected $sourceFolder)){
        throw 'Pinned source MailItem is absent.'
    }
    $targetStore=$null;$matches=0
    $storeCount=[int]$ns.Stores.Count
    if($storeCount -lt 2 -or $storeCount -gt 128){throw 'Unsafe Outlook store count.'}
    for($i=1;$i -le $storeCount;$i++){
        $s=$ns.Stores.Item($i);$file=''
        try{$file=[string]$s.FilePath}catch{continue}
        if($file -and [string]::Equals([IO.Path]::GetFullPath($file),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
            $matches++;$targetStore=$s
        }
    }
    if($matches -ne 1 -or $null -eq $targetStore){throw 'Target PST not uniquely mounted.'}
    $root=$targetStore.GetRootFolder()
    $folderCount=[int]$root.Folders.Count
    if($folderCount -lt 1 -or $folderCount -gt 2048){throw 'Unsafe destination folder count.'}
    $target=$null;$named=0
    for($j=1;$j -le $folderCount;$j++){
        $f=$root.Folders.Item($j)
        if([string]$f.Name -ceq $destName){$named++;$target=$f}
    }
    if($named -ne 1){throw 'Exactly one precreated target folder required.'}
    $query='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+"'"+[string]$original.InternetMessageId+"'"
    $selected=$inbox.Items.Restrict($query)
    if([int]$selected.Count -ne 1 -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$selected.Item(1).EntryID) -Expected $sourceId)){
        throw 'BW4k7f exact source InternetMessageId must identify the pinned MailItem uniquely.'
    }
    $stage='Two independent destination-empty and source-one observations'
    $make=@{
        SuiteId=$SuiteId;TestId=$TestId
        SourceEntryId=$sourceId;SourceFolderEntryId=$sourceFolder
        SourceStoreId=[string]$src.StoreId
        DestinationStoreId=[string]$targetStore.StoreID
        DestinationPstLeaf=$leaf
        DestinationRootEntryId=[string]$root.EntryID
        DestinationFolderEntryId=[string]$target.EntryID
        DestinationFolderParentEntryId=[string]$target.Parent.EntryID
        DestinationFolderStoreId=[string]$target.StoreID
        DestinationFolderName=[string]$target.Name
        MatchedTargetNamedFolderCount=$named
        AttemptClaimExists=$false;LegacyClaimExists=$false
    }
    $a=[pscustomobject]($make+@{
        DestinationFolderItemCount=[int]$target.Items.Count
        SourceMessageIdMatches=[int]$inbox.Items.Restrict($query).Count
        DestinationMessageIdMatches=[int]$target.Items.Restrict($query).Count
    })
    [void](Assert-OPA265BW4k7fExactEmptyTarget -Observed $a)
    $second=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7eSemanticSourceSnapshot.ps1') @argsCheck
    [void](Assert-OPA265BW4k7fEvidencePins -Verified $second)
    $b=[pscustomobject]($make+@{
        DestinationFolderItemCount=[int]$target.Items.Count
        SourceMessageIdMatches=[int]$inbox.Items.Restrict($query).Count
        DestinationMessageIdMatches=[int]$target.Items.Restrict($query).Count
    })
    [void](Assert-OPA265BW4k7fStableEmptyTarget -First $a -Second $b)
    if([IO.File]::Exists($claim) -or [IO.File]::Exists($legacy)){throw 'Claim appeared during read-only review.'}
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7f.ExactSourceOneEmptyTargetPreMoveReadOnly.1'
        Status=$(if($dry){'WhatIfNoClaimNoMove'}else{'ExactAttachment1KEmptyTargetIndependentlyReviewedNoMove'})
        SuiteId=$SuiteId;TestId=$TestId
        SourceMessageIdMatches=1;DestinationMessageIdMatches=0
        DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
        DestinationFolderEntryId=[string]$target.EntryID
        DestinationFolderItemCount=0
        VerifiedSemanticSnapshotSha256=$ExpectedSemanticSnapshotSha256
        VerifiedSizeDecisionSha256=$ExpectedDecisionSha256
        IndependentSemanticReviews=2
        OutlookMoveExecuted=$false;AttemptClaimWritten=$false
        WriterPermit=$false;AutomaticRetryAllowed=$false;ProductionReady=$false
    }
}catch{
    throw ('BW4k7f STOP at ['+$stage+']: '+[string]$_.Exception.Message+'. No PST creation/mount or MailItem.Move performed.')
}finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
