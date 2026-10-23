#requires -Version 5.1
# 2.6.4-E. Test-only detach/reopen identity assessment; pure preflight and
# observational helpers. No Move, journal append, retry or process termination.
. (Join-Path $PSScriptRoot 'WorkerReadOnlyRecovery.ps1')

function Get-OPA264IdentityProbePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId)
    $paths=Get-OPA264TestPaths -RunId $RunId
    return [pscustomobject]@{
        RunId=$paths.RunId
        Claim=Join-Path $paths.Directory 'identity-probe.claim'
        Before=Join-Path $paths.Directory 'identity-before.json'
        Report=Join-Path $paths.Directory 'identity-report.json'
    }
}

function Assert-OPA264IdentityProbeScope {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)
    $paths=Assert-OPA264RecoveryFixture -Request $Request -RunId ([string]$Request.RunId)
    $probe=Get-OPA264IdentityProbePaths -RunId $paths.RunId
    foreach ($path in @($probe.Claim,$probe.Before,$probe.Report,
        $paths.ClaimPath,$paths.ResponsePath,
        (Join-Path $paths.Directory 'controller-dispatch.claim'),
        (Join-Path $paths.Directory 'controller-result.json'),
        (Join-Path $paths.Directory 'crash-barrier.json'))) {
        if (Test-Path -LiteralPath $path) {
            throw 'Identity probe requires an unused prepared disposable fixture; never overwrite or repeat.'
        }
    }
    return $paths
}

function Get-OPA264ExactTestStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][string]$PstPath
    )
    $match=$null; $count=0
    for ($i=1;$i -le [int]$Namespace.Stores.Count;$i++) {
        $store=$Namespace.Stores.Item($i)
        if ([string]::Equals([string]$store.FilePath,$PstPath,
            [StringComparison]::OrdinalIgnoreCase)) {
            $match=$store; $count++
        }
    }
    if ($count -ne 1) { throw 'Disposable PST not uniquely mounted at the exact path.' }
    # Never detach the user's default store, even in a supposedly test profile.
    if ([string]$Namespace.DefaultStore.StoreID -ceq [string]$match.StoreID) {
        throw 'Refusing to examine or detach the default Outlook store.'
    }
    return $match
}

function Get-OPA264ExactTestFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Store,
          [Parameter(Mandatory=$true)][string]$FolderName)
    $folders=$Store.GetRootFolder().Folders
    $count=0; $found=$null
    for ($i=1; $i -le [int]$folders.Count; $i++) {
        $candidate=$folders.Item($i)
        if ([string]$candidate.Name -ceq $FolderName) {
            $found=$candidate; $count++
        }
    }
    if ($count -ne 1 -or [string]$found.StoreID -cne [string]$Store.StoreID) {
        throw 'Disposable synthetic test folder missing or not unique.'
    }
    return $found
}

function Get-OPA264IdentityObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Intent)
    $paths=Assert-OPA264RecoveryFixture -Request $Request -RunId ([string]$Request.RunId)
    $sourceStore=Get-OPA264ExactTestStore -Namespace $Namespace -PstPath $paths.SourcePst
    $archiveStore=Get-OPA264ExactTestStore -Namespace $Namespace -PstPath $paths.ArchivePst
    if ([string]$sourceStore.StoreID -ceq [string]$archiveStore.StoreID) {
        throw 'Disposable source and archive must be separate stores.'
    }
    $src=Get-OPA264ExactTestFolder -Store $sourceStore -FolderName 'OPA264-TestSource'
    $dst=Get-OPA264ExactTestFolder -Store $archiveStore -FolderName 'OPA264-TestArchive'
    $snapshotSource=New-OPAReadOnlyMoveSnapshot -Folder $src -FolderPath ([string]$src.FolderPath) -StoreIdentity ([string]$sourceStore.StoreID) -Role Source
    $snapshotArchive=New-OPAReadOnlyMoveSnapshot -Folder $dst -FolderPath ([string]$dst.FolderPath) -StoreIdentity ([string]$archiveStore.StoreID) -Role Destination -ArchivePst $paths.ArchivePst
    if (-not $snapshotSource.ScanComplete -or -not $snapshotArchive.ScanComplete) {
        throw 'Identity observation requires full, error-free scans of both synthetic folders.'
    }
    $srcMatches=@($snapshotSource.Items | Where-Object { Test-OPAMoveFingerprint -Intent $Intent -Observed $_ })
    $dstMatches=@($snapshotArchive.Items | Where-Object { Test-OPAMoveFingerprint -Intent $Intent -Observed $_ })
    if (@($snapshotSource.Items).Count -gt 1 -or
        @($snapshotArchive.Items).Count -gt 1 -or
        (@($snapshotSource.Items).Count + @($snapshotArchive.Items).Count) -ne 1 -or
        ($srcMatches.Count + $dstMatches.Count) -ne 1) {
        throw 'Identity probe requires exactly one uniquely fingerprinted synthetic message across both PSTs.'
    }
    $message=if ($srcMatches.Count -eq 1) { $srcMatches[0] } else { $dstMatches[0] }
    return [pscustomobject]@{
        RunId=$paths.RunId
        SourcePst=$paths.SourcePst
        ArchivePst=$paths.ArchivePst
        SourceStoreId=[string]$sourceStore.StoreID
        ArchiveStoreId=[string]$archiveStore.StoreID
        SourceFolderId=[string]$src.EntryID
        ArchiveFolderId=[string]$dst.EntryID
        SourceFolderPath=[string]$src.FolderPath
        ArchiveFolderPath=[string]$dst.FolderPath
        MessageStoreRole=if ($srcMatches.Count -eq 1) { 'Source' } else { 'Archive' }
        MailEntryId=[string]$message.EntryId
        SourceMatches=$srcMatches.Count
        ArchiveMatches=$dstMatches.Count
        FullyScanned=$true
    }
}

