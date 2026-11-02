#requires -Version 5.1
# BW4k7f: exact disposable Attachment1K, source-only semantically sealed, no Move.
. (Join-Path $PSScriptRoot 'BW4k7eImmutableSemanticSnapshot265.ps1')

function Assert-OPA265BW4k7fEvidencePins {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Verified)
    if([string]$Verified.Schema -cne '2.6.5-BW4k7e.IndependentSourceSnapshotVerify.1' -or
       [string]$Verified.Status -cne 'OriginalRecipientStateSnapshotVerifiedNoWriterPermit' -or
       [string]$Verified.SnapshotSha256 -cne 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac' -or
       [string]$Verified.RecipientDigestSha256 -cne '11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024' -or
       [string]$Verified.UserStateDigestSha256 -cne '2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'){
        throw 'BW4k7f original independently verified semantic source snapshot pin mismatch.'
    }
    foreach($field in @('WriterPermit','OutlookMoveExecuted','ProductionReady')){
        if($Verified.$field -isnot [bool] -or $Verified.$field){
            throw ('BW4k7f forged source writer permit '+$field)
        }
    }
    return $true
}

function Assert-OPA265BW4k7fExactEmptyTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Observed)
    $names=@('SuiteId','TestId','SourceEntryId','SourceFolderEntryId',
        'SourceStoreId','DestinationStoreId','DestinationPstLeaf',
        'DestinationRootEntryId','DestinationFolderEntryId',
        'DestinationFolderParentEntryId','DestinationFolderStoreId',
        'DestinationFolderName','MatchedTargetNamedFolderCount',
        'DestinationFolderItemCount','SourceMessageIdMatches',
        'DestinationMessageIdMatches','AttemptClaimExists','LegacyClaimExists')
    foreach($n in $names){
        if($Observed.PSObject.Properties.Name -cnotcontains $n){
            throw ('BW4k7f destination evidence incomplete: '+$n)
        }
    }
    if(@($Observed.PSObject.Properties.Name).Count -ne $names.Count -or
       [string]$Observed.SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       [string]$Observed.TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       [string]$Observed.SourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35A46D3C00' -or
       [string]$Observed.SourceFolderEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A3582800000' -or
       [string]$Observed.DestinationPstLeaf -cne 'OPA265-BW4j-74912f94d52348569efdd5528a92426f-87e72fd09e774098a403cbe99870b9e7.pst' -or
       [string]$Observed.DestinationFolderName -cne 'OPA265-BW4j-87e72fd09e774098a403cbe99870b9e7'){
        throw 'BW4k7f wrong exact original fixture or destination PST/folder.'
    }
    foreach($field in @('SourceStoreId','DestinationStoreId','DestinationRootEntryId',
        'DestinationFolderEntryId','DestinationFolderParentEntryId','DestinationFolderStoreId')){
        if([string]::IsNullOrWhiteSpace([string]$Observed.$field)){
            throw ('BW4k7f empty Outlook opaque identity '+$field)
        }
    }
    if([string]$Observed.SourceStoreId -ceq [string]$Observed.DestinationStoreId -or
       [string]$Observed.DestinationFolderStoreId -cne [string]$Observed.DestinationStoreId -or
       [string]$Observed.DestinationFolderParentEntryId -cne [string]$Observed.DestinationRootEntryId -or
       [string]$Observed.DestinationFolderEntryId -ceq [string]$Observed.SourceFolderEntryId -or
       [int]$Observed.MatchedTargetNamedFolderCount -ne 1 -or
       [int]$Observed.DestinationFolderItemCount -ne 0 -or
       [int]$Observed.SourceMessageIdMatches -ne 1 -or
       [int]$Observed.DestinationMessageIdMatches -ne 0 -or
       $Observed.AttemptClaimExists -isnot [bool] -or $Observed.AttemptClaimExists -or
       $Observed.LegacyClaimExists -isnot [bool] -or $Observed.LegacyClaimExists){
        throw 'BW4k7f source-one/destination-zero empty-PST preflight blocked; no Move.'
    }
    return $true
}

function Assert-OPA265BW4k7fStableEmptyTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$First,
          [Parameter(Mandatory=$true)][psobject]$Second)
    [void](Assert-OPA265BW4k7fExactEmptyTarget -Observed $First)
    [void](Assert-OPA265BW4k7fExactEmptyTarget -Observed $Second)
    foreach($n in $First.PSObject.Properties.Name){
        if([string]$First.$n -cne [string]$Second.$n){
            throw ('BW4k7f destination changed between read-only reviews: '+$n)
        }
    }
    return $true
}
