#requires -Version 5.1
# ARCH3w1: independently verify original archived Part2 semantic content instead of mutable PST binary SHA; exact ARCH3r historical checkpoint and ORIGINAL ArchiveVerifier required.
# Reuse exact already SEALED ARCH3v ten original ARCH2b semantic hashes.
# No Outlook MailItem.Move, no PST allocation, no shared DuplicateIndex writes,
# no MoveClaimed, no retry, and no production writer.
. (Join-Path $PSScriptRoot 'ARCH3vRealTenFullWitness.ps1')
. (Join-Path $PSScriptRoot 'ARCH3jRealOneShotPrepareIntent.ps1')
. (Join-Path $PSScriptRoot 'ARCH3rCompletedPilotCheckpoint.ps1')

function Get-OPA265ARCH3w1Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId)
    $ref=Get-OPA265ARCH3iEvidenceLayout -RunId $RunId
    $root=Join-Path ([string]$ref.LocalAppData) ('OPA265-ARCH3w1-'+$RunId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3w1.Layout.1'
        RunId=$RunId;Root=$root
        ManifestPath=(Join-Path $root 'original-ten-prepare-intents.json')
        JournalPath=(Join-Path $root 'original-operation-journal.jsonl')
    }
}

function Get-OPA265ARCH3w1HistoricalPins {
    [CmdletBinding()]
    param()
    return @{
        RunId='9d276dc4-a0e6-4e74-891f-81502fafe7db'
        IntentSha256='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
        JournalSha256='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
        ReviewSha256='3c455f4da4ee32fd9f0d046ac5e36cc3d013c0913cf86ddee69d359f700831c3'
        CommitClaimSha256='fc0e51d828d3b82fb3e46b22bdca6ff50f54f86366d1f9ec5ff5c937e221527a'
        CommitSealSha256='0fa26ba60ebe9685a6b13c5f989b1c5a840f54d5bc8302f87679b4e7dc6e67f0'
    }
}

function Get-OPA265ARCH3w1HistoricalPart2Digest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Chain,
          [Parameter(Mandatory=$true)][object]$Checkpoint,
          [Parameter(Mandatory=$true)][string]$Part2)
    if([string]$Checkpoint.Schema -cne '2.6.5-ARCH3r.RealCompletedPilotCheckpoint.1' -or
       [string]$Checkpoint.OriginalFullWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c' -or
       [string]$Checkpoint.ArchiveEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000' -or
       [string]$Checkpoint.OriginalSharedIndexSha256 -cne '5ada35eb30f34ff60dc4b89f23aa071b72cc0b98e5ff57299d61f1714b13d7ae' -or
       [string]$Chain.Claim.SourceEntryId -cne [string]$Checkpoint.SourceEntryId -or
       [string]$Chain.Claim.NewArchivePst -cne $Part2 -or
       [string]$Chain.OriginalIntent.FullOriginalWitnessSha256 -cne [string]$Checkpoint.OriginalFullWitnessSha256 -or
       [string]$Chain.Claim.DestinationStoreId -cne [string]$Chain.DestinationReady.DestinationStoreId -or
       -not [bool]$Chain.Claim.OperatorApprovedOneRealMove -or
       [bool]$Chain.Claim.AutomaticRetryAllowed){
        throw 'ARCH3w1 historical ORIGINAL ARCH3o/r pinned Part2 semantic source contract changed. STOP.'
    }
    [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $Chain.Sealed.OriginalWitness -ExpectedOriginalWitnessSha256 ([string]$Checkpoint.OriginalFullWitnessSha256))
    return (Get-OPA265ARCH3bDigest -Parts @(
       '2.6.5-ARCH3w1.OriginalPart2SemanticProof.1',
       [string]$Checkpoint.RunId,[string]$Checkpoint.SourceEntryId,
       [string]$Checkpoint.ArchiveEntryId,
       [string]$Checkpoint.OriginalFullWitnessSha256,
       [string]$Checkpoint.OriginalSharedIndexSha256,
       [string]$Checkpoint.OriginalOperationJournalSha256,
       [string]$Chain.OriginalIntent.OriginalContractSha256,
       [string]$Chain.Claim.DestinationStoreId,
       [string]$Chain.Claim.DestinationFolderEntryId,
       [string]$Part2,'2020\Входящие'
    ))
}

function Get-OPA265ARCH3w1HistoricalEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Part2)
    $pins=Get-OPA265ARCH3w1HistoricalPins
    $checkpoint=Get-OPA265ARCH3rCompletedRealCheckpoint -Mode Audit @pins
    if(-not [bool]$checkpoint.OriginalFullSemanticWitnessVerified -or
       -not [bool]$checkpoint.OriginalIndependentIndexReadback -or
       -not [bool]$checkpoint.OriginalArchiveVerifierEvidencePresent -or
       [int]$checkpoint.OriginalSharedIndexEntryCount -ne 501){
        throw 'ARCH3w1 historical post-restart original verifier / 501 index proof not valid.'
    }
    # ARCH3p's precommit reader accepts only an Intent-only journal.
    # A Reconciled 501-index historical pilot must use ORIGINAL postcommit
    # ARCH3q state and its exact immutable per-stage SHA-provenance instead.
    $state=Get-OPA265ARCH3qState -RunId $pins.RunId -IntentSha256 $pins.IntentSha256 -JournalSha256 $pins.JournalSha256
    if([string]$state.JournalPhase -cne 'Reconciled' -or
       [int]$state.IndexCount -ne 501 -or -not [bool]$state.SealExists){
        throw 'ARCH3w1 original Part2 real pilot must be journal Reconciled and indexed 501.'
    }
    $stages=Get-OPA265ARCH3qPinnedStages -State $state
    $chain=[pscustomobject]@{
        Claim=$stages.Claim
        DestinationReady=$stages.Ready
        OriginalIntent=$state.Intent
        Sealed=$stages.Sealed
    }
    $digest=Get-OPA265ARCH3w1HistoricalPart2Digest -Chain $chain -Checkpoint $checkpoint -Part2 $Part2
    return [pscustomobject]@{Chain=$chain;Checkpoint=$checkpoint;SemanticSha256=$digest}
}

