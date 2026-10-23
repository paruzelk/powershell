#requires -Version 5.1
<#
.SYNOPSIS
  Read-only preflight for an EXISTING Outlook test profile/PST.
.DESCRIPTION
  DOES NOT require a profile named OPA264-LAB or zero accounts.
  Attaches ONLY to an already-running Outlook.Application. No PST create,
  mount, detach, copying, MailItem.Move, journal write or file deletion.
  -PstPath selects an exact already mounted PST for later human review.
.EXAMPLE
  powershell.exe -NoProfile -STA -File .\Test-OPA264CurrentPst.ps1 -Review
.EXAMPLE
  powershell.exe -NoProfile -STA -File .\Test-OPA264CurrentPst.ps1 -Review -PstPath 'D:\Test\Current.pst'
#>
[CmdletBinding()]
param(
    [switch]$Review,
    [string]$PstPath = ''
)
$ErrorActionPreference='Stop'
if (-not $Review) { throw 'Explicit -Review is required.' }
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'Use Windows PowerShell 5.1 with -STA.'
}
$target=''
if (-not [string]::IsNullOrWhiteSpace($PstPath)) {
    if (-not [IO.Path]::IsPathRooted($PstPath) -or
        $PstPath.StartsWith('\\',[StringComparison]::Ordinal) -or
        [IO.Path]::GetExtension($PstPath) -ine '.pst') {
        throw 'PstPath must be an absolute local filesystem path to a .pst file.'
    }
    $target=[IO.Path]::GetFullPath($PstPath)
}
$app=$null; $ns=$null
try {
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'Outlook must already be running with the current TEST profile.' }
    $ns=$app.GetNamespace('MAPI')
    $profile=[string]$ns.CurrentProfileName
    $accounts=[int]$ns.Accounts.Count
    $defaultStoreId=[string]$ns.DefaultStore.StoreID
    $stores=[int]$ns.Stores.Count
    $found=New-Object 'System.Collections.Generic.List[object]'
    $selected=$null
    for ($i=1;$i -le $stores;$i++) {
        $store=$ns.Stores.Item($i)
        $path=''
        try { $path=[string]$store.FilePath }
        catch { $path='' }
        if ([string]::IsNullOrWhiteSpace($path) -or
            [IO.Path]::GetExtension($path) -ine '.pst') { continue }
        $canonical=''
        try { $canonical=[IO.Path]::GetFullPath($path) }
        catch { continue }
        $sizeMB=$null
        $isFile=[IO.File]::Exists($canonical)
        if ($isFile) {
            try {
                $attributes=([IO.File]::GetAttributes($canonical))
                if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'PST file is a reparse point.'
                }
                $sizeMB=[Math]::Round(([double](Get-Item -LiteralPath $canonical -Force).Length / 1MB),2)
            }
            catch {
                if ($target -and [string]::Equals($canonical,$target,[StringComparison]::OrdinalIgnoreCase)) {
                    throw ('Selected PST cannot be safely inspected: ' + $_.Exception.Message)
                }
                $sizeMB=$null
            }
        }
        $row=[pscustomobject]@{
            StoreIndex=$i
            DisplayName=[string]$store.DisplayName
            PstPath=$canonical
            Exists=$isFile
            SizeMB=$sizeMB
            IsDefault=([string]$store.StoreID -ceq $defaultStoreId)
            Selected=$false
        }
        if ($target -and [string]::Equals($canonical,$target,[StringComparison]::OrdinalIgnoreCase)) {
            if ($null -ne $selected) { throw 'More than one Outlook store maps to the selected PST path.' }
            $row.Selected=$true
            $selected=$row
        }
        [void]$found.Add($row)
    }
    if ($target -and $null -eq $selected) {
        throw 'The selected PST is not mounted in this Outlook session.'
    }
    if ($null -ne $selected -and -not $selected.Exists) {
        throw 'The selected PST file does not exist.'
    }
    return [pscustomobject]@{
        Schema='2.6.4-Live.CurrentPst.1'
        Status=if ($target) { 'SelectedPstReadOnlyVerified' } else { 'PstInventoryReadOnly' }
        CurrentProfile=$profile
        EmailAccountsCount=$accounts
        TotalOutlookStores=$stores
        PstStoreCount=$found.Count
        SelectedPstPath=$target
        Stores=$found.ToArray()
        ProductionDataClassification='UserMustConfirmTestOnly'
        MailMoveExecuted=$false
        PstMountedOrDetached=$false
        JournalModified=$false
        CleanupPerformed=$false
        ReadyForExistingPstMove=$false
        NextStep='Verify exact test-PST path and backup; current disposable Worker requires NEW Source.pst and Archive.pst.'
    }
}
finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
