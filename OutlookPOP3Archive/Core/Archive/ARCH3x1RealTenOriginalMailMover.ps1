#requires -Version 5.1
# ARCH3x1: ONE bounded real TEST PST batch of exactly ten original POP3 MailItems.
# Reuses original ARCH3w1 ten Intent/ARCH3v full witness, original Year
# folder/PST creator, original MailMover provider and ARCH3c durable records.
# NO Resume, NO automatic retry, NO Reconciled/Index before real postrestart verification.
. (Join-Path $PSScriptRoot 'ARCH3w1SemanticPart2Intents.ps1')
. (Join-Path $PSScriptRoot 'ARCH3xOriginalBatchTenFence.ps1')

function Get-OPA265ARCH3x1Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId)
    if($RunId -cne '093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'){
        throw 'ARCH3x1 requires the exact sealed ten-mail operator RunId.'
    }
    $base=Get-OPA265ARCH3iEvidenceLayout -RunId $RunId
    $root=Join-Path ([string]$base.LocalAppData) ('OPA265-ARCH3x1-'+$RunId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x1.Layout.1'
        Root=$root;RunId=$RunId
        WriterEntryPath=(Join-Path $root 'writer-entry.json')
    }
}

function Get-OPA265ARCH3x1PinnedPrepared {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SealSha256,
          [Parameter(Mandatory=$true)][string]$ManifestSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256)
    foreach($s in @($SealSha256,$ManifestSha256,$JournalSha256)){
        if($s -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH3x1 requires exact externally pinned SHA256 for ARCH3v/ARCH3w1 evidence.'}
    }
    $layout=Get-OPA265ARCH3w1Layout -RunId $RunId
    $review=Test-OPA265ARCH3w1PreparedReadback -Layout $layout -SealSha256 $SealSha256 -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256
    if([int]$review.PreparedIntentCount -ne 10 -or
       [int]$review.OriginalJournalEventCount -ne 10 -or
       [int]$review.TotalAttachmentCount -ne 12 -or
       -not [bool]$review.Part2OriginalArchiveVerifierProven -or
       [bool]$review.MoveClaimed -or [bool]$review.WriterPermit){
        throw 'ARCH3x1 prepared original ten Intent and historical Part2 proof are incomplete.'
    }
    $m=Read-OPA265ARCH3cPinnedJson -Path ([string]$layout.ManifestPath) -ExpectedSha256 $ManifestSha256
    $sealLayout=Get-OPA265ARCH3vEvidenceLayout -RunId $RunId
    $v=Read-OPA265ARCH3cPinnedJson -Path ([string]$sealLayout.WitnessPath) -ExpectedSha256 $SealSha256
    if([string]$m.SealSha256 -cne $SealSha256 -or
       [string]$m.RunId -cne $RunId -or
       [string]$m.SourcePst -cne [string]$v.SourcePst -or
       [int]$m.BatchSize -ne 10 -or @($m.Rows).Count -ne 10 -or
       @($v.Rows).Count -ne 10 -or
       [string]$m.TargetPstPreview -cne [string]$v.TargetPstPreview){
        throw 'ARCH3x1 original ARCH3v/ARCH3w1 ten source identity drift.'
    }
    return [pscustomobject]@{Manifest=$m;Seal=$v;Review=$review;Layout=$layout}
}

