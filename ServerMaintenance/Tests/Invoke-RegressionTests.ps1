#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('SMF-Regression-' + [guid]::NewGuid().ToString('N'))
$Passed = 0
$Failed = 0

function Assert-SMFTest {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        $script:Passed++
        Write-Output "PASS: $Name"
    } else {
        $script:Failed++
        Write-Output "FAIL: $Name"
    }
}

function New-SMFLauncherFixture {
    param([string]$Path)
    [void](New-Item -ItemType Directory -Path (Join-Path $Path 'Config'), (Join-Path $Path 'Core') -Force)
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'Start-SMF.ps1') -Destination (Join-Path $Path 'Start-SMF.ps1')
    @'
$SMFConfig = @{
    Profile = 'Analyze'
    Modules = @{ Fake = @{ Enabled = $true; Order = 1; Profiles = @('Analyze','Day','Night') } }
    Profiles = @{
        Analyze = @{ Delete = $false; DeepClean = $false; GenerateReport = $false }
        Day = @{ Delete = $true; DeepClean = $false; GenerateReport = $false }
        Night = @{ Delete = $true; DeepClean = $true; GenerateReport = $false }
    }
}
'@ | Set-Content -LiteralPath (Join-Path $Path 'Config\Config.ps1') -Encoding Ascii
    @'
function Initialize-SMFLogger { param($Path) }
function Write-SMFLog { param($Message, $Level) }
function Get-SMFEnvironment { return [pscustomobject]@{ Admin = $false } }
function Import-SMFModules { param($ModulesPath,$Config,$Profile) return [pscustomobject]@{ Name='Fake'; Order=1; ExecuteFunction='Invoke-Fake'; Status='Registered' } }
function Invoke-SMFModules {
    param($Context,$Modules)
    Set-Content -LiteralPath (Join-Path $Context.Root 'ObservedProfile.txt') -Value $Context.Profile -Encoding Ascii
    $status = if ($Context.Profile -eq 'Day') { 'Failed' } elseif ($Context.Profile -eq 'Analyze') { 'Partial' } else { 'Completed' }
    [void]$Context.Results.Add([pscustomobject]@{
        Module='Fake'; Status=$status; StartTime=Get-Date; EndTime=Get-Date; Duration=[timespan]::Zero
        FilesFound=0; FilesProcessed=0; FilesDeleted=0; BytesBefore=0; BytesFreed=0
        Errors=@(); Warnings=@()
    })
}
function New-SMFReport { param($Context) if (Test-Path -LiteralPath (Join-Path $Context.Root 'FailReport.txt')) { throw 'report failed' } }
'@ | Set-Content -LiteralPath (Join-Path $Path 'Core\Fixture.ps1') -Encoding Ascii
}