function Assert-OPA265ARCH3w1Part2SingleMailTree {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Root)
    # A Part2 created for exactly one archived source cannot silently acquire
    # other Outlook items in previously unseen folders. Any unexpected item
    # is a separate forensic state and blocks Prepare, not just a new SHA.
    $stack=New-Object System.Collections.Stack
    $stack.Push($Root)
    $seen=0;$total=0;$target=0
    while($stack.Count -gt 0){
        $folder=$stack.Pop()
        $folders=$null;$items=$null
        try{
            $seen++
            if($seen -gt 128){throw 'ARCH3w1 original Part2 folder tree exceeded strict bound.'}
            $path=[string]$folder.FolderPath
            $isTarget=$path.EndsWith('\2020\Входящие',[StringComparison]::OrdinalIgnoreCase)
            $items=$folder.Items
            $count=[int]$items.Count
            if($count -lt 0 -or $count -gt 100000){throw 'ARCH3w1 archive folder count invalid.'}
            if($isTarget){
                $target++
                if($count -ne 1){throw 'ARCH3w1 original Part2 target folder must contain ONE item.'}
            }elseif($count -ne 0){
                throw ('ARCH3w1 unknown nonempty Part2 folder; manual review: '+$path)
            }
            $total+=$count
            $folders=$folder.Folders
            for($i=1;$i -le [int]$folders.Count;$i++){
                $child=$folders.Item($i)
                if($null -eq $child){throw 'ARCH3w1 unreadable Part2 child folder.'}
                $stack.Push($child)
            }
        }finally{
            Release-OPA265ARCH2c4Com -Object $items
            Release-OPA265ARCH2c4Com -Object $folders
            if(-not [object]::ReferenceEquals($folder,$Root)){Release-OPA265ARCH2c4Com -Object $folder}
        }
    }
    if($target -ne 1 -or $total -ne 1){throw 'ARCH3w1 original Part2 archive semantic inventory not exactly one mail.'}
    return $true
}

function Test-OPA265ARCH3w1LiveOriginalPart2 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$Part2,
          [Parameter(Mandatory=$true)][object]$Evidence)
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3w1 original ArchiveVerifier requires Windows PowerShell 5.1 STA.'
    }
    $chain=$Evidence.Chain
    $claim=$chain.Claim;$sourceIntent=$chain.OriginalIntent
    $session=$null;$archive=$null;$root=$null;$folder=$null;$item=$null;$destWitness=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout (Get-OPA265ARCH2dLayout -RunId ([string]$claim.RunId) -LocalAppData $env:LOCALAPPDATA) -SourcePst $SourcePst
        if(-not [bool]$session.Scope.Approved -or
           (Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne [string]$sourceIntent.SourceStoreIdSha256 -or
           [string]$session.Inbox.EntryID -cne [string]$sourceIntent.SourceFolderEntryId){
            throw 'ARCH3w1 original source POP3/Inbox changed from historical completed one-shot.'
        }
        $archive=Get-OPA265ARCH3pMountedPart2 -Namespace $session.Namespace -Part2 $Part2 -StoreId ([string]$claim.DestinationStoreId)
        if([string]$archive.StoreID -ceq [string]$session.SourceStore.StoreID -or
           [string]$archive.StoreID -ceq [string]$session.DefaultStoreId){
            throw 'ARCH3w1 original Part2 is a prohibited source/default store.'
        }
        foreach($account in @($session.Accounts)){
            if([string]$account.DeliveryStoreId -ceq [string]$archive.StoreID){
                throw 'ARCH3w1 original Part2 is an account delivery store.'
            }
        }
        $root=$archive.GetRootFolder()
        [void](Assert-OPA265ARCH3w1Part2SingleMailTree -Root $root)
        $folder=Get-OPAFolderByPath -Root $root -RelativePath '2020\Входящие'
        if($null -eq $folder -or
           [string]$folder.StoreID -cne [string]$archive.StoreID -or
           [string]$folder.EntryID -cne [string]$claim.DestinationFolderEntryId -or
           [int]$folder.Items.Count -ne 1){
            throw 'ARCH3w1 original Part2 folder is ambiguous or target EntryID changed.'
        }
        $item=$folder.Items.Item(1)
        if($null -eq $item -or [int]$item.Class -ne 43 -or
           [string]$item.EntryID -cne [string]$Evidence.Checkpoint.ArchiveEntryId){
            throw 'ARCH3w1 original archived destination EntryID differs from completed pilot.'
        }
        $destWitness=Get-OPA265ARCH2bMailSemanticWitness -Mail $item
        $comparison=Compare-OPA265ARCH2bMailSemanticWitness -Source $chain.Sealed.OriginalWitness -Destination $destWitness
        if(-not [bool]$comparison.CriticalContentMatches -or @($comparison.IssueCodes).Count -ne 0){
            throw 'ARCH3w1 historical Part2 full Body/HTML/attachment/userstate witness changed.'
        }
        $expected=[pscustomobject]@{
            SourceEntryId=[string]$claim.SourceEntryId
            ArchiveEntryId=[string]$Evidence.Checkpoint.ArchiveEntryId
            ArchivePst=$Part2
            TargetFolderPath=[string]$folder.FolderPath
            SourceFolderPath=[string]$session.Inbox.FolderPath
            InternetMessageId=[string](Get-OPAInternetMessageId -Item $item)
            Subject=[string]$item.Subject;Sender='';Size=$null
            SourceSemanticWitness=$chain.Sealed.OriginalWitness
        }
        $before=[long]$session.Inbox.Items.Count
        $verified=Test-OPAArchiveMoves -Namespace $session.Namespace -SourceFolder @($session.Inbox) -ArchiveStores @($archive) -ExpectedMoved 1 -ExpectedMoves @($expected) -RequireSemanticWitness
        [void](Test-OPA265ARCH3pOriginalVerifierResult -Verified $verified -SourceCountBefore $before -SourceEntryId ([string]$claim.SourceEntryId))
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3w1.LiveOriginalPart2Verifier.1'
            Status='OriginalHistoricalPart2OneMailFullSemanticAndOriginalVerifierConfirmed'
            OriginalArchiveVerifierUsed=$true
            OriginalPart2TargetCount=1;OriginalPart2TotalItemCount=1
            OriginalFullWitnessSha256=[string]$Evidence.Checkpoint.OriginalFullWitnessSha256
            OriginalArchiveEntryId=[string]$Evidence.Checkpoint.ArchiveEntryId
            SemanticSha256=[string]$Evidence.SemanticSha256
            RealMailMovePerformed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $item
        Release-OPA265ARCH2c4Com -Object $folder
        Release-OPA265ARCH2c4Com -Object $root
        Release-OPA265ARCH2c4Com -Object $archive
        Close-OPA265ARCH2dSession -Session $session
    }
}

