#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [PSCustomObject]@{
        Name        = "Clear-WindowsLogs"
        Version     = "1.0.1"
        Description = "Analyze and clear Windows Event Logs"
    }
}

function global:Invoke-ClearWindowsLogs {
    param($Context)

    $Result = New-SMFResult -ModuleName "Clear-WindowsLogs"

    try {
        $Settings = $Context.Config.Settings.WindowsLogs
        if (-not $Settings.Enabled) {
            Add-SMFResultDetail $Result "Windows Logs module disabled"
            Complete-SMFResult $Result
            return $Result
        }

        $KeepDays = $Settings.KeepDays
        Add-SMFResultDetail $Result "Keep days: $KeepDays"
        Add-SMFResultDetail $Result "Delete mode: $($Context.ProfileSettings.Delete)"

        $Logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue

        foreach ($Log in $Logs) {
            try {
                if ($null -eq $Log -or $Log.RecordCount -le 0) { continue }
                $Result.FilesFound++
                Add-SMFResultDetail $Result "Log: $($Log.LogName) Records: $($Log.RecordCount)"

                if ($Context.WhatIf) {
                    Add-SMFResultDetail $Result "WhatIf: Would clear log $($Log.LogName)"
                    continue
                }

                if ($Context.ProfileSettings.Delete) {
                    wevtutil.exe cl "$($Log.LogName)" 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $Result.FilesDeleted++
                    } else {
                        Add-SMFResultWarning $Result "Failed to clear log: $($Log.LogName)"
                    }
                }
            }
            catch {
                Add-SMFResultWarning $Result "Exception processing log: $($Log.LogName)"
            }
        }

        Complete-SMFResult $Result
    }
    catch {
        Add-SMFResultError $Result $_.Exception.Message
        Complete-SMFResult $Result "Failed"
    }

    return $Result
}