#requires -Version 5.1
# BW4k7h: original Attachment1K POST-MOVE, read-only raw-flag vs user-field attribution.
# No Claim or PST writes, no Move, no source rebaseline and no production permissions.
[CmdletBinding()]
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
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [Parameter(Mandatory=$true)][string]$ExpectedDestinationFolderEntryId,
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7h STOP: Windows PowerShell 5.1 STA required.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7hPostMoveFlagAttribution265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$app=$null;$ns=$null;$stage='Pin original immutable source/Claim/destination identity'
try{
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       $ExpectedPlanSha256 -cne '6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63' -or
       $ExpectedFiveEvidenceSetSha256 -cne 'ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3' -or
       $ExpectedSourceEvidenceSha256 -cne '0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0' -or
       $ExpectedDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
       $ExpectedSemanticSnapshotSha256 -cne 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac' -or
       $ExpectedClaimSha256 -cne '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c' -or
       $ExpectedDestinationEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B24002000' -or
       $ExpectedDestinationFolderEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B82800000' -or
       $ExpectedProfileName -cne 'Outlook'){
        throw 'BW4k7h exact immutable source/claim/destination pins mismatch.'
    }
    $auditParams=@{
        SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        ExpectedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
        ExpectedDecisionSha256=$ExpectedDecisionSha256
        ExpectedSemanticSnapshotSha256=$ExpectedSemanticSnapshotSha256
        ExpectedClaimSha256=$ExpectedClaimSha256
        ExpectedDestinationEntryId=$ExpectedDestinationEntryId
        SourcePst=$SourcePst;DestinationPst=$DestinationPst
        ExpectedDestinationFolderEntryId=$ExpectedDestinationFolderEntryId
        ExpectedProfileName=$ExpectedProfileName
    }
    $stage='Repeat independent original BW4k7g postmove content, attachment, recipients audit'
    $audit=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7gPostMoveReadOnly.ps1') @auditParams
    if([string]$audit.Schema -cne '2.6.5-BW4k7g.IndependentPostMoveSemanticAudit.1' -or
       [string]$audit.Status -cne 'SourceZeroDestinationOneSemanticMismatchRequiresManualReview' -or
       [string]$audit.VerifiedOneShotClaimSha256 -cne $ExpectedClaimSha256 -or
       [string]$audit.VerifiedSourceSemanticSnapshotSha256 -cne $ExpectedSemanticSnapshotSha256 -or
       [int]$audit.SourceMessageIdMatches -ne 0 -or
       [int]$audit.DestinationMessageIdMatches -ne 1 -or
       [bool]$audit.FullUserStateSha256Matches -or
       -not [bool]$audit.FullRecipientSha256Matches -or
       -not [bool]$audit.SignificantReadAttachBitsMatch -or
       -not [bool]$audit.AttachmentBytesAndSha256Match -or
       -not [bool]$audit.SearchKeyAndInternetMessageIdentityMatches -or
       -not [bool]$audit.SubjectMatches -or
       -not [bool]$audit.SenderMatches -or
       -not [bool]$audit.BodyMatches -or
       -not [bool]$audit.HtmlBodyMatches -or
       -not [bool]$audit.ReceivedUtcTicksMatches -or
       [bool]$audit.WriterPermit -or [bool]$audit.ProductionReady){
        throw 'BW4k7h not the original exact recipient-matched user-state-only SHA discrepancy.'
    }
    $stage='Recheck static original BW4k7e immutable source user-state baseline'
    $sourcePath=Get-OPA265BW4k7eSnapshotPath -SuiteId $SuiteId -TestId $TestId
    if(-not [IO.File]::Exists($sourcePath) -or
       (([IO.File]::GetAttributes($sourcePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $sourcePath -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSemanticSnapshotSha256){
        throw 'BW4k7h original pre-Move recipient/state snapshot SHA changed.'
    }
    $original=Get-Content -LiteralPath $sourcePath -Encoding UTF8 -Raw | ConvertFrom-Json
    [void](Assert-OPA265BW4k7gOriginalStaticSnapshot -Record $original)
    $stage='Locate exact one archived MailItem in uniquely mounted PST'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'BW4k7h wrong Outlook profile.'
    }
    $dst=$null;$hits=0;$count=[int]$ns.Stores.Count
    if($count -lt 2 -or $count -gt 128){
        throw 'BW4k7h invalid Outlook store count.'
    }
    for($i=1;$i -le $count;$i++){
        $s=$ns.Stores.Item($i);$fp=''
        try{$fp=[string]$s.FilePath}catch{continue}
        if($fp -and [string]::Equals([IO.Path]::GetFullPath($fp),
            [IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
            $dst=$s;$hits++
        }
    }
    if($hits -ne 1 -or $null -eq $dst){
        throw 'BW4k7h archive PST not uniquely mounted.'
    }
    $folder=$ns.GetFolderFromID($ExpectedDestinationFolderEntryId,[string]$dst.StoreID)
    if([string]$folder.EntryID -cne $ExpectedDestinationFolderEntryId -or
       [string]$folder.StoreID -cne [string]$dst.StoreID -or
       [string]$folder.Name -cne 'OPA265-BW4j-87e72fd09e774098a403cbe99870b9e7' -or
       [int]$folder.Items.Count -ne 1){
        throw 'BW4k7h archived folder no longer has exact unique original mail.'
    }
    $mail=$ns.GetItemFromID($ExpectedDestinationEntryId,[string]$dst.StoreID)
    if($null -eq $mail -or [string]$mail.EntryID -cne $ExpectedDestinationEntryId -or
       [string]$mail.Parent.EntryID -cne $ExpectedDestinationFolderEntryId){
        throw 'BW4k7h archived MailItem EntryID or parent changed.'
    }
    $stage='Compute destination canonical SHA twice, replacing ONLY full raw MAPIFlags with original'
    $semArgs=@{
        Mail=$mail
        ExpectedEntryId=$ExpectedDestinationEntryId
        ExpectedFolderId=$ExpectedDestinationFolderEntryId
        ExpectedStoreId=[string]$dst.StoreID
    }
    $sem1=Get-OPA265BW4k7gDestinationSemantic @semArgs
    $state1=Get-OPA265BW4k7hStateFieldsReadOnly -Mail $mail
    $hashArgs=@{
        DestinationState=$state1
        DestinationFlags=[int]$sem1.MapiFlags
        OriginalFlags=[int]$original.MapiFlags
        OriginalUserStateSha256=[string]$original.UserStateDigestSha256
        ObservedDestinationUserStateSha256=[string]$sem1.UserStateDigestSha256
    }
    $a=Compare-OPA265BW4k7hRawFlagAttribution @hashArgs
    $sem2=Get-OPA265BW4k7gDestinationSemantic @semArgs
    [void](Assert-OPA265BW4k7gStableDestSemantics -First $sem1 -Second $sem2)
    $state2=Get-OPA265BW4k7hStateFieldsReadOnly -Mail $mail
    $hashArgs.DestinationState=$state2
    $hashArgs.DestinationFlags=[int]$sem2.MapiFlags
    $hashArgs.ObservedDestinationUserStateSha256=[string]$sem2.UserStateDigestSha256
    $b=Compare-OPA265BW4k7hRawFlagAttribution @hashArgs
    [void](Assert-OPA265BW4k7hStableAttribution -First $a -Second $b)
    if($b.DestinationUserStateSha256 -ceq $original.UserStateDigestSha256 -or
       -not $b.SignificantReadAttachBitsMatch){
        throw 'BW4k7h unexpected original mismatch or READ/HASATTACH flag changed.'
    }
    $stage='Final independent Claim/source snapshot/three historic Claim SHA fencing'
    $null=Read-OPA265BW4k7gClaimVerified -ExpectedClaimSha256 $ExpectedClaimSha256
    [void](Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId $SuiteId)
    if((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSemanticSnapshotSha256){
        throw 'BW4k7h original source snapshot changed during read-only attribution.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7h.IndependentPostMoveFlagAttribution.1'
        Status=[string]$b.Status
        SuiteId=$SuiteId;TestId=$TestId
        OriginalOneShotClaimSha256=$ExpectedClaimSha256
        OriginalRecipientStateSnapshotSha256=$ExpectedSemanticSnapshotSha256
        SourceMessageIdMatches=0;DestinationMessageIdMatches=1
        DestinationEntryId=$ExpectedDestinationEntryId
        OriginalMapiFlags=[int]$b.OriginalMapiFlags
        DestinationMapiFlags=[int]$b.DestinationMapiFlags
        OriginalMapiFlagsHex=[string]$b.OriginalMapiFlagsHex
        DestinationMapiFlagsHex=[string]$b.DestinationMapiFlagsHex
        ChangedMapiFlagsXor=[int]$b.ChangedMapiFlagsXor
        ChangedMapiFlagsXorHex=[string]$b.ChangedMapiFlagsXorHex
        ChangedFlagBitValues=@($b.ChangedFlagBitValues)
        SignificantReadAttachBitsMatch=[bool]$b.SignificantReadAttachBitsMatch
        DestinationUserStateSha256=[string]$b.DestinationUserStateSha256
        ReconstructedOriginalFlagsUserStateSha256=[string]$b.ReconstructedOriginalFlagsUserStateSha256
        OriginalUserStateSha256=[string]$b.OriginalUserStateSha256
        CapturedOutlookUserFieldsMatchExcludingRawMapiFlags=[bool]$b.CapturedOutlookUserFieldsMatchExcludingRawMapiFlags
        OnlyRawMapiFlagsChanged=[bool]$b.OnlyRawMapiFlagsChanged
        ChangedRawFlagBitsSemanticallyClassified=$false
        PriorObservedMismatchMayBeReclassifiedAutomatically=$false
        IndependentDestinationSemanticReads=2
        RawRecipientAddressesExposed=$false
        ExistingClaimRewritten=$false
        OriginalEvidenceRewritten=$false
        OutlookMoveExecuted=$false
        WriterPermit=$false;AutomaticRetryAllowed=$false;ProductionReady=$false
        NextAction='Stop;NeverRetryMove;ReviewChangedRawMapiFlagsBitsBeforeAnySemanticDecision'
    }
}catch{
    throw ('BW4k7h STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. Never retry MailItem.Move; only read-only investigation permitted.')
}finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