function Get-OPA265ARCH3w1OriginalYearParts {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst)
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting
    Clear-OPAArchivePartCache -SourcePst $source
    $known=@(Get-OPAArchivePstPartsOnDiskAll -SourcePst $source | Where-Object {[int]$_.Year -eq 2020})
    if($known.Count -ne 2){throw 'ARCH3w1 requires exactly existing 2020 Part1/Part2.'}
    $first=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 1
    $second=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 2
    $third=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 3
    foreach($item in @(@{Number=1;Path=$first},@{Number=2;Path=$second})){
        if(@($known | Where-Object {[int]$_.Part -eq [int]$item.Number -and [string]$_.Path -ceq [string]$item.Path}).Count -ne 1 -or
           -not [IO.File]::Exists([string]$item.Path) -or
           (([IO.File]::GetAttributes([string]$item.Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3w1 missing/reparsed/ambiguous historical archive part.'
        }
    }
    if([IO.File]::Exists($third) -or [IO.Directory]::Exists($third)){
        throw 'ARCH3w1 Part3 destination is occupied; no Intent.'
    }
    if([long]([IO.FileInfo]::new($first)).Length -ne 271360 -or
       [long]([IO.FileInfo]::new($second)).Length -ne 525312){
        throw 'ARCH3w1 original parts size drift; cannot assume metadata-only changes. STOP.'
    }
    $firstSha=(Get-FileHash -LiteralPath $first -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if($firstSha -cne '8bc491f7b5e7b71e5458f88b01fa684f22270b425d7eca3fba572b1914e2514b'){
        throw 'ARCH3w1 original Part1 exact binary SHA changed; no independent full witness for Part1. STOP.'
    }
    # Existing Part2 PST raw SHA is NOT used for the permit, because Outlook
    # mutates MAPI provider bytes while logical archived mail remains unchanged.
    # Instead reconstruct the immutable ARCH3o/ARCH3p/ARCH3q/ARCH3r chain,
    # then run the ORIGINAL live ArchiveVerifier on the exact archived mail.
    $evidence=Get-OPA265ARCH3w1HistoricalEvidence -Part2 $second
    $live=Test-OPA265ARCH3w1LiveOriginalPart2 -SourcePst $source -Part2 $second -Evidence $evidence
    if(-not [bool]$live.OriginalArchiveVerifierUsed -or
       [string]$live.SemanticSha256 -cne [string]$evidence.SemanticSha256 -or
       [int]$live.OriginalPart2TotalItemCount -ne 1){
        throw 'ARCH3w1 original Part2 full semantic live verification did not pass.'
    }
    return @(
        [pscustomobject][ordered]@{
            Part=1;Path=$first;LengthBytes=[long]271360
            Sha256=$firstSha
            ProofKind='OriginalPstBinarySha256'
            OriginalWitnessSha256=''
            ArchiveEntryId=''
        },
        [pscustomobject][ordered]@{
            Part=2;Path=$second;LengthBytes=[long]525312
            Sha256=[string]$evidence.SemanticSha256
            ProofKind='OriginalArchiveVerifierFullSemanticSha256'
            OriginalWitnessSha256=[string]$evidence.Checkpoint.OriginalFullWitnessSha256
            ArchiveEntryId=[string]$evidence.Checkpoint.ArchiveEntryId
        }
    )
}

function Assert-OPA265ARCH3w1SealedSource {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SealSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedAuditSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedPreviewSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedOriginalIndexSha256)
    foreach($hash in @($SealSha256,$ExpectedAuditSha256,$ExpectedPreviewSha256,$ExpectedOriginalIndexSha256)){
        if($hash -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH3w1 exact SHA pins required.'}
    }
    $l=Get-OPA265ARCH3vEvidenceLayout -RunId $RunId
    $review=Test-OPA265ARCH3vFullTenReadback -Layout $l -SealSha256 $SealSha256
    if([string]$review.AuditSha256 -cne $ExpectedAuditSha256 -or
       [string]$review.PreviewSha256 -cne $ExpectedPreviewSha256 -or
       [string]$review.OriginalIndexSha256 -cne $ExpectedOriginalIndexSha256 -or
       [int]$review.BatchSize -ne 10 -or
       [int]$review.TotalAttachmentCount -ne 12 -or
       [int]$review.FullOriginalWitnessesVerified -ne 10){
        throw 'ARCH3w1 real operator original ten sealed semantic witness pins drifted.'
    }
    $doc=Read-OPA265ARCH3cPinnedJson -Path ([string]$l.WitnessPath) -ExpectedSha256 $SealSha256
    if([string]$doc.RunId -cne $RunId -or
       [string]$doc.TargetPstPreview -cne (Get-OPAArchivePartPath -SourcePst ([string]$doc.SourcePst) -Year 2020 -Part 3) -or
       [int]$doc.TotalAttachmentCount -ne 12 -or
       [bool]$doc.RealMailMovePerformed -or
       [bool]$doc.WriterPermit -or [bool]$doc.ProductionReady){
        throw 'ARCH3w1 original sealed real 10 target or no-writer flags invalid.'
    }
    return $doc
}

function Get-OPA265ARCH3w1PrepareDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest)
    if([string]$Manifest.Schema -cne '2.6.5-ARCH3w1.TenOriginalIntentManifest.1' -or
       [string]$Manifest.RunId -cnotmatch '^[a-f0-9-]{36}$' -or
       [string]$Manifest.SealSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Manifest.AuditSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Manifest.PreviewSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Manifest.OriginalIndexSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Manifest.SourceStoreIdSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [int]$Manifest.BatchSize -ne 10 -or
       [int]$Manifest.TotalAttachmentCount -ne 12 -or
       [bool]$Manifest.MoveClaimed -or
       [bool]$Manifest.RealMailMovePerformed -or
       [bool]$Manifest.OriginalDuplicateIndexWritten -or
       [bool]$Manifest.ArchivePstCreated -or
       [bool]$Manifest.WriterPermit -or [bool]$Manifest.ProductionReady){
        throw 'ARCH3w1 manifest missing original 10 real source immutable pins.'
    }
    $parts=@('2.6.5-ARCH3w1.TenOriginalIntentManifest.1',
        [string]$Manifest.RunId,[string]$Manifest.SourcePst,
        [string]$Manifest.SealSha256,[string]$Manifest.AuditSha256,
        [string]$Manifest.PreviewSha256,[string]$Manifest.OriginalIndexSha256,
        [string]$Manifest.SourceStoreIdSha256,[string]$Manifest.SourcePstLengthBytes,
        [string]$Manifest.TargetPstPreview,[string]$Manifest.BatchSize)
    $archives=@($Manifest.ExistingArchiveParts)
    if($archives.Count -ne 2){throw 'ARCH3w1 original two archive parts required.'}
    for($n=1;$n -le 2;$n++){
        $a=$archives[$n-1]
        if(($n -eq 1 -and ([string]$a.ProofKind -cne 'OriginalPstBinarySha256' -or
                        [string]$a.Sha256 -cne '8bc491f7b5e7b71e5458f88b01fa684f22270b425d7eca3fba572b1914e2514b' -or
                        [long]$a.LengthBytes -ne 271360)) -or
           ($n -eq 2 -and ([string]$a.ProofKind -cne 'OriginalArchiveVerifierFullSemanticSha256' -or
                        [string]$a.OriginalWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c' -or
                        [string]$a.ArchiveEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000' -or
                        [long]$a.LengthBytes -ne 525312)) -or
           [int]$a.Part -ne $n -or [string]$a.Sha256 -cnotmatch '^[a-f0-9]{64}
           [long]$a.LengthBytes -le 0){
            throw 'ARCH3w1 original 2020 archive part immutable SHA or length invalid.'
        }
        $parts+=@([string]$a.Part,[string]$a.Path,[string]$a.LengthBytes,[string]$a.Sha256,[string]$a.ProofKind,[string]$a.OriginalWitnessSha256,[string]$a.ArchiveEntryId)
    }
    $rows=@($Manifest.Rows)
    if($rows.Count -ne 10){throw 'ARCH3w1 original ten intent manifest row count drift.'}
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $ops=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $count=0
    for($i=0;$i -lt 10;$i++){
        $r=$rows[$i]
        if([int]$r.Ordinal -ne ($i+1) -or
           [string]$r.SourceEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
           -not $ids.Add([string]$r.SourceEntryId) -or
           [string]$r.OriginalOperationId -cne ('ARCH3b-'+[string]$r.OriginalContractSha256) -or
           [string]$r.OriginalContractSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           -not $ops.Add([string]$r.OriginalOperationId) -or
           [string]$r.FullOriginalWitnessSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$r.TargetFolderPath -cne '2020\Входящие' -or
           [int]$r.AttachmentCount -lt 0 -or
           [int]$r.AttachmentCount -gt 128){
            throw ('ARCH3w1 invalid/duplicated original source Intent row '+($i+1))
        }
        $count+=[int]$r.AttachmentCount
        $parts+=@([string]$r.Ordinal,[string]$r.SourceEntryId,
            [string]$r.OriginalOperationId,[string]$r.OriginalContractSha256,
            [string]$r.FullOriginalWitnessSha256,[string]$r.TargetFolderPath,
            [string]$r.AttachmentCount)
    }
    if($count -ne [int]$Manifest.TotalAttachmentCount){throw 'ARCH3w1 10 original attachment count mismatch.'}
    return (Get-OPA265ARCH3bDigest -Parts $parts)
}

function New-OPA265ARCH3w1Manifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Seal,
          [Parameter(Mandatory=$true)][string]$SealSha256,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$ExistingArchiveParts)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($r in @($Seal.Rows)){
        [void]$rows.Add([pscustomobject][ordered]@{
            Ordinal=[int]$r.Ordinal
            SourceEntryId=[string]$r.SourceEntryId
            OriginalOperationId=[string]$r.OriginalOperationId
            OriginalContractSha256=[string]$r.OriginalContractSha256
            FullOriginalWitnessSha256=[string]$r.FullOriginalWitnessSha256
            TargetFolderPath=[string]$r.TargetFolderPath
            AttachmentCount=[int]$r.AttachmentCount
        })
    }
    $m=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3w1.TenOriginalIntentManifest.1'
        RunId=[string]$Seal.RunId
        SourcePst=[string]$Seal.SourcePst
        SealSha256=$SealSha256
        AuditSha256=[string]$Seal.AuditSha256
        PreviewSha256=[string]$Seal.PreviewSha256
        OriginalIndexSha256=[string]$Seal.OriginalIndexSha256
        SourceStoreIdSha256=[string]$Seal.SourceStoreIdSha256
        SourcePstLengthBytes=[long]$Seal.SourcePstLengthBytes
        TargetPstPreview=[string]$Seal.TargetPstPreview
        BatchSize=10
        TotalAttachmentCount=[int]$Seal.TotalAttachmentCount
        ExistingArchiveParts=@($ExistingArchiveParts)
        Rows=@($rows.ToArray())
        OriginalOperationJournalIntentWritten=$false
        MoveClaimed=$false
        RealMailMovePerformed=$false
        OriginalDuplicateIndexWritten=$false
        ArchivePstCreated=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
    $digest=Get-OPA265ARCH3w1PrepareDigest -Manifest $m
    $m | Add-Member -NotePropertyName PrepareDigest -NotePropertyValue $digest
    return $m
}

