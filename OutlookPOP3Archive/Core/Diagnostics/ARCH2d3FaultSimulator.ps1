#requires -Version 5.1
# ARCH2d3: SELF-CONTAINED synthetic fault-injection model.
# Never connects to Outlook, never opens a PST, never invokes the live writer.
# Uses the actual immutable ARCH2c4 evidence writer and ARCH2d reconciliation
# policy against disposable, bounded caller-supplied synthetic sandbox files.
. (Join-Path $PSScriptRoot '../Archive/ARCH2dBatchPolicy.ps1')

function New-OPA265ARCH2d3Witness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateRange(1,10)][int]$Ordinal)
    $hash={param([string]$value) Get-OPA265ARCH2bTextSha256 -Text $value}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
        ItemClass=43
        InternetMessageIdSha256=(& $hash ('<arch2d3-'+$Ordinal+'@invalid.test>'))
        SubjectSha256=(& $hash ('Синтетика Ω '+$Ordinal))
        SenderSha256=(& $hash 'sender@invalid.test')
        ToSha256=(& $hash 'recipient@invalid.test')
        CcSha256=(& $hash '')
        BccSha256=(& $hash '')
        RecipientCount=0
        OrderedRecipientDigestSha256=(& $hash '')
        BodySha256=(& $hash ('Синтетический оригинал '+$Ordinal))
        BodyUtf16Length=[int](('Синтетический оригинал '+$Ordinal).Length)
        HtmlBodySha256=(& $hash ('<p>Синтетика '+$Ordinal+'</p>'))
        HtmlBodyUtf16Length=[int](('<p>Синтетика '+$Ordinal+'</p>').Length)
        ReceivedUtcTicks=[int64](637792704000000000+$Ordinal*10000000)
        SentUtcTicks=[int64](637792704000000000+$Ordinal*10000000)
        UnRead=$false
        Importance=1
        Sensitivity=0
        CategoriesSha256=(& $hash '')
        AttachmentCount=0
        Attachments=@()
        MailItemSizeDiagnosticBytes=1400
    }
}

function Assert-OPA265ARCH2d3SandboxRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot)
    $path=[IO.Path]::GetFullPath($SandboxRoot)
    $userProfile=[string]$env:USERPROFILE
    $localData=[string]$env:LOCALAPPDATA
    if(-not [IO.Directory]::Exists($path) -or
       (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       $path -match 'OutlookPOP3Archive-ARCH2(?:c4|d)-Real' -or
       $path -match '[\\/]Файлы Outlook(?:[\\/]|$)' -or
       ([string]::Equals($path,[IO.Path]::GetPathRoot($path),[StringComparison]::OrdinalIgnoreCase)) -or
       ($userProfile -and [string]::Equals($path,$userProfile,[StringComparison]::OrdinalIgnoreCase)) -or
       ($localData -and [string]::Equals($path,$localData,[StringComparison]::OrdinalIgnoreCase))){
        throw 'ARCH2d3 synthetic sandbox must be a separate existing regular scratch directory, never a PST directory or profile root.'
    }
    return $path
}

