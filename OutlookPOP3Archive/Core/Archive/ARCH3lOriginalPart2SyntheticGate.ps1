#requires -Version 5.1
# ARCH3l: STRICTLY SYNTHETIC Part2 selection boundary called INSIDE
# the ORIGINAL MailMover.Move-OPAItemsWithLimit loop. Does not open Outlook,
# create PST, authorize real writer, sync a DuplicateIndex, or re-run a Move.
# Requires the existing ARCH3d missing-PST TEMP + PSCustomObject scope.
function Assert-OPA265ARCH3lSyntheticPart2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Scope,
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$Candidate,
        [Parameter(Mandatory=$true)][object[]]$ExistingArchiveParts,
        [ValidateSet('BeforeDestination','DestinationReady')][string]$Stage='BeforeDestination',
        [object]$Destination
    )
    if([string]$Scope.Schema -cne '2.6.5-ARCH3d.ProtectedScope.1' -or
       -not [bool]$Scope.SyntheticOnly -or
       [bool]$Scope.RealOutlookObjectAllowed -or
       [bool]$Scope.OriginalPstAllowed -or
       [bool]$Scope.ProductionReady -or
       [string]$Transaction.TransactionId -cne [string]$Scope.TransactionId -or
       [string]$Transaction.State.SourcePst -cne [string]$Scope.SourcePst -or
       [string]$Transaction.State.SourceStoreId -cne 'ARCH3D-SYNTHETIC-NOT-REAL-STORE'){
        throw 'ARCH3l requires the ORIGINAL ARCH3d synthetic-only boundary.'
    }
    $src=[IO.Path]::GetFullPath([string]$Scope.SourcePst)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $parent=[IO.Path]::GetDirectoryName($src)
    if(-not ($parent+[IO.Path]::DirectorySeparatorChar).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($parent) -cne [string]$Scope.TransactionId -or
       [IO.Path]::GetFileName($src) -cne 'info@stios.ru.pst' -or
       [IO.File]::Exists($src) -or
       [IO.Directory]::Exists($src)){
        throw 'ARCH3l refuses real source PST or nonisolated synthetic fixture.'
    }
    if($null -eq $Candidate -or
       [string]$Candidate.EntryID -cnotmatch '^[A-Fa-f0-9]{16,1024}$' -or
       [datetime]$Candidate.ArchiveDate -lt [datetime]'2020-01-01' -or
       [datetime]$Candidate.ArchiveDate -ge [datetime]'2021-01-01' -or
       [string]$Candidate.FolderName -cne 'Входящие'){
        throw 'ARCH3l synthetic 2020 Inbox candidate not pinned.'
    }
    $part1=Get-OPAArchivePartPath -SourcePst $src -Year 2020 -Part 1
    $part2=Get-OPAArchivePartPath -SourcePst $src -Year 2020 -Part 2
    $target=Get-OPAArchiveTargetPath -ReceivedTime ([datetime]$Candidate.ArchiveDate) -SourceFolderName ([string]$Candidate.FolderName) -SourceFolderPath ([string]$Candidate.SourceFolderPath) -Grouping Year
    if($target -cne '2020\Входящие' -or
       @($ExistingArchiveParts).Count -ne 1 -or
       [int]$ExistingArchiveParts[0].Part -ne 1 -or
       [int]$ExistingArchiveParts[0].Year -ne 2020 -or
       -not [string]::Equals([string]$ExistingArchiveParts[0].Path,$part1,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.File]::Exists($part2) -or [IO.Directory]::Exists($part2)){
        throw 'ARCH3l refuses altered original Year Part1/Part2 collision topology.'
    }
    if($Stage -ceq 'DestinationReady'){
        if($null -eq $Destination -or $null -eq $Destination.Folder -or
           -not [string]::Equals([string]$Destination.Path,$part2,[StringComparison]::OrdinalIgnoreCase) -or
           -not ([string]$Destination.Folder.FolderPath).EndsWith(('\'+$target),[StringComparison]::OrdinalIgnoreCase)){
            throw 'ARCH3l ORIGINAL destination selected wrong existing Part1/part/year/folder. Stop BEFORE provider claim.'
        }
    }elseif($null -ne $Destination){
        throw 'ARCH3l before-destination gate cannot receive a destination.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3l.OriginalMoverSyntheticPart2Gate.1'
        Status=if($Stage -ceq 'BeforeDestination'){'BeforeOriginalDestinationProtected'}else{'OriginalPart2AndTargetValidatedBeforeProviderClaim'}
        SourcePst=$src
        OriginalPart1=$part1
        RequiredNewPart2=$part2
        OriginalTargetFolder=$target
        ExistingSharedIndexSyncAllowed=$false
        SourcePstExists=$false
        LiveOutlookAllowed=$false
        SyntheticOnly=$true
        WriterPermit=$false
        ProductionReady=$false
    }
}
