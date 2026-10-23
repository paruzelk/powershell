#requires -Version 5.1
<#
.SYNOPSIS
  Read-only preflight for the OutlookPOP3Archive 2.6.4 disposable PST tests.
.DESCRIPTION
  Requires an already-running, independently created TEST Outlook profile.
  Does not create Outlook, import a PST, detach, move, send mail or write files.
  Refuses profiles with configured email accounts or multiple attached stores.
.EXAMPLE
  powershell.exe -NoLogo -NoProfile -STA -File .\Test-OPA264IsolatedOutlook.ps1 -Review
#>
[CmdletBinding()]
param(
    [string]$ExpectedProfileName = 'OPA264-LAB',
    [switch]$Review
)
$ErrorActionPreference = 'Stop'
if (-not $Review) { throw 'Explicit -Review is required.' }
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'Use Windows PowerShell 5.1 with -STA.'
}
if ($ExpectedProfileName -cne 'OPA264-LAB') {
    throw 'Preflight accepts ONLY the dedicated test Outlook profile OPA264-LAB.'
}
$app = $null
$ns = $null
try {
    $app = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'Outlook must be running with the isolated test profile.' }
    $ns = $app.GetNamespace('MAPI')
    $profile = [string]$ns.CurrentProfileName
    if ($profile -cne $ExpectedProfileName) {
        throw ("Active Outlook profile is not the isolated OPA264-LAB profile (observed: '{0}')." -f $profile)
    }
    $accounts = [int]$ns.Accounts.Count
    if ($accounts -ne 0) {
        throw ("Isolated test Outlook must have ZERO email accounts; found {0}." -f $accounts)
    }
    $stores = [int]$ns.Stores.Count
    if ($stores -ne 1) {
        throw ("Expected exactly ONE empty baseline/default store before creating disposable PSTs; found {0}." -f $stores)
    }
    $store = $ns.Stores.Item(1)
    $storePath = [string]$store.FilePath
    if ([string]::IsNullOrWhiteSpace($storePath)) {
        throw 'Baseline Outlook store must be a local data file, not an Exchange/online store.'
    }
    if ($storePath.StartsWith('\\',[StringComparison]::Ordinal) -or
        [string]::IsNullOrWhiteSpace([IO.Path]::GetPathRoot($storePath))) {
        throw 'Baseline Outlook store must be a local drive path.'
    }
    if ([string]$ns.DefaultStore.StoreID -cne [string]$store.StoreID) {
        throw 'The only store is not the default store. Refusing the test preflight.'
    }
    if ($storePath -match '(?i)\\(outlookpop3archive|opa263_archive)') {
        throw 'Suspicious baseline store path. Verify the profile is a new, empty lab profile.'
    }
    [pscustomobject]@{
        Status = 'ReadOnlyPreflightPassed'
        Profile = $profile
        EmailAccounts = $accounts
        BaselineStores = $stores
        BaselineStorePath = $storePath
        FixtureCreated = $false
        PSTMountedOrDetached = $false
        MailMoveExecuted = $false
        NextAction = 'Review manually, then create a NEW OPA264 disposable fixture.'
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
