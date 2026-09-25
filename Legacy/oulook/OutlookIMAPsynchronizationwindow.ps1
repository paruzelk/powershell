#Requires -Version 5.1

<#
.SYNOPSIS
    Configure Outlook IMAP synchronization window.

.DESCRIPTION
    Searches all Outlook profiles of the current user and configures
    the "IMAP months to sync" registry value for every IMAP account.

.NOTES
    Version : 1.0.0
    Author  : ChatGPT
    Target  : Outlook 2019 / Outlook 2021 / Microsoft 365
               PowerShell 5.1
#>

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

#==================================================
# Configuration
#==================================================

# Allowed values:
#
# "All"
# "1"
# "3"
# "6"
# "12"
# "24"
# "60"

[string]$DesiredMonths = "12"

$LogFolder = Join-Path $env:LOCALAPPDATA "OutlookIMAPSync"
$LogFile   = Join-Path $LogFolder "OutlookIMAPSync.log"

#==================================================
# Exit codes
#==================================================

$EXIT_SUCCESS         = 0
$EXIT_OUTLOOK_RUNNING = 1
$EXIT_NO_PROFILES     = 2
$EXIT_NO_IMAP         = 3
$EXIT_REGISTRY_ERROR  = 4
$EXIT_UNKNOWN_ERROR   = 5

#==================================================
# Functions
#==================================================

function Initialize-Logging
{
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $LogFolder))
    {
        New-Item `
            -Path $LogFolder `
            -ItemType Directory `
            -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $LogFile))
    {
        New-Item `
            -Path $LogFile `
            -ItemType File `
            -Force | Out-Null
    }
}

function Write-Log
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[{0}] {1,-5} : {2}" -f $TimeStamp, $Level, $Message

    Write-Host $Line

    Add-Content `
        -Path $LogFile `
        -Value $Line `
        -Encoding UTF8
}

function Test-OutlookRunning
{
    [CmdletBinding()]
    param()

    $Process = Get-Process OUTLOOK -ErrorAction SilentlyContinue

    if ($null -ne $Process)
    {
        Write-Log "Outlook process detected."

        return $true
    }

    Write-Log "Outlook is not running."

    return $false
}
function Get-OutlookProfiles
{
    [CmdletBinding()]
    param()

    $ProfilesRoot = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles"

    if (-not (Test-Path -LiteralPath $ProfilesRoot))
    {
        Write-Log "Outlook profiles registry key not found." -Level WARN

        return @()
    }

    $Profiles = @(Get-ChildItem -Path $ProfilesRoot -ErrorAction Stop)

    if ($Profiles.Count -eq 0)
    {
        Write-Log "No Outlook profiles found." -Level WARN

        return @()
    }

    Write-Log ("Found {0} Outlook profile(s)." -f $Profiles.Count)

    foreach ($Profile in $Profiles)
    {
        Write-Log ("Profile: {0}" -f $Profile.PSChildName)

        [PSCustomObject]@{
            Name = $Profile.PSChildName
            Path = $Profile.PSPath
        }
    }
}

function Get-IMAPAccounts
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [array]$Profiles
    )

    foreach ($Profile in $Profiles)
    {
        Write-Log ("Scanning profile: {0}" -f $Profile.Name)

        $Keys = @(Get-ChildItem -Path $Profile.Path -Recurse -ErrorAction SilentlyContinue)

        foreach ($Key in $Keys)
        {
            try
            {
                $Props = Get-ItemProperty -Path $Key.PSPath -ErrorAction Stop
            }
            catch
            {
                continue
            }

            $PropertyNames = $Props.PSObject.Properties.Name

            $IsIMAP =
                ($PropertyNames -contains "Account Name") -and
                ($PropertyNames -contains "IMAP Server") -and
                ($PropertyNames -contains "SMTP Server")

            if (-not $IsIMAP)
            {
                continue
            }

            Write-Log ("IMAP account found: {0}" -f $Props."Account Name")

            [PSCustomObject]@{
                Profile      = $Profile.Name
                Account      = $Props."Account Name"
                IMAPServer   = $Props."IMAP Server"
                SMTPServer   = $Props."SMTP Server"
                RegistryPath = $Key.PSPath
            }
        }
    }
}
#==================================================
# IMAP Sync Window
#==================================================

function Get-CurrentSyncWindow
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string]$RegistryPath
    )

    try
    {
        $Value = (Get-ItemProperty -Path $RegistryPath -Name "IMAP months to sync" -ErrorAction Stop)."IMAP months to sync"
    }
    catch
    {
        # Значение отсутствует.
        # Outlook считает это режимом "Все".

        return "All"
    }

    return [string]$Value
}

function Set-CurrentSyncWindow
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [Parameter(Mandatory)]
        [string]$DesiredValue
    )

    try
    {
        if ($DesiredValue -eq "All")
        {
            Remove-ItemProperty `
                -Path $RegistryPath `
                -Name "IMAP months to sync" `
                -ErrorAction SilentlyContinue

            return
        }

        New-ItemProperty `
            -Path $RegistryPath `
            -Name "IMAP months to sync" `
            -PropertyType DWord `
            -Value ([int]$DesiredValue) `
            -Force | Out-Null
    }
    catch
    {
        throw
    }
}

function Set-IMAPAccountsSyncWindow
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [array]$Accounts,

        [Parameter(Mandatory)]
        [string]$DesiredValue
    )

    foreach ($Account in $Accounts)
    {
        Write-Log ("Processing account: {0}" -f $Account.Account)

        $CurrentValue = Get-CurrentSyncWindow -RegistryPath $Account.RegistryPath

        Write-Log ("Current value : {0}" -f $CurrentValue)
        Write-Log ("Desired value : {0}" -f $DesiredValue)

        if ($CurrentValue -eq $DesiredValue)
        {
            Write-Log "Already configured."

            continue
        }

        try
        {
            Set-CurrentSyncWindow `
                -RegistryPath $Account.RegistryPath `
                -DesiredValue $DesiredValue

            Write-Log ("Updated successfully ({0} -> {1})" -f $CurrentValue, $DesiredValue)
        }
        catch
        {
            Write-Log ("Unable to update registry: {0}" -f $_.Exception.Message) -Level ERROR

            throw
        }
    }
}
#==================================================
# Configuration
#==================================================

function Invoke-IMAPConfiguration
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [array]$Accounts,

        [Parameter(Mandatory)]
        [string]$DesiredValue
    )

    foreach ($Account in $Accounts)
    {
        Write-Log ("------------------------------------------")
        Write-Log ("Profile : {0}" -f $Account.Profile)
        Write-Log ("Account : {0}" -f $Account.Account)

        $CurrentValue = Get-CurrentSyncWindow `
            -RegistryPath $Account.RegistryPath

        Write-Log ("Current : {0}" -f $CurrentValue)
        Write-Log ("Desired : {0}" -f $DesiredValue)

        if ($CurrentValue -eq $DesiredValue)
        {
            Write-Log "Already configured."

            continue
        }

        try
        {
            Set-CurrentSyncWindow `
                -RegistryPath $Account.RegistryPath `
                -DesiredValue $DesiredValue

            Write-Log ("Updated successfully ({0} -> {1})" -f $CurrentValue, $DesiredValue)
        }
        catch
        {
            Write-Log ("Registry update failed: {0}" -f $_.Exception.Message) -Level ERROR

            throw
        }
    }
}
#==================================================
# Main
#==================================================

