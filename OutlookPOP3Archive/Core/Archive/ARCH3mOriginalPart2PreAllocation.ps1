#requires -Version 5.1
# ARCH3m: called by the ORIGINAL MailMover destination selector before any
# target PST allocation, only with ARCH3d+ARCH3l fake TEMP protected scope.
# No Outlook COM, no real source PST and NO production writer permit.
function Assert-OPA265ARCH3mSyntheticPreAllocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$Scope,
        [Parameter(Mandatory=$true)][object]$Candidate,
        [Parameter(Mandatory=$true)][object[]]$ExistingArchiveParts,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][datetime]$ReceivedTime,
        [Parameter(Mandatory=$true)][string]$SourceFolderName,
        [Parameter(Mandatory=$true)][string]$SourceFolderPath,
        [Parameter(Mandatory=$true)][string]$AccountEmail
    )
    # Revalidate the original fake scope ON EACH destination call, not only
    # once in the parent loop. No caller can bypass with a forged switch.
    if($null -eq $Namespace -or $Namespace.GetType().FullName -cne 'System.Management.Automation.PSCustomObject' -or
       -not [bool]$Namespace.Synthetic -or
       $null -eq $Scope -or
       [string]$Scope.Schema -cne '2.6.5-ARCH3d.ProtectedScope.1' -or
       -not [bool]$Scope.SyntheticOnly -or
       [bool]$Scope.RealOutlookObjectAllowed -or
       [bool]$Scope.OriginalPstAllowed -or
       [bool]$Scope.ProductionReady){
        throw 'ARCH3m refuses real Outlook COM or forged original synthetic boundary.'
    }
    if([string]$Transaction.TransactionId -cne [string]$Scope.TransactionId -or
       [string]$Transaction.State.SourcePst -cne [string]$Scope.SourcePst -or
       [string]$Transaction.State.SourceStoreId -cne 'ARCH3D-SYNTHETIC-NOT-REAL-STORE' -or
       [string]$Transaction.State.ArchiveGrouping -cne 'Year' -or
       [string]$Transaction.State.AccountEmail -cne 'info@stios.ru' -or
       $SourceFolderName -cne 'Входящие' -or
       $SourceFolderPath -cne [string]$Candidate.SourceFolderPath -or
       $AccountEmail -cne 'info@stios.ru' -or
       $ReceivedTime.Ticks -ne ([datetime]$Candidate.ReceivedTime).Ticks -or
       $ReceivedTime.Year -ne 2020 -or
       $SourcePst -cne [string]$Scope.SourcePst){
        throw 'ARCH3m candidate/source/original synthetic operation identity drift.'
    }
    $source=[IO.Path]::GetFullPath($SourcePst)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    $dir=[IO.Path]::GetDirectoryName($source)
    if(-not ($dir+[IO.Path]::DirectorySeparatorChar).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($dir) -cne [string]$Scope.TransactionId -or
       [IO.Path]::GetFileName($source) -cne 'info@stios.ru.pst' -or
       [IO.File]::Exists($source) -or [IO.Directory]::Exists($source)){
        throw 'ARCH3m synthetic source must be a MISSING fake TEMP PST.'
    }
    if([int]$Transaction.State.Limit -ne 1 -or
       @($Transaction.State.ArchivePsts).Count -ne 0 -or
       [string]$Transaction.State.ArchivePst -ne '' -or
       [string]$Transaction.State.CurrentArchivePst -ne ''){
        throw 'ARCH3m requires pristine original one-message synthetic transaction.'
    }
    # Reuse ARCH3l's original Year naming, topology and nested folder checks
    # BEFORE New-OPAArchivePst / AddStoreEx is even reachable.
    $checked=Assert-OPA265ARCH3lSyntheticPart2 -Scope $Scope -Transaction $Transaction -Candidate $Candidate -ExistingArchiveParts $ExistingArchiveParts -Stage BeforeDestination
    $part1=[string]$checked.OriginalPart1
    $part2=[string]$checked.RequiredNewPart2
    $onDisk=@(Get-OPAArchivePstPartsOnDisk -SourcePst $source -Year 2020)
    if($onDisk.Count -gt 0 -and
       ($onDisk.Count -ne 1 -or [int]$onDisk[0].Part -ne 1 -or
       -not [string]::Equals([string]$onDisk[0].Path,$part1,[StringComparison]::OrdinalIgnoreCase))){
        throw 'ARCH3m original on-disk archive topology disagrees with sealed synthetic fixture.'
    }
    if([IO.File]::Exists($part2) -or [IO.Directory]::Exists($part2)){
        throw 'ARCH3m new Part2 already exists, never overwrite or reopen.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3m.OriginalSyntheticPart2PreAllocation.1'
        Status='OriginalPart2SelectedBeforeAnyArchiveStoreOpen'
        OriginalPart1=$part1
        ForcedPart2=$part2
        FolderPath=[string]$checked.OriginalTargetFolder
        ArchiveYear=2020
        Part=2
        SyntheticOnly=$true
        PSTCreatedByGate=$false
        ExistingPart1OpenedByGate=$false
        RealOutlookAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
