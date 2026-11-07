#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [PSCustomObject]@{
        Name        = "Clear-WindowsLogs"
        Version     = "1.0.1"
        Description = "Inventory Windows Event Logs without clearing channels"
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

        Add-SMFResultDetail $Result "Event Log inventory only; channel clear disabled"

        $Logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue

        foreach ($Log in $Logs) {
            try {
                if ($null -eq $Log -or $Log.RecordCount -le 0) { continue }
                $Result.FilesFound++
                Add-SMFResultDetail $Result "Log: $($Log.LogName) Records: $($Log.RecordCount)"

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
