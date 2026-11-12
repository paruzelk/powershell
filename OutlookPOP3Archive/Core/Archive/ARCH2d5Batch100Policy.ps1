#requires -Version 5.1
# ARCH2d5 dedicated 100-mail real POP3 pilot. Pure policy and immutable
# SHA256 chain audit. Original ARCH2d ten-mail writer remains unchanged.
. (Join-Path $PSScriptRoot 'ARCH2dBatchCore.ps1')

function Get-OPA265ARCH2d5Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    $g=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$g) -or $g -eq [guid]::Empty -or
       $g.ToString('D') -cne $RunId){throw 'ARCH2d5 requires canonical lowercase GUID RunId.'}
    $local=[IO.Path]::GetFullPath($LocalAppData)
    if(-not [IO.Directory]::Exists($local) -or $local.StartsWith('\\') -or
       (([IO.File]::GetAttributes($local) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2d5 local APPDATA must exist, not be UNC/reparse.'
    }
    $root=Join-Path $local 'OutlookPOP3Archive-ARCH2d5-RealBatch100'
    $dir=Join-Path $root ('run-'+$RunId)
    $base='OPA265-ARCH2d5-'+$RunId
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d5.Layout.1';RunId=$RunId;Root=$root
        RunDirectory=$dir
        ArchivePst=(Join-Path $dir ($base+'.pst'))
        ArchiveFolder=$base
        IntentPath=(Join-Path $dir 'prepare-intent.json')
        ManifestPath=(Join-Path $dir 'pre-move-manifest.json')
        GlobalClaimPath=(Join-Path $root 'ARCH2d5-BATCH100-ONCE-CLAIM.json')
        FinalSealPath=(Join-Path $dir 'batch-final-seal.json')
        AccountEmail='info@stios.ru';ProfileName='Outlook'
        BatchSize=100
        WriterPermit=$false;ProductionReady=$false
    }
}
function Assert-OPA265ARCH2d5Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout)
    $expected=Get-OPA265ARCH2d5Layout -RunId ([string]$Layout.RunId) -LocalAppData $env:LOCALAPPDATA
    foreach($name in @('Root','RunDirectory','ArchivePst','ArchiveFolder','IntentPath','ManifestPath',
        'GlobalClaimPath','FinalSealPath','AccountEmail','ProfileName')){
        if([string]$Layout.$name -cne [string]$expected.$name){throw ('ARCH2d5 forged layout: '+$name)}
    }
    foreach($path in @($Layout.Root,$Layout.RunDirectory,$Layout.ArchivePst,
        $Layout.IntentPath,$Layout.ManifestPath,$Layout.GlobalClaimPath,$Layout.FinalSealPath)){
        if(([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) -and
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH2d5 reparse artifact forbidden.'
        }
    }
    if([int]$Layout.BatchSize -ne 100){throw 'ARCH2d5 exactly 100 originals.'}
    return $true
}
function Get-OPA265ARCH2d5ItemPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][ValidateRange(1,100)][int]$Ordinal,
          [ValidateSet('Claim','Return')][string]$Kind='Claim')
    return (Join-Path ([string]$Layout.RunDirectory) ('move-{0:D3}-{1}.json' -f $Ordinal,$Kind.ToLowerInvariant()))
}
function Get-OPA265ARCH2d5CheckpointPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][ValidateRange(10,100)][int]$ThroughOrdinal)
    if($ThroughOrdinal % 10 -ne 0){throw 'ARCH2d5 checkpoint only after full multiple of ten.'}
    return Join-Path ([string]$Layout.RunDirectory) ('checkpoint-{0:D3}-seal.json' -f $ThroughOrdinal)
}
function Assert-OPA265ARCH2d5EntryIds {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$EntryIds)
    if(@($EntryIds).Count -ne 100){throw 'ARCH2d5 requires EXACTLY 100 pinned existing Inbox EntryIDs.'}
    $set=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($id in $EntryIds){
        if([string]$id -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or -not $set.Add([string]$id)){
            throw 'ARCH2d5 malformed or duplicated real source EntryID.'
        }
    }
    return $true
}
function Assert-OPA265ARCH2d5Approval {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Prepare','MoveBatch')][string]$Action,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][bool]$Confirmed,
          [Parameter(Mandatory=$true)][string]$ApprovalText)
    $expected=$Action.ToUpperInvariant()+' ARCH2D5 '+$RunId
    if(-not $Confirmed -or $ApprovalText -cne $expected){
        throw ('ARCH2d5 explicit one-time operator approval required: '+$expected)
    }
    return $true
}
function Assert-OPA265ARCH2d5Manifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$SourceStoreId,
          [Parameter(Mandatory=$true)][string]$SourceFolderId)
    if([string]$Manifest.Schema -cne '2.6.5-ARCH2d5.PreMoveManifest.1' -or
       [string]$Manifest.RunId -cne [string]$Layout.RunId -or
       [string]$Manifest.SourcePst -cne $SourcePst -or
       [string]$Manifest.ArchivePst -cne [string]$Layout.ArchivePst -or
       [string]$Manifest.ArchiveFolder -cne [string]$Layout.ArchiveFolder -or
       [string]$Manifest.SourceStoreId -cne $SourceStoreId -or
       [string]$Manifest.SourceFolderId -cne $SourceFolderId -or
       [string]$Manifest.ArchiveStoreId -ceq $SourceStoreId -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.ArchiveFolderId) -or
       [int]$Manifest.PrepareOutlookProcessId -le 0 -or
       [int64]$Manifest.PrepareOutlookProcessStartUtcTicks -le 0 -or
       [int]$Manifest.BatchSize -ne 100 -or
       [bool]$Manifest.WriterPermit -or [bool]$Manifest.ProductionReady -or
       [string]$Manifest.IntentSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d5 sealed 100-mail manifest source, archive or schema mismatch.'
    }
    $items=@($Manifest.Items)
    if($items.Count -ne 100){throw 'ARCH2d5 manifest must contain exactly 100 items.'}
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $sigs=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    for($i=0;$i -lt 100;$i++){
        $row=$items[$i]
        if($null -eq $row -or [int]$row.Ordinal -ne $i+1 -or
           [string]$row.SourceEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
           -not $ids.Add([string]$row.SourceEntryId) -or
           -not (Test-OPA265ARCH2bWitnessSchema -Witness $row.SourceSemanticWitness)){
            throw ('ARCH2d5 invalid or duplicate original at ordinal '+($i+1))
        }
        $sig=Get-OPA265ARCH2dSemanticSignature -Witness $row.SourceSemanticWitness
        if([string]$row.SemanticSignature -cne $sig -or -not $sigs.Add($sig)){
            throw ('ARCH2d5 ambiguous/duplicate semantic match at ordinal '+($i+1))
        }
    }
    return $true
}
function Read-OPA265ARCH2d5CurrentJson {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    # Current hash alone is NOT an independently anchored historical hash.
    if(-not [IO.File]::Exists($Path)){throw 'ARCH2d5 missing piece of sealed chain.'}
    $sha=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    $record=Read-OPA265ARCH2c4JsonSealed -Path $Path -ExpectedSha256 $sha
    if($null -eq $record -or $record -is [array]){throw 'ARCH2d5 nonobject journal.'}
    return [pscustomobject]@{Record=$record;CurrentSha256=$sha}
}
function Read-OPA265ARCH2d5BaseEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$ManifestSha256,
          [Parameter(Mandatory=$true)][string]$BatchClaimSha256)
    if($ManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $BatchClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d5 operator-pinned manifest and global claim SHA256 required.'
    }
    $manifest=Read-OPA265ARCH2c4JsonSealed -Path $Layout.ManifestPath -ExpectedSha256 $ManifestSha256
    [void](Assert-OPA265ARCH2d5Manifest -Manifest $manifest -Layout $Layout -SourcePst $SourcePst -SourceStoreId ([string]$manifest.SourceStoreId) -SourceFolderId ([string]$manifest.SourceFolderId))
    $intent=Read-OPA265ARCH2c4JsonSealed -Path $Layout.IntentPath -ExpectedSha256 ([string]$manifest.IntentSha256)
    if([string]$intent.Schema -cne '2.6.5-ARCH2d5.PrepareIntent.1' -or
       [string]$intent.RunId -cne [string]$Layout.RunId -or
       [string]$intent.SourcePst -cne $SourcePst -or
       [string]$intent.DestinationPst -cne [string]$Layout.ArchivePst -or
       [string]$intent.SourceStoreId -cne [string]$manifest.SourceStoreId -or
       [string]$intent.SourceFolderId -cne [string]$manifest.SourceFolderId -or
       [int]$intent.PlannedCount -ne 100 -or
       @($intent.SourceEntryIds).Count -ne 100 -or
       -not [bool]$intent.NewTargetOnly -or
       [bool]$intent.AutomaticPrepareRetryAllowed){
        throw 'ARCH2d5 original anchored Prepare intent mismatch.'
    }
    for($i=0;$i -lt 100;$i++){
        if([string]$intent.SourceEntryIds[$i] -cne [string]$manifest.Items[$i].SourceEntryId){
            throw 'ARCH2d5 source ordinal changed since original Prepare.'
        }
    }
    $global=Read-OPA265ARCH2c4JsonSealed -Path $Layout.GlobalClaimPath -ExpectedSha256 $BatchClaimSha256
    if([string]$global.Schema -cne '2.6.5-ARCH2d5.BatchOnceClaim.1' -or
       [string]$global.RunId -cne [string]$Layout.RunId -or
       [string]$global.ManifestSha256 -cne $ManifestSha256 -or
       [string]$global.SourcePst -cne $SourcePst -or
       [int]$global.PlannedCount -ne 100 -or
       [int]$global.MoveProcessId -le 0 -or
       [int64]$global.MoveProcessStartUtcTicks -le 0 -or
       -not [bool]$global.ClaimedBeforeAnyMove -or
       [bool]$global.AutomaticRetryAllowed){
        throw 'ARCH2d5 global once-only claim mismatch.'
    }
    return [pscustomobject]@{
        Manifest=$manifest
        GlobalClaim=$global
        ManifestSha256=$ManifestSha256
        BatchClaimSha256=$BatchClaimSha256
    }
}
function Read-OPA265ARCH2d5FullChain {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][object]$Base,
          [string]$FinalSealSha256='')
    if($FinalSealSha256 -and $FinalSealSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d5 supplied final seal SHA256 must be canonical lowercase.'
    }
    $manifest=$Base.Manifest
    $globalSha=[string]$Base.BatchClaimSha256
    $issues=New-Object 'System.Collections.Generic.List[string]'
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $checkpointHashes=New-Object 'System.Collections.Generic.List[string]'
    $previousReceipt=''
    $previousCheckpoint=''
    $priorClaimMissing=$false
    $priorReturnMissing=$false
    $priorCheckpointMissing=$false
    $originalReturnedIds=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    for($i=1;$i -le 100;$i++){
        $orig=$manifest.Items[$i-1]
        $claimPath=Get-OPA265ARCH2d5ItemPath -Layout $Layout -Ordinal $i
        $returnPath=Get-OPA265ARCH2d5ItemPath -Layout $Layout -Ordinal $i -Kind Return
        $claimExists=[IO.File]::Exists($claimPath)
        $returnExists=[IO.File]::Exists($returnPath)
        $claimStatus='Missing';$returnStatus='Missing'
        $claimSha='';$receiptSha='';$returnedId=''
        $itemIssues=New-Object 'System.Collections.Generic.List[string]'
        if($claimExists){
            if($priorClaimMissing){$itemIssues.Add('NonPrefixClaimSequence')|Out-Null}
            try {
                $c=Read-OPA265ARCH2d5CurrentJson -Path $claimPath
                $claim=$c.Record;$claimSha=[string]$c.CurrentSha256
                if([string]$claim.Schema -cne '2.6.5-ARCH2d5.IndividualClaim.1' -or
                   [string]$claim.RunId -cne [string]$Layout.RunId -or
                   [int]$claim.Ordinal -ne $i -or
                   [string]$claim.ManifestSha256 -cne [string]$Base.ManifestSha256 -or
                   [string]$claim.BatchClaimSha256 -cne $globalSha -or
                   [string]$claim.SourceEntryId -cne [string]$orig.SourceEntryId -or
                   [string]$claim.SourceStoreId -cne [string]$manifest.SourceStoreId -or
                   [string]$claim.ArchiveStoreId -cne [string]$manifest.ArchiveStoreId -or
                   [string]$claim.ArchiveFolderId -cne [string]$manifest.ArchiveFolderId -or
                   [string]$claim.PreviousReceiptSha256 -cne $previousReceipt -or
                   [string]$claim.PreviousCheckpointSha256 -cne $previousCheckpoint -or
                   -not [bool]$claim.ClaimedBeforeMove -or [bool]$claim.AutomaticRetryAllowed){
                    throw 'Individual claim broken chain or identity.'
                }
                $claimStatus='ValidChainLink'
            }catch{
                $claimStatus='Invalid'
                $itemIssues.Add('InvalidItemClaimOrChain')|Out-Null
            }
        }else{$priorClaimMissing=$true}
        if($returnExists){
            if($priorReturnMissing){$itemIssues.Add('NonPrefixReturnSequence')|Out-Null}
            if(-not $claimExists){$itemIssues.Add('ReturnWithoutClaim')|Out-Null}
            try{
                $r=Read-OPA265ARCH2d5CurrentJson -Path $returnPath
                $receipt=$r.Record;$receiptSha=[string]$r.CurrentSha256
                $returnedId=[string]$receipt.DestinationEntryId
                if([string]$receipt.Schema -cne '2.6.5-ARCH2d5.MoveReturn.1' -or
                   [string]$receipt.RunId -cne [string]$Layout.RunId -or
                   [int]$receipt.Ordinal -ne $i -or
                   [string]$receipt.ClaimSha256 -cne $claimSha -or
                   [string]$receipt.PreviousReceiptSha256 -cne $previousReceipt -or
                   [string]$receipt.ArchiveStoreId -cne [string]$manifest.ArchiveStoreId -or
                   [string]$receipt.ArchiveFolderId -cne [string]$manifest.ArchiveFolderId -or
                   $returnedId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
                   $claimStatus -cne 'ValidChainLink' -or
                   -not [bool]$receipt.IndependentRestartReviewRequired -or
                   [bool]$receipt.ProductionReady){
                    throw 'Receipt is incomplete, unverifiable or not linked.'
                }
                if(-not $originalReturnedIds.Add($returnedId)){
                    throw 'Duplicate returned destination EntryId.'
                }
                $returnStatus='ValidChainLink'
            }catch{
                $returnStatus='Invalid'
                $itemIssues.Add('InvalidOrTornReturnReceipt')|Out-Null
            }
        }else{$priorReturnMissing=$true}
        if($returnStatus -eq 'ValidChainLink'){$previousReceipt=$receiptSha}
        elseif($returnExists){$previousReceipt='BROKEN_CHAIN_AT_'+$i}
        if($i % 10 -eq 0){
            $checkpointPath=Get-OPA265ARCH2d5CheckpointPath -Layout $Layout -ThroughOrdinal $i
            $checkpointExists=[IO.File]::Exists($checkpointPath)
            if($checkpointExists){
                if($priorCheckpointMissing){$itemIssues.Add('NonPrefixCheckpointSequence')|Out-Null}
                try {
                    $cp=Read-OPA265ARCH2d5CurrentJson -Path $checkpointPath
                    $rec=$cp.Record
                    if([string]$rec.Schema -cne '2.6.5-ARCH2d5.CheckpointSeal.1' -or
                       [string]$rec.RunId -cne [string]$Layout.RunId -or
                       [int]$rec.ThroughOrdinal -ne $i -or
                       [string]$rec.BatchClaimSha256 -cne $globalSha -or
                       [string]$rec.ManifestSha256 -cne [string]$Base.ManifestSha256 -or
                       [string]$rec.LastReceiptSha256 -cne $previousReceipt -or
                       [string]$rec.PreviousCheckpointSha256 -cne $previousCheckpoint -or
                       $returnStatus -cne 'ValidChainLink' -or
                       -not [bool]$rec.SealedAfterReceipt){
                        throw 'Checkpoint seal chain mismatch.'
                    }
                    $previousCheckpoint=[string]$cp.CurrentSha256
                    $checkpointHashes.Add($previousCheckpoint)|Out-Null
                }catch{
                    $itemIssues.Add('InvalidCheckpointSeal')|Out-Null
                    $previousCheckpoint='BROKEN_CHECKPOINT_'+$i
                    $checkpointHashes.Add('')|Out-Null
                }
            }else{
                $itemIssues.Add('MissingCheckpointSeal')|Out-Null
                $priorCheckpointMissing=$true
                $checkpointHashes.Add('')|Out-Null
                $previousCheckpoint='MISSING_CHECKPOINT_'+$i
            }
        }
        $status=if($itemIssues.Count -gt 0){'InvalidEvidence'
        }elseif($claimStatus -eq 'ValidChainLink' -and $returnStatus -eq 'ValidChainLink'){'ClaimReturnChainLinked'
        }elseif($claimStatus -eq 'ValidChainLink'){'ClaimWithoutValidReturn'
        }elseif(-not $claimExists -and -not $returnExists){'NotClaimed'}else{'InvalidEvidence'}
        foreach($problem in @($itemIssues.ToArray())){
            $issues.Add(('Item'+('{0:D3}' -f $i)+':'+$problem))|Out-Null
        }
        $rows.Add([pscustomobject][ordered]@{
            Ordinal=$i
            SourceEntryId=[string]$orig.SourceEntryId
            SemanticSignature=[string]$orig.SemanticSignature
            ClaimStatus=$claimStatus;ReturnStatus=$returnStatus
            ClaimExists=$claimExists;ReturnExists=$returnExists
            ClaimCurrentSha256=$claimSha;ReturnCurrentSha256=$receiptSha
            DestinationEntryId=$returnedId
            EvidenceStatus=$status
            IssueCodes=@($itemIssues.ToArray())
        })|Out-Null
    }
    $fullLinked=@($rows.ToArray()|Where-Object {$_.EvidenceStatus -ceq 'ClaimReturnChainLinked'}).Count
    $anyIssues=($issues.Count -gt 0)
    $finalPresent=[IO.File]::Exists([string]$Layout.FinalSealPath)
    $finalValidated=$false
    $finalHash=''
    if($finalPresent){
        try{
            if($FinalSealSha256){
                $final=Read-OPA265ARCH2c4JsonSealed -Path $Layout.FinalSealPath -ExpectedSha256 $FinalSealSha256
                $finalHash=$FinalSealSha256
            }else{
                $current=Read-OPA265ARCH2d5CurrentJson -Path $Layout.FinalSealPath
                $final=$current.Record;$finalHash=$current.CurrentSha256
            }
            if([string]$final.Schema -cne '2.6.5-ARCH2d5.BatchFinalSeal.1' -or
               [string]$final.RunId -cne [string]$Layout.RunId -or
               [string]$final.ManifestSha256 -cne [string]$Base.ManifestSha256 -or
               [string]$final.BatchClaimSha256 -cne $globalSha -or
               [int]$final.CompletedCount -ne 100 -or
               [string]$final.LastReceiptSha256 -cne $previousReceipt -or
               [string]$final.LastCheckpointSha256 -cne $previousCheckpoint -or
               @($final.CheckpointSha256).Count -ne 10){
                throw 'Invalid final 100-mail seal.'
            }
            for($i=0;$i -lt 10;$i++){
                if([string]$final.CheckpointSha256[$i] -cne [string]$checkpointHashes[$i]){
                    throw 'Final seal references different checkpoint.'
                }
            }
            $finalValidated=($fullLinked -eq 100 -and -not $anyIssues)
            if(-not $finalValidated){throw 'Final seal exists but claimed/return/checkpoint chain incomplete.'}
        }catch{
            $issues.Add('InvalidFinalSealOrHash')|Out-Null
            $finalValidated=$false
        }
    }elseif($FinalSealSha256){
        $issues.Add('OperatorPinnedFinalSealMissing')|Out-Null
    }
    $fullVerified=($fullLinked -eq 100 -and $finalValidated -and
        -not $anyIssues -and $FinalSealSha256 -and $issues.Count -eq 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d5.SealedReceiptChainAudit.1'
        RunId=[string]$Layout.RunId
        ManifestSha256=[string]$Base.ManifestSha256
        BatchClaimSha256=$globalSha
        FinalSealSha256=$finalHash
        FinalSealPresent=$finalPresent
        FinalSealValid=$finalValidated
        FinalSealExternallyPinned=([bool]$FinalSealSha256 -and $finalValidated)
        AllHundredChainVerified=[bool]$fullVerified
        Items=@($rows.ToArray())
        Problems=@($issues.ToArray())
        LinkedItems=$fullLinked
        Claimed=@($rows.ToArray()|Where-Object {$_.ClaimExists}).Count
        Returned=@($rows.ToArray()|Where-Object {$_.ReturnExists}).Count
        CheckpointCount=@($checkpointHashes.ToArray()|Where-Object {$_ -match '^[a-f0-9]{64}$'}).Count
        CheckpointSha256=@($checkpointHashes.ToArray())
        LastReceiptSha256=$previousReceipt
        PerItemClaimsAndReceiptsChainAnchoredByFinalSeal=$fullVerified
        AutomaticRetryAllowed=$false;ProductionReady=$false
    }
}
