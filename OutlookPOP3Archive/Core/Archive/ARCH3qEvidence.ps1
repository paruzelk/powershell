#requires -Version 5.1
# ARCH3q independent real ARCH3p review sealing and original SHA chain.
. (Join-Path $PSScriptRoot 'ARCH3qState.ps1')

function Get-OPA265ARCH3qPinnedStages {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$State)
    $expected=[ordered]@{
        'ARCH3o-WriterEntry.json'='3c2754eede8fddf17943549924a990dbef56cf1a681647343acd194766bd2d69'
        'ARCH3o-DestinationReady.json'='25fedcfead0d38471f54b564867a10cc33958867e6bd923668df0f3594991398'
        'ARCH3o-MoveClaimed.json'='2d43dc624c5f58293c74aafee0772af097f84d3fb1fd8940621e9db92006ae70'
        'ARCH3o-ProviderInvocation.json'='ac0d0cde82869cc47e58d31d3ac677227a9cb03ef4982b69e859cd5009fd4bb9'
        'ARCH3o-MoveReturned.json'='f76ef15fa88000ad747f5fba3b385c5b033ada3978828bbf7a6b71aa8140f2d8'
    }
    $items=@{}
    foreach($name in $expected.Keys){
        $path=Join-Path ([string]$State.Layout.Root) $name
        if(-not [IO.File]::Exists($path) -or
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw ('ARCH3q original protected stage missing/redirected: '+$name)
        }
        $items[$name]=Read-OPA265ARCH3cPinnedJson -Path $path -ExpectedSha256 ([string]$expected[$name])
    }
    $w=$items['ARCH3o-WriterEntry.json']
    $d=$items['ARCH3o-DestinationReady.json']
    $c=$items['ARCH3o-MoveClaimed.json']
    $v=$items['ARCH3o-ProviderInvocation.json']
    $r=$items['ARCH3o-MoveReturned.json']
    if([string]$w.Schema -cne '2.6.5-ARCH3o.WriterEntry.1' -or
       [string]$d.Schema -cne '2.6.5-ARCH3o.DestinationReady.1' -or
       [string]$c.Schema -cne '2.6.5-ARCH3o.RealOneShotMoveClaim.1' -or
       [string]$v.Schema -cne '2.6.5-ARCH3o.ProviderInvocation.1' -or
       [string]$r.Schema -cne '2.6.5-ARCH3o.MoveReturned.1' -or
       [string]$c.WriterEntrySha256 -cne [string]$expected['ARCH3o-WriterEntry.json'] -or
       [string]$d.WriterEntrySha256 -cne [string]$expected['ARCH3o-WriterEntry.json'] -or
       [string]$c.DestinationReadySha256 -cne [string]$expected['ARCH3o-DestinationReady.json'] -or
       [string]$v.ClaimSha256 -cne [string]$expected['ARCH3o-MoveClaimed.json'] -or
       [string]$r.MoveClaimSha256 -cne [string]$expected['ARCH3o-MoveClaimed.json'] -or
       [string]$r.ProviderInvocationSha256 -cne [string]$expected['ARCH3o-ProviderInvocation.json'] -or
       [string]$r.ArchiveEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000' -or
       [string]$r.OriginalWitnessSha256 -cne [string]$State.Intent.FullOriginalWitnessSha256 -or
       [string]$r.OriginalContractSha256 -cne [string]$State.Intent.OriginalContractSha256 -or
       [string]$c.SourceEntryId -cne [string]$State.Intent.SourceEntryId -or
       [string]$v.SourceEntryId -cne [string]$State.Intent.SourceEntryId -or
       [string]$r.SourceEntryId -cne [string]$State.Intent.SourceEntryId -or
       [string]$r.NewArchivePst -cne [string]$State.Intent.NewArchivePst -or
       [string]$c.DestinationStoreId -cne [string]$d.DestinationStoreId -or
       [string]$c.DestinationFolderEntryId -cne [string]$d.DestinationFolderEntryId -or
       [string]$v.DestinationFolderEntryId -cne [string]$c.DestinationFolderEntryId -or
       [string]$r.DestinationStoreId -cne [string]$c.DestinationStoreId -or
       [string]$r.DestinationFolderEntryId -cne [string]$c.DestinationFolderEntryId -or
       -not [bool]$c.OperatorApprovedOneRealMove -or
       [bool]$c.AutomaticRetryAllowed -or [bool]$r.DuplicateIndexWritten -or
       [bool]$r.OriginalJournalReconciled){
        throw 'ARCH3q exact original ARCH3o full staged SHA chain invalid.'
    }
    $sealed=Get-OPA265ARCH3jSealedSource -SealRunId ([string]$State.Intent.SourceSealRunId) -SealSha256 ([string]$State.Intent.SourceSealSha256)
    [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $sealed.OriginalWitness -ExpectedOriginalWitnessSha256 ([string]$State.Intent.FullOriginalWitnessSha256))
    if([string]$sealed.SourceEntryId -cne [string]$State.Intent.SourceEntryId -or
       [string]$sealed.SourceFolderEntryId -cne [string]$State.Intent.SourceFolderEntryId -or
       [string]$sealed.SourceStoreIdSha256 -cne [string]$State.Intent.SourceStoreIdSha256){
        throw 'ARCH3q original ARCH3i source full semantic seal mismatch.'
    }
    return [pscustomobject]@{
        Writer=$w;Ready=$d;Claim=$c;Invocation=$v;Receipt=$r
        Sealed=$sealed
        MoveClaimSha256=[string]$expected['ARCH3o-MoveClaimed.json']
        ProviderInvocationSha256=[string]$expected['ARCH3o-ProviderInvocation.json']
        MoveReceiptSha256=[string]$expected['ARCH3o-MoveReturned.json']
    }
}