function Assert-OPA265ARCH3w1ManifestMatchesSeal {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][object]$Seal)
    if([string]$Manifest.RunId -cne [string]$Seal.RunId -or
       [string]$Manifest.SourcePst -cne [string]$Seal.SourcePst -or
       [string]$Manifest.AuditSha256 -cne [string]$Seal.AuditSha256 -or
       [string]$Manifest.PreviewSha256 -cne [string]$Seal.PreviewSha256 -or
       [string]$Manifest.OriginalIndexSha256 -cne [string]$Seal.OriginalIndexSha256 -or
       [string]$Manifest.SourceStoreIdSha256 -cne [string]$Seal.SourceStoreIdSha256 -or
       [long]$Manifest.SourcePstLengthBytes -ne [long]$Seal.SourcePstLengthBytes -or
       [string]$Manifest.TargetPstPreview -cne [string]$Seal.TargetPstPreview -or
       [string]$Manifest.PrepareDigest -cne (Get-OPA265ARCH3w1PrepareDigest -Manifest $Manifest)){
        throw 'ARCH3w1 manifest digest or source sealed provenance invalid.'
    }
    for($i=0;$i -lt 10;$i++){
        $s=$Seal.Rows[$i];$r=$Manifest.Rows[$i]
        if([int]$r.Ordinal -ne [int]$s.Ordinal -or
           [string]$r.SourceEntryId -cne [string]$s.SourceEntryId -or
           [string]$r.OriginalOperationId -cne [string]$s.OriginalOperationId -or
           [string]$r.OriginalContractSha256 -cne [string]$s.OriginalContractSha256 -or
           [string]$r.FullOriginalWitnessSha256 -cne [string]$s.FullOriginalWitnessSha256 -or
           [string]$r.TargetFolderPath -cne [string]$s.TargetFolderPath -or
           [int]$r.AttachmentCount -ne [int]$s.AttachmentCount){
            throw ('ARCH3w1 manifest row differs from sealed ARCH3v full original witness at '+($i+1))
        }
    }
    return $true
}

