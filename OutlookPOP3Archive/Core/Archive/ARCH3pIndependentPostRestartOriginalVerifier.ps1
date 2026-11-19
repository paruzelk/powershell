#requires -Version 5.1
# ARCH3p: independent REAL Outlook post-restart verification of one
# ARCH3o operation. ORIGINAL ArchiveVerifier is mandatory. READ ONLY
# for source/archive PST, original OperationJournal and DuplicateIndex.
# No Move, Resume, journal reconciliation or index appends.
. (Join-Path $PSScriptRoot 'ARCH3oOneRealOriginalMailMover.ps1')
. (Join-Path $PSScriptRoot 'ArchiveVerifier.ps1')

function Assert-OPA265ARCH3pOperatorPin {
    [CmdletBinding()]
    param([string]$RunId,[string]$IntentSha256,[string]$JournalSha256)
    if($RunId -cne '9d276dc4-a0e6-4e74-891f-81502fafe7db' -or
       $IntentSha256 -cne 'f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b' -or
       $JournalSha256 -cne 'a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'){
        throw 'ARCH3p requires exact operator original ARCH3j RunId, Intent and Journal SHA.'
    }
}

function Get-OPA265ARCH3pClaimChain {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256,
          [string]$ExpectedMoveClaimSha256='')
    [void](Assert-OPA265ARCH3pOperatorPin -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256)
    # The original ARCH3o Status performs an independent read-only inspection
    # of the original immutable ARCH3j Intent/JOURNAL (exact SHA, Intent-only).
    $status=Get-OPA265ARCH3oOneShotStatus -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    if(-not [bool]$status.OriginalJournalIntentPreserved -or
       [bool]$status.AutomaticRetryAllowed -or [bool]$status.WriterPermit){
        throw 'ARCH3p original journal or one-shot status is unsafe.'
    }
    foreach($flag in @('WriterEntryExists','DestinationReadyExists','MoveClaimed','ProviderInvocationExists')){
        if(-not [bool]$status.$flag){
            throw ('ARCH3p missing durable stage '+$flag+'. No replay, manual review.')
        }
    }
    $sha=$status.EvidenceSha256
    if($null -eq $sha){throw 'ARCH3p original protected evidence SHA inventory missing.'}
    $l=Get-OPA265ARCH3jLayout -RunId $RunId
    $w=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $l.Root 'ARCH3o-WriterEntry.json') -ExpectedSha256 ([string]$sha['ARCH3o-WriterEntry.json'])
    $d=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $l.Root 'ARCH3o-DestinationReady.json') -ExpectedSha256 ([string]$sha['ARCH3o-DestinationReady.json'])
    $c=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $l.Root 'ARCH3o-MoveClaimed.json') -ExpectedSha256 ([string]$sha['ARCH3o-MoveClaimed.json'])
    $p=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $l.Root 'ARCH3o-ProviderInvocation.json') -ExpectedSha256 ([string]$sha['ARCH3o-ProviderInvocation.json'])
    $receipt=$null
    if([bool]$status.MoveReturnedReceiptExists){
        $receipt=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $l.Root 'ARCH3o-MoveReturned.json') -ExpectedSha256 ([string]$sha['ARCH3o-MoveReturned.json'])
    }
    $intent=Read-OPA265ARCH3cPinnedJson -Path ([string]$l.IntentPath) -ExpectedSha256 $IntentSha256
    $part2='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.Archive-2020-02.pst'
    $entry='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    $full='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
    $contract='2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
    if($ExpectedMoveClaimSha256 -and
       $ExpectedMoveClaimSha256 -cne [string]$sha['ARCH3o-MoveClaimed.json']){
        throw 'ARCH3p independent expected MoveClaim SHA mismatch.'
    }
    if([string]$w.Schema -cne '2.6.5-ARCH3o.WriterEntry.1' -or
       [string]$d.Schema -cne '2.6.5-ARCH3o.DestinationReady.1' -or
       [string]$c.Schema -cne '2.6.5-ARCH3o.RealOneShotMoveClaim.1' -or
       [string]$p.Schema -cne '2.6.5-ARCH3o.ProviderInvocation.1' -or
       [string]$w.RunId -cne $RunId -or [string]$d.RunId -cne $RunId -or
       [string]$c.RunId -cne $RunId -or [string]$p.RunId -cne $RunId -or
       [string]$w.IntentSha256 -cne $IntentSha256 -or
       [string]$w.JournalSha256 -cne $JournalSha256 -or
       [string]$c.IntentSha256 -cne $IntentSha256 -or
       [string]$c.JournalSha256 -cne $JournalSha256 -or
       [string]$w.SourceEntryId -cne $entry -or [string]$c.SourceEntryId -cne $entry -or
       [string]$p.SourceEntryId -cne $entry -or [string]$intent.SourceEntryId -cne $entry -or
       [string]$w.OriginalWitnessSha256 -cne $full -or
       [string]$d.OriginalWitnessSha256 -cne $full -or
       [string]$c.OriginalWitnessSha256 -cne $full -or
       [string]$intent.FullOriginalWitnessSha256 -cne $full -or
       [string]$w.NewArchivePst -cne $part2 -or
       [string]$d.NewArchivePst -cne $part2 -or
       [string]$c.NewArchivePst -cne $part2 -or
       [string]$p.NewArchivePst -cne $part2 -or
       [string]$intent.NewArchivePst -cne $part2 -or
       [string]$intent.OriginalContractSha256 -cne $contract -or
       [string]$c.WriterEntrySha256 -cne [string]$sha['ARCH3o-WriterEntry.json'] -or
       [string]$d.WriterEntrySha256 -cne [string]$sha['ARCH3o-WriterEntry.json'] -or
       [string]$c.DestinationReadySha256 -cne [string]$sha['ARCH3o-DestinationReady.json'] -or
       [string]$p.ClaimSha256 -cne [string]$sha['ARCH3o-MoveClaimed.json'] -or
       [string]$c.DestinationStoreId -cne [string]$d.DestinationStoreId -or
       [string]$c.DestinationFolderEntryId -cne [string]$d.DestinationFolderEntryId -or
       [string]$p.DestinationFolderEntryId -cne [string]$d.DestinationFolderEntryId -or
       [int]$c.OutlookProcessId -le 0 -or [long]$c.OutlookProcessStartUtcTicks -le 0 -or
       -not [bool]$c.OperatorApprovedOneRealMove -or
       [bool]$c.AutomaticRetryAllowed -or [bool]$p.AutomaticRetryAllowed -or
       [bool]$w.AutomaticRetryAllowed -or [bool]$c.ProductionReady){
        throw 'ARCH3p original ARCH3o witness/claim/provider SHA chain inconsistent.'
    }
    if($null -ne $receipt -and
       ([string]$receipt.Schema -cne '2.6.5-ARCH3o.MoveReturned.1' -or
        [string]$receipt.RunId -cne $RunId -or
        [string]$receipt.SourceEntryId -cne $entry -or
        [string]$receipt.NewArchivePst -cne $part2 -or
        [string]$receipt.OriginalWitnessSha256 -cne $full -or
        [string]$receipt.OriginalContractSha256 -cne $contract -or
        [string]$receipt.MoveClaimSha256 -cne [string]$sha['ARCH3o-MoveClaimed.json'] -or
        [string]$receipt.ProviderInvocationSha256 -cne [string]$sha['ARCH3o-ProviderInvocation.json'] -or
        [string]$receipt.DestinationStoreId -cne [string]$c.DestinationStoreId -or
        [string]$receipt.DestinationFolderEntryId -cne [string]$c.DestinationFolderEntryId -or
        [string]$receipt.ArchiveEntryId -cnotmatch '^[A-Fa-f0-9]{16,1024}$' -or
        [bool]$receipt.IndependentPostRestartVerified -or
        [bool]$receipt.DuplicateIndexWritten -or [bool]$receipt.OriginalJournalReconciled)){
        throw 'ARCH3p original ARCH3o receipt is not immutable pre-restart evidence.'
    }
    $sealed=Get-OPA265ARCH3jSealedSource -SealRunId ([string]$intent.SourceSealRunId) -SealSha256 ([string]$intent.SourceSealSha256)
    [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $sealed.OriginalWitness -ExpectedOriginalWitnessSha256 $full)
    if([string]$sealed.SourceEntryId -cne $entry -or
       [string]$sealed.SourceFolderEntryId -cne [string]$intent.SourceFolderEntryId -or
       [string]$sealed.SourceStoreIdSha256 -cne [string]$intent.SourceStoreIdSha256){
        throw 'ARCH3p original independently sealed full source witness has changed.'
    }
    return [pscustomobject]@{
        Status=$status;Layout=$l;Writer=$w;DestinationReady=$d;Claim=$c;Invocation=$p
        MoveReturned=$receipt;OriginalIntent=$intent;Sealed=$sealed
        MoveClaimSha256=[string]$sha['ARCH3o-MoveClaimed.json']
        ProviderInvocationSha256=[string]$sha['ARCH3o-ProviderInvocation.json']
        MoveReceiptSha256=if($null -eq $receipt){''}else{[string]$sha['ARCH3o-MoveReturned.json']}
    }
}

