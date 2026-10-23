#requires -Version 5.1

# =====================================
# Server Maintenance Framework
# Configuration
# =====================================

$SMFConfig = @{

    # Default profile (used when -Profile not specified)
    Profile = "Analyze"

    # Execution profiles
    Profiles = @{
        "Analyze" = @{
            Delete        = $false
            DeepClean     = $false
            GenerateReport = $true
        }
        "Day" = @{
            Delete        = $true
            DeepClean     = $false
            GenerateReport = $true
        }
        "Night" = @{
            Delete        = $true
            DeepClean     = $true
            GenerateReport = $true
        }
    }

    # Global settings for various cleaning tasks
    Settings = @{

        # Temporary files settings
        Temp = @{
            MaxAgeDays          = 7
            IncludeWindowsTemp  = $true
            IncludeUserTemp     = $true
            IncludeNetworkPaths = $false
            SkipLockedFiles     = $true
            ExcludedUsers       = @(
                "Administrator",
                "Default",
                "Default User",
                "Public",
                "Guest"
            )
        }

        # Windows Event Logs
        WindowsLogs = @{
            Enabled  = $true # Event channel inventory only
        }

        WindowsFileLogs = @{
            Enabled  = $true
            KeepDays = 30
        }

        # Browser caches
        BrowserCache = @{
            IncludeSiteStorage = $false
            Edge   = @{ Enabled = $true }
            Yandex = @{ Enabled = $true }
            Chrome = @{ Enabled = $true }
        }

        # IIS logs
        IIS = @{
            Enabled  = $true
            KeepDays = 30
        }

        # Windows Error Reporting (WER)
        WER = @{
            Enabled  = $true
            KeepDays = 30
        }

        # Recycle Bin (new)
        RecycleBin = @{
            Enabled        = $true
            ExcludedUsers  = @(
                "Administrator",
                "Default",
                "Default User",
                "Public",
                "Guest"
            )
        }
        # User Profiles Cleanup (stale profiles)
UserProfiles = @{
    Enabled              = $false
    MaxAgeDays           = 90
    ADMode               = "Disabled"          # "Disabled", "Enabled", "All"
    ExcludedUsers        = @(
        "Administrator",
        "Default",
        "Default User",
        "Public",
        "Guest"
    )
    DomainOnly           = $true
    MinimumProfileSizeMB = 50
    ConfirmBeforeDelete  = $true
    ProtectedGroupSIDs   = @(
        "S-1-5-21-*-512",   # Domain Admins
        "S-1-5-21-*-519",   # Enterprise Admins
        "S-1-5-21-*-518",   # Schema Admins
        "S-1-5-32-544"      # Builtin Administrators
    )
}
    }

    # Module definitions
    Modules = @{
        "Test-Module" = @{
            Enabled  = $false
            Order    = 1
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-Temp" = @{
            Enabled  = $true
            Order    = 10
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-RecycleBin" = @{
            Enabled  = $true
            Order    = 20
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-WindowsLogs" = @{
            Enabled  = $true
            Order    = 30
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-WindowsFileLogs" = @{
            Enabled  = $true
            Order    = 35
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-YandexCache" = @{
            Enabled  = $true
            Order    = 40
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-ChromeCache" = @{
            Enabled  = $true
            Order    = 45
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-EdgeCache" = @{
            Enabled  = $true
            Order    = 50
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-IISLogs" = @{
            Enabled  = $true
            Order    = 60
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-WER" = @{
            Enabled  = $true
            Order    = 70
            Profiles = @("Analyze", "Day", "Night")
        }
        "Clear-UserProfiles" = @{
    Enabled  = $false
    Order    = 80
    Profiles = @("Analyze", "Day", "Night")
}
    }

    # Reports directory (relative to this config file)
    ReportPath = "$PSScriptRoot\..\Reports"

    # Framework version
    Version = "1.0.0"
}
