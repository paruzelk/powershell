#requires -Version 5.1

param(
    [ValidateSet("Analyze","Day","Night")]
    [string]$SMFProfile,
    [switch]$WhatIf
)

$Root = Split-Path $MyInvocation.MyCommand.Path -Parent

# --- Admin rights check ---
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "WARNING: Script is not running as Administrator. Some operations may fail." -ForegroundColor Yellow
    Write-Host "It is recommended to run this script with administrative privileges." -ForegroundColor Yellow
}

# --- Load configuration ---
$ConfigPath = Join-Path $Root "Config\Config.ps1"
if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Configuration file not found at $ConfigPath" -ForegroundColor Red
    exit 1
}

try {
    . $ConfigPath
} catch {
    Write-Host "ERROR: Failed to load configuration: $_" -ForegroundColor Red
    exit 1
}

if ($null -eq $SMFConfig) {
    Write-Host "ERROR: Configuration loading failed." -ForegroundColor Red
    exit 1
}
if ($null -eq $SMFConfig.Modules) {
    Write-Host "ERROR: Configuration error: Modules section missing." -ForegroundColor Red
    exit 1
}
if ($null -eq $SMFConfig.Profiles) {
    Write-Host "ERROR: Configuration error: Profiles section missing." -ForegroundColor Red
    exit 1
}

# --- Interactive menu (if -SMFProfile not specified) ---
if (-not $SMFProfile) {
    $whatIfMode = $WhatIf
    do {
        Clear-Host
        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "  Server Maintenance Framework - Interactive Mode" -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Available actions:" -ForegroundColor White
        Write-Host ""
        Write-Host "  1. Run Analyze (view only) - Profile: Analyze" -ForegroundColor Green
        Write-Host "  2. Run Day cleanup - Profile: Day" -ForegroundColor Yellow
        Write-Host "  3. Run Night cleanup (deep) - Profile: Night" -ForegroundColor Red
        Write-Host ""
        Write-Host "  4. Toggle WhatIf mode (safe run)" -ForegroundColor Magenta
        Write-Host "     Current status: $(if ($whatIfMode) { 'ON' } else { 'OFF' })" -ForegroundColor $(if ($whatIfMode) { 'Green' } else { 'Red' })
        Write-Host ""
        Write-Host "  5. Show current configuration and edit" -ForegroundColor Cyan
        Write-Host "  6. View last report" -ForegroundColor Gray
        Write-Host "  7. Exit" -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "Select action (1-7)"

        switch ($choice) {
            "1" {
                $SMFProfile = "Analyze"
                $WhatIf = $whatIfMode
                Write-Host "`nStarting Analyze..." -ForegroundColor Green
                if ($WhatIf) { Write-Host "WhatIf mode: ON (no changes will be made)" -ForegroundColor Yellow }
                $confirm = Read-Host "Press Enter to confirm or enter 'n' to cancel"
                if ($confirm -ne 'n') { break } else { $SMFProfile = $null; continue }
            }
            "2" {
                $SMFProfile = "Day"
                $WhatIf = $whatIfMode
                Write-Host "`nStarting Day cleanup..." -ForegroundColor Yellow
                if ($WhatIf) { Write-Host "WhatIf mode: ON (no changes will be made)" -ForegroundColor Yellow }
                $confirm = Read-Host "Press Enter to confirm or enter 'n' to cancel"
                if ($confirm -ne 'n') { break } else { $SMFProfile = $null; continue }
            }
            "3" {
                $SMFProfile = "Night"
                $WhatIf = $whatIfMode
                Write-Host "`nStarting Night cleanup..." -ForegroundColor Red
                if ($WhatIf) { Write-Host "WhatIf mode: ON (no changes will be made)" -ForegroundColor Yellow }
                $confirm = Read-Host "Press Enter to confirm or enter 'n' to cancel"
                if ($confirm -ne 'n') { break } else { $SMFProfile = $null; continue }
            }
            "4" {
                $whatIfMode = -not $whatIfMode
                Write-Host "`nWhatIf mode toggled to: $(if ($whatIfMode) { 'ON' } else { 'OFF' })" -ForegroundColor Yellow
                Read-Host "Press Enter to continue"
                continue
            }
            "5" {
                Write-Host "`nCurrent configuration (JSON format):" -ForegroundColor Cyan
                Write-Host "----------------------------------------" -ForegroundColor Gray
                $jsonOutput = $SMFConfig | ConvertTo-Json -Depth 10
                Write-Host $jsonOutput -ForegroundColor White
                Write-Host "----------------------------------------" -ForegroundColor Gray
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  [1] Open config file in Notepad for editing" -ForegroundColor Cyan
                Write-Host "  [2] Return to main menu" -ForegroundColor Gray
                $subChoice = Read-Host "Select option (1-2)"
                if ($subChoice -eq "1") {
                    $configFile = Join-Path $Root "Config\Config.ps1"
                    if (Test-Path $configFile) {
                        Write-Host "`nOpening $configFile in Notepad..." -ForegroundColor Cyan
                        Start-Process notepad.exe -ArgumentList $configFile
                        Write-Host "After editing, save and restart the script to apply changes." -ForegroundColor Yellow
                    } else {
                        Write-Host "`nConfig file not found!" -ForegroundColor Red
                    }
                    Read-Host "`nPress Enter to continue"
                }
                continue
            }
            "6" {
                $lastReport = Get-ChildItem "$Root\Reports\*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($lastReport) {
                    Write-Host "`nOpening last report: $($lastReport.Name)" -ForegroundColor Cyan
                    Start-Process $lastReport.FullName
                } else {
                    Write-Host "`nNo reports found." -ForegroundColor Red
                }
                Read-Host "`nPress Enter to continue"
                continue
            }
            "7" {
                Write-Host "`nExiting..." -ForegroundColor Gray
                exit 0
            }
            default {
                Write-Host "`nInvalid choice. Try again." -ForegroundColor Red
                Start-Sleep -Milliseconds 500
                continue
            }
        }
        if ($SMFProfile) { break }
    } while ($true)
}