function Compare-OPA264IdentityObservations {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After)
    $required=@('RunId','SourcePst','ArchivePst','SourceStoreId','ArchiveStoreId',
        'SourceFolderId','ArchiveFolderId','SourceFolderPath','ArchiveFolderPath',
        'MessageStoreRole','MailEntryId','FullyScanned')
    foreach ($input in @($Before,$After)) {
        if ($null -eq $input) { throw 'Identity observation is null.' }
        foreach ($field in $required) {
            if ($input.PSObject.Properties.Name -cnotcontains $field -or
                [string]::IsNullOrWhiteSpace([string]$input.$field)) {
                throw "Identity observation missing $field."
            }
        }
    }
    if (-not [bool]$Before.FullyScanned -or -not [bool]$After.FullyScanned) {
        throw 'Cannot compare incomplete identity scans.'
    }
    if ([string]$Before.RunId -cne [string]$After.RunId -or
        [string]$Before.SourcePst -cne [string]$After.SourcePst -or
        [string]$Before.ArchivePst -cne [string]$After.ArchivePst) {
        throw 'Reattached identity observation has different RunId or PST scope.'
    }
    $storeChanged=([string]$Before.SourceStoreId -cne [string]$After.SourceStoreId -or
        [string]$Before.ArchiveStoreId -cne [string]$After.ArchiveStoreId)
    $folderChanged=([string]$Before.SourceFolderId -cne [string]$After.SourceFolderId -or
        [string]$Before.ArchiveFolderId -cne [string]$After.ArchiveFolderId -or
        [string]$Before.SourceFolderPath -cne [string]$After.SourceFolderPath -or
        [string]$Before.ArchiveFolderPath -cne [string]$After.ArchiveFolderPath)
    $mailChanged=([string]$Before.MailEntryId -cne [string]$After.MailEntryId)
    $locationChanged=([string]$Before.MessageStoreRole -cne [string]$After.MessageStoreRole)
    $classification='Stable'
    if ($locationChanged) { $classification='LocationChanged' }
    elseif ($storeChanged) { $classification='StoreIdChanged' }
    elseif ($folderChanged) { $classification='FolderIdentityChanged' }
    elseif ($mailChanged) { $classification='MailEntryIdChanged' }
    return [pscustomobject]@{
        Schema='2.6.4-E.1'
        RunId=[string]$Before.RunId
        Status=$classification
        StoreIdChanged=$storeChanged
        FolderIdentityChanged=$folderChanged
        MailEntryIdChanged=$mailChanged
        MessageLocationChanged=$locationChanged
        SourceMatchesBefore=[int]$Before.SourceMatches
        SourceMatchesAfter=[int]$After.SourceMatches
        ArchiveMatchesBefore=[int]$Before.ArchiveMatches
        ArchiveMatchesAfter=[int]$After.ArchiveMatches
        AutomaticRetryAllowed=$false
        MailMoveAllowed=$false
        JournalWriteAllowed=$false
        AutomaticCompletionAllowed=$false
        ProvenMoved=$false
        RequiresManualReview=$true
        Disposition='StopAndPreserveEvidence'
    }
}
