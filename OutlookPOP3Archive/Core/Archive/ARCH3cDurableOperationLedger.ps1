#requires -Version 5.1
# ARCH3c synthetic-only persisted evidence adapter. Reuses EXISTING
# ARCH3b source->destination contract and OperationJournal. NEVER touches
# Outlook, PSTs, original legacy transaction/index or historic ARCH2 evidence.
. (Join-Path $PSScriptRoot 'ARCH3bOriginalMoverContract.ps1')
. (Join-Path $PSScriptRoot 'OperationJournal.ps1')

function Get-OPA265ARCH3cLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ScratchRoot,
          [Parameter(Mandatory=$true)][object]$Contract)
    if([string]$Contract.Schema -cne '2.6.5-ARCH3b.OperationContract.1' -or
       [string]$Contract.ContractSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Contract.OperationId -cne ('ARCH3b-'+[string]$Contract.ContractSha256) -or
       [bool]$Contract.WriterPermit -or
       [string]$Contract.TransactionId -cnotmatch '^ARCH3C-SYNTHETIC-[a-zA-Z0-9-]{1,64}$'){
        throw 'ARCH3c requires an explicitly synthetic, nonwriting ARCH3b operation contract.'
    }
    # Absolutely constrain the intentional synthetic disk writes to TEMP.
    $scratch=[IO.Path]::GetFullPath($ScratchRoot)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    if(-not $scratch.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       ($scratch.Length -le $temp.Length) -or
       [IO.Path]::GetFileName($scratch) -cnotmatch '^ARCH3C-SYNTHETIC-[a-zA-Z0-9-]{1,64}$'){
        throw 'ARCH3c journal directory must be explicitly named ARCH3C-SYNTHETIC-... under OS TEMP.'
    }
    $sub=$scratch
    if([IO.Directory]::Exists($sub) -and
       (([IO.File]::GetAttributes($sub) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3c synthetic directory cannot be a reparse point.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3c.SyntheticLayout.1'
        Root=$sub
        ContractSha256=[string]$Contract.ContractSha256
        TransactionId=[string]$Contract.TransactionId
        OperationId=[string]$Contract.OperationId
        OperationJournal=(Join-Path $sub 'original-operation-journal.jsonl')
        FinalSeal=(Join-Path $sub 'final-seal.json')
    }
}
function Get-OPA265ARCH3cStageNames {
    return @('PrepareIntent','DestinationReady','SourceWitnessAnchored',
             'MoveClaimed','MoveReturned','IndependentContentVerified',
             'IndexCommitted')
}
function Get-OPA265ARCH3cStagePath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][ValidateSet('PrepareIntent','DestinationReady',
             'SourceWitnessAnchored','MoveClaimed','MoveReturned',
             'IndependentContentVerified','IndexCommitted')][string]$Stage)
    return (Join-Path ([string]$Layout.Root) ($Stage+'.json'))
}
function Write-OPA265ARCH3cJsonOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][object]$Record)
    $json=ConvertTo-Json -InputObject $Record -Depth 12 -Compress -ErrorAction Stop
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($json)
    if($bytes.Length -le 4 -or $bytes.Length -gt 1048576){throw 'ARCH3c synthetic JSON size limit breached.'}
    # No overwrite, ever; even process death leaves a visible non-retry claim.
    $fs=$null
    try{
        $fs=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,
              [IO.FileAccess]::Write,[IO.FileShare]::None)
        $fs.Write($bytes,0,$bytes.Length)
        $fs.Flush($true)
    }finally{if($null -ne $fs){$fs.Dispose()}}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Read-OPA265ARCH3cPinnedJson {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$ExpectedSha256)
    if($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH3c external SHA256 pin must be canonical lowercase.'}
    if(-not [IO.File]::Exists($Path)){throw 'ARCH3c sealed evidence missing.'}
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if($actual -cne $ExpectedSha256){throw 'ARCH3c evidence SHA256 differs from pin.'}
    $data=[IO.File]::ReadAllBytes($Path)
    if($data.Length -gt 1048576){throw 'ARCH3c sealed evidence exceeds limit.'}
    $obj=ConvertFrom-Json -InputObject ((New-Object Text.UTF8Encoding($false,$true)).GetString($data)) -ErrorAction Stop
    if($null -eq $obj -or $obj -is [array]){throw 'ARCH3c sealed evidence is not a JSON object.'}
    return $obj
}
function Invoke-OPA265ARCH3cSyntheticWrite {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Contract,
          [Parameter(Mandatory=$true)][string]$ScratchRoot,
          [Parameter(Mandatory=$true)][bool]$ConfirmSyntheticWrite,
          [ValidateSet('None','PrepareIntent','DestinationReady',
            'SourceWitnessAnchored','MoveClaimed','MoveReturned',
            'IndependentContentVerified','IndexCommitted')][string]$InjectStopAfter='None')
    if(-not $ConfirmSyntheticWrite){throw 'ARCH3c synthetic durable file-write requires explicit opt-in.'}
    $layout=Get-OPA265ARCH3cLayout -ScratchRoot $ScratchRoot -Contract $Contract
    # A run directory already exists => never re-enter; partial evidence
    # must be forensically inspected, never replayed.
    if([IO.Directory]::Exists($layout.Root) -or [IO.File]::Exists($layout.FinalSeal)){
        throw 'ARCH3c synthetic operation directory exists; NO replay/overwrite.'
    }
    [void][IO.Directory]::CreateDirectory($layout.Root)
    $prev=''
    $stageHashes=New-Object 'System.Collections.Generic.List[object]'
    $witnessHash=Get-OPA265ARCH3bDigest -Parts @('ARCH3c SYNTHETIC NO REAL MAIL',$layout.ContractSha256)
    $syntheticDest='00000000FEDCBA9876543210FEDCBA987654321000000001'
    foreach($stage in @(Get-OPA265ARCH3cStageNames)){
        $fields=[ordered]@{
            Schema='2.6.5-ARCH3c.SyntheticStage.1'
            TransactionId=$layout.TransactionId
            OperationId=$layout.OperationId
            ContractSha256=$layout.ContractSha256
            Phase=$stage
            PreviousStageSha256=$prev
            SyntheticOnly=$true
            OriginalOutlookNeverContacted=$true
            SourceWitnessSha256=if($stage -in @('SourceWitnessAnchored','MoveClaimed','MoveReturned','IndependentContentVerified','IndexCommitted')){$witnessHash}else{''}
            ClaimedBeforeComMove=($stage -in @('MoveClaimed','MoveReturned','IndependentContentVerified','IndexCommitted'))
            DestinationEntryId=if($stage -in @('MoveReturned','IndependentContentVerified','IndexCommitted')){$syntheticDest}else{''}
            IndependentRealOutlookRestartVerified=$false
        }
        $path=Get-OPA265ARCH3cStagePath -Layout $layout -Stage $stage
        $prev=Write-OPA265ARCH3cJsonOnce -Path $path -Record ([pscustomobject]$fields)
        $stageHashes.Add([pscustomobject]@{Phase=$stage;Sha256=$prev})|Out-Null
        # Reuse ORIGINAL append-only OperationJournal, not a duplicate.
        # Map prepared Intent and the SYNTHETIC verified point; deliberately
        # no Completed event immediately after MoveReturned, because the
        # original resolver treats Completed as terminal (cannot later append
        # Reconciled). This is explicitly a legacy integration constraint.
        if($stage -ceq 'PrepareIntent'){
            [void](Write-OPAOperationJournalEvent -Path $layout.OperationJournal -TransactionId $layout.TransactionId -OperationId $layout.OperationId -Sequence 1 -Phase Intent -SourceEntryId ([string]$Contract.SourceEntryId) -ArchivePst ([string]$Contract.PlannedArchivePst) -SourceStoreId ([string]$Contract.SourceStoreId) -SourceFolderPath ([string]$Contract.SourceFolderPath) -TargetFolderPath ([string]$Contract.PlannedTargetFolderPath) -Message 'ARCH3c SYNTHETIC ONLY, no real PST or mail.')
        }
        if($stage -ceq 'IndependentContentVerified'){
            [void](Write-OPAOperationJournalEvent -Path $layout.OperationJournal -TransactionId $layout.TransactionId -OperationId $layout.OperationId -Sequence 2 -Phase Reconciled -SourceEntryId ([string]$Contract.SourceEntryId) -ArchiveEntryId $syntheticDest -ArchivePst ([string]$Contract.PlannedArchivePst) -SourceStoreId ([string]$Contract.SourceStoreId) -SourceFolderPath ([string]$Contract.SourceFolderPath) -TargetFolderPath ([string]$Contract.PlannedTargetFolderPath) -Message 'ARCH3c SYNTHETIC simulation, NEVER interpreted as real Reconcile.')
        }
        if($InjectStopAfter -ceq $stage){
            throw ('ARCH3c injected crash AFTER durable synthetic '+$stage+'; no synthetic automatic replay.')
        }
    }
    $journalHash=(Get-FileHash -LiteralPath $layout.OperationJournal -Algorithm SHA256).Hash.ToLowerInvariant()
    $final=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3c.SyntheticFinalSeal.1'
        TransactionId=$layout.TransactionId
        OperationId=$layout.OperationId
        ContractSha256=$layout.ContractSha256
        StageHashes=@($stageHashes.ToArray())
        OriginalOperationJournalSha256=$journalHash
        SyntheticOnly=$true
        OutlookContacted=$false
        PstOpened=$false
        ProductionReady=$false
    }
    $finalSha=Write-OPA265ARCH3cJsonOnce -Path $layout.FinalSeal -Record $final
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3c.SyntheticWritten.1'
        Status='SevenDurableSyntheticStagesAndOriginalOperationJournalSealedNoCom'
        OperationId=$layout.OperationId
        EvidenceRoot=$layout.Root
        StageCount=7
        FinalSealSha256=$finalSha
        OriginalOperationJournalSha256=$journalHash
        OutlookContacted=$false;PstOpened=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}