function Get-OPA265ARCH3x1RealPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Prepared,
          [Parameter(Mandatory=$true)][string]$ManifestSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256)
    $m=$Prepared.Manifest;$v=$Prepared.Seal
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst ([string]$m.SourcePst) -RequireExisting
    if([IO.File]::Exists([string]$m.TargetPstPreview) -or
       [IO.Directory]::Exists([string]$m.TargetPstPreview)){
        throw 'ARCH3x1 new Part3 already exists: no archive writer.'
    }
    $parts=@(Get-OPA265ARCH3w1OriginalYearParts -SourcePst $source)
    if($parts.Count -ne 2){throw 'ARCH3x1 original Year parts readback missing.'}
    for($i=0;$i -lt 2;$i++){
        if([int]$parts[$i].Part -ne ($i+1) -or
           [string]$parts[$i].Path -cne [string]$m.ExistingArchiveParts[$i].Path -or
           [string]$parts[$i].Sha256 -cne [string]$m.ExistingArchiveParts[$i].Sha256 -or
           [long]$parts[$i].LengthBytes -ne [long]$m.ExistingArchiveParts[$i].LengthBytes){
            throw 'ARCH3x1 original Part1 binary or Part2 full semantic proof changed.'
        }
    }
    $full=Get-OPA265ARCH3vFullReadOnlyAudit -RunId ([string]$m.RunId) -SourcePst $source -ExpectedPreviewSha256 ([string]$m.PreviewSha256) -ExpectedSourceStoreIdSha256 ([string]$m.SourceStoreIdSha256) -ExpectedOriginalIndexSha256 ([string]$m.OriginalIndexSha256) -ExpectedSourcePstLengthBytes ([long]$m.SourcePstLengthBytes)
    if([string]$full.AuditSha256 -cne [string]$m.AuditSha256 -or
       @($full._Envelope.Rows).Count -ne 10 -or [int]$full.TotalAttachmentCount -ne 12){
        throw 'ARCH3x1 original preflight source 10 full Body/HTML/attachment witnesses changed.'
    }
    $digestParts=New-Object 'System.Collections.Generic.List[string]'
    foreach($x in @('ARCH3x1 REAL TEN ORIGINAL PREFLIGHT', [string]$m.RunId,
        $ManifestSha256,$JournalSha256,[string]$m.SealSha256,[string]$full.AuditSha256,
        [string]$m.OriginalIndexSha256,[string]$m.SourceStoreIdSha256,
        [string]$m.SourcePstLengthBytes,[string]$m.TargetPstPreview,
        [string]$parts[0].Sha256,[string]$parts[0].LengthBytes,
        [string]$parts[1].Sha256,[string]$parts[1].LengthBytes)){
        [void]$digestParts.Add($x)
    }
    for($i=0;$i -lt 10;$i++){
        $row=$full._Envelope.Rows[$i];$saved=$v.Rows[$i];$intent=$m.Rows[$i]
        if([int]$row.Ordinal -ne ($i+1) -or
           [string]$row.SourceEntryId -cne [string]$saved.SourceEntryId -or
           [string]$row.FullOriginalWitnessSha256 -cne [string]$saved.FullOriginalWitnessSha256 -or
           [string]$row.FullOriginalWitnessSha256 -cne [string]$intent.FullOriginalWitnessSha256 -or
           [string]$row.OriginalOperationId -cne [string]$intent.OriginalOperationId -or
           [string]$row.OriginalContractSha256 -cne [string]$intent.OriginalContractSha256 -or
           [string]$row.TargetFolderPath -cne '2020\Входящие' -or
           [int]$row.AttachmentCount -ne [int]$intent.AttachmentCount){
            throw ('ARCH3x1 full original preflight row drift at ordinal '+($i+1))
        }
        foreach($x in @([string]$row.Ordinal,[string]$row.SourceEntryId,[string]$row.OriginalOperationId,
            [string]$row.FullOriginalWitnessSha256,[string]$row.OriginalContractSha256)){
            [void]$digestParts.Add($x)
        }
    }
    if((Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst $source).OriginalIndexSha256 -cne [string]$m.OriginalIndexSha256 -or
       [long]([IO.FileInfo]::new($source)).Length -ne [long]$m.SourcePstLengthBytes -or
       [IO.File]::Exists([string]$m.TargetPstPreview)){
        throw 'ARCH3x1 original shared index, source PST or Part3 changed while preflighting.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x1.RealPreflight.1'
        Status='TenOriginalRealSourceFullWitnessAndHistoricalYearPartsReadOnlyReady'
        RunId=[string]$m.RunId
        PreflightDigest=(Get-OPA265ARCH3bDigest -Parts @($digestParts.ToArray()))
        TargetPst=[string]$m.TargetPstPreview
        OriginalArchivePart=3;OriginalArchiveYear=2020
        OriginalFullWitnessCount=10;OriginalAttachmentCount=12
        OriginalArchiveVerifierPart2Passed=$true
        OriginalSharedIndexSha256=[string]$m.OriginalIndexSha256
        OriginalJournalIntents=10
        RealMailMovePerformed=$false;ArchivePstCreated=$false
        WriterPermit=$false;ProductionReady=$false;AutomaticMoveRetryAllowed=$false
    }
}