function Get-OPA265ARCH3pMountedPart2 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][string]$Part2,
          [Parameter(Mandatory=$true)][string]$StoreId)
    $n=[int]$Namespace.Stores.Count
    if($n -lt 1 -or $n -gt 32){throw 'ARCH3p Outlook Store count outside safe bounds.'}
    $match=$null;$count=0
    for($i=1;$i -le $n;$i++){
        $s=$null
        try{
            $s=$Namespace.Stores.Item($i)
            if($null -ne $s -and
               [string]::Equals([IO.Path]::GetFullPath([string]$s.FilePath),
                   [IO.Path]::GetFullPath($Part2),[StringComparison]::OrdinalIgnoreCase)){
                $count++
                if($count -eq 1){$match=$s;$s=$null}
            }
        }finally{Release-OPA265ARCH2c4Com -Object $s}
    }
    if($count -ne 1 -or $null -eq $match -or
       [string]$match.StoreID -cne $StoreId){
        Release-OPA265ARCH2c4Com -Object $match
        throw 'ARCH3p exactly one already MOUNTED original Part2 with pinned StoreID required; never AddStoreEx.'
    }
    return $match
}

function Test-OPA265ARCH3pOriginalVerifierResult {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Verified,
          [Parameter(Mandatory=$true)][long]$SourceCountBefore,
          [Parameter(Mandatory=$true)][string]$SourceEntryId)
    # SourceCountBefore is the ORIGINAL folder total, not zero; only target
    # source EntryID must have vanished. Exact target count must equal ONE.
    if(-not [bool]$Verified.Verified -or -not [bool]$Verified.EntryIdsVerified -or
       -not [bool]$Verified.SemanticWitnessRequired -or
       -not [bool]$Verified.AllRequiredOriginalSemanticWitnessesPresent -or
       [int]$Verified.ExpectedMoved -ne 1 -or
       [int]$Verified.ExpectedEntryIdsChecked -ne 1 -or
       [int]$Verified.TargetCount -ne 1 -or
       [long]$Verified.ObservedSourceCount -ne $SourceCountBefore -or
       @($Verified.MissingEntryIds).Count -gt 0 -or
       @($Verified.WarningEntryIds | Where-Object { [string]$_ -notlike 'STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT:*' }).Count -gt 0){
        throw ('ARCH3p ORIGINAL ArchiveVerifier failed or returned ambiguous evidence for '+$SourceEntryId)
    }
    return $true
}

