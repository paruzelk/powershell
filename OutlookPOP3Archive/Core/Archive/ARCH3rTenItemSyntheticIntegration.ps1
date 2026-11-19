#requires -Version 5.1
# ARCH3r TEN synthetic mail fixtures. Uses ORIGINAL ARCH2b full semantic
# witness comparer, ORIGINAL operation journal and ORIGINAL shared index.
# NO Outlook COM, MailItem.Move, real PST, real ARCH3j folder or production
# writer. This is a simulated transaction state machine, not an actual
# 10-message Outlook ArchiveVerifier certification.
. (Join-Path $PSScriptRoot 'ARCH3rCompletedPilotCheckpoint.ps1')

function New-OPA265ARCH3rSyntheticWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateRange(1,10)][int]$Number)
    $hash={param([string]$v) Get-OPA265ARCH2bTextSha256 -Text $v}
    $att=New-Object 'System.Collections.Generic.List[object]'
    $attachmentCount=($Number % 3)
    for($i=1;$i -le $attachmentCount;$i++){
        $name=('synthetic-{0}-{1}.bin' -f $Number,$i)
        $bytes=([Text.Encoding]::UTF8).GetBytes(('SYNTHETIC ONLY: payload '+$Number+'/'+$i))
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$payloadHash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        [void]$att.Add([pscustomobject]@{
            Index=$i;Type=1;NameUtf8Sha256=(& $hash $name)
            PayloadByteCount=[int64]$bytes.Length;PayloadSha256=$payloadHash
        })
    }
    $text=('ARCH3r full virtual Body for synthetic mail '+$Number)
    $html=('<html><body><p>ARCH3r synthetic '+$Number+'</p></body></html>')
    $date=[datetime]::new(2020,2,1,12,0,0,[DateTimeKind]::Utc).AddDays($Number)
    $w=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
        ItemClass=43
        InternetMessageIdSha256=(& $hash ('<arch3r-synth-'+$Number+'@invalid>'))
        SubjectSha256=(& $hash ('ARCH3r synthetic '+$Number))
        SenderSha256=(& $hash 'synthetic@example.invalid')
        ToSha256=(& $hash 'to@example.invalid')
        CcSha256=(& $hash '')
        BccSha256=(& $hash '')
        RecipientCount=1
        OrderedRecipientDigestSha256=(& $hash ('1|'+(& $hash 'Synthetic Recipient')+'|'+(& $hash 'to@example.invalid')))
        BodySha256=(& $hash $text)
        BodyUtf16Length=[int]$text.Length
        HtmlBodySha256=(& $hash $html)
        HtmlBodyUtf16Length=[int]$html.Length
        ReceivedUtcTicks=[int64]$date.Ticks
        SentUtcTicks=[int64]$date.AddHours(-2).Ticks
        UnRead=[bool]($Number % 2 -eq 0)
        Importance=1
        Sensitivity=0
        CategoriesSha256=(& $hash 'synthetic')
        AttachmentCount=[int]$att.Count
        Attachments=@($att.ToArray())
        MailItemSizeDiagnosticBytes=[int64](2048+$Number)
    }
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $w)){throw 'ARCH3r synthetic original full semantic witness schema rejected.'}
    return $w
}

function New-OPA265ARCH3rTenSyntheticPlan {
    [CmdletBinding()]
    param([ValidateSet('None','DuplicateSource','DuplicateDestination')][string]$InjectIdentityFault='None')
    $rows=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le 10;$i++){
        $id=('{0:X32}' -f $i)
        $dest=('{0:X32}' -f (40960+$i))
        if($InjectIdentityFault -eq 'DuplicateSource' -and $i -eq 5){$id=('{0:X32}' -f 1)}
        if($InjectIdentityFault -eq 'DuplicateDestination' -and $i -eq 5){$dest=('{0:X32}' -f 40961)}
        $w=New-OPA265ARCH3rSyntheticWitness -Number $i
        [void]$rows.Add([pscustomobject][ordered]@{
            Number=$i;SourceEntryId=$id;ArchiveEntryId=$dest
            SourceFolderPath='\\SYNTHETIC-POP3\Входящие'
            TargetFolderPath='\\SYNTHETIC-ARCHIVE\2020\Входящие'
            Subject=('ARCH3r synthetic '+$i)
            SourceWitness=$w
            OriginalSourceWitnessDigest=Get-OPA265ARCH2bTextSha256 -Text (ConvertTo-Json -InputObject $w -Depth 12 -Compress)
        })
    }
    $sourceSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $archiveSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $rows){
        if(-not $sourceSet.Add([string]$row.SourceEntryId) -or
           -not $archiveSet.Add([string]$row.ArchiveEntryId) -or
           -not (Test-OPA265ARCH2bWitnessSchema -Witness $row.SourceWitness)){
            throw 'ARCH3r synthetic ten-item plan contains duplicate IDs or incomplete full original witness. NO Move.'
        }
    }
    return $rows.ToArray()
}

