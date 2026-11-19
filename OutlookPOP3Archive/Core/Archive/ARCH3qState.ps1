#requires -Version 5.1
# ARCH3q original journal / original shared index state after REAL ARCH3p.
# Read-only, including after original Reconciled. Never a MailItem.Move.
. (Join-Path $PSScriptRoot 'ARCH3pIndependentPostRestartOriginalVerifier.ps1')

function Get-OPA265ARCH3qState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256)
    [void](Assert-OPA265ARCH3pOperatorPin -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256)
    $l=Get-OPA265ARCH3jLayout -RunId $RunId
    if(-not [IO.Directory]::Exists([string]$l.Root) -or
       (([IO.File]::GetAttributes([string]$l.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'ARCH3q protected operator evidence root unsafe.'}
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath ([string]$l.Root))
    $allowed=@('original-prepare-intent.json','original-operation-journal.jsonl',
       'ARCH3o-WriterEntry.json','ARCH3o-DestinationReady.json','ARCH3o-MoveClaimed.json',
       'ARCH3o-ProviderInvocation.json','ARCH3o-MoveReturned.json','ARCH3q-IndependentReview.json',
       'ARCH3q-CommitClaim.json','ARCH3q-IndexCommitted.json')
    foreach($f in @([IO.Directory]::GetFileSystemEntries([string]$l.Root))){
        if($allowed -cnotcontains [IO.Path]::GetFileName($f) -or
           -not [IO.File]::Exists($f) -or
           (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3q unknown or redirected protected evidence; forensic STOP.'
        }
    }
    $i=Read-OPA265ARCH3cPinnedJson -Path ([string]$l.IntentPath) -ExpectedSha256 $IntentSha256
    if([string]$i.Schema -cne '2.6.5-ARCH3j.RealTestPstPrepareIntent.1' -or
       [string]$i.RunId -cne $RunId -or
       [string]$i.SourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00' -or
       [string]$i.NewArchivePst -cne 'C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.Archive-2020-02.pst' -or
       [string]$i.FullOriginalWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c' -or
       [string]$i.OriginalContractSha256 -cne '2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88' -or
       [bool]$i.WriterPermit -or [bool]$i.LiveMovePerformed){throw 'ARCH3q original operator Intent changed.'}
    $raw=[IO.File]::ReadAllBytes([string]$l.JournalPath)
    $j=Read-OPAOperationJournal -Path ([string]$l.JournalPath)
    $e=@($j.Events)
    if([bool]$j.TrailingPartial -or $e.Count -notin @(1,2) -or
       [string]$e[0].Phase -cne 'Intent' -or [long]$e[0].Sequence -ne 1 -or
       [string]$e[0].OperationId -cne [string]$i.OperationId -or
       [string]$e[0].TransactionId -cne ('ARCH3j-'+$RunId) -or
       [string]$e[0].SourceEntryId -cne [string]$i.SourceEntryId){throw 'ARCH3q original journal not exactly Intent/optional Reconciled.'}
    $len=0
    for($n=0;$n -lt $raw.Length;$n++){if($raw[$n] -eq 10){$len=$n+1;break}}
    if($len -le 0){throw 'ARCH3q original Intent newline absent.'}
    $prefix=New-Object byte[] $len
    [Array]::Copy($raw,0,$prefix,0,$len)
    if((Get-OPAOperationJournalSha256 -Bytes $prefix) -cne $JournalSha256){
        throw 'ARCH3q original Intent byte prefix does not match immutable SHA.'
    }
    if($e.Count -eq 2 -and
       ([string]$e[1].Phase -cne 'Reconciled' -or [long]$e[1].Sequence -ne 2 -or
        [string]$e[1].OperationId -cne [string]$i.OperationId -or
        [string]$e[1].TransactionId -cne ('ARCH3j-'+$RunId) -or
        [string]$e[1].SourceEntryId -cne [string]$i.SourceEntryId -or
        [string]$e[1].ArchiveEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000' -or
        [string]$e[1].ArchivePst -cne [string]$i.NewArchivePst)){
        throw 'ARCH3q journal Reconciled does not match protected real Move.'
    }
    if(-not [IO.File]::Exists([string]$i.ExistingArchivePart1) -or
       [IO.FileInfo]::new([string]$i.ExistingArchivePart1).Length -ne 271360 -or
       -not [IO.File]::Exists([string]$i.NewArchivePst) -or
       [IO.FileInfo]::new([string]$i.NewArchivePst).Length -le 0){
        throw 'ARCH3q existing Part1 drift or real Part2 not found.'
    }
    $indexDir=Join-Path ([IO.Path]::GetDirectoryName([string]$i.ExistingArchivePart1)) 'OutlookPOP3Archive-Transactions'
    if(-not [IO.Directory]::Exists($indexDir) -or
       (([IO.File]::GetAttributes($indexDir) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3q original shared DuplicateIndex path unsafe.'
    }
    $gate=Get-OPA265ARCH3jIndexSafety -Part1 ([string]$i.ExistingArchivePart1) -SourceEntryId ([string]$i.SourceEntryId)
    $index=Import-OPADuplicateIndex -ArchivePst ([string]$i.ExistingArchivePart1)
    $count=@($index.Entries).Count
    $entry=Test-OPADuplicateEntry -Index $index -SourceEntryId ([string]$i.SourceEntryId)
    if(($count -notin @(500,501)) -or
       ($count -eq 500 -and ($null -ne $entry -or -not [bool]$gate.Approved)) -or
       ($count -eq 501 -and ($null -eq $entry -or
           [string]$entry.ArchiveEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000' -or
           [string]$entry.ArchivePst -cne [string]$i.NewArchivePst))){
        throw 'ARCH3q original shared DuplicateIndex 500/501 state invalid.'
    }
    $proof=Join-Path ([string]$l.Root) 'ARCH3q-IndependentReview.json'
    $claim=Join-Path ([string]$l.Root) 'ARCH3q-CommitClaim.json'
    $seal=Join-Path ([string]$l.Root) 'ARCH3q-IndexCommitted.json'
    if((($e.Count -eq 2 -or $count -eq 501) -and
        (-not [IO.File]::Exists($proof) -or -not [IO.File]::Exists($claim))) -or
       ([IO.File]::Exists($seal) -and ($e.Count -ne 2 -or $count -ne 501))){
        throw 'ARCH3q original journal/index advanced without immutable commit chain.'
    }
    return [pscustomobject]@{
        Layout=$l;Intent=$i;Journal=$j;JournalPhase=[string]$e[-1].Phase
        JournalSha256=(Get-FileHash -LiteralPath ([string]$l.JournalPath) -Algorithm SHA256).Hash.ToLowerInvariant()
        Index=$index;IndexCount=$count;ExistingIndexEntry=$entry
        ProofPath=$proof;ClaimPath=$claim;SealPath=$seal
        ProofExists=[IO.File]::Exists($proof);ClaimExists=[IO.File]::Exists($claim);SealExists=[IO.File]::Exists($seal)
    }
}

function Assert-OPA265ARCH3qOriginalJournalReconciled {
    param([Parameter(Mandatory=$true)][object]$State)
    if([string]$State.JournalPhase -cne 'Reconciled' -or @($State.Journal.Events).Count -ne 2){
        throw 'ARCH3q original Reconciled event not found.'
    }
    $resolved=Resolve-OPAOperationRecovery -Journal $State.Journal
    if(@($resolved.Resolved).Count -ne 1 -or [string]$resolved.Resolved[0].Status -cne 'Reconciled'){
        throw 'ARCH3q original recovery resolver could not verify single Reconciled.'
    }
    return $true
}
