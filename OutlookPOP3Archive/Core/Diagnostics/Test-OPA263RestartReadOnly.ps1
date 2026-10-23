#requires -Version 5.1
<#
.SYNOPSIS
    Independent-process READ-ONLY verification of an unresolved 2.6.3 MailMove.
.DESCRIPTION
    Run in a NEW Windows PowerShell 5.1 -STA process while the intended
    Outlook test profile and the disposable source/archive PSTs remain
    mounted. Reads the old durable journal and actual Outlook folders.
    Does not create/open/detach PST stores, copy/move/delete mail, repair
    journals, or acknowledge/reconcile a Move.
.EXAMPLE
    powershell.exe -NoProfile -STA -File .\Core\Diagnostics\Test-OPA263RestartReadOnly.ps1 -JournalPath 'C:\Temp\OPA263-Live-...\live-....operations.jsonl' -ExpectedStatus Ambiguous
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JournalPath,
    [ValidateSet('Ambiguous','SourceOnly','DestinationCandidate','BothPresent','MissingBoth','IncompleteScan','ScopeMismatch','AlreadyTerminal','InsufficientEvidence','UntrustedJournal','IdentityConflict')]
    [string]$ExpectedStatus='Ambiguous'
)
$ErrorActionPreference='Stop'
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Run using Windows PowerShell 5.1 -STA in a NEW process.'
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'Core/Runtime/ComManager.ps1')
. (Join-Path $root 'Core/Archive/ArchiveSelector.ps1')
. (Join-Path $root 'Core/Archive/OperationJournal.ps1')
. (Join-Path $root 'Core/Archive/MoveReconciliation.ps1')

function Get-OPA263ReadOnlyFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Store,
        [Parameter(Mandatory=$true)][string]$ExpectedPath
    )
    $rootFolder=$Store.GetRootFolder()
    if ($null -eq $rootFolder) { throw 'Outlook store root folder unavailable.' }
    $rootPath=[string]$rootFolder.FolderPath
    if ([string]::IsNullOrWhiteSpace($rootPath)) { throw 'Outlook store root folder path empty.' }
    if ($rootPath -ieq $ExpectedPath) { return $rootFolder }
    $prefix=$rootPath+[string][char]92
    if (-not $ExpectedPath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw ("Expected folder '{0}' is outside mounted store root '{1}'." -f $ExpectedPath,$rootPath)
    }
    $relative=$ExpectedPath.Substring($prefix.Length)
    $parts=@($relative.Split([char]92) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0) { throw 'Empty relative Outlook folder path.' }
    $current=$rootFolder
    foreach ($part in $parts) {
        $found=$null
        $folders=$current.Folders
        $count=[int]$folders.Count
        for ($index=1; $index -le $count; $index++) {
            $candidate=$folders.Item($index)
            if ($null -ne $candidate -and [string]$candidate.Name -ieq [string]$part) {
                if ($null -ne $found) { throw "Ambiguous Outlook subfolder name: '$part'." }
                $found=$candidate
            }
        }
        if ($null -eq $found) { throw ("Missing existing Outlook folder '{0}' under '{1}'." -f $part,[string]$current.FolderPath) }
        $current=$found
    }
    if ([string]$current.FolderPath -ine $ExpectedPath) {
        throw ("Resolved folder identity mismatch: expected '{0}', got '{1}'." -f $ExpectedPath,[string]$current.FolderPath)
    }
    return $current
}

function Get-OPA263ReadOnlyMountedStores {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][object]$Intent
    )
    $expectedArchive=[IO.Path]::GetFullPath([string]$Intent.ArchivePst)
    $source=$null; $destination=$null
    $stores=$Namespace.Stores
    for ($i=1; $i -le [int]$stores.Count; $i++) {
        $store=$stores.Item($i)
        if ($null -eq $store) { continue }
        $storeId=[string]$store.StoreID
        if ([string]::IsNullOrWhiteSpace($storeId)) { continue }
        if ($storeId -ceq [string]$Intent.SourceStoreId) {
            if ($null -ne $source) { throw 'More than one mounted source store with persisted StoreID.' }
            $source=$store
        }
        $path=''
        try { $path=[string]$store.FilePath } catch {}
        if (-not [string]::IsNullOrWhiteSpace($path) -and
            [IO.Path]::GetFullPath($path) -ieq $expectedArchive) {
            if ($null -ne $destination) { throw 'More than one mounted store for persisted destination PST.' }
            $destination=$store
        }
    }
    if ($null -eq $source) {
        throw 'Persisted POP3 source StoreID not mounted. Do NOT substitute another store.'
    }
    if ($null -eq $destination) {
        throw 'Exact destination archive PST not mounted. This read-only verifier will not mount it.'
    }
    if ([string]$source.StoreID -ceq [string]$destination.StoreID) {
        throw 'Source and archive store identities unexpectedly equal.'
    }
    return [pscustomobject]@{Source=$source;Destination=$destination}
}

