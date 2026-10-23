#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet("Analyze","Day","Night")]
    [Alias('Profile')]
    [string]$SMFProfile,
    [switch]$WhatIf
)

# =====================================
# Server Maintenance Framework
# Main Launcher
# =====================================

$Root = Split-Path $MyInvocation.MyCommand.Path -Parent

# --- Проверка административных прав ---
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "WARNING: Script is not running as Administrator. Some operations may fail." -ForegroundColor Yellow
    Write-Host "It is recommended to run this script with administrative privileges." -ForegroundColor Yellow
}

# --- Проверка наличия конфигурации ---
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

# Валидация конфигурации
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

# --- Выбор профиля ---
$ActiveProfile = if ($SMFProfile) { $SMFProfile } else { $SMFConfig.Profile }

if ([string]::IsNullOrEmpty($ActiveProfile)) {
    Write-Host "ERROR: No profile specified and default profile is empty." -ForegroundColor Red
    exit 1
}
if ($null -eq $SMFConfig.Profiles[$ActiveProfile]) {
    Write-Host "ERROR: Unknown profile: $ActiveProfile" -ForegroundColor Red
    exit 1
}

# --- Загрузка ядра (Core) ---
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

# Проверка, что все необходимые функции определены
$requiredFunctions = @('Initialize-SMFLogger','Write-SMFLog','Get-SMFEnvironment','Import-SMFModules','Invoke-SMFModules','New-SMFReport')
$missing = $requiredFunctions | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
if ($missing) {
    Write-Host "ERROR: Missing required core functions: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

# --- Инициализация логгера ---
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

# --- Вывод заголовка ---
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

# --- Профиль ---
Write-Host ""
Write-Host "Profile:"
Write-Host $ActiveProfile

# --- Создание контекста ---
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

# --- Загрузка и выполнение модулей ---
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
        $ModuleExecutionFailed = $true
    }
} else {
    Write-Host ""
    Write-Host "No modules to execute."
}

# --- Вывод результатов ---
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

# --- Завершение и отчёт ---
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

$FailedResults = @($SMFContext.Results | Where-Object { $_.Status -eq 'Failed' })
$ExitCode = if ($ModuleExecutionFailed -or $FailedResults.Count -gt 0) { 1 } else { 0 }
Write-SMFLog "SMF finished (exit code $ExitCode)"
Write-Host ""
Write-Host "SMF finished. Exit code: $ExitCode"
exit $ExitCode