function Test-OPA265ARCH3w1PreparedReadback {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$ManifestSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256,
          [Parameter(Mandatory=$true)][string]$SealSha256)
    foreach($h in @($ManifestSha256,$JournalSha256,$SealSha256)){
        if($h -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH3w1 Review requires three SHA256 hashes.'}
    }
    if(-not [IO.Directory]::Exists([string]$Layout.Root) -or
       (([IO.File]::GetAttributes([string]$Layout.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       @([IO.Directory]::GetFileSystemEntries([string]$Layout.Root)).Count -ne 2){
        throw 'ARCH3w1 protected real intent directory missing or unexpected content. NO RETRY.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$Layout.Root))
    foreach($p in @([string]$Layout.ManifestPath,[string]$Layout.JournalPath)){
        if(-not [IO.File]::Exists($p) -or
           (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3w1 required original manifest/journal missing or unsafe.'
        }
    }
    $m=Read-OPA265ARCH3cPinnedJson -Path ([string]$Layout.ManifestPath) -ExpectedSha256 $ManifestSha256
    $hist=Get-OPA265ARCH3w1HistoricalEvidence -Part2 ([string]$m.ExistingArchiveParts[1].Path)
    if([string]$m.ExistingArchiveParts[1].Sha256 -cne [string]$hist.SemanticSha256){
        throw 'ARCH3w1 protected manifest Part2 semantic SHA differs from ORIGINAL historical completed pilot.'
    }
    $v=Assert-OPA265ARCH3w1SealedSource -RunId ([string]$Layout.RunId) -SealSha256 $SealSha256 -ExpectedAuditSha256 ([string]$m.AuditSha256) -ExpectedPreviewSha256 ([string]$m.PreviewSha256) -ExpectedOriginalIndexSha256 ([string]$m.OriginalIndexSha256)
    if([string]$m.SealSha256 -cne $SealSha256){throw 'ARCH3w1 source seal hash mismatched protected manifest.'}
    [void](Assert-OPA265ARCH3w1ManifestMatchesSeal -Manifest $m -Seal $v)
    $bytes=[IO.File]::ReadAllBytes([string]$Layout.JournalPath)
    if($bytes.Length -lt 2 -or $bytes[$bytes.Length-1] -ne 10){
        throw 'ARCH3w1 torn original OperationJournal; NO RETRY.'
    }
    if((Get-FileHash -LiteralPath ([string]$Layout.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $JournalSha256){
        throw 'ARCH3w1 original ten Intent journal SHA changed; NO RETRY.'
    }
    $r=Read-OPAOperationJournal -Path ([string]$Layout.JournalPath)
    if([bool]$r.TrailingPartial -or @($r.Events).Count -ne 10){
        throw 'ARCH3w1 original journal must contain exactly 10 sealed Intent events; NO RETRY.'
    }
    $storeId=''
    for($i=0;$i -lt 10;$i++){
        $e=$r.Events[$i];$row=$m.Rows[$i]
        if([string]$e.SchemaVersion -cne '1.0' -or
           [string]$e.Phase -cne 'Intent' -or
           [string]$e.OperationKind -cne 'MailMove' -or
           [long]$e.Sequence -ne ($i+1) -or
           [string]$e.TransactionId -cne ('ARCH3w1-'+[string]$Layout.RunId) -or
           [string]$e.OperationId -cne [string]$row.OriginalOperationId -or
           [string]$e.SourceEntryId -cne [string]$row.SourceEntryId -or
           [string]$e.ArchivePst -cne [string]$m.TargetPstPreview -or
           [string]$e.TargetFolderPath -cne [string]$row.TargetFolderPath -or
           [string]$e.SourceFolderPath -cne '\\info@stios.ru\Входящие' -or
           [string]$e.ArchiveEntryId -cne '' -or
           [string]$e.Message -cne ('ARCH3w1 evidence-only; seal='+$SealSha256+'; fullOriginalWitness='+[string]$row.FullOriginalWitnessSha256+'; no COM Move/MoveClaimed.')){
            throw ('ARCH3w1 original Intent event '+($i+1)+' does not match sealed source; NO RETRY.')
        }
        if($i -eq 0){$storeId=[string]$e.SourceStoreId}
        if([string]$e.SourceStoreId -cne $storeId -or
           (Get-OPA265ARCH2bTextSha256 -Text $storeId) -cne [string]$m.SourceStoreIdSha256){
            throw ('ARCH3w1 original POP3 StoreID drift in journal at '+($i+1))
        }
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3w1.TenOriginalIntentReadback.1'
        Status='TenOriginalOperationJournalRealTestPstIntentsIndependentlyVerifiedNoMove'
        RunId=[string]$m.RunId
        OriginalSealSha256=$SealSha256
        AuditSha256=[string]$m.AuditSha256
        PreviewSha256=[string]$m.PreviewSha256
        OriginalIndexSha256=[string]$m.OriginalIndexSha256
        PrepareDigest=[string]$m.PrepareDigest
        ManifestSha256=$ManifestSha256
        JournalSha256=$JournalSha256
        ManifestPath=[string]$Layout.ManifestPath
        JournalPath=[string]$Layout.JournalPath
        PreparedIntentCount=10
        OriginalJournalEventCount=10
        OriginalArchiveYear=2020
        OriginalArchivePart=3
        TotalAttachmentCount=12
        OriginalFullWitnessesVerified=10
        OriginalOperationJournalIntentWritten=$true
        Part2OriginalArchiveVerifierProven=$true
        Part2BinaryShaExcludedFromPrepareDigest=$true
        OriginalArchivePstCreated=$false
        OriginalDuplicateIndexWritten=$false
        RealMailMovePerformed=$false
        MoveClaimed=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3w1TenOriginalIntent {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Prepare','Review')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [string]$SealSha256='',
        [string]$ExpectedAuditSha256='',
        [string]$ExpectedPreviewSha256='',
        [string]$ExpectedOriginalIndexSha256='',
        [string]$ExpectedPrepareDigest='',
        [string]$ManifestSha256='',
        [string]$JournalSha256='',
        [switch]$ConfirmPrepareIntent
    )
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3w1 requires native Windows PowerShell 5.1.'
    }
    $layout=Get-OPA265ARCH3w1Layout -RunId $RunId
    if($Mode -ceq 'Review'){
        if($ConfirmPrepareIntent -or $ExpectedPrepareDigest -or
           $ExpectedAuditSha256 -or $ExpectedPreviewSha256 -or $ExpectedOriginalIndexSha256){
            throw 'ARCH3w1 Review only accepts RunId, SealSha256, ManifestSha256, JournalSha256.'
        }
        return (Test-OPA265ARCH3w1PreparedReadback -Layout $layout -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256 -SealSha256 $SealSha256)
    }
    if($ExpectedPrepareDigest -and $Mode -cne 'Prepare'){
        throw 'ARCH3w1 ExpectedPrepareDigest can only authorize evidence-only Prepare.'
    }
    $v=Assert-OPA265ARCH3w1SealedSource -RunId $RunId -SealSha256 $SealSha256 -ExpectedAuditSha256 $ExpectedAuditSha256 -ExpectedPreviewSha256 $ExpectedPreviewSha256 -ExpectedOriginalIndexSha256 $ExpectedOriginalIndexSha256
    if([IO.Directory]::Exists([string]$layout.Root) -or [IO.File]::Exists([string]$layout.Root)){
        throw 'ARCH3w1 RunId already contains intent evidence. Do not rerun Prepare; use Review or forensic inspection.'
    }
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst ([string]$v.SourcePst) -RequireExisting
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3w1.Plan.1'
            Status='ExactProtectedArch3vTenRealSourceIntentsPlannedNoOutlookNoWrites'
            RunId=$RunId;SealSha256=$SealSha256
            AuditSha256=$ExpectedAuditSha256
            PreviewSha256=$ExpectedPreviewSha256
            SourcePst=$source;BatchSize=10
            Part2BinaryShaExcludedFromPrepareDigest=$true
            EvidenceRoot=[string]$layout.Root
            OriginalOperationJournalIntentWritten=$false
            OutlookContacted=$false;RealMailMovePerformed=$false
            MoveClaimed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3w1 Audit and Prepare require Windows PowerShell 5.1 STA.'
    }
    if($Mode -ceq 'Prepare' -and -not $ConfirmPrepareIntent){
        throw 'ARCH3w1 Prepare requires explicit -ConfirmPrepareIntent for evidence-only original Journal.'
    }
    if($Mode -ceq 'Prepare' -and $ExpectedPrepareDigest -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3w1 Prepare requires exact previously observed Audit PrepareDigest.'
    }
    if($Mode -ceq 'Prepare' -and -not $PSCmdlet.ShouldProcess([string]$layout.JournalPath,'Persist EXACTLY TEN original OperationJournal Intent entries in private LOCALAPPDATA ONLY, NO MOVE')){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3w1.WhatIf.1'
            Status='TenOriginalPrepareIntentWhatIfNoOutlookNoWrites'
            RunId=$RunId;OriginalOperationJournalIntentWritten=$false
            RealMailMovePerformed=$false;MoveClaimed=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    $before=Get-OPA265ARCH3w1OriginalYearParts -SourcePst $source
    $current=Get-OPA265ARCH3vFullReadOnlyAudit -RunId $RunId -SourcePst $source -ExpectedPreviewSha256 $ExpectedPreviewSha256 -ExpectedSourceStoreIdSha256 ([string]$v.SourceStoreIdSha256) -ExpectedOriginalIndexSha256 $ExpectedOriginalIndexSha256 -ExpectedSourcePstLengthBytes ([long]$v.SourcePstLengthBytes)
    if([string]$current.AuditSha256 -cne $ExpectedAuditSha256 -or
       @($current._Envelope.Rows).Count -ne 10){
        throw 'ARCH3w1 full original ARCH2b ten semantic content changed from protected ARCH3v Seal. STOP.'
    }
    for($i=0;$i -lt 10;$i++){
        $row=$v.Rows[$i];$fresh=$current._Envelope.Rows[$i]
        if([string]$row.SourceEntryId -cne [string]$fresh.SourceEntryId -or
           [string]$row.OriginalContractSha256 -cne [string]$fresh.OriginalContractSha256 -or
           [string]$row.FullOriginalWitnessSha256 -cne [string]$fresh.FullOriginalWitnessSha256){
            throw ('ARCH3w1 original full semantic SHA mismatch at ordinal '+($i+1))
        }
    }
    $after=Get-OPA265ARCH3w1OriginalYearParts -SourcePst $source
    for($i=0;$i -lt 2;$i++){
        if([string]$before[$i].Sha256 -cne [string]$after[$i].Sha256 -or
           [long]$before[$i].LengthBytes -ne [long]$after[$i].LengthBytes){
            throw 'ARCH3w1 original Year2020 archive part changed during full semantic audit.'
        }
    }
    $m=New-OPA265ARCH3w1Manifest -Seal $v -SealSha256 $SealSha256 -ExistingArchiveParts $after
    [void](Assert-OPA265ARCH3w1ManifestMatchesSeal -Manifest $m -Seal $v)
    if($Mode -ceq 'Audit'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3w1.TenOriginalIntentAudit.1'
            Status='ExactTenSealedOriginalWitnessesPermitEvidenceOnlyJournalPrepare'
            RunId=$RunId;SourcePst=$source
            SealSha256=$SealSha256
            AuditSha256=$ExpectedAuditSha256
            PreviewSha256=$ExpectedPreviewSha256
            OriginalIndexSha256=$ExpectedOriginalIndexSha256
            PrepareDigest=[string]$m.PrepareDigest
            ArchiveYear=2020;ArchivePart=3
            TargetPstPreview=[string]$m.TargetPstPreview
            ExistingOriginalArchiveParts=@($after)
            Part2OriginalArchiveVerifierProven=$true
            Part2BinaryShaExcludedFromPrepareDigest=$true
            PreparedIntentCount=0;PlannedIntentCount=10
            FullOriginalWitnessesVerified=10;TotalAttachmentCount=12
            OriginalOperationJournalIntentWritten=$false
            OriginalDuplicateIndexWritten=$false
            ArchivePstCreated=$false;RealMailMovePerformed=$false
            MoveClaimed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    if([string]$m.PrepareDigest -cne $ExpectedPrepareDigest){
        throw 'ARCH3w1 original 10 source archive part or semantic PrepareDigest changed; no evidence writes.'
    }
    # Re-establish real POP3 StoreID for the original journal's canonical
    # SourceStoreId (never use a SHA instead of a COM StoreID).
    $session=$null;$storeId=''
    try{
        $session=Open-OPA265ARCH2dSession -Layout (Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA) -SourcePst $source
        if(-not [bool]$session.Scope.Approved -or [string]$session.Namespace.CurrentProfileName -cne 'Outlook'){
            throw 'ARCH3w1 original POP3 Outlook session no longer approved.'
        }
        $storeId=[string]$session.SourceStore.StoreID
        if((Get-OPA265ARCH2bTextSha256 -Text $storeId) -cne [string]$m.SourceStoreIdSha256 -or
           [string]$session.Inbox.FolderPath -cne '\\info@stios.ru\Входящие'){
            throw 'ARCH3w1 original POP3 StoreID/Inbox changed immediately before durable Intent.'
        }
        if((Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst $source).OriginalIndexSha256 -cne $ExpectedOriginalIndexSha256 -or
           [long]([IO.FileInfo]::new($source)).Length -ne [long]$m.SourcePstLengthBytes -or
           [IO.File]::Exists([string]$m.TargetPstPreview)){
            throw 'ARCH3w1 shared index/sourcePST/Part3 changed immediately before durable Intent.'
        }
        $atWrite=Get-OPA265ARCH3w1OriginalYearParts -SourcePst $source
        for($i=0;$i -lt 2;$i++){
            if([string]$atWrite[$i].Sha256 -cne [string]$after[$i].Sha256 -or
               [long]$atWrite[$i].LengthBytes -ne [long]$after[$i].LengthBytes){
                throw 'ARCH3w1 original archive part changed before Intent.'
            }
        }
        if([IO.Directory]::Exists([string]$layout.Root) -or [IO.File]::Exists([string]$layout.Root)){
            throw 'ARCH3w1 evidence directory appeared concurrently. STOP.'
        }
        # Protected directory + CreateNew manifest BEFORE original journal.
        # A crash is irrevocably visible; an incomplete journal may NOT be
        # continued automatically, regardless of whether it has 1..9 Intents.
        New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout
        $manifestSha=Write-OPA265ARCH3cJsonOnce -Path ([string]$layout.ManifestPath) -Record $m
        foreach($row in @($m.Rows)){
            [void](Write-OPAOperationJournalEvent -Path ([string]$layout.JournalPath) -TransactionId ('ARCH3w1-'+$RunId) -OperationId ([string]$row.OriginalOperationId) -Sequence ([long]$row.Ordinal) -Phase Intent -SourceEntryId ([string]$row.SourceEntryId) -ArchivePst ([string]$m.TargetPstPreview) -SourceStoreId $storeId -SourceFolderPath ([string]$session.Inbox.FolderPath) -TargetFolderPath ([string]$row.TargetFolderPath) -Message ('ARCH3w1 evidence-only; seal='+$SealSha256+'; fullOriginalWitness='+[string]$row.FullOriginalWitnessSha256+'; no COM Move/MoveClaimed.'))
        }
        $journalSha=(Get-FileHash -LiteralPath ([string]$layout.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant()
        return (Test-OPA265ARCH3w1PreparedReadback -Layout $layout -ManifestSha256 $manifestSha -JournalSha256 $journalSha -SealSha256 $SealSha256)
    }finally{Close-OPA265ARCH2dSession -Session $session}
}