$ExitCode = $EXIT_SUCCESS

try
{
    Initialize-Logging

    Add-Content -Path $LogFile -Value ""

    Write-Log "=========================================="
    Write-Log "Outlook IMAP Sync started."
    Write-Log ("Desired value : {0}" -f $DesiredMonths)
    Write-Log ("User          : {0}" -f $env:USERNAME)
    Write-Log ("Computer      : {0}" -f $env:COMPUTERNAME)

    #
    # Outlook must be closed
    #

    if (Test-OutlookRunning)
    {
        $ExitCode = $EXIT_OUTLOOK_RUNNING

        Write-Log "Outlook is running. Configuration skipped." -Level WARN

        return
    }

    #
    # Get Outlook profiles
    #

    $Profiles = @(Get-OutlookProfiles)

    if ($Profiles.Count -eq 0)
    {
        $ExitCode = $EXIT_NO_PROFILES

        Write-Log "No Outlook profiles found." -Level WARN

        return
    }

    #
    # Get IMAP accounts
    #

    $IMAPAccounts = @(Get-IMAPAccounts -Profiles $Profiles)

    if ($IMAPAccounts.Count -eq 0)
    {
        $ExitCode = $EXIT_NO_IMAP

        Write-Log "No IMAP accounts found." -Level WARN

        return
    }

    Write-Log ("Found {0} IMAP account(s)." -f $IMAPAccounts.Count)

    #
    # Configure IMAP accounts
    #

    Invoke-IMAPConfiguration `
        -Accounts $IMAPAccounts `
        -DesiredValue $DesiredMonths

    Write-Log "Configuration completed successfully."
}
catch
{
    $ExitCode = $EXIT_REGISTRY_ERROR

    Write-Log $_.Exception.Message -Level ERROR
}
finally
{
    Write-Log ("Exit code : {0}" -f $ExitCode)

    exit $ExitCode
}