function Invoke-OPA265ARCH2d3SyntheticFault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SandboxRoot,
        [Parameter(Mandatory=$true)]
        [ValidateSet('None','GlobalClaimCollision','GlobalClaimTornWrite','AfterGlobalClaimBeforeFirstItem',
                     'ItemClaimCollision','ItemClaimTornWrite','AfterItemClaimBeforeCom',
                     'ComThrowsWithoutApply','ComAppliesThenThrows','ComReturnsBeforeReceipt',
                     'ReturnReceiptCollision','ReturnReceiptTornWrite','AfterReturnCrash',
                     'ChangedOriginalBeforeGlobalClaim','ChangedOriginalBeforeItemClaim',
                     'ChangedDestinationBody','UnknownSourceProvider','DuplicateDestination',
                     'NoRestart')]
        [string]$Fault,
        [ValidateSet(1,5,10)][int]$FaultAt=5
    )
    $scratch=Assert-OPA265ARCH2d3SandboxRoot -SandboxRoot $SandboxRoot
    # Synthetic sequence has deterministic identities, independent of live
    # mailbox and stored original operator RunIds. New directory per case.
    $caseDir=Join-Path $scratch ('ARCH2d3-SYNTH-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($caseDir)
    $globalPath=Join-Path $caseDir 'ARCH2d-BATCH-ONCE-CLAIM.json'
    $states=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le 10;$i++){
        $w=New-OPA265ARCH2d3Witness -Ordinal $i
        if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $w)){
            throw 'ARCH2d3 synthetic fixture incomplete: stop.'
        }
        $states.Add([pscustomobject]@{
            Ordinal=$i
            SourceEntryId=('1234567890ABCDEF{0:D4}' -f $i)
            OriginalWitness=$w
            DestinationWitness=$null
            SourcePresence=1
            ClaimSha256=''
            ReturnSha256=''
            ClaimPath=(Join-Path $caseDir ('move-{0:D2}-claim.json' -f $i))
            ReturnPath=(Join-Path $caseDir ('move-{0:D2}-return.json' -f $i))
            ComInvocations=0
        })|Out-Null
    }
    $globalSha=''
    $halt='NoFault'
    $failedAt=0
    $beforeGlobal=($Fault -eq 'ChangedOriginalBeforeGlobalClaim')
    if($beforeGlobal){
        $halt='SourcePreflightMismatchBeforeAnyClaim'
        $failedAt=$FaultAt
    }else{
        try {
            if($Fault -eq 'GlobalClaimCollision'){
                [IO.File]::WriteAllBytes($globalPath,[byte[]]@(1))
            }
            if($Fault -eq 'GlobalClaimTornWrite'){
                [IO.File]::WriteAllBytes($globalPath,[byte[]]@(123,34,115,99))
            }
            # Use the actual production immutable writer CreateNew + Flush(true)
            # with exactly the same global-before-individual invariant.
            $globalSha=Write-OPA265ARCH2c4JsonOnce -Path $globalPath -Value ([pscustomobject]@{
                Schema='2.6.5-ARCH2d.BatchOnceClaim.1'
                RunId='77777777-8888-4999-aabb-cccccccccccc'
                ManifestSha256=('b'*64)
                PlannedCount=10
                OneBatchAttemptClaimedBeforeFirstComMove=$true
                AutomaticResumeOrRetryAllowed=$false
            })
            if($Fault -eq 'AfterGlobalClaimBeforeFirstItem'){
                throw 'ARCH2d3 crash injected after global claim before item 1'
            }
            for($i=1;$i -le 10;$i++){
                $row=$states[$i-1]
                if($i -eq $FaultAt -and $Fault -eq 'ChangedOriginalBeforeItemClaim'){
                    throw 'ARCH2d3 simulated source changed after global claim'
                }
                if($i -eq $FaultAt -and $Fault -eq 'ItemClaimCollision'){
                    [IO.File]::WriteAllBytes([string]$row.ClaimPath,[byte[]]@(1))
                }
                if($i -eq $FaultAt -and $Fault -eq 'ItemClaimTornWrite'){
                    [IO.File]::WriteAllBytes([string]$row.ClaimPath,[byte[]]@(123,34,97))
                }
                # Exact same writer that live ARCH2d uses, never overwrites.
                $row.ClaimSha256=Write-OPA265ARCH2c4JsonOnce -Path $row.ClaimPath -Value ([pscustomobject]@{
                    Schema='2.6.5-ARCH2d.IndividualMoveClaim.1'
                    RunId='77777777-8888-4999-aabb-cccccccccccc'
                    Ordinal=$i
                    SourceEntryId=[string]$row.SourceEntryId
                    BatchClaimSha256=$globalSha
                    ClaimedBeforeComMove=$true
                    AutomaticRetryAllowed=$false
                })
                if($i -eq $FaultAt -and $Fault -eq 'AfterItemClaimBeforeCom'){
                    throw 'ARCH2d3 crash injected after durable individual claim before COM call'
                }
                # FAKE COM: no live object, no PST, no source mutation.
                $row.ComInvocations++
                if($i -eq $FaultAt -and $Fault -eq 'ComThrowsWithoutApply'){
                    throw 'ARCH2d3 FAKE COM throws before applying: actual provider outcome unknowable'
                }
                $row.DestinationWitness=Copy-OPA265ARCH2d3Witness -Witness $row.OriginalWitness
                $row.SourcePresence=0
                if($i -eq $FaultAt -and $Fault -eq 'ChangedDestinationBody'){
                    $row.DestinationWitness.BodySha256=Get-OPA265ARCH2bTextSha256 -Text 'CORRUPTED AFTER MOVE'
                }
                if($i -eq $FaultAt -and $Fault -eq 'UnknownSourceProvider'){
                    $row.SourcePresence=-1
                }
                if($i -eq $FaultAt -and $Fault -eq 'ComAppliesThenThrows'){
                    throw 'ARCH2d3 FAKE COM applied then threw: no Return; no retry'
                }
                if($i -eq $FaultAt -and $Fault -eq 'ComReturnsBeforeReceipt'){
                    throw 'ARCH2d3 crash injected after COM success before return journal'
                }
                if($i -eq $FaultAt -and $Fault -eq 'ReturnReceiptCollision'){
                    [IO.File]::WriteAllBytes([string]$row.ReturnPath,[byte[]]@(1))
                }
                if($i -eq $FaultAt -and $Fault -eq 'ReturnReceiptTornWrite'){
                    [IO.File]::WriteAllBytes([string]$row.ReturnPath,[byte[]]@(123,34,120))
                }
                $row.ReturnSha256=Write-OPA265ARCH2c4JsonOnce -Path $row.ReturnPath -Value ([pscustomobject]@{
                    Schema='2.6.5-ARCH2d.MoveReturnObservation.1'
                    RunId='77777777-8888-4999-aabb-cccccccccccc'
                    Ordinal=$i
                    ClaimSha256=[string]$row.ClaimSha256
                    IndependentPostRestartVerificationRequired=$true
                })
                if($i -eq $FaultAt -and $Fault -eq 'AfterReturnCrash'){
                    throw 'ARCH2d3 crash injected after successful return observation'
                }
            }
        } catch {
            $halt=$_.Exception.Message
            # FaultAt=0 is reserved for pre-item global-claim crash/error.
            $failedAt=if($Fault -cin @('GlobalClaimCollision','GlobalClaimTornWrite',
                'AfterGlobalClaimBeforeFirstItem')){0}else{$i}
        }
    }
    $globalValid=$false
    if($globalSha){
        try {
            $saved=Read-OPA265ARCH2c4JsonSealed -Path $globalPath -ExpectedSha256 $globalSha
            $globalValid=([string]$saved.Schema -ceq '2.6.5-ARCH2d.BatchOnceClaim.1' -and
                [bool]$saved.OneBatchAttemptClaimedBeforeFirstComMove -and
                -not [bool]$saved.AutomaticResumeOrRetryAllowed)
        }catch{$globalValid=$false}
    }
    # READ-ONLY independent projection of observable physical state plus
    # checked immutable evidence. A missing receipt does NOT authorize retry.
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $sourceUnknown=0
    $badEvidence=0
    $returnMissingOrBad=0
    foreach($row in @($states.ToArray())){
        $claimed=[IO.File]::Exists([string]$row.ClaimPath)
        $returnPresent=[IO.File]::Exists([string]$row.ReturnPath)
        $claimValid=$false
        if($claimed -and $row.ClaimSha256){
            try {
                $v=Read-OPA265ARCH2c4JsonSealed -Path $row.ClaimPath -ExpectedSha256 $row.ClaimSha256
                $claimValid=([int]$v.Ordinal -eq [int]$row.Ordinal -and
                    [string]$v.SourceEntryId -ceq [string]$row.SourceEntryId -and
                    [string]$v.BatchClaimSha256 -ceq $globalSha -and
                    [bool]$v.ClaimedBeforeComMove -and
                    -not [bool]$v.AutomaticRetryAllowed)
            }catch{$claimValid=$false}
        }
        $returnValid=$false
        if($returnPresent -and $row.ReturnSha256){
            try {
                $v=Read-OPA265ARCH2c4JsonSealed -Path $row.ReturnPath -ExpectedSha256 $row.ReturnSha256
                $returnValid=([int]$v.Ordinal -eq [int]$row.Ordinal -and
                    [string]$v.ClaimSha256 -ceq [string]$row.ClaimSha256)
            }catch{$returnValid=$false}
        }
        if($returnPresent -and -not $returnValid){$badEvidence++}
        if($claimed -and -not $claimValid){$badEvidence++}
        if($claimed -and -not $returnValid){$returnMissingOrBad++}
        if([int]$row.SourcePresence -eq -1){$sourceUnknown++}
        $semanticMatches=$false
        if($null -ne $row.DestinationWitness){
            $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $row.OriginalWitness -Destination $row.DestinationWitness
            $semanticMatches=[bool]$cmp.CriticalContentMatches
        }
        $status='ManualReviewRequired'
        if($globalValid -and $claimValid -and [int]$row.SourcePresence -eq 0 -and $semanticMatches){
            $status='MovedAndSemanticallyMatched'
        }elseif($globalValid -and -not $claimed -and -not $returnPresent -and
            [int]$row.SourcePresence -eq 1 -and $null -eq $row.DestinationWitness){
            $status='NotAttemptedOriginalSourcePresent'
        }
        $rows.Add([pscustomobject][ordered]@{
            Ordinal=[int]$row.Ordinal
            Status=$status
            MoveClaimExists=$claimed
            MoveClaimValid=$claimValid
            MoveReturnExists=$returnPresent
            MoveReturnValid=$returnValid
            OriginalSourcePresentState=[int]$row.SourcePresence
            DestinationSemanticMatches=$semanticMatches
            FakeComInvocationCount=[int]$row.ComInvocations
        })|Out-Null
    }
    $destinationCount=@($states.ToArray()|Where-Object{$null -ne $_.DestinationWitness}).Count
    if($Fault -eq 'DuplicateDestination' -and $destinationCount -gt 0){$destinationCount++}
    $restarted=($Fault -ne 'NoRestart')
    $decision=Get-OPA265ARCH2dReconcileDecision -ItemResults @($rows.ToArray()) -DestinationItemCount $destinationCount -RestartConfirmed $restarted
    if(-not $globalValid -or $badEvidence -gt 0 -or $sourceUnknown -gt 0){
        $decision.Status='ManualReviewRequiredNoAutomaticRetry'
        $decision.IndependentlyVerifiedAllTen=$false
    }
    # A lost Return record can still have proven CONTENT after restart, but
    # completion receipt/whole-batch state must NOT become a clean PASS.
    if($returnMissingOrBad -gt 0 -and [bool]$decision.IndependentlyVerifiedAllTen){
        $decision.Status='ManualReviewRequiredNoAutomaticRetry'
        $decision.IndependentlyVerifiedAllTen=$false
    }
    # Missing restart is a hard blocker for independent verification, not
    # an instruction to rerun the writer.
    $repeatBlocked=[IO.File]::Exists($globalPath) -or [IO.Directory]::Exists($caseDir)
    $result=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d3.SyntheticFaultMatrixCase.1'
        Status=if($halt -eq 'NoFault'){'SyntheticTenAttempted'}else{'SyntheticFaultStopped'}
        Fault=$Fault
        FaultAt=[int]$FaultAt
        HaltReason=$halt
        HaltedAt=[int]$failedAt
        GlobalClaimExists=[IO.File]::Exists($globalPath)
        GlobalClaimValid=$globalValid
        IndividualClaims=@($rows.ToArray()|Where-Object{$_.MoveClaimExists}).Count
        ReturnObservations=@($rows.ToArray()|Where-Object{$_.MoveReturnExists}).Count
        FakeComMoveCalls=@($states.ToArray()|Measure-Object -Property ComInvocations -Sum).Sum
        FakeDestinationCount=$destinationCount
        VerifiedMoved=[int]$decision.VerifiedMoved
        NotAttempted=[int]$decision.NotAttempted
        BadEvidenceCount=$badEvidence
        MissingOrBadReturnCount=$returnMissingOrBad
        ReconcileStatus=[string]$decision.Status
        IndependentlyVerifiedAllTen=[bool]$decision.IndependentlyVerifiedAllTen
        RestartConfirmed=$restarted
        ReplayBlocked=$repeatBlocked
        AutomaticRetryAllowed=$false
        ActualOutlookContacted=$false
        ActualPstReadOrWritten=$false
        TestedHistoricalRealRunId=$false
        ProductionReady=$false
        Rows=@($rows.ToArray())
        SandboxCaseDirectory=$caseDir
    }
    return $result
}