function Invoke-OPA265ARCH3pIndependentRestartReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Chain)
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3p independent live Outlook review requires Windows PowerShell 5.1 -STA.'
    }
    $c=$Chain.Claim;$intent=$Chain.OriginalIntent;$sealed=$Chain.Sealed
    $part1=[string]$intent.ExistingArchivePart1
    $part2=[string]$c.NewArchivePst
    if(-not [IO.File]::Exists($part2) -or [IO.FileInfo]::new($part2).Length -le 0 -or
       [IO.FileInfo]::new($part1).Length -ne 271360){
        throw 'ARCH3p real Part2 missing or existing original Part1 changed.'
    }
    $index=Get-OPA265ARCH3jIndexSafety -Part1 $part1 -SourceEntryId ([string]$c.SourceEntryId)
    if(-not [bool]$index.Approved -or [int]$index.EntryCount -ne 500){
        throw 'ARCH3p original shared DuplicateIndex mutated before independent review.'
    }
    $session=$null;$archive=$null;$root=$null;$folder=$null;$item=$null
    try {
        $session=Open-OPA265ARCH2dSession -Layout (Get-OPA265ARCH2dLayout -RunId ([string]$c.RunId) -LocalAppData $env:LOCALAPPDATA) -SourcePst ([string]$intent.SourcePst)
        if(-not [bool]$session.Scope.Approved -or
           (Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne [string]$intent.SourceStoreIdSha256 -or
           [string]$session.Inbox.EntryID -cne [string]$intent.SourceFolderEntryId){
            throw 'ARCH3p reopened original POP3 source does not match prior sealed scope.'
        }
        if([int]$session.OutlookProcessId -eq [int]$c.OutlookProcessId -or
           [long]$session.OutlookProcessStartUtcTicks -le [long]$c.OutlookProcessStartUtcTicks){
            throw 'ARCH3p independent Outlook process restart NOT observed. Close Outlook completely and reopen.'
        }
        $archive=Get-OPA265ARCH3pMountedPart2 -Namespace $session.Namespace -Part2 $part2 -StoreId ([string]$c.DestinationStoreId)
        if([string]$archive.StoreID -ceq [string]$session.SourceStore.StoreID -or
           [string]$archive.StoreID -ceq [string]$session.DefaultStoreId){
            throw 'ARCH3p archive part2 is source or default store, prohibited.'
        }
        foreach($a in @($session.Accounts)){
            if([string]$a.DeliveryStoreId -ceq [string]$archive.StoreID){
                throw 'ARCH3p archive became email account delivery store.'
            }
        }
        $root=$archive.GetRootFolder()
        $folder=Get-OPAFolderByPath -Root $root -RelativePath '2020\Входящие'
        if($null -eq $folder -or
           [string]$folder.StoreID -cne [string]$archive.StoreID -or
           [string]$folder.EntryID -cne [string]$c.DestinationFolderEntryId -or
           -not ([string]$folder.FolderPath).EndsWith('\2020\Входящие',[StringComparison]::OrdinalIgnoreCase) -or
           [int]$folder.Items.Count -ne 1){
            throw 'ARCH3p original Year2020 Inbox folder not exact or target not ONE item.'
        }
        $item=$folder.Items.Item(1)
        if($null -eq $item -or [int]$item.Class -ne 43 -or
           [string]$item.EntryID -cnotmatch '^[A-Fa-f0-9]{16,1024}$'){
            throw 'ARCH3p single destination MailItem invalid.'
        }
        # Read the ORIGINAL complete pre-Move witness sealed in ARCH3i.
        # Full content + HTML + recipients + attachment SHA are mandatory.
        $original=$sealed.OriginalWitness
        [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $original -ExpectedOriginalWitnessSha256 ([string]$c.OriginalWitnessSha256))
        $destWitness=Get-OPA265ARCH2bMailSemanticWitness -Mail $item
        $semantic=Compare-OPA265ARCH2bMailSemanticWitness -Source $original -Destination $destWitness
        if(-not [bool]$semantic.CriticalContentMatches -or @($semantic.IssueCodes).Count -ne 0){
            throw 'ARCH3p independent destination complete original semantic witness mismatch.'
        }
        $messageId=[string](Get-OPAInternetMessageId -Item $item)
        $subject=[string]$item.Subject
        $expectedEntry=if($null -ne $Chain.MoveReturned){[string]$Chain.MoveReturned.ArchiveEntryId}else{[string]$item.EntryID}
        $originalExpected=[pscustomobject]@{
            SourceEntryId=[string]$c.SourceEntryId
            ArchiveEntryId=$expectedEntry
            ArchivePst=$part2
            TargetFolderPath=[string]$folder.FolderPath
            SourceFolderPath=[string]$session.Inbox.FolderPath
            InternetMessageId=$messageId
            Subject=$subject
            Sender=''
            Size=$null
            SourceSemanticWitness=$original
        }
        $countBefore=[long]$session.Inbox.Items.Count
        # Required ORIGINAL verifier: it enumerates the source folder,
        # proves the source ID is absent, resolves the recorded archive
        # folder, then checks original full SHA via ARCH2b witness.
        $result=Test-OPAArchiveMoves -Namespace $session.Namespace -SourceFolder @($session.Inbox) -ArchiveStores @($archive) -ExpectedMoved 1 -ExpectedMoves @($originalExpected) -RequireSemanticWitness
        [void](Test-OPA265ARCH3pOriginalVerifierResult -Verified $result -SourceCountBefore $countBefore -SourceEntryId ([string]$c.SourceEntryId))
        if([IO.FileInfo]::new($part1).Length -ne 271360){
            throw 'ARCH3p existing Part1 size changed during original verifier.'
        }
        $after=Get-OPA265ARCH3jIndexSafety -Part1 $part1 -SourceEntryId ([string]$c.SourceEntryId)
        if(-not [bool]$after.Approved -or [int]$after.EntryCount -ne 500){
            throw 'ARCH3p original shared index changed during independent verifier.'
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3p.IndependentRealOutlookOriginalVerifierReview.1'
            Status='IndependentRealOutlookRestartOriginalArchiveVerifierSourceAbsentArchiveOneFullSemanticMatch'
            RunId=[string]$c.RunId
            OriginalMoveClaimSha256=[string]$Chain.MoveClaimSha256
            OriginalProviderInvocationSha256=[string]$Chain.ProviderInvocationSha256
            OriginalMoveReceiptSha256=[string]$Chain.MoveReceiptSha256
            MoveReceiptWasMissingButProviderInvocationPresent=($null -eq $Chain.MoveReturned)
            OriginalSourceEntryId=[string]$c.SourceEntryId
            OriginalWitnessSha256=[string]$c.OriginalWitnessSha256
            ObservedDestinationEntryId=[string]$item.EntryID
            ArchivePst=$part2
            ArchiveFolderPath=[string]$folder.FolderPath
            SourceFolderCountObserved=[long]$result.ObservedSourceCount
            OriginalVerifierSourceIdAbsent=$true
            OriginalVerifierDestinationCount=1
            OriginalVerifierSemanticMatch=$true
            OriginalArchiveVerifierUsed=$true
            ReopenedOutlookProcessId=[int]$session.OutlookProcessId
            ReopenedOutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            OriginalMoveOutlookProcessId=[int]$c.OutlookProcessId
            OriginalMoveOutlookProcessStartUtcTicks=[long]$c.OutlookProcessStartUtcTicks
            RealOutlookRestartConfirmed=$true
            JournalRemainsIntent=$true
            DuplicateIndexEntriesRemain=500
            OriginalOperationJournalReconciled=$false
            DuplicateIndexWritten=$false
            AutomaticMoveRetryAllowed=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $item
        Release-OPA265ARCH2c4Com -Object $folder
        Release-OPA265ARCH2c4Com -Object $root
        Release-OPA265ARCH2c4Com -Object $archive
        Close-OPA265ARCH2dSession -Session $session
    }
}

function Invoke-OPA265ARCH3pPostRestart {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Plan','Review','Status')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256,
          [string]$ExpectedMoveClaimSha256='')
    [void](Assert-OPA265ARCH3pOperatorPin -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256)
    $chain=Get-OPA265ARCH3pClaimChain -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256 -ExpectedMoveClaimSha256 $ExpectedMoveClaimSha256
    if($Mode -cne 'Review'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3p.PinnedOriginalReceiptPlan.1'
            Status=if($Mode -ceq 'Status'){'OriginalPostRestartEvidenceReadOnlyStatus'}else{'OriginalPostRestartVerifierReadyNoOutlookNoWrites'}
            RunId=$RunId
            ClaimSha256=[string]$chain.MoveClaimSha256
            ProviderInvocationSha256=[string]$chain.ProviderInvocationSha256
            MoveReceiptExists=($null -ne $chain.MoveReturned)
            OriginalSemanticWitnessSha256=[string]$chain.Claim.OriginalWitnessSha256
            OriginalJournalIntentUnchanged=$true
            RealOutlookContacted=$false
            IndependentPostRestartVerified=$false
            AutomaticMoveRetryAllowed=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }
    return (Invoke-OPA265ARCH3pIndependentRestartReview -Chain $chain)
}