# --- Main script logic ---
$ActiveProfile = $SMFProfile

if ([string]::IsNullOrEmpty($ActiveProfile)) {
    Write-Host "ERROR: No profile specified." -ForegroundColor Red
    exit 1
}
if ($null -eq $SMFConfig.Profiles[$ActiveProfile]) {
    Write-Host "ERROR: Unknown profile: $ActiveProfile" -ForegroundColor Red
    exit 1
}

# --- Load Core ---
$CorePath = Join-Path $Root "Core"
if (-not (Test-Path $CorePath)) {
    Write-Host "ERROR: Core folder not found: $CorePath" -ForegroundColor Red
    exit 1
}
$CoreFiles = Get-ChildItem "$CorePath\*.ps1" -ErrorAction SilentlyContinue
if ($CoreFiles.Count -eq 0) {
    Write-Host "ERROR: No core modules found in $CorePath" -ForegroundColor Red
    exit 1
}
foreach ($file in $CoreFiles) {
    try {
        . $file.FullName
    } catch {
        Write-Host "ERROR: Failed to load core module '$($file.Name)': $_" -ForegroundColor Red
        exit 1
    }
}

$requiredFunctions = @('Initialize-SMFLogger','Write-SMFLog','Get-SMFEnvironment','Import-SMFModules','Invoke-SMFModules','New-SMFReport')
$missing = $requiredFunctions | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
if ($missing) {
    Write-Host "ERROR: Missing required core functions: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

# --- Logger init ---
$LogDir = Join-Path $Root "Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$LogPath = Join-Path $LogDir "SMF.log"

try {
    Initialize-SMFLogger -Path $LogPath
    Write-SMFLog "SMF started"
    Write-SMFLog "Profile: $ActiveProfile"
    if ($WhatIf) { Write-SMFLog "WHATIF mode enabled (no changes will be made)" }
} catch {
    Write-Host "ERROR: Logger initialization failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================="
Write-Host " Server Maintenance Framework "
Write-Host "================================="
Write-Host ""
Write-Host "Project structure: OK"
Write-Host "Configuration: OK"
Write-Host "Core modules loaded: $($CoreFiles.Count)"

if ($WhatIf) {
    Write-Host "WHATIF mode: ENABLED (no changes will be made)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Profile:"
Write-Host $ActiveProfile

$SMFContext = [PSCustomObject]@{
    RunId           = [guid]::NewGuid().ToString()
    StartTime       = Get-Date
    EndTime         = $null
    Duration        = $null
    Root            = $Root
    Config          = $SMFConfig
    Profile         = $ActiveProfile
    ProfileSettings = $SMFConfig.Profiles[$ActiveProfile]
    ComputerName    = $env:COMPUTERNAME
    Environment     = Get-SMFEnvironment
    ReportPath      = Join-Path $Root "Reports"
    Version         = "1.0.0"
    Results         = [System.Collections.ArrayList]::new()
    WhatIf          = $WhatIf
}

Write-Host ""
Write-Host "Environment:"
$SMFContext.Environment | Format-List

Write-SMFLog "Loading modules"
try {
    [array]$Modules = Import-SMFModules -ModulesPath (Join-Path $Root "Modules") -Config $SMFConfig -Profile $ActiveProfile
} catch {
    Write-SMFLog "ERROR loading modules: $_"
    Write-Host "ERROR: Failed to load modules: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Modules:"
if ($Modules.Count -eq 0) {
    Write-Host "No modules loaded"
} else {
    $Modules | Format-Table Name, Order, ExecuteFunction, Status
}

if ($Modules.Count -gt 0) {
    Write-Host ""
    Write-Host "Execution results:"
    Write-SMFLog "Executing modules"
    try {
        Invoke-SMFModules -Context $SMFContext -Modules $Modules
    } catch {
        Write-SMFLog "ERROR during module execution: $_"
        Write-Host "ERROR: Module execution failed: $_" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "No modules to execute."
}

Write-Host ""
Write-Host "Results summary:"
if ($SMFContext.Results.Count -eq 0) {
    Write-Host "No execution results."
} else {
    $properties = @('Module','Status','StartTime','EndTime','Duration')
    $firstResult = $SMFContext.Results[0]
    $optionalProps = @('FilesFound','FilesProcessed','FilesDeleted','BytesBefore','BytesFreed')
    foreach ($prop in $optionalProps) {
        if ($firstResult.PSObject.Properties.Name -contains $prop) {
            $properties += $prop
        }
    }
    $SMFContext.Results | Format-Table $properties
}

$SMFContext.EndTime = Get-Date
$SMFContext.Duration = $SMFContext.EndTime - $SMFContext.StartTime

if (Get-Command New-SMFReport -ErrorAction SilentlyContinue) {
    try {
        New-SMFReport -Context $SMFContext
    } catch {
        Write-Host "Report generation failed: $_" -ForegroundColor Yellow
        Write-SMFLog "Report generation failed: $_"
    }
} else {
    Write-Host "Report function not available." -ForegroundColor Yellow
}

Write-SMFLog "SMF finished"
Write-Host ""
Write-Host "Initialization completed."
exit 0