function Get-OPA265ARCH3rSyntheticSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$JournalPath,
          [Parameter(Mandatory=$true)][string]$FakeArchivePst,
          [Parameter(Mandatory=$true)][int]$Claimed,
          [Parameter(Mandatory=$true)][int]$ProviderInvoked,
          [Parameter(Mandatory=$true)][int]$Compared,
          [Parameter(Mandatory=$true)][string]$Status,
          [Parameter(Mandatory=$true)][string]$Workspace)
    $journal=Read-OPAOperationJournal -Path $JournalPath
    $resolved=Resolve-OPAOperationRecovery -Journal $journal
    $index=Import-OPADuplicateIndex -ArchivePst $FakeArchivePst
    $indexPath=Get-OPADuplicateIndexJournalPath -ArchivePst $FakeArchivePst
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3r.TenSyntheticOriginalJournalIndex.1'
        Status=$Status
        SyntheticWorkspace=$Workspace
        SyntheticPlannedMessages=10;SyntheticMoveClaims=$Claimed
        SyntheticProviderInvocations=$ProviderInvoked
        SyntheticFullSemanticComparisons=$Compared
        OriginalOperationJournalEventCount=@($journal.Events).Count
        OriginalOperationJournalReconciledCount=@($resolved.Resolved | Where-Object {$_.Status -ceq 'Reconciled'}).Count
        OriginalOperationJournalIndeterminateCount=@($resolved.Indeterminate).Count
        OriginalSharedIndexEntryCount=@($index.Entries).Count
        OriginalOperationJournalSha256=(Get-FileHash -LiteralPath $JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
        OriginalSharedIndexSha256=if([IO.File]::Exists($indexPath)){(Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()}else{''}
        OriginalJournalFunctionsUsed=$true
        OriginalDuplicateIndexFunctionsUsed=$true
        OriginalFullSemanticComparatorUsed=$true
        OriginalArchiveVerifierOutlookCOMExecuted=$false
        SyntheticClaimsDurablyFlushed=$true
        AutomaticMoveRetryAllowed=$false
        RealOutlookContacted=$false;RealPstOpenedOrWritten=$false
        RealOperationJournalOrDuplicateIndexWritten=$false
        WriterPermit=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3rSyntheticTen {
    [CmdletBinding()]
    param(
        [ValidateSet('None','DuplicateSource','DuplicateDestination','HtmlDrift','AttachmentDrift',
          'ProviderUnknown','AfterClaimBeforeProvider','AfterJournalReconciled','AfterIndexAppend')][string]$InjectFault='None',
        [ValidateRange(1,10)][int]$FaultAt=4,
        [string]$SyntheticTempRoot=[IO.Path]::GetTempPath()
    )
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $base=[IO.Path]::GetFullPath($SyntheticTempRoot)
    if(-not $base.EndsWith([IO.Path]::DirectorySeparatorChar)){ $base += [IO.Path]::DirectorySeparatorChar }
    if(-not $base.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       -not [IO.Directory]::Exists($base) -or
       (([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3r synthetic root MUST be existing OS TEMP subdirectory, not real PST directories.'
    }
    $identity=if($InjectFault -cin @('DuplicateSource','DuplicateDestination')){$InjectFault}else{'None'}
    $rows=@(New-OPA265ARCH3rTenSyntheticPlan -InjectIdentityFault $identity)
    $root=Join-Path $base ('OPA265-ARCH3r-SYNTH-'+[guid]::NewGuid().ToString('N'))
    if([IO.Directory]::Exists($root) -or [IO.File]::Exists($root)){throw 'ARCH3r synthetic workspace collision.'}
    [void][IO.Directory]::CreateDirectory($root)
    $journalPath=Join-Path $root 'synthetic-original-operation-journal.jsonl'
    $fakeArchivePst=Join-Path $root 'SYNTHETIC-NOT-A-REAL-PST.pst'
    $run='ARCH3r-SYNTH-'+[guid]::NewGuid().ToString('N')
    $nClaim=0;$nProvider=0;$nCompared=0
    try {
        # Original append-only operation journal Intent for ten unique
        # immutable full semantic records. No real provider actions.
        foreach($item in $rows){
            [void](Write-OPAOperationJournalEvent -Path $journalPath -TransactionId $run -OperationId ($run+'-'+$item.Number) -Sequence ([long]$item.Number) -Phase Intent -SourceEntryId $item.SourceEntryId -ArchivePst $fakeArchivePst -SourceFolderPath $item.SourceFolderPath -TargetFolderPath $item.TargetFolderPath -Subject $item.Subject)
        }
        $rj=Read-OPAOperationJournal -Path $journalPath
        if(@($rj.Events).Count -ne 10 -or [bool]$rj.TrailingPartial){throw 'ARCH3r original synthetic ten Intent journal readback invalid.'}
        foreach($item in $rows){
            $claim=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH3r.SyntheticMoveClaim.1';TransactionId=$run
                SourceEntryId=[string]$item.SourceEntryId
                PlannedArchiveEntryId=[string]$item.ArchiveEntryId
                OriginalSemanticWitnessSha256=[string]$item.OriginalSourceWitnessDigest
                SyntheticOnly=$true;AutomaticMoveRetryAllowed=$false;WriterPermit=$false
            }
            $claimPath=Join-Path $root ('SYNTH-MoveClaim-'+$item.Number+'.json')
            $claimSha=Write-OPA265ARCH3cJsonOnce -Path $claimPath -Record $claim
            [void](Read-OPA265ARCH3cPinnedJson -Path $claimPath -ExpectedSha256 $claimSha)
            $nClaim++
            if($InjectFault -ceq 'AfterClaimBeforeProvider' -and $item.Number -eq $FaultAt){
                return (Get-OPA265ARCH3rSyntheticSnapshot -JournalPath $journalPath -FakeArchivePst $fakeArchivePst -Claimed $nClaim -ProviderInvoked $nProvider -Compared $nCompared -Status 'SimulatedAfterClaimUnknownNoAutomaticRetry' -Workspace $root)
            }
            $provider=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH3r.SyntheticProviderInvocation.1'
                SourceEntryId=[string]$item.SourceEntryId
                MoveClaimSha256=$claimSha
                SyntheticOnly=$true;AutomaticMoveRetryAllowed=$false;WriterPermit=$false
            }
            $providerPath=Join-Path $root ('SYNTH-ProviderInvocation-'+$item.Number+'.json')
            $providerSha=Write-OPA265ARCH3cJsonOnce -Path $providerPath -Record $provider
            [void](Read-OPA265ARCH3cPinnedJson -Path $providerPath -ExpectedSha256 $providerSha)
            $nProvider++
            if($InjectFault -ceq 'ProviderUnknown' -and $item.Number -eq $FaultAt){
                return (Get-OPA265ARCH3rSyntheticSnapshot -JournalPath $journalPath -FakeArchivePst $fakeArchivePst -Claimed $nClaim -ProviderInvoked $nProvider -Compared $nCompared -Status 'SimulatedProviderUnknownOriginalJournalIntentOnlyNoReplay' -Workspace $root)
            }
        }
        # Provider is never called; this stage only SIMULATES it. Independently
        # build all destination full witnesses and compare through ORIGINAL
        # ARCH2b function before any original Reconciled/index append.
        foreach($item in $rows){
            $destination=New-OPA265ARCH3rSyntheticWitness -Number ([int]$item.Number)
            if($InjectFault -ceq 'HtmlDrift' -and $item.Number -eq $FaultAt){
                $destination.HtmlBodySha256=Get-OPA265ARCH2bTextSha256 -Text 'HTML DRIFT SYNTHETIC'
            }
            if($InjectFault -ceq 'AttachmentDrift' -and $item.Number -eq $FaultAt){
                if([int]$destination.AttachmentCount -le 0){throw 'ARCH3r attachment drift fixture needs item with attachments.'}
                $destination.Attachments[0].PayloadSha256=Get-OPA265ARCH2bTextSha256 -Text 'ATTACHMENT DRIFT SYNTHETIC'
            }
            $compare=Compare-OPA265ARCH2bMailSemanticWitness -Source $item.SourceWitness -Destination $destination
            $nCompared++
            if(-not [bool]$compare.CriticalContentMatches -or @($compare.IssueCodes).Count -gt 0){
                return (Get-OPA265ARCH3rSyntheticSnapshot -JournalPath $journalPath -FakeArchivePst $fakeArchivePst -Claimed $nClaim -ProviderInvoked $nProvider -Compared $nCompared -Status 'SimulatedCriticalContentMismatchNoOriginalJournalOrIndexCommit' -Workspace $root)
            }
        }
        # Synthetic-only independent semantic evidence gate.  No original
        # ArchiveVerifier COM execution is asserted at this stage.
        $reconciled=0
        foreach($item in $rows){
            [void](Write-OPAOperationJournalEvent -Path $journalPath -TransactionId $run -OperationId ($run+'-'+$item.Number) -Sequence ([long](10+$item.Number)) -Phase Reconciled -SourceEntryId $item.SourceEntryId -ArchiveEntryId $item.ArchiveEntryId -ArchivePst $fakeArchivePst -SourceFolderPath $item.SourceFolderPath -TargetFolderPath $item.TargetFolderPath -Subject $item.Subject -Message 'SYNTHETIC ONLY NO REAL OUTLOOK MOVE OR VERIFIER')
            $reconciled++
            if($InjectFault -ceq 'AfterJournalReconciled' -and $item.Number -eq $FaultAt){
                return (Get-OPA265ARCH3rSyntheticSnapshot -JournalPath $journalPath -FakeArchivePst $fakeArchivePst -Claimed $nClaim -ProviderInvoked $nProvider -Compared $nCompared -Status 'SimulatedPartiallyReconciledOriginalJournalNoIndexNoAutoRetry' -Workspace $root)
            }
        }
        $checked=Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $journalPath)
        if(@($checked.Resolved).Count -ne 10 -or @($checked.Indeterminate).Count -ne 0){
            throw 'ARCH3r original ten-item postsemantic journal recovery resolver failed.'
        }
        $index=Import-OPADuplicateIndex -ArchivePst $fakeArchivePst
        if(@($index.Entries).Count -ne 0){throw 'ARCH3r synthetic original index not empty before verified transaction.'}
        $old=$global:OPADurabilityMode
        try {
            $global:OPADurabilityMode='Safe'
            foreach($item in $rows){
                Add-OPADuplicateEntry -Index $index -SourceEntryId $item.SourceEntryId -ArchiveEntryId $item.ArchiveEntryId -SourceFolderPath $item.SourceFolderPath -TargetFolderPath $item.TargetFolderPath -ReceivedTime ([datetime]::new(2020,2,1,12,0,0,[DateTimeKind]::Utc).AddDays($item.Number)) -Subject $item.Subject -TransactionId $run -TransactionLimit 10 -ArchiveGrouping Year -SourcePst (Join-Path $root 'SYNTHETIC-NOT-A-REAL-SOURCE.pst') -ArchivePst $fakeArchivePst
                Sync-OPADuplicateJournalStreams
                if($InjectFault -ceq 'AfterIndexAppend' -and $item.Number -eq $FaultAt){
                    return (Get-OPA265ARCH3rSyntheticSnapshot -JournalPath $journalPath -FakeArchivePst $fakeArchivePst -Claimed $nClaim -ProviderInvoked $nProvider -Compared $nCompared -Status 'SimulatedPartialOriginalIndexAppendNoAutoReplay' -Workspace $root)
                }
            }
        }finally{
            Close-OPADuplicateJournalStreams
            $global:OPADurabilityMode=$old
        }
        $result=Get-OPA265ARCH3rSyntheticSnapshot -JournalPath $journalPath -FakeArchivePst $fakeArchivePst -Claimed $nClaim -ProviderInvoked $nProvider -Compared $nCompared -Status 'AllTenSyntheticFullSemanticAndOriginalJournalIndexReadbackPassedNoLiveWriter' -Workspace $root
        if([int]$result.OriginalOperationJournalReconciledCount -ne 10 -or
           [int]$result.OriginalSharedIndexEntryCount -ne 10 -or
           [int]$result.OriginalOperationJournalEventCount -ne 20){
            throw 'ARCH3r synthetic original ten-item final readback inconsistent.'
        }
        $reloaded=Import-OPADuplicateIndex -ArchivePst $fakeArchivePst
        foreach($item in $rows){
            $entry=Test-OPADuplicateEntry -Index $reloaded -SourceEntryId $item.SourceEntryId
            if($null -eq $entry -or
               [string]$entry.ArchiveEntryId -cne [string]$item.ArchiveEntryId -or
               [string]$entry.ArchivePst -cne $fakeArchivePst){
                throw 'ARCH3r simulated original 10-item duplicate index independent readback mismatch.'
            }
        }
        return $result
    }finally{
        Close-OPADuplicateJournalStreams
    }
}
