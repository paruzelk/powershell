#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [PSCustomObject]@{
        Name = 'Clear-WindowsFileLogs'
        Version = '1.0.0'
        Description = 'Analyze and remove old files under Windows Logs'
    }
}

function global:Invoke-ClearWindowsFileLogs {
    param($Context)

    $Result = New-SMFResult -ModuleName 'Clear-WindowsFileLogs'
    try {
        $Settings = $Context.Config.Settings.WindowsFileLogs
        if (-not $Settings.Enabled) {
            Add-SMFResultDetail $Result 'Windows file log module disabled'
            Complete-SMFResult $Result
            return $Result
        }

        $KeepDays = 0
        $ValidKeepDays = [int]::TryParse([string]$Settings.KeepDays, [ref]$KeepDays)
        if (-not $ValidKeepDays -or $KeepDays -lt 1 -or $KeepDays -gt 3650) {
            throw 'WindowsFileLogs.KeepDays must be an integer from 1 to 3650'
        }
        if ([string]::IsNullOrWhiteSpace($env:windir)) { throw 'WINDIR is empty' }
        $CutoffDate = (Get-Date).AddDays(-$KeepDays)
        $Path = Join-Path $env:windir 'Logs'
        if (-not (Test-Path -LiteralPath $Path)) {
            Add-SMFResultDetail $Result "Path not found: $Path"
            Complete-SMFResult $Result
            return $Result
        }

        $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Windows Logs root is a reparse point: $Path"
        }
        $pending = New-Object System.Collections.Stack
        $pending.Push($Path)
        while ($pending.Count -gt 0) {
            $current = [string]$pending.Pop()
            try {
                $entries = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
            } catch {
                Add-SMFResultWarning $Result "Cannot scan $current`: $($_.Exception.Message)"
                continue
            }
            $Result.DirectoriesScanned++
            foreach ($entry in $entries) {
                if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    Add-SMFResultWarning $Result "Skipping reparse point: $($entry.FullName)"
                    continue
                }
                if ($entry.PSIsContainer) {
                    $pending.Push($entry.FullName)
                    continue
                }
                if ($entry.LastWriteTime -ge $CutoffDate) { continue }
                $Result.FilesFound++
                $Result.BytesBefore += $entry.Length
                if ($Context.WhatIf -or -not $Context.ProfileSettings.Delete) {
                    Add-SMFResultDetail $Result "Would delete: $($entry.FullName)"
                    continue
                }
                try {
                    Remove-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop
                    $Result.FilesDeleted++
                    $Result.BytesFreed += $entry.Length
                } catch {
                    Add-SMFResultWarning $Result "Failed to delete: $($entry.FullName): $($_.Exception.Message)"
                }
            }
        }
        Complete-SMFResult $Result
    } catch {
        Add-SMFResultError $Result $_.Exception.Message
        Complete-SMFResult $Result 'Failed'
    }
    return $Result
}
