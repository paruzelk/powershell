#requires -Version 5.1
# BW4k7v2a8 forensic read only: exact already-moved synthetic BW4k7v2a7 item.
# No Outlook COM writers, attachment SaveAsFile, file writes, Move, Delete, or PST mount.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Review')][string]$Mode='Review',
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedClaimSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedDestinationEntryId
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v2a8 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a7PostSaveBaselinePolicy265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a8AttachmentAttributionPolicy265.ps1')
if($SuiteId -cne '1a6683eb-3136-46eb-a1a8-ed8ece33b52c' -or
   $ExpectedManifestSha256 -cne '77311b1df742545e15c01d755858b31395e76446fd4d43497775b2bed98bc2f1' -or
   $ExpectedClaimSha256 -cne 'ff4093e90fb7663d514085f087ea2cd46fde6c7c6bdb23b36f38ba41c1aa21a2' -or
   $ExpectedDestinationEntryId -cne '00000000D2D5FCF473B27142BB218ABB3C07996824002000'){
    throw 'BW4k7v2a8 only supports one exact independently reconciled BW4k7v2a7 SuiteId/manifest/claim/destination.'
}
$layout=Get-OPA265BW4k7v2a7Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
[void](Assert-OPA265BW4k7v2a7Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a8.Plan.1'
        Status='OriginalSuitePinnedNoOutlookNoFileWrites'
        SuiteId=$SuiteId
        OriginalManifestSha256=$ExpectedManifestSha256
        OriginalClaimSha256=$ExpectedClaimSha256
        DestinationEntryId=$ExpectedDestinationEntryId
        ExactOriginalTargetPst=[string]$layout.PstPath
        Operation='Read-only exact previously moved synthetic message attachment metadata'
        RawBodyAttachmentContentsNamesAndSignaturesReturned=$false
        AnyOutlookWriter=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
if(-not [IO.File]::Exists([string]$layout.PstPath) -or
   -not [IO.File]::Exists([string]$layout.ManifestPath) -or
   -not [IO.File]::Exists([string]$layout.MoveClaimPath) -or
   -not [IO.File]::Exists([string]$layout.MoveReturnPath)){
    throw 'BW4k7v2a8 original test PST or immutable original manifest/claim/return missing.'
}
$manifest=Read-OPA265BW4k7v2a1SealedJson -Path $layout.ManifestPath -ExpectedSha256 $ExpectedManifestSha256
$claim=Read-OPA265BW4k7v2a1SealedJson -Path $layout.MoveClaimPath -ExpectedSha256 $ExpectedClaimSha256
$returnSha=(Get-FileHash -LiteralPath $layout.MoveReturnPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($returnSha -cne '9a89be00eeb85163afd557494bf16b7999c45f388fd7a25c59c35ccc65bf62cc'){
    throw 'BW4k7v2a8 original immutable Move return SHA256 changed.'
}
if([string]$manifest.Schema -cne '2.6.5-BW4k7v2a7.PreMoveManifest.1' -or
   [string]$claim.Schema -cne '2.6.5-BW4k7v2a7.OneShotMoveClaim.1' -or
   [string]$manifest.SuiteId -cne $SuiteId -or [string]$claim.SuiteId -cne $SuiteId -or
   [string]$manifest.PstPath -cne [string]$layout.PstPath -or
   [string]$manifest.Subject -cne [string]$layout.Subject -or
   [string]$claim.ManifestSha256 -cne $ExpectedManifestSha256 -or
   [string]$claim.SourceEntryId -cne [string]$manifest.SourceEntryId -or
   [string]$claim.TargetStoreId -cne [string]$manifest.TargetStoreId -or
   [string]$claim.TargetFolderId -cne [string]$manifest.TargetFolderId -or
   [string]$manifest.SyntheticSavedActualBodySha256 -cnotmatch '^[a-f0-9]{64}$' -or
   -not [bool]$claim.OneShotMoveClaimedBeforeComCall -or
   -not [bool]$claim.RetryForbiddenEvenAfterException -or
   [bool]$manifest.ProductionReady -or [bool]$claim.ProductionReady){
    throw 'BW4k7v2a8 immutable original MAPI claim and preMove baseline mismatch.'
}
function Get-OPA265BW4k7v2a8OptionalMapiProperty {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Item,
          [Parameter(Mandatory=$true)][string]$Tag,
          [ValidateSet('Boolean','Long','String')][string]$Kind='Long')
    try{
        $raw=$Item.PropertyAccessor.GetProperty(
            ('http://schemas.microsoft.com/mapi/proptag/'+$Tag))
        $v=$null
        if($Kind -eq 'Boolean'){$v=[bool]$raw}
        elseif($Kind -eq 'String'){$v=[string]$raw}
        else{$v=[long]$raw}
        return [pscustomobject]@{Available=$true;Value=$v;ErrorCategory=''}
    }catch{
        return [pscustomobject]@{Available=$false;Value=$null;ErrorCategory='ProviderPropertyUnavailable'}
    }
}
$app=$null;$ns=$null
try{
    $procs=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($procs.Count -ne 1){throw 'BW4k7v2a8 exactly one active Outlook process is required.'}
    $proc=$procs[0]
    $ticks=[long]$proc.StartTime.ToUniversalTime().Ticks
    $restarted=([int]$proc.Id -ne [int]$claim.MoveProcessId -and
        $ticks -ne [long]$claim.MoveProcessStartUtcTicks)
    if(-not $restarted){throw 'BW4k7v2a8 Outlook was not restarted after the original one-shot Move.'}
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'BW4k7v2a8 wrong Outlook profile.'
    }
    $matchesAcct=0
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $a=$ns.Accounts.Item($i)
        if([string]$a.SmtpAddress -ieq [string]$layout.Pop3SmtpAddress -and
           [int]$a.AccountType -eq 2){
            $matchesAcct++
            if([string]$a.DeliveryStore.StoreID -cne [string]$manifest.Pop3DeliveryStoreId){
                throw 'BW4k7v2a8 POP3 original delivery store identity changed.'
            }
        }
    }
    if($matchesAcct -ne 1){throw 'BW4k7v2a8 original POP3 account no longer unique.'}
    $drafts=$ns.DefaultStore.GetDefaultFolder(16)
    if([string]$drafts.StoreID -cne [string]$manifest.SourceStoreId -or
       [string]$drafts.EntryID -cne [string]$manifest.SourceFolderId){
        throw 'BW4k7v2a8 original source Drafts identity changed.'
    }
    $target=$null;$targetMatches=0
    $storeCount=[int]$ns.Stores.Count
    if($storeCount -lt 1 -or $storeCount -gt 32){
        throw 'BW4k7v2a8 too many or missing Outlook stores.'
    }
    for($i=1;$i -le $storeCount;$i++){
        $s=$ns.Stores.Item($i)
        $path=[string]$s.FilePath
        if(-not [string]::IsNullOrWhiteSpace($path) -and
            [string]::Equals([IO.Path]::GetFullPath($path),
                [string]$layout.PstPath,[StringComparison]::OrdinalIgnoreCase)){
            $target=$s;$targetMatches++
        }
    }
    if($targetMatches -ne 1 -or
       [string]$target.StoreID -cne [string]$manifest.TargetStoreId){
        throw 'BW4k7v2a8 exact original target PST no longer uniquely mounted.'
    }
    $root=$target.GetRootFolder()
    if([int]$root.Folders.Count -gt 128){throw 'BW4k7v2a8 target PST folder topology exceeds bounds.'}
    $targetFolder=$null;$folderMatches=0
    for($i=1;$i -le [int]$root.Folders.Count;$i++){
        $folder=$root.Folders.Item($i)
        if([string]$folder.Name -ceq [string]$layout.TargetFolderName){
            $folderMatches++;$targetFolder=$folder
        }
    }
    if($folderMatches -ne 1 -or
       [string]$targetFolder.EntryID -cne [string]$manifest.TargetFolderId -or
       [string]$targetFolder.StoreID -cne [string]$manifest.TargetStoreId){
        throw 'BW4k7v2a8 wrong exact destination folder.'
    }
    # Search ONLY exact synthetic Subject in known default Drafts and disposable PST folder.
    $sourceItems=$drafts.Items.Restrict(("[Subject] = '"+[string]$layout.Subject+"'"))
    $sourceCount=[int]$sourceItems.Count
    $destItems=$targetFolder.Items.Restrict(("[Subject] = '"+[string]$layout.Subject+"'"))
    $destCount=[int]$destItems.Count
    if($sourceCount -ne 0 -or $destCount -ne 1){
        throw 'BW4k7v2a8 original source=0 destination=1 no longer holds.'
    }
    $item=$ns.GetItemFromID($ExpectedDestinationEntryId,[string]$manifest.TargetStoreId)
    if([string]$item.EntryID -cne $ExpectedDestinationEntryId -or
       [string]$item.Parent.EntryID -cne [string]$manifest.TargetFolderId -or
       [string]$item.Parent.StoreID -cne [string]$manifest.TargetStoreId -or
       [string]$item.Subject -cne [string]$layout.Subject -or
       [int]$item.Class -ne 43){
        throw 'BW4k7v2a8 pinned exact destination EntryID/parent/subject mismatch.'
    }
    $snapshot=[pscustomobject]@{
        Class=[int]$item.Class;Subject=[string]$item.Subject
        Body=[string]$item.Body;To=[string]$item.To;Unread=[bool]$item.UnRead
    }
    $w=Get-OPA265BW4k7v2a7SemanticWitness -Snapshot $snapshot
    $semanticMatch=([string]$w.SemanticSha256 -ceq [string]$manifest.SemanticSha256)
    $flags=Get-OPA265BW4k7v2a8OptionalMapiProperty -Item $item -Tag '0x0E070003'
    if(-not $flags.Available){
        throw 'BW4k7v2a8 raw PR_MESSAGE_FLAGS unavailable; cannot attribute bit delta.'
    }
    $has=Get-OPA265BW4k7v2a8OptionalMapiProperty -Item $item -Tag '0x0E1B000B' -Kind Boolean
    $mapiSize=Get-OPA265BW4k7v2a8OptionalMapiProperty -Item $item -Tag '0x0E080003'
    $size=[long]$item.Size
    $count=0;$countRead=$false
    $entries=New-Object 'System.Collections.Generic.List[object]'
    try{
        $count=[int]$item.Attachments.Count
        if($count -lt 0 -or $count -gt 16){
            throw 'BW4k7v2a8 too many attachments for bounded diagnostic.'
        }
        for($i=1;$i -le $count;$i++){
            $attachment=$item.Attachments.Item($i)
            # Only metadata; never read filename, display name, content bytes, or save.
            $hidden=Get-OPA265BW4k7v2a8OptionalMapiProperty -Item $attachment -Tag '0x7FFE000B' -Kind Boolean
            $method=Get-OPA265BW4k7v2a8OptionalMapiProperty -Item $attachment -Tag '0x37050003'
            $attachFlags=Get-OPA265BW4k7v2a8OptionalMapiProperty -Item $attachment -Tag '0x37140003'
            $entries.Add([pscustomobject][ordered]@{
                Ordinal=$i
                Type=[int]$attachment.Type
                SizeBytes=[long]$attachment.Size
                Position=[int]$attachment.Position
                HiddenPropertyAvailable=[bool]$hidden.Available
                Hidden=if($hidden.Available){[bool]$hidden.Value}else{$null}
                AttachMethodAvailable=[bool]$method.Available
                AttachMethod=if($method.Available){[long]$method.Value}else{$null}
                AttachFlagsAvailable=[bool]$attachFlags.Available
                AttachFlags=if($attachFlags.Available){[long]$attachFlags.Value}else{$null}
                FileNameRead=$false;ContentBytesRead=$false
            })
        }
        $countRead=$true
    }catch{
        # A partial attachment inventory must not be presented as complete.
        $countRead=$false
    }
    $input=[pscustomobject][ordered]@{
        OutlookRestartConfirmed=$restarted
        SourceMatches=$sourceCount;DestinationMatches=$destCount
        DestinationIdentityMatchesPinned=$true
        SemanticSha256MatchesManifest=$semanticMatch
        DestinationRawMapiFlags=[long]$flags.Value
        DestinationSizeBytes=$size
        AttachmentCountReadComplete=$countRead
        DestinationAttachmentsCount=$count
        AttachmentSummaries=@($entries.ToArray())
        PrHasAttachAvailable=[bool]$has.Available
        PrHasAttach=if($has.Available){[bool]$has.Value}else{$null}
    }
    $decision=Test-OPA265BW4k7v2a8FlagsAndAttachments -Snapshot $input -Manifest $manifest -Claim $claim
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a8.LiveAttachmentForensicsReadOnly.1'
        Status=[string]$decision.Status
        SuiteId=$SuiteId
        OriginalManifestSha256=$ExpectedManifestSha256
        OriginalClaimSha256=$ExpectedClaimSha256
        OriginalMoveReturnSha256=$returnSha
        DestinationEntryId=$ExpectedDestinationEntryId
        SourceMatches=$sourceCount
        DestinationMatches=$destCount
        OutlookRestartConfirmed=$restarted
        DestinationSemanticMatchesOriginal=$semanticMatch
        PrMessageFlagsAvailable=[bool]$flags.Available
        PrHasAttachAvailable=[bool]$has.Available
        PrMessageSizeAvailable=[bool]$mapiSize.Available
        PrMessageSizeBytes=if($mapiSize.Available){[long]$mapiSize.Value}else{$null}
        MailItemSizeBytes=$size
        PrMessageSizeMatchesOutlookSize=if($mapiSize.Available){([long]$mapiSize.Value -eq $size)}else{$null}
        AttachmentCountReadComplete=$countRead
        AttachmentSummaries=@($entries.ToArray())
        Attribution=$decision
        RawBodyAttachmentContentFileNamesOrSignaturesReturned=$false
        OriginalTestPstOrMessagesModified=$false
        OriginalMoveRetried=$false
        WriterPermit=$false;ProductionReady=$false
    }
}finally{
    foreach($obj in @($ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}