$fullJournal=[IO.Path]::GetFullPath($JournalPath)
if (-not [IO.File]::Exists($fullJournal)) { throw "Operation journal not found: $fullJournal" }
$hashBefore=(Get-FileHash -LiteralPath $fullJournal -Algorithm SHA256).Hash
$journal=Read-OPAOperationJournal -Path $fullJournal
$state=Resolve-OPAOperationRecovery -Journal $journal
$pending=@($state.Indeterminate | Where-Object { [string]$_.OperationKind -ceq 'MailMove' })
if ($pending.Count -ne 1) {
    throw ("Expected precisely one unresolved MailMove operation; found {0}." -f $pending.Count)
}
$operationId=[string]$pending[0].OperationId
$intent=@($journal.Events | Where-Object {
    [string]$_.OperationId -ceq $operationId -and [string]$_.Phase -ceq 'Intent'
})
if ($intent.Count -ne 1) { throw 'Expected exactly one durable MailMove Intent.' }
$event=$intent[0]
if ([string]::IsNullOrWhiteSpace([string]$event.SourceStoreId) -or
    [string]::IsNullOrWhiteSpace([string]$event.SourceFolderPath) -or
    [string]::IsNullOrWhiteSpace([string]$event.TargetFolderPath) -or
    [string]::IsNullOrWhiteSpace([string]$event.ArchivePst)) {
    throw 'Persisted MailMove Intent is missing mandatory PST/folder identities.'
}
if (-not [IO.File]::Exists([string]$event.ArchivePst)) {
    throw 'Persisted destination archive PST file is missing on disk.'
}
# No New-Object -ComObject, no AddStore: never open Outlook or other profiles.
$outlook=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
$namespace=$outlook.GetNamespace('MAPI')
$stores=Get-OPA263ReadOnlyMountedStores -Namespace $namespace -Intent $event
$source=Get-OPA263ReadOnlyFolder -Store $stores.Source -ExpectedPath ([string]$event.SourceFolderPath)
$destination=Get-OPA263ReadOnlyFolder -Store $stores.Destination -ExpectedPath ([string]$event.TargetFolderPath)
$result=Invoke-OPAReadOnlyInterruptedMoveReview -JournalPath $fullJournal -OperationId $operationId `
    -SourceFolder $source -DestinationFolder $destination `
    -SourceStoreId ([string]$stores.Source.StoreID) `
    -SourceFolderPath ([string]$event.SourceFolderPath) `
    -DestinationStoreId ([string]$stores.Destination.StoreID) `
    -TargetFolderPath ([string]$event.TargetFolderPath) `
    -ArchivePst ([string]$event.ArchivePst)
$hashAfter=(Get-FileHash -LiteralPath $fullJournal -Algorithm SHA256).Hash
if ($hashBefore -cne $hashAfter) {
    throw 'Journal file changed during read-only verification; fail closed.'
}
if ([bool]$result.AutomaticRetryAllowed -or [bool]$result.ProvenMoved -or
    -not [bool]$result.RequiresManualReview) {
    throw 'Read-only verifier unexpectedly authorized Move retry or completion.'
}
$result | Format-List TransactionId,OperationId,Status,Reason,SourceMatches,DestinationMatches,AutomaticRetryAllowed,ProvenMoved,RequiresManualReview,JournalLastSequence
Write-Host ("Journal SHA-256 unchanged: {0}" -f $hashAfter)
if ([string]$result.Status -cne $ExpectedStatus) {
    throw ("Restart read-only classification mismatch: expected '{0}', got '{1}'." -f $ExpectedStatus,[string]$result.Status)
}
Write-Host ("PASS: new-process read-only reconciliation = {0}, no automatic Move retry." -f $result.Status)