function Get-OPA265ARCH3x1ReadOnlyStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout)
    if(-not [IO.Directory]::Exists([string]$Layout.Root)){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x1.ReadOnlyStatus.1';Status='NoRealTenWriterEntry'
            RunId=[string]$Layout.RunId
            WriterEntryPresent=$false;Claims=0;Invocations=0;MoveReturns=0
            AutomaticMoveRetryAllowed=$false;ProductionReady=$false;WriterPermit=$false
        }
    }
    if((([IO.File]::GetAttributes([string]$Layout.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3x1 writer evidence redirected: STOP.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$Layout.Root))
    $names=@([IO.Directory]::GetFileSystemEntries([string]$Layout.Root) | ForEach-Object {[IO.Path]::GetFileName($_)})
    foreach($n in $names){
        if($n -cne 'writer-entry.json' -and
           $n -cnotmatch '^(0[1-9]|10)-(claim|invocation|returned)\.json$'){
            throw 'ARCH3x1 unexpected or nested file in writer evidence: manual review.'
        }
    }
    $present=[IO.File]::Exists([string]$Layout.WriterEntryPath)
    if(-not $present){throw 'ARCH3x1 writer directory exists without entry: unknown and no retry.'}
    $c=0;$v=0;$r=0;$firstUnfinished=0
    $writerSha=(Get-FileHash -LiteralPath $Layout.WriterEntryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $writer=Read-OPA265ARCH3cPinnedJson -Path $Layout.WriterEntryPath -ExpectedSha256 $writerSha
    if([string]$writer.Schema -cne '2.6.5-ARCH3x1.RealTenWriterEntry.1' -or
       [string]$writer.RunId -cne [string]$Layout.RunId -or
       [bool]$writer.ProductionReady){throw 'ARCH3x1 writer evidence is invalid.'}
    for($i=1;$i -le 10;$i++){
        $stem=('{0:00}' -f $i)
        $cf=Join-Path $Layout.Root ($stem+'-claim.json')
        $vf=Join-Path $Layout.Root ($stem+'-invocation.json')
        $rf=Join-Path $Layout.Root ($stem+'-returned.json')
        $hasC=[IO.File]::Exists($cf);$hasV=[IO.File]::Exists($vf);$hasR=[IO.File]::Exists($rf)
        if(($hasV -and -not $hasC) -or ($hasR -and -not $hasV) -or
           ($firstUnfinished -gt 0 -and ($hasC -or $hasV -or $hasR))){
            throw 'ARCH3x1 noncontiguous/invalid real Move evidence; MANUAL REVIEW.'
        }
        if($hasC){
            $cobj=Read-OPA265ARCH3cPinnedJson -Path $cf -ExpectedSha256 (Get-FileHash -LiteralPath $cf -Algorithm SHA256).Hash.ToLowerInvariant()
            if([string]$cobj.Schema -cne '2.6.5-ARCH3x1.RealTenMoveClaim.1' -or
               [int]$cobj.Ordinal -ne $i -or [string]$cobj.WriterEntrySha256 -cne $writerSha -or
               -not [bool]$cobj.OperatorApprovedTenRealMoves){throw 'ARCH3x1 claim invalid.'}
            $c++
        }
        if($hasV){
            $vobj=Read-OPA265ARCH3cPinnedJson -Path $vf -ExpectedSha256 (Get-FileHash -LiteralPath $vf -Algorithm SHA256).Hash.ToLowerInvariant()
            if([string]$vobj.Schema -cne '2.6.5-ARCH3x1.RealTenProviderInvocation.1' -or
               [int]$vobj.Ordinal -ne $i -or
               [string]$vobj.ClaimSha256 -cne (Get-FileHash -LiteralPath $cf -Algorithm SHA256).Hash.ToLowerInvariant()){
                throw 'ARCH3x1 invocation/claim SHA chain invalid.'
            }
            $v++
        }
        if($hasR){
            $robj=Read-OPA265ARCH3cPinnedJson -Path $rf -ExpectedSha256 (Get-FileHash -LiteralPath $rf -Algorithm SHA256).Hash.ToLowerInvariant()
            if([string]$robj.Schema -cne '2.6.5-ARCH3x1.RealTenMoveReturned.1' -or
               [int]$robj.Ordinal -ne $i -or
               [string]$robj.ClaimSha256 -cne [string]$vobj.ClaimSha256 -or
               [string]$robj.ProviderInvocationSha256 -cne (Get-FileHash -LiteralPath $vf -Algorithm SHA256).Hash.ToLowerInvariant() -or
               [string]$robj.ArchiveEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$'){
                throw 'ARCH3x1 real returned receipt SHA chain invalid.'
            }
            $r++
        }
        if($firstUnfinished -eq 0 -and (-not $hasC -or -not $hasV -or -not $hasR)){
            $firstUnfinished=$i
        }
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x1.ReadOnlyStatus.1'
        Status=if($r -eq 10){'TenOriginalComMovesReturnedIndependentRestartRequired'}else{'PartialOrUnknownRealTenWriterManualReviewNoReplay'}
        RunId=[string]$Layout.RunId;WriterEntryPresent=$true
        WriterEntrySha256=$writerSha;Claims=$c;Invocations=$v;MoveReturns=$r
        FirstUnfinishedOrdinal=$firstUnfinished
        IndependentPostRestartVerified=$false
        OriginalSharedIndexWritten=$false;OriginalJournalReconciled=$false
        AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3x1RealTen {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Move','Status')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [string]$SealSha256='',
        [string]$ManifestSha256='',
        [string]$JournalSha256='',
        [string]$ExpectedPreflightDigest='',
        [switch]$ConfirmTenRealMoves
    )
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3x1 requires native Windows PowerShell 5.1.'
    }
    $layout=Get-OPA265ARCH3x1Layout -RunId $RunId
    if($Mode -ceq 'Status'){
        if($SealSha256 -or $ManifestSha256 -or $JournalSha256 -or
           $ExpectedPreflightDigest -or $ConfirmTenRealMoves){
            throw 'ARCH3x1 Status is disk-only and accepts RunId only.'
        }
        return (Get-OPA265ARCH3x1ReadOnlyStatus -Layout $layout)
    }
    if($ConfirmTenRealMoves -and $Mode -cne 'Move'){
        throw 'ARCH3x1 explicit operator authorization accepted only for Move.'
    }
    if($ExpectedPreflightDigest -and $Mode -cne 'Move'){
        throw 'ARCH3x1 external PreflightDigest accepted only for Move.'
    }
    $p=Get-OPA265ARCH3x1PinnedPrepared -RunId $RunId -SealSha256 $SealSha256 -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256
    if([IO.Directory]::Exists([string]$layout.Root) -or [IO.File]::Exists([string]$layout.Root)){
        throw 'ARCH3x1 live writer was entered previously. Use Status, NEVER REPLAY.'
    }
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x1.Plan.1'
            Status='TenProtectedOriginalIntentsAndOriginalYearPart3PlannedNoOutlookNoWrites'
            RunId=$RunId;SourcePst=[string]$p.Manifest.SourcePst
            TargetPst=[string]$p.Manifest.TargetPstPreview
            PreparedIntentCount=10
            RealOutlookContacted=$false;ArchivePstCreated=$false;RealMailMovePerformed=$false
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3x1 real Outlook Audit/Move requires Windows PowerShell 5.1 STA.'
    }
    if($Mode -ceq 'Move'){
        if(-not $ConfirmTenRealMoves -or $ExpectedPreflightDigest -cnotmatch '^[a-f0-9]{64}$'){
            throw 'ARCH3x1 real Move requires explicit -ConfirmTenRealMoves and SHA from current Audit.'
        }
        if(-not $PSCmdlet.ShouldProcess([string]$p.Manifest.TargetPstPreview,
            'Perform one irreversible TEST POP3 batch of TEN original Outlook COM Moves, NO retry')){
            return [pscustomobject]@{
                Schema='2.6.5-ARCH3x1.WhatIf.1';Status='WhatIfBeforeRealOutlookPstOrWriterWrites'
                RealOutlookContacted=$false;WriterPermit=$false;ProductionReady=$false
            }
        }
    }
    $audit=Get-OPA265ARCH3x1RealPreflight -Prepared $p -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256
    if($Mode -ceq 'Audit'){return $audit}
    if([string]$audit.PreflightDigest -cne $ExpectedPreflightDigest){
        throw 'ARCH3x1 original preflight digest changed: no live writer.'
    }
    $m=$p.Manifest;$v=$p.Seal
    $session=$null;$archive=$null;$folder=$null;$first=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout (Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA) -SourcePst ([string]$m.SourcePst)
        if(-not [bool]$session.Scope.Approved -or
           [string]$session.Namespace.CurrentProfileName -cne 'Outlook' -or
           (Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne [string]$m.SourceStoreIdSha256 -or
           [string]$session.Inbox.FolderPath -cne '\\info@stios.ru\Входящие'){
            throw 'ARCH3x1 exact original POP3/Outlook/Inbox scope changed.'
        }
        if((Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst ([string]$m.SourcePst)).OriginalIndexSha256 -cne [string]$m.OriginalIndexSha256 -or
           [long]([IO.FileInfo]::new([string]$m.SourcePst)).Length -ne [long]$m.SourcePstLengthBytes -or
           [IO.File]::Exists([string]$m.TargetPstPreview) -or
           $null -ne (Get-OpaStoreByPathCached -Namespace $session.Namespace -Path ([string]$m.TargetPstPreview))){
            throw 'ARCH3x1 original index/source Part3 changed before protected writer entry.'
        }
        $writer=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x1.RealTenWriterEntry.1'
            RunId=$RunId
            PreparedManifestSha256=$ManifestSha256;PreparedJournalSha256=$JournalSha256
            SealSha256=$SealSha256
            PreflightDigest=$ExpectedPreflightDigest
            SourcePst=[string]$m.SourcePst;TargetPst=[string]$m.TargetPstPreview
            SourceStoreIdSha256=[string]$m.SourceStoreIdSha256
            SourceFolderEntryId=[string]$session.Inbox.EntryID
            OriginalSharedIndexSha256=[string]$m.OriginalIndexSha256
            OutlookProcessId=[int]$session.OutlookProcessId
            OutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            BatchSize=10;OperatorApprovedTenRealMoves=$true
            IndependentPostRestartVerified=$false
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        # NO RETRY marker before touching the NEW target PST; protected DACL
        # and the original CreateNew/Flush(true) writer are mandatory.
        New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout
        $writerSha=Write-OPA265ARCH3cJsonOnce -Path ([string]$layout.WriterEntryPath) -Record $writer
        $archive=New-OPAArchivePst -Namespace $session.Namespace -ArchivePst ([string]$m.TargetPstPreview) -AccountEmail 'info@stios.ru' -ARCH3oRequireNewUnusedPst
        if($null -eq $archive -or
           -not [string]::Equals([IO.Path]::GetFullPath([string]$archive.FilePath),[IO.Path]::GetFullPath([string]$m.TargetPstPreview),[StringComparison]::OrdinalIgnoreCase) -or
           [string]$archive.StoreID -ceq [string]$session.SourceStore.StoreID -or
           [string]$archive.StoreID -ceq [string]$session.DefaultStoreId -or
           -not [IO.File]::Exists([string]$m.TargetPstPreview)){
            throw 'ARCH3x1 original unused Part3 creation returned unexpected store; NO RETRY.'
        }
        foreach($a in @($session.Accounts)){
            if([string]$a.DeliveryStoreId -ceq [string]$archive.StoreID){
                throw 'ARCH3x1 new archive Part3 is an account delivery store. STOP.'
            }
        }
        $first=$session.Namespace.GetItemFromID([string]$m.Rows[0].SourceEntryId,[string]$session.SourceStore.StoreID)
        if($null -eq $first -or [int]$first.Class -ne 43){throw 'ARCH3x1 first exact MailItem missing after Part3 allocation.'}
        $date=Get-OPAArchiveItemDate -Item $first
        if($null -eq $date -or ([datetime]$date).Ticks -ne [long]$v.Rows[0].ArchiveDateLocalTicks){
            throw 'ARCH3x1 first original archive date changed after new PST creation.'
        }
        $folder=Get-OPAArchiveFolder -ArchiveStore $archive -SourceFolderName ([string]$session.Inbox.Name) -SourceFolderPath ([string]$session.Inbox.FolderPath) -ReceivedTime ([datetime]$date) -Grouping Year
        if($null -eq $folder -or [string]$folder.StoreID -cne [string]$archive.StoreID -or
           -not ([string]$folder.FolderPath).EndsWith('\2020\Входящие',[StringComparison]::OrdinalIgnoreCase) -or
           [int]$folder.Items.Count -ne 0){
            throw 'ARCH3x1 original Year2020 Inbox Part3 target must be new and empty.'
        }
        Release-OPA265ARCH2c4Com -Object $first
        $first=$null
        $previousReceiptSha=''
        $resultRows=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le 10;$i++){
            $row=$m.Rows[$i-1];$saved=$v.Rows[$i-1]
            $mail=$null;$parent=$null
            try{
                if([int]$folder.Items.Count -ne ($i-1) -or
                   (Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst ([string]$m.SourcePst)).OriginalIndexSha256 -cne [string]$m.OriginalIndexSha256){
                    throw ('ARCH3x1 original destination count or shared index changed at item '+$i)
                }
                $mail=$session.Namespace.GetItemFromID([string]$row.SourceEntryId,[string]$session.SourceStore.StoreID)
                if($null -eq $mail -or [int]$mail.Class -ne 43 -or
                   [string]$mail.EntryID -cne [string]$row.SourceEntryId){
                    throw ('ARCH3x1 exact original Inbox message missing at ordinal '+$i)
                }
                $parent=$mail.Parent
                $date=Get-OPAArchiveItemDate -Item $mail
                if($null -eq $parent -or [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
                   [string]$parent.StoreID -cne [string]$session.SourceStore.StoreID -or
                   [string]$parent.FolderPath -cne '\\info@stios.ru\Входящие' -or
                   $null -eq $date -or ([datetime]$date).Ticks -ne [long]$saved.ArchiveDateLocalTicks){
                    throw ('ARCH3x1 original source parent/date drift at ordinal '+$i)
                }
                $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
                [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $w -ExpectedOriginalWitnessSha256 ([string]$row.FullOriginalWitnessSha256))
                if([int]$w.AttachmentCount -ne [int]$row.AttachmentCount -or
                   [string]$w.SubjectSha256 -cne [string]$saved.SubjectSha256){
                    throw ('ARCH3x1 actual attachments/subject drift at ordinal '+$i)
                }
                $claim=[pscustomobject][ordered]@{
                    Schema='2.6.5-ARCH3x1.RealTenMoveClaim.1'
                    RunId=$RunId;Ordinal=$i
                    WriterEntrySha256=$writerSha
                    PreparedManifestSha256=$ManifestSha256;PreparedJournalSha256=$JournalSha256
                    SourceEntryId=[string]$row.SourceEntryId
                    OriginalOperationId=[string]$row.OriginalOperationId
                    OriginalContractSha256=[string]$row.OriginalContractSha256
                    FullOriginalWitnessSha256=[string]$row.FullOriginalWitnessSha256
                    SourceStoreIdSha256=[string]$m.SourceStoreIdSha256
                    TargetPst=[string]$m.TargetPstPreview
                    DestinationStoreId=[string]$archive.StoreID
                    DestinationFolderEntryId=[string]$folder.EntryID
                    PreviousMoveReceiptSha256=$previousReceiptSha
                    OperatorApprovedTenRealMoves=$true
                    AutomaticRetryAllowed=$false;ProductionReady=$false
                }
                $prefix=('{0:00}' -f $i)
                $claimSha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $layout.Root ($prefix+'-claim.json')) -Record $claim
                $result=Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall -Mail $mail -Folder $folder -RunId $RunId -Ordinal $i -ClaimSha256 $claimSha
                if(-not [bool]$result.OneMoveReturned -or
                   [string]$result.DestinationEntryId -cnotmatch '^[a-fA-F0-9]{16,1024}$'){
                    throw 'ARCH3x1 COM Move outcome UNKNOWN; no retry.'
                }
                $receipt=[pscustomobject][ordered]@{
                    Schema='2.6.5-ARCH3x1.RealTenMoveReturned.1'
                    RunId=$RunId;Ordinal=$i
                    ClaimSha256=$claimSha
                    ProviderInvocationSha256=[string]$result.ProviderInvocationSha256
                    SourceEntryId=[string]$row.SourceEntryId
                    ArchiveEntryId=[string]$result.DestinationEntryId
                    FullOriginalWitnessSha256=[string]$row.FullOriginalWitnessSha256
                    PreviousMoveReceiptSha256=$previousReceiptSha
                    DestinationStoreId=[string]$archive.StoreID
                    DestinationFolderEntryId=[string]$folder.EntryID
                    IndependentPostRestartVerified=$false
                    OriginalJournalReconciled=$false;OriginalDuplicateIndexWritten=$false
                    AutomaticRetryAllowed=$false;ProductionReady=$false
                }
                $previousReceiptSha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $layout.Root ($prefix+'-returned.json')) -Record $receipt
                [void]$resultRows.Add([pscustomobject]@{Ordinal=$i;SourceEntryId=[string]$row.SourceEntryId;ArchiveEntryId=[string]$result.DestinationEntryId;ReceiptSha256=$previousReceiptSha})
            }finally{
                Release-OPA265ARCH2c4Com -Object $parent
                Release-OPA265ARCH2c4Com -Object $mail
            }
        }
        $status=Get-OPA265ARCH3x1ReadOnlyStatus -Layout $layout
        if([int]$status.MoveReturns -ne 10 -or [int]$status.Invocations -ne 10 -or [int]$status.Claims -ne 10){
            throw 'ARCH3x1 ten COM returns not independently durable on disk; no retry.'
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x1.LiveTenReturned.1'
            Status='TenOriginalRealPop3ComMovesReturnedIndependentOutlookRestartRequired'
            RunId=$RunId;OriginalTenMoved=10
            TargetPst=[string]$m.TargetPstPreview
            OutlookProcessId=[int]$session.OutlookProcessId
            OutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            WriterEntrySha256=$writerSha;LastMoveReceiptSha256=$previousReceiptSha
            Rows=@($resultRows.ToArray())
            IndependentPostRestartVerified=$false
            OriginalJournalReconciled=$false;OriginalDuplicateIndexWritten=$false
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $first
        Release-OPA265ARCH2c4Com -Object $folder
        Release-OPA265ARCH2c4Com -Object $archive
        Close-OPA265ARCH2dSession -Session $session
    }
}
