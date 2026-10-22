function Get-OPAAccountProtocol {
    param([Parameter(Mandatory=$true)][object]$Account)
    try {
        switch ([int]$Account.AccountType) {
            1 { "IMAP"; break }
            2 { "POP3"; break }
            default { "Unknown" }
        }
    } catch { "Unknown" }
}

function Get-OPAOutlookDiscovery {
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [string]$ProfileName
    )

    if ($null -eq $Namespace) { throw "MAPI Namespace is required." }

    $accounts = @($Namespace.Accounts)
    $stores = @($Namespace.Stores)
    $accountInfo = @()
    $pop3Sources = @()

    # Discovery is intentionally side-effect free: it collects data only.
    # Console rendering is owned by Write-OPADiscoverySummary so that a single
    # discovery pass cannot produce duplicate console output.
    foreach ($account in $accounts) {
        $protocol = Get-OPAAccountProtocol $account
        $name = [string]$account.SmtpAddress
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$account.UserName }

        $accountInfo += [pscustomobject]@{
            Name=$name; UserName=[string]$account.UserName
            AccountType=[int]$account.AccountType; Protocol=$protocol
        }
    }

    foreach ($account in $accounts) {
        if ((Get-OPAAccountProtocol $account) -ne "POP3") { continue }

        $name = [string]$account.SmtpAddress
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$account.UserName }

        $store = $null
        try { $store = $account.DeliveryStore } catch {}

        if ($null -eq $store) {
            foreach ($candidate in $stores) {
                try {
                    if ([string]$candidate.DisplayName -ieq $name) {
                        $store = $candidate
                        break
                    }
                } catch {}
            }
        }

        if ($null -eq $store) { continue }

        $path = ""
        try { $path = [string]$store.FilePath } catch {}
        if ([IO.Path]::GetExtension($path) -ine ".pst") { continue }

        $pop3Sources += [pscustomobject]@{
            AccountName=$name
            AccountEmail=$(if(-not [string]::IsNullOrWhiteSpace([string]$account.SmtpAddress)){[string]$account.SmtpAddress}else{[string]$account.UserName})
            UserName=[string]$account.UserName
            Protocol="POP3"
            StoreName=[string]$store.DisplayName
            FilePath=$path
            StoreHandle=$store
        }
    }

    [pscustomobject]@{
        Profile=$ProfileName
        Accounts=$accountInfo
        Stores=$stores
        Pop3Sources=$pop3Sources
    }
}

# Compatibility aliases.
function Get-OPAOutlookDiscoveryResult {
    param([Parameter(Mandatory=$true)][object]$Namespace,[string]$ProfileName)
    Get-OPAOutlookDiscovery -Namespace $Namespace -ProfileName $ProfileName
}


# Public integration interface expected by OutlookPOP3Archive.ps1.
function Get-OutlookDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$ComSession,

        [string]$ProfileName
    )

    if ($null -eq $ComSession) {
        throw "COM session is required."
    }

    $namespace = $ComSession.Namespace
    if ($null -eq $namespace) {
        throw "COM session does not contain a MAPI Namespace."
    }

    $actualProfile = ""
    try { $actualProfile = [string]$namespace.CurrentProfileName } catch {}

    if (-not [string]::IsNullOrWhiteSpace($ProfileName) -and
        -not [string]::IsNullOrWhiteSpace($actualProfile) -and
        $ProfileName -ine $actualProfile) {
        throw "Outlook profile '$ProfileName' is not the current MAPI profile '$actualProfile'."
    }

    return Get-OPAOutlookDiscovery -Namespace $namespace -ProfileName $actualProfile
}