function New-OPA265ARCH3qLiveChain {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$State)
    # Direct call to original independent ARCH3p verifier, bypassing its
    # precommit Intent-only reader after original journal Reconciled.
    $o=Get-OPA265ARCH3qPinnedStages -State $State
    return [pscustomobject]@{
        Claim=$o.Claim;OriginalIntent=$State.Intent;Sealed=$o.Sealed;MoveReturned=$o.Receipt
        MoveClaimSha256=[string]$o.MoveClaimSha256
        ProviderInvocationSha256=[string]$o.ProviderInvocationSha256
        MoveReceiptSha256=[string]$o.MoveReceiptSha256
    }
}

function Assert-OPA265ARCH3qLiveReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$State)
    if([string]$Review.Schema -cne '2.6.5-ARCH3p.IndependentRealOutlookOriginalVerifierReview.1' -or
       [string]$Review.Status -cne 'IndependentRealOutlookRestartOriginalArchiveVerifierSourceAbsentArchiveOneFullSemanticMatch' -or
       [string]$Review.RunId -cne [string]$State.Intent.RunId -or
       [string]$Review.OriginalMoveClaimSha256 -cne '2d43dc624c5f58293c74aafee0772af097f84d3fb1fd8940621e9db92006ae70' -or
       [string]$Review.OriginalProviderInvocationSha256 -cne 'ac0d0cde82869cc47e58d31d3ac677227a9cb03ef4982b69e859cd5009fd4bb9' -or
       [string]$Review.OriginalMoveReceiptSha256 -cne 'f76ef15fa88000ad747f5fba3b385c5b033ada3978828bbf7a6b71aa8140f2d8' -or
       [string]$Review.OriginalSourceEntryId -cne [string]$State.Intent.SourceEntryId -or
       [string]$Review.ObservedDestinationEntryId -cne '00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000' -or
       [string]$Review.ArchivePst -cne [string]$State.Intent.NewArchivePst -or
       [string]$Review.OriginalWitnessSha256 -cne [string]$State.Intent.FullOriginalWitnessSha256 -or
       [int]$Review.OriginalVerifierDestinationCount -ne 1 -or
       -not [bool]$Review.OriginalVerifierSourceIdAbsent -or
       -not [bool]$Review.OriginalVerifierSemanticMatch -or
       -not [bool]$Review.OriginalArchiveVerifierUsed -or
       -not [bool]$Review.RealOutlookRestartConfirmed -or
       [int]$Review.ReopenedOutlookProcessId -le 0 -or
       [int]$Review.ReopenedOutlookProcessId -eq [int]$Review.OriginalMoveOutlookProcessId -or
       [long]$Review.ReopenedOutlookProcessStartUtcTicks -le [long]$Review.OriginalMoveOutlookProcessStartUtcTicks -or
       [bool]$Review.AutomaticMoveRetryAllowed -or [bool]$Review.DuplicateIndexWritten -or
       [bool]$Review.OriginalOperationJournalReconciled){
        throw 'ARCH3q independent original real ARCH3p verifier result invalid.'
    }
    return $true
}

function Get-OPA265ARCH3qReviewSeal {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$State,
          [Parameter(Mandatory=$true)][string]$ReviewSha256)
    $p=Read-OPA265ARCH3cPinnedJson -Path ([string]$State.ProofPath) -ExpectedSha256 $ReviewSha256
    if([string]$p.Schema -cne '2.6.5-ARCH3q.IndependentRealReviewSeal.1' -or
       [string]$p.RunId -cne [string]$State.Intent.RunId -or
       [string]$p.OriginalIntentSha256 -cne 'f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b' -or
       [string]$p.OriginalJournalIntentSha256 -cne 'a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e' -or
       [string]$p.OriginalMoveClaimSha256 -cne '2d43dc624c5f58293c74aafee0772af097f84d3fb1fd8940621e9db92006ae70' -or
       [bool]$p.ProductionReady){
        throw 'ARCH3q immutable postrestart original-review record invalid.'
    }
    [void](Assert-OPA265ARCH3qLiveReview -Review $p.Review -State $State)
    [void](Get-OPA265ARCH3qPinnedStages -State $State)
    return $p
}
