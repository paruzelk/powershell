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

        $Files = Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.LastWriteTime -lt $CutoffDate }
        foreach ($File in $Files) {
            $Result.FilesFound++
            $Result.BytesBefore += $File.Length
            if ($Context.WhatIf -or -not $Context.ProfileSettings.Delete) {
                Add-SMFResultDetail $Result "Would delete: $($File.FullName)"
                continue
            }
            try {
                Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
                $Result.FilesDeleted++
                $Result.BytesFreed += $File.Length
            } catch {
                Add-SMFResultWarning $Result "Failed to delete: $($File.FullName): $($_.Exception.Message)"
            }
        }
        Complete-SMFResult $Result
    } catch {
        Add-SMFResultError $Result $_.Exception.Message
        Complete-SMFResult $Result 'Failed'
    }
    return $Result
}
