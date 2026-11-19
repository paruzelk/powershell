#requires -Version 5.1
# ARCH3u: operator-designated REAL TEST POP3 PST, exactly-ten READ-ONLY preview.
# Reuse original ARCH2d POP3 session, ArchiveSelector, ARCH3b original
# MailMover/ArchiveGrouping contract and original DuplicateIndex importer.
# NO Move, AddStoreEx, witness/intent/claim/operation journal or PST writes.
. (Join-Path $PSScriptRoot 'ARCH3jRealOneShotPrepareIntent.ps1')
. (Join-Path $PSScriptRoot 'ARCH3gExistingArchiveCollisionGate.ps1')

function Get-OPA265ARCH3uSharedIndexReadOnly {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst)
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst
    $dir=Join-Path ([IO.Path]::GetDirectoryName($source)) 'OutlookPOP3Archive-Transactions'
    $jsonl=Join-Path $dir 'DuplicateIndex.jsonl'
    $legacy=Join-Path $dir 'DuplicateIndex.json'
    if(-not [IO.Directory]::Exists($dir) -or -not [IO.File]::Exists($jsonl) -or
       (([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3u original shared DuplicateIndex directory/JSONL absent or unsafe. STOP.'
    }
    foreach($p in @($jsonl,$legacy)){
        if([IO.File]::Exists($p) -and
           (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3u shared index contains reparse/link file. STOP.'
        }
    }
    # Original importer is intentionally last-wins, therefore first reject
    # duplicate source selectors, malformed rows and unfinished JSONL tail.
    $bytes=[IO.File]::ReadAllBytes($jsonl)
    if($bytes.Length -lt 2 -or $bytes[$bytes.Length-1] -ne 10){
        throw 'ARCH3u original shared DuplicateIndex JSONL empty or torn. STOP.'
    }
    $rawIds=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $count=0
    foreach($line in [IO.File]::ReadAllLines($jsonl)){
        if([string]::IsNullOrWhiteSpace($line)){throw 'ARCH3u shared index contains blank JSONL entry.'}
        $item=ConvertFrom-Json -InputObject $line -ErrorAction Stop
        $id=[string]$item.SourceEntryId
        if($id -cnotmatch '^[a-fA-F0-9]{16,1024}$' -or -not $rawIds.Add($id)){
            throw 'ARCH3u shared index contains malformed or duplicate SourceEntryId. STOP.'
        }
        $count++
        if($count -gt 1000000){throw 'ARCH3u shared index exceeds read-only bound.'}
    }
    $archive=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 1
    $index=Import-OPADuplicateIndex -ArchivePst $archive
    if(@($index.Entries).Count -lt $count){
        throw 'ARCH3u original importer lost a raw JSONL row. STOP.'
    }
    return [pscustomobject][ordered]@{
        Index=$index
        OriginalIndexSha256=(Get-FileHash -LiteralPath $jsonl -Algorithm SHA256).Hash.ToLowerInvariant()
        LegacyBaseSha256=if([IO.File]::Exists($legacy)){(Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash.ToLowerInvariant()}else{''}
        IndexPath=$jsonl
        LegacyBasePath=$legacy
        OriginalIndexEntryCount=[int]@($index.Entries).Count
        RawIndexRowCount=$count
    }
}

function New-OPA265ARCH3uTenPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$SourceStoreId,
        [Parameter(Mandatory=$true)][string]$InboxEntryId,
        [Parameter(Mandatory=$true)][string]$InboxPath,
        [Parameter(Mandatory=$true)][string]$InboxName,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Candidates,
        [AllowEmptyCollection()][string[]]$IndexedSourceEntryIds=@(),
        [AllowEmptyCollection()][object[]]$ExistingParts=@(),
        [Parameter(Mandatory=$true)][string]$OriginalIndexSha256
    )
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst
    $g=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$g) -or $g -eq [guid]::Empty -or
       $g.ToString('D') -cne $RunId -or
       $InboxEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
       [string]::IsNullOrWhiteSpace($SourceStoreId) -or $SourceStoreId.Length -gt 2048 -or
       [string]::IsNullOrWhiteSpace($InboxName) -or
       -not $InboxPath.StartsWith('\\') -or
       $OriginalIndexSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3u canonical RunId/Inbox/Store/Index SHA required.'
    }
    if(@($Candidates).Count -lt 10 -or @($Candidates).Count -gt 128){
        throw 'ARCH3u needs 10..128 source selector candidates; no partial batch.'
    }
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $indexed=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($id in @($IndexedSourceEntryIds)){
        if($id -cnotmatch '^[0-9a-fA-F]{16,1024}$'){throw 'ARCH3u malformed original indexed SourceEntryId.'}
        [void]$indexed.Add($id)
    }
    $available=New-Object 'System.Collections.Generic.List[object]'
    $excluded=0
    foreach($c in $Candidates){
        if($null -eq $c){throw 'ARCH3u null selector candidate.'}
        $id=[string]$c.EntryID
        $date=[datetime]$c.ArchiveDate
        if($id -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or -not $ids.Add($id) -or
           [string]$c.SourceFolderPath -cne $InboxPath -or
           [string]$c.FolderName -cne $InboxName -or
           $date.Year -lt 1900 -or $date.Year -gt 2100){
            throw 'ARCH3u selector candidate duplicate, not original Inbox, or invalid date.'
        }
        if($indexed.Contains($id)){$excluded++;continue}
        [void]$available.Add($c)
    }
    $ordered=@($available.ToArray() | Sort-Object ArchiveDate,EntryID)
    $year=0;$chosen=@()
    foreach($group in @($ordered | Group-Object {([datetime]$_.ArchiveDate).Year})){
        if(@($group.Group).Count -ge 10){
            $year=[int]$group.Name
            $chosen=@($group.Group | Select-Object -First 10)
            break
        }
    }
    if($chosen.Count -ne 10){throw 'ARCH3u cannot find exactly ten unindexed messages from ONE year within bounded Inbox sample.'}
    $yearParts=@($ExistingParts | Where-Object {[int]$_.Year -eq $year})
    $partPlan=Get-OPA265ARCH3gPartPlan -SourcePst $source -ArchiveYear $year -SourceEntryId ([string]$chosen[0].EntryID) -ExistingParts $yearParts
    $part=1
    if($yearParts.Count -gt 0){$part=[int](($yearParts | Measure-Object -Property Part -Maximum).Maximum)+1}
    if($part -gt 99 -or [IO.File]::Exists([string]$partPlan.NextUnusedPartPathPreview) -or
       [IO.Directory]::Exists([string]$partPlan.NextUnusedPartPathPreview)){
        throw 'ARCH3u next annual archive part already exists or exceeds bound. STOP.'
    }
    $contract=New-OPA265ARCH3bBatchPreview -Candidates $chosen -TransactionId ('ARCH3u-'+$RunId) -SourcePst $source -SourceStoreId $SourceStoreId -ArchiveGrouping Year -ArchivePart $part
    if([int]$contract.PlannedItems -ne 10){throw 'ARCH3u original MailMover batch contract not exactly ten.'}
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $digestParts=New-Object 'System.Collections.Generic.List[object]'
    foreach($x in @($contract.Items)){
        # ARCH3b contract contains ArchiveDateUtc, NOT ArchiveDate.
        # Keep the original selector's local DateTime for exact Outlook COM
        # recheck, but prove it is the date hashed in the original contract.
        $sourceRow=@($chosen | Where-Object {[string]$_.EntryID -ceq [string]$x.SourceEntryId})
        if($sourceRow.Count -ne 1){throw 'ARCH3u original contract has no unique source selector row.'}
        $selectedDate=[datetime]$sourceRow[0].ArchiveDate
        $dateUtc=$selectedDate.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
        if([string]$x.ArchiveDateUtc -cne $dateUtc){
            throw 'ARCH3u original ArchiveDateUtc contract drift from selector DateTime.'
        }
        if([int]$x.ArchiveYear -ne $year -or
           [string]$x.PlannedArchivePst -cne [string]$partPlan.NextUnusedPartPathPreview -or
           [string]$x.SourceFolderPath -cne $InboxPath -or
           $indexed.Contains([string]$x.SourceEntryId)){
            throw 'ARCH3u original routing/duplicate index invariant failed. STOP.'
        }
        [void]$digestParts.Add([string]$x.ContractSha256)
        [void]$rows.Add([pscustomobject][ordered]@{
            SourceEntryId=[string]$x.SourceEntryId
            SourceFolderPath=[string]$x.SourceFolderPath
            ArchiveYear=[int]$x.ArchiveYear
            ArchiveDate=$selectedDate
            OriginalOperationId=[string]$x.OperationId
            OriginalContractSha256=[string]$x.ContractSha256
            TargetFolderPath=[string]$x.PlannedTargetFolderPath
            TargetPstPreview=[string]$x.PlannedArchivePst
        })
    }
    $all=@('2.6.5-ARCH3u.RealBatchTenPreview.1',$RunId,$source,$SourceStoreId,$InboxEntryId,$InboxPath,$OriginalIndexSha256,[string]$year,[string]$part)
    $all+=@($digestParts.ToArray())
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3u.RealBatchTenPreview.1'
        Status='TenOriginalInboxCandidatesAndNextUnusedYearPartReadOnlyNoMove'
        RunId=$RunId
        SourcePst=$source
        InboxEntryId=$InboxEntryId
        SourceStoreIdSha256=(Get-OPA265ARCH2bTextSha256 -Text $SourceStoreId)
        BatchSize=10
        SampleCandidateCount=@($Candidates).Count
        SampleAlreadyIndexedCount=$excluded
        SelectedYear=$year
        SelectedArchivePart=$part
        TargetPstPreview=[string]$partPlan.NextUnusedPartPathPreview
        ExistingYearPartCount=[int]$partPlan.ExistingPartCount
        OriginalIndexSha256=$OriginalIndexSha256
        PreviewSha256=(Get-OPA265ARCH3bDigest -Parts $all)
        OriginalMailMoverContractsUsed=$true
        OriginalYearRoutingUsed=$true
        OriginalDuplicateIndexConsulted=$true
        Rows=@($rows.ToArray())
        FullOriginalSemanticWitnessesCaptured=$false
        OriginalOperationJournalWritten=$false
        OriginalDuplicateIndexWritten=$false
        ArchivePstCreated=$false
        RealMailMovePerformed=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3uRealBatchTenPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Inventory')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$SourcePst
    )
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting:($Mode -ceq 'Inventory')
    $guid=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$guid) -or $guid -eq [guid]::Empty -or $guid.ToString('D') -cne $RunId){
        throw 'ARCH3u requires a canonical lowercase GUID RunId.'
    }
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3u.Plan.1'
            Status='RealTestPstOriginalTenReadOnlyPreflightPlannedNoOutlook'
            RunId=$RunId;SourcePst=$source;BatchSize=10
            OutlookContacted=$false;SourcePstOpened=$false
            NoPstOrJournalWrites=$true;RealMailMovePerformed=$false
            AutomaticMoveRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
       [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3u Inventory requires Windows PowerShell 5.1 -STA.'
    }
    $layout=Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
    $session=$null
    try {
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $source
        if(-not [bool]$session.Scope.Approved -or [string]$session.Namespace.CurrentProfileName -cne 'Outlook'){
            throw 'ARCH3u only approved Outlook profile POP3 test PST permitted.'
        }
        $index=Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst $source
        $itemsCount=[int]$session.Inbox.Items.Count
        if($itemsCount -lt 10 -or $itemsCount -gt 500000){throw 'ARCH3u Inbox item count outside bounded range.'}
        $diag=Get-OPAArchiveCandidates -SourceFolder $session.Inbox -Limit 128 -Diagnostics
        if([int]$diag.SelectionErrors -gt 0 -or -not [bool]$diag.UsedSort -or @($diag.Candidates).Count -lt 10){
            throw 'ARCH3u original Inbox selector errors, no chronological sort, or fewer than 10 candidates.'
        }
        # Inspect disk afresh; no archive part creation, mounting or reservation.
        Clear-OPAArchivePartCache -SourcePst $source
        $existing=@(Get-OPAArchivePstPartsOnDiskAll -SourcePst $source)
        foreach($p in $existing){
            if(-not [IO.File]::Exists([string]$p.Path) -or
               (([IO.File]::GetAttributes([string]$p.Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
                throw 'ARCH3u original annual archive part missing or reparse point.'
            }
        }
        $preview=New-OPA265ARCH3uTenPreview -RunId $RunId -SourcePst $source -SourceStoreId ([string]$session.SourceStore.StoreID) -InboxEntryId ([string]$session.Inbox.EntryID) -InboxPath ([string]$session.Inbox.FolderPath) -InboxName ([string]$session.Inbox.Name) -Candidates @($diag.Candidates) -IndexedSourceEntryIds @($index.Index.Entries | ForEach-Object {[string]$_.SourceEntryId}) -ExistingParts $existing -OriginalIndexSha256 ([string]$index.OriginalIndexSha256)
        # Reopen each exact selected original Inbox MailItem: avoid a stale
        # selector snapshot being mistaken for a durable semantic witness.
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach($row in @($preview.Rows)){
            $mail=$null;$parent=$null
            try {
                $mail=$session.Namespace.GetItemFromID([string]$row.SourceEntryId,[string]$session.SourceStore.StoreID)
                if($null -eq $mail -or [int]$mail.Class -ne 43 -or
                   [string]$mail.EntryID -cne [string]$row.SourceEntryId -or
                   -not $seen.Add([string]$mail.EntryID)){
                    throw 'ARCH3u exact source MailItem not found/unique at recheck.'
                }
                $parent=$mail.Parent
                if($null -eq $parent -or
                   [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
                   [string]$parent.StoreID -cne [string]$session.SourceStore.StoreID -or
                   ([datetime](Get-OPAArchiveItemDate -Item $mail)).Ticks -ne ([datetime]$row.ArchiveDate).Ticks){
                    throw 'ARCH3u original candidate left approved POP3 Inbox or date changed.'
                }
                $row | Add-Member -NotePropertyName AttachmentCount -NotePropertyValue ([int]$mail.Attachments.Count)
                $row | Add-Member -NotePropertyName SubjectSha256 -NotePropertyValue (Get-OPA265ARCH2bTextSha256 -Text ([string]$mail.Subject))
            } finally{
                Release-OPA265ARCH2c4Com -Object $parent
                Release-OPA265ARCH2c4Com -Object $mail
            }
        }
        if((Get-FileHash -LiteralPath ([string]$index.IndexPath) -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$index.OriginalIndexSha256){
            throw 'ARCH3u original shared DuplicateIndex changed during read-only preflight. STOP.'
        }
        if($index.LegacyBaseSha256 -and
           (Get-FileHash -LiteralPath ([string]$index.LegacyBasePath) -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$index.LegacyBaseSha256){
            throw 'ARCH3u original legacy DuplicateIndex changed during preflight. STOP.'
        }
        $preview | Add-Member -NotePropertyName Mode -NotePropertyValue 'Inventory'
        $preview | Add-Member -NotePropertyName OutlookContacted -NotePropertyValue $true
        $preview | Add-Member -NotePropertyName OutlookProcessId -NotePropertyValue ([int]$session.OutlookProcessId)
        $preview | Add-Member -NotePropertyName OutlookProcessStartUtcTicks -NotePropertyValue ([int64]$session.OutlookProcessStartUtcTicks)
        $preview | Add-Member -NotePropertyName InboxObservedCount -NotePropertyValue $itemsCount
        $preview | Add-Member -NotePropertyName SourcePstLengthBytes -NotePropertyValue ([int64]([IO.FileInfo]::new($source)).Length)
        $preview | Add-Member -NotePropertyName OriginalSharedIndexEntryCount -NotePropertyValue ([int]$index.OriginalIndexEntryCount)
        $preview | Add-Member -NotePropertyName OriginalLegacyIndexSha256 -NotePropertyValue ([string]$index.LegacyBaseSha256)
        $preview | Add-Member -NotePropertyName NoPstOrJournalWrites -NotePropertyValue $true
        return $preview
    }finally{
        Close-OPA265ARCH2dSession -Session $session
    }
}