function Test-OPA265ARCH3cSyntheticEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Contract,
          [Parameter(Mandatory=$true)][string]$ScratchRoot,
          [string]$ExternallyPinnedFinalSealSha256='')
    $layout=Get-OPA265ARCH3cLayout -ScratchRoot $ScratchRoot -Contract $Contract
    $issues=New-Object 'System.Collections.Generic.List[string]'
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $prev=''
    $missing=$false
    $all=@(Get-OPA265ARCH3cStageNames)
    foreach($stage in $all){
        $path=Get-OPA265ARCH3cStagePath -Layout $layout -Stage $stage
        if(-not [IO.File]::Exists($path)){
            $missing=$true
            continue
        }
        if($missing){[void]$issues.Add('NonPrefixStageSequence')}
        try{
            $sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            $record=Read-OPA265ARCH3cPinnedJson -Path $path -ExpectedSha256 $sha
            if([string]$record.Schema -cne '2.6.5-ARCH3c.SyntheticStage.1' -or
               [string]$record.TransactionId -cne $layout.TransactionId -or
               [string]$record.OperationId -cne $layout.OperationId -or
               [string]$record.ContractSha256 -cne $layout.ContractSha256 -or
               [string]$record.Phase -cne $stage -or
               [string]$record.PreviousStageSha256 -cne $prev -or
               -not [bool]$record.SyntheticOnly -or
               -not [bool]$record.OriginalOutlookNeverContacted -or
               [bool]$record.IndependentRealOutlookRestartVerified){
                throw 'Stage identity, order or synthetic safety mismatch.'
            }
            $rows.Add([pscustomobject]@{Phase=$stage;Sha256=$sha})|Out-Null
            $prev=$sha
        }catch{
            [void]$issues.Add(('InvalidStage:'+ $stage))
            $prev='BROKEN-STAGE-'+$stage
        }
    }
    $operationEvents=@()
    $journalHash=''
    if([IO.File]::Exists($layout.OperationJournal)){
        try{
            $journalHash=(Get-FileHash -LiteralPath $layout.OperationJournal -Algorithm SHA256).Hash.ToLowerInvariant()
            $j=Read-OPAOperationJournal -Path $layout.OperationJournal
            $recovery=Resolve-OPAOperationRecovery -Journal $j
            $operationEvents=@($j.Events)
            if($j.TrailingPartial -or @($operationEvents).Count -gt 2 -or
               @($operationEvents).Count -lt 1 -or
               [string]$operationEvents[0].Phase -cne 'Intent' -or
               [string]$operationEvents[0].OperationId -cne $layout.OperationId -or
               [string]$operationEvents[0].TransactionId -cne $layout.TransactionId -or
               [string]$operationEvents[0].SourceEntryId -cne [string]$Contract.SourceEntryId){
                throw 'Original operation journal Intent invalid.'
            }
            if(@($operationEvents).Count -eq 2 -and
               ([string]$operationEvents[1].Phase -cne 'Reconciled' -or
                [string]$operationEvents[1].ArchiveEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
                [string]$operationEvents[1].OperationId -cne $layout.OperationId)){
                throw 'Original operation journal Reconciled invalid.'
            }
            if(@($operationEvents).Count -eq 2 -and
               @($rows.ToArray()|Where-Object{$_.Phase -ceq 'IndependentContentVerified'}).Count -ne 1){
                throw 'Synthetic Reconciled was written without independent-simulation stage.'
            }
        }catch{
            [void]$issues.Add('OriginalOperationJournalInvalidOrTorn')
        }
    }else{[void]$issues.Add('MissingOriginalOperationJournal')}
    $finalExists=[IO.File]::Exists($layout.FinalSeal)
    $finalValid=$false
    if($finalExists){
        try{
            if($ExternallyPinnedFinalSealSha256 -cnotmatch '^[a-f0-9]{64}$'){
                throw 'Externally pinned final SHA256 required.'
            }
            $final=Read-OPA265ARCH3cPinnedJson -Path $layout.FinalSeal -ExpectedSha256 $ExternallyPinnedFinalSealSha256
            if([string]$final.Schema -cne '2.6.5-ARCH3c.SyntheticFinalSeal.1' -or
               [string]$final.OperationId -cne $layout.OperationId -or
               [string]$final.TransactionId -cne $layout.TransactionId -or
               [string]$final.ContractSha256 -cne $layout.ContractSha256 -or
               [string]$final.OriginalOperationJournalSha256 -cne $journalHash -or
               @($final.StageHashes).Count -ne 7 -or
               @($rows.ToArray()).Count -ne 7 -or
               @($operationEvents).Count -ne 2 -or
               -not [bool]$final.SyntheticOnly -or [bool]$final.ProductionReady){
                throw 'Original operation journal/final seal mismatch.'
            }
            for($i=0;$i -lt 7;$i++){
                if([string]$final.StageHashes[$i].Phase -cne [string]$rows[$i].Phase -or
                   [string]$final.StageHashes[$i].Sha256 -cne [string]$rows[$i].Sha256){
                    throw 'Synthetic final seal stage SHA changed.'
                }
            }
            $finalValid=($issues.Count -eq 0)
        }catch{[void]$issues.Add('InvalidOrUnpinnedFinalSeal')}
    }elseif($ExternallyPinnedFinalSealSha256){[void]$issues.Add('FinalSealMissing')}
    $full=($finalValid -and $issues.Count -eq 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3c.SyntheticEvidenceAudit.1'
        Status=if($full){'SyntheticDurableStageAndOriginalJournalChainFullyPinnedNoOutlook'
          }elseif($issues.Count -eq 0){'PartialSyntheticOneShotEvidenceNoRetry'
          }else{'SyntheticEvidenceDiscrepancyManualReviewNoRetry'}
        OperationId=$layout.OperationId
        StageCount=@($rows.ToArray()).Count
        OriginalOperationJournalEventCount=@($operationEvents).Count
        FinalSealPresent=$finalExists
        FinalSealExternallyPinned=$finalValid
        Issues=@($issues.ToArray())
        SyntheticOnly=$true
        OutlookContacted=$false;PstOpened=$false
        LiveMailMoved=$false;IndependentLivePstVerified=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}