function Copy-OPA265ARCH2d3Witness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness)
    # Simulation only; does not copy Outlook objects or attachments.
    $serialized=ConvertTo-Json -InputObject $Witness -Depth 12 -Compress
    return (ConvertFrom-Json -InputObject $serialized)
}

function Invoke-OPA265ARCH2d3SyntheticMatrix {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxRoot)
    $cases=@(
        'None','GlobalClaimCollision','GlobalClaimTornWrite',
        'AfterGlobalClaimBeforeFirstItem','ItemClaimCollision',
        'ItemClaimTornWrite','AfterItemClaimBeforeCom','ComThrowsWithoutApply',
        'ComAppliesThenThrows','ComReturnsBeforeReceipt','ReturnReceiptCollision',
        'ReturnReceiptTornWrite','AfterReturnCrash','ChangedOriginalBeforeGlobalClaim',
        'ChangedOriginalBeforeItemClaim','ChangedDestinationBody',
        'UnknownSourceProvider','DuplicateDestination','NoRestart'
    )
    $results=New-Object 'System.Collections.Generic.List[object]'
    foreach($fault in $cases){
        foreach($ord in @(1,5,10)){
            $results.Add((Invoke-OPA265ARCH2d3SyntheticFault -SandboxRoot $SandboxRoot -Fault $fault -FaultAt $ord))|Out-Null
        }
    }
    $all=@($results.ToArray())
    if($all.Count -ne 57 -or
       @($all|Where-Object {$_.ActualOutlookContacted -or $_.ActualPstReadOrWritten -or
           $_.AutomaticRetryAllowed -or -not $_.ReplayBlocked}).Count -gt 0){
        throw 'ARCH2d3 synthetic safety invariant failed; STOP.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d3.SyntheticFailureMatrix.1'
        Status='SyntheticFaultMatrixCompletedNoOutlookNoPstNoReplayPermit'
        Cases=$all.Count
        InjectedFaultCases=@($all|Where-Object{$_.Fault -ne 'None'}).Count
        Ordinals=@(1,5,10)
        Scenarios=@($cases)
        ResultRows=$all
        ActualOutlookContacted=$false
        ActualPstReadOrWritten=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