try {
    [void](New-Item -ItemType Directory -Path $TestRoot -Force)
    $Fixture = Join-Path $TestRoot 'Launcher'
    New-SMFLauncherFixture -Path $Fixture
    $Launcher = Join-Path $Fixture 'Start-SMF.ps1'

    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher -Profile Night 2>&1
    $Observed = Get-Content -LiteralPath (Join-Path $Fixture 'ObservedProfile.txt') -Raw
    Assert-SMFTest ($Observed.Trim() -eq 'Night') 'Documented -Profile selects Night'

    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher -Profile Day 2>&1
    Assert-SMFTest ($LASTEXITCODE -ne 0) 'Failed module gives nonzero process exit'

    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher -Profile Analyze 2>&1
    Assert-SMFTest ($LASTEXITCODE -eq 2) 'Partial module gives distinct process exit'

    Set-Content -LiteralPath (Join-Path $Fixture 'FailReport.txt') -Value 'fail' -Encoding Ascii
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher -Profile Night 2>&1
    Assert-SMFTest ($LASTEXITCODE -eq 1) 'Report failure gives nonzero process exit'
    Remove-Item -LiteralPath (Join-Path $Fixture 'FailReport.txt')

    $ErrorActionPreference = 'Continue'
    try { $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher -UnknownOption 2>&1 }
    finally { $ErrorActionPreference = 'Stop' }
    Assert-SMFTest ($LASTEXITCODE -ne 0) 'Unknown launcher option is rejected'

    . (Join-Path $ProjectRoot 'Core\Module.ps1')
    . (Join-Path $ProjectRoot 'Core\ModuleLoader.ps1')
    function Write-SMFLog { param($Message,$Level) }
    $missingThrown = $false
    try {
        $null = Import-SMFModules -ModulesPath (Join-Path $TestRoot 'NoModules') -Config @{ Modules = @{ Missing = @{ Enabled = $true; Order = 1; Profiles = @('Analyze') } } } -Profile Analyze
    } catch { $missingThrown = $true }
    Assert-SMFTest $missingThrown 'Missing enabled module fails loading'

    . (Join-Path $ProjectRoot 'Core\Common.ps1')
    $LiteralDir = Join-Path $TestRoot 'Literal'
    [void](New-Item -ItemType Directory -Path $LiteralDir)
    $LiteralFile = Join-Path $LiteralDir 'item[1].tmp'
    $NeighborFile = Join-Path $LiteralDir 'item1.tmp'
    Set-Content -LiteralPath $LiteralFile -Value 'target' -Encoding Ascii
    Set-Content -LiteralPath $NeighborFile -Value 'neighbor' -Encoding Ascii
    $removed = Remove-SMFFileSafe -Path $LiteralFile
    Assert-SMFTest ($removed -and -not (Test-Path -LiteralPath $LiteralFile) -and (Test-Path -LiteralPath $NeighborFile)) 'Literal cleanup removes only bracketed filename'
    $IsolatedFile = Join-Path $LiteralDir 'only[2].tmp'
    Set-Content -LiteralPath $IsolatedFile -Value 'isolated' -Encoding Ascii
    $removed = Remove-SMFFileSafe -Path $IsolatedFile
    Assert-SMFTest ($removed -and -not (Test-Path -LiteralPath $IsolatedFile)) 'Literal cleanup recognizes bracketed filename without wildcard match'

    . (Join-Path $ProjectRoot 'Core\Result.ps1')
    $warningResult = New-SMFResult -ModuleName 'WarningCase'
    Add-SMFResultWarning $warningResult 'One file was locked'
    Complete-SMFResult $warningResult
    Assert-SMFTest ($warningResult.Status -eq 'Partial') 'Warning produces Partial result'
    $errorResult = New-SMFResult -ModuleName 'ErrorCase'
    Add-SMFResultError $errorResult 'Scan failed'
    Complete-SMFResult $errorResult
    Assert-SMFTest ($errorResult.Status -eq 'Failed') 'Error produces Failed result'
    $fixtureRunContext = [pscustomobject]@{ Results = [System.Collections.ArrayList]::new() }
    Invoke-SMFModules -Context $fixtureRunContext -Modules @([pscustomobject]@{ Name = 'MissingAtRun'; ExecuteFunction = 'Invoke-NotAvailable' })
    Assert-SMFTest ($fixtureRunContext.Results.Count -eq 1 -and $fixtureRunContext.Results[0].Status -eq 'Failed') 'Missing function at execution creates failed result'

    foreach ($moduleName in @('Temp','WER','IISLogs')) {
        . (Join-Path $ProjectRoot "Modules\Clear-$moduleName.ps1")
        $settingsKey = if ($moduleName -eq 'IISLogs') { 'IIS' } else { $moduleName }
        $settings = @{ Temp = @{ MaxAgeDays = -1; IncludeWindowsTemp = $true; IncludeUserTemp = $false };
                       WER = @{ Enabled = $true; KeepDays = -1 };
                       IIS = @{ Enabled = $true; KeepDays = -1 } }
        $invalidContext = [pscustomobject]@{
            Config = @{ Settings = $settings }
            ProfileSettings = @{ Delete = $true }
            WhatIf = $false
        }
        $command = if ($moduleName -eq 'IISLogs') { 'Invoke-ClearIISLogs' } else { "Invoke-Clear$moduleName" }
        $result = & $command -Context $invalidContext
        Assert-SMFTest ($result.Status -eq 'Failed' -and $result.FilesDeleted -eq 0 -and ($result.Errors -join ' ') -match 'days|retention') "$settingsKey rejects negative retention"
    }

    $FileLogModule = Join-Path $ProjectRoot 'Modules\Clear-WindowsFileLogs.ps1'
    if (Test-Path -LiteralPath $FileLogModule) {
        . $FileLogModule
        $FakeWindows = Join-Path $TestRoot 'Windows'
        $LogDir = Join-Path $FakeWindows 'Logs'
        [void](New-Item -ItemType Directory -Path $LogDir -Force)
        $Old = Join-Path $LogDir 'old.log'
        $Recent = Join-Path $LogDir 'recent.log'
        Set-Content -LiteralPath $Old -Value 'old' -Encoding Ascii
        Set-Content -LiteralPath $Recent -Value 'recent' -Encoding Ascii
        (Get-Item -LiteralPath $Old).LastWriteTime = (Get-Date).AddDays(-40)
        $originalWindir = $env:windir
        try {
            $env:windir = $FakeWindows
            $context = [pscustomobject]@{
                Config = @{ Settings = @{ WindowsFileLogs = @{ Enabled = $true; KeepDays = 30 } } }
                ProfileSettings = @{ Delete = $true }
                WhatIf = $false
            }
            $result = Invoke-ClearWindowsFileLogs -Context $context
            Assert-SMFTest ($result.FilesDeleted -eq 1 -and -not (Test-Path -LiteralPath $Old) -and (Test-Path -LiteralPath $Recent)) 'Windows file logs respect retention'
            Set-Content -LiteralPath $Old -Value 'old again' -Encoding Ascii
            (Get-Item -LiteralPath $Old).LastWriteTime = (Get-Date).AddDays(-40)
            $context.ProfileSettings.Delete = $false
            $result = Invoke-ClearWindowsFileLogs -Context $context
            Assert-SMFTest ($result.FilesFound -eq 1 -and $result.FilesDeleted -eq 0 -and (Test-Path -LiteralPath $Old)) 'Analyze keeps eligible Windows file logs'
            $context.ProfileSettings.Delete = $true
            $context.WhatIf = $true
            $result = Invoke-ClearWindowsFileLogs -Context $context
            Assert-SMFTest ($result.FilesFound -eq 1 -and $result.FilesDeleted -eq 0 -and (Test-Path -LiteralPath $Old)) 'WhatIf keeps eligible Windows file logs'
            $context.WhatIf = $false
            $context.Config.Settings.WindowsFileLogs.KeepDays = -1
            $result = Invoke-ClearWindowsFileLogs -Context $context
            Assert-SMFTest ($result.Status -eq 'Failed' -and (Test-Path -LiteralPath $Recent)) 'Invalid retention fails without deleting Windows file logs'
            $context.Config.Settings.WindowsFileLogs.KeepDays = 30
            $context.ProfileSettings.Delete = $false
            $GoodDir = Join-Path $LogDir 'Good'
            $DeniedDir = Join-Path $LogDir 'Denied'
            [void](New-Item -ItemType Directory -Path $GoodDir, $DeniedDir -Force)
            $GoodFile = Join-Path $GoodDir 'old.log'
            Set-Content -LiteralPath $GoodFile -Value 'good' -Encoding Ascii
            (Get-Item -LiteralPath $GoodFile).LastWriteTime = (Get-Date).AddDays(-40)
            $script:DeniedLogDir = $DeniedDir
            function global:Get-ChildItem {
                param($LiteralPath, [switch]$File, [switch]$Directory, [switch]$Recurse, [switch]$Force, $ErrorAction)
                if ($LiteralPath -eq $script:DeniedLogDir) { throw 'fixture access denied' }
                Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
            }
            try {
                $result = Invoke-ClearWindowsFileLogs -Context $context
                Assert-SMFTest ($result.Status -eq 'Partial' -and $result.FilesFound -ge 2 -and (Test-Path -LiteralPath $GoodFile)) 'Unreadable log subfolder leaves other folders inventoried'
            } finally { Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue }
        } finally { $env:windir = $originalWindir }
    } else {
        Assert-SMFTest $false 'Windows file log module exists'
    }

    . (Join-Path $ProjectRoot 'Modules\Clear-WindowsLogs.ps1')
    $script:EventClearCalled = $false
    function global:Get-WinEvent { param($ListLog,$ErrorAction) return [pscustomobject]@{LogName='Application';RecordCount=1} }
    function global:wevtutil.exe { $script:EventClearCalled = $true }
    $context = [pscustomobject]@{
        Config = @{ Settings = @{ WindowsLogs = @{ Enabled = $true; KeepDays = 30 } } }
        ProfileSettings = @{ Delete = $true }
        WhatIf = $false
    }
    $null = Invoke-ClearWindowsLogs -Context $context
    Assert-SMFTest (-not $script:EventClearCalled) 'Event Log inventory never clears channels'

    Remove-Item Function:\Get-WinEvent -ErrorAction SilentlyContinue
    Remove-Item Function:\wevtutil.exe -ErrorAction SilentlyContinue

    . (Join-Path $ProjectRoot 'Modules\Clear-RecycleBin.ps1')
    $RecycleDrive = Join-Path $TestRoot 'RecycleDrive'
    $RecycleRoot = Join-Path $RecycleDrive '$Recycle.Bin'
    $UserSid = 'S-1-5-21-100-200-300-1001'
    $UserBin = Join-Path $RecycleRoot $UserSid
    $NestedBin = Join-Path $UserBin '$Rfolder'
    [void](New-Item -ItemType Directory -Path $NestedBin -Force)
    $BinFile = Join-Path $NestedBin 'item[1].txt'
    Set-Content -LiteralPath $BinFile -Value 'recycled' -Encoding Ascii
    $script:MockRecycleRoot = $RecycleDrive
    function global:Get-SMFRecycleRoots { return @($script:MockRecycleRoot) }
    function global:Get-CimInstance { param($ClassName,$ErrorAction) return @() }
    $recycleContext = [pscustomobject]@{
        Config = @{ Settings = @{ RecycleBin = @{ Enabled = $true; ExcludedUsers = @() } } }
        ProfileSettings = @{ Delete = $false }
        WhatIf = $false
    }
    $result = Invoke-ClearRecycleBin -Context $recycleContext
    Assert-SMFTest ($result.FilesFound -eq 1 -and $result.FilesDeleted -eq 0 -and (Test-Path -LiteralPath $BinFile)) 'Analyze inventories another user recycle bin'
    $recycleContext.ProfileSettings.Delete = $true
    $recycleContext.WhatIf = $true
    $result = Invoke-ClearRecycleBin -Context $recycleContext
    Assert-SMFTest ($result.FilesFound -eq 1 -and $result.FilesDeleted -eq 0 -and (Test-Path -LiteralPath $BinFile)) 'WhatIf keeps another user recycle bin'
    $recycleContext.WhatIf = $false
    $recycleContext.Config.Settings.RecycleBin.ExcludedUsers = @($UserSid)
    $result = Invoke-ClearRecycleBin -Context $recycleContext
    Assert-SMFTest ($result.FilesDeleted -eq 0 -and (Test-Path -LiteralPath $BinFile)) 'Exact SID exclusion protects a recycle bin'
    $recycleContext.Config.Settings.RecycleBin.ExcludedUsers = @()
    $linkFolder = [pscustomobject]@{ FullName = $UserBin; Attributes = [System.IO.FileAttributes]::ReparsePoint }
    $linkResult = New-SMFResult -ModuleName 'RecycleLink'
    Invoke-SMFRecycleFolder -Folder $linkFolder -Context $recycleContext -Result $linkResult -UserName $UserSid
    Complete-SMFResult $linkResult
    Assert-SMFTest ($linkResult.Status -eq 'Partial' -and (Test-Path -LiteralPath $BinFile)) 'Recycle bin refuses a reparse point SID folder'
    $result = Invoke-ClearRecycleBin -Context $recycleContext
    Assert-SMFTest ($result.FilesDeleted -eq 1 -and -not (Test-Path -LiteralPath $BinFile) -and -not (Test-Path -LiteralPath $NestedBin) -and (Test-Path -LiteralPath $UserBin)) 'Cleanup empties another user recycle bin without removing SID folder'
    Remove-Item Function:\Get-SMFRecycleRoots -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue

    $script:ScannedCachePaths = @()
    function global:Test-Path { param($Path) return $true }
    function global:Get-ChildItem {
        param($Path, [switch]$Directory, [switch]$File, [switch]$Recurse, [switch]$Force, $ErrorAction)
        if ($Path -eq 'C:\Users') { return [pscustomobject]@{ Name = 'Tester'; FullName = 'C:\Users\Tester' } }
        if ($Directory) { return [pscustomobject]@{ Name = 'Default'; FullName = (Join-Path $Path 'Default') } }
        $script:ScannedCachePaths += $Path
        return @()
    }
    $browserContext = [pscustomobject]@{
        Config = @{ Settings = @{
            BrowserCache = @{
                Chrome = @{ Enabled = $true }; Edge = @{ Enabled = $true }; Yandex = @{ Enabled = $true }
                IncludeSiteStorage = $false
            }
            Temp = @{ ExcludedUsers = @() }
        } }
        ProfileSettings = @{ Delete = $true; DeepClean = $true }
        WhatIf = $true
    }
    foreach ($name in @('Chrome','Edge','Yandex')) {
        . (Join-Path $ProjectRoot "Modules\Clear-$($name)Cache.ps1")
        $command = "Invoke-Clear$($name)Cache"
        $null = & $command -Context $browserContext
    }
    $siteStorageScanned = @($script:ScannedCachePaths | Where-Object { $_ -match 'IndexedDB|Service Worker\\Database' }).Count -gt 0
    Assert-SMFTest (-not $siteStorageScanned -and $script:ScannedCachePaths.Count -gt 0) 'Night excludes browser site storage by default'

    Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-SMFRecycleRoots -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
    $ReportFixture = Join-Path $TestRoot 'ReportHelper'
    $ReportDir = Join-Path $ReportFixture 'Reports'
    [void](New-Item -ItemType Directory -Path $ReportDir -Force)
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'JSON-totalFreedMB.ps1') -Destination (Join-Path $ReportFixture 'JSON-totalFreedMB.ps1')
    '{"Modules":[{"BytesFreed":1048576},{"BytesFreed":2097152}]}' |
        Set-Content -LiteralPath (Join-Path $ReportDir 'sample.json') -Encoding Ascii
    $helperOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ReportFixture 'JSON-totalFreedMB.ps1') 2>&1
    Assert-SMFTest (($helperOutput -join ' ') -match 'Total freed: 3(\.0+)? MB') 'JSON helper reads reports beside its script'

    . (Join-Path $ProjectRoot 'Core\Report.ps1')
    $BlockedReportPath = Join-Path $TestRoot 'BlockedReportPath'
    Set-Content -LiteralPath $BlockedReportPath -Value 'file' -Encoding Ascii
    $reportContext = [pscustomobject]@{
        ProfileSettings = @{ GenerateReport = $true }
        ReportPath = $BlockedReportPath
        Version = 'test'; ComputerName = 'fixture'; Profile = 'Analyze'; RunId = 'fixture'
        StartTime = Get-Date; EndTime = Get-Date; Duration = [timespan]::Zero
        Results = [System.Collections.ArrayList]::new()
    }
    $reportThrew = $false
    $ErrorActionPreference = 'Continue'
    try { New-SMFReport -Context $reportContext } catch { $reportThrew = $true }
    finally { $ErrorActionPreference = 'Stop' }
    Assert-SMFTest $reportThrew 'Report writer propagates filesystem failure'
    $reportContext.ReportPath = $ReportDir
    $unsafeResult = New-SMFResult -ModuleName 'Unsafe'
    Add-SMFResultWarning $unsafeResult '<script>alert(1)</script>'
    Complete-SMFResult $unsafeResult
    [void]$reportContext.Results.Add($unsafeResult)
    New-SMFReport -Context $reportContext
    $htmlReport = Get-ChildItem -LiteralPath $ReportDir -Filter '*.html' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $htmlText = Get-Content -LiteralPath $htmlReport.FullName -Raw
    Assert-SMFTest ($htmlText.Contains('&lt;script&gt;alert(1)&lt;/script&gt;') -and -not $htmlText.Contains('<script>alert(1)</script>')) 'HTML report escapes warning text'
} finally {
    Remove-Item Function:\Get-WinEvent -ErrorAction SilentlyContinue
    Remove-Item Function:\wevtutil.exe -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
    $ExpectedTempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $ResolvedTestRoot = [System.IO.Path]::GetFullPath($TestRoot)
    if ($ResolvedTestRoot.StartsWith(($ExpectedTempParent + '\SMF-Regression-'), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $TestRoot)) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}

Write-Output "Tests: $Passed passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
exit 0
