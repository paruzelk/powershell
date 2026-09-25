#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [PSCustomObject]@{
        Name        = "Clear-IISLogs"
        Version     = "1.0.0"
        Description = "Analyze and clear IIS log files"
    }
}

function global:Invoke-ClearIISLogs {
    param($Context)

    $Result = New-SMFResult -ModuleName "Clear-IISLogs"

    try {
        $Settings = $Context.Config.Settings.IIS
        $KeepDays = $Settings.KeepDays
        $CutoffDate = (Get-Date).AddDays(-$KeepDays)

        Add-SMFResultDetail $Result "Keep days: $KeepDays"

        $Paths = @("$env:SystemDrive\inetpub\logs\LogFiles")
        foreach ($Path in $Paths) {
            if (!(Test-Path $Path)) {
                Add-SMFResultDetail $Result "Path not found: $Path"
                continue
            }
            Add-SMFResultDetail $Result "Scanning: $Path"

            $Files = Get-ChildItem -Path $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -lt $CutoffDate }

            foreach ($File in $Files) {
                try {
                    $Result.FilesFound++
                    $Size = $File.Length
                    $Result.BytesBefore += $Size

                    if ($Context.WhatIf) {
                        Add-SMFResultDetail $Result "WhatIf: Would delete $($File.FullName)"
                        continue
                    }

                    if ($Context.ProfileSettings.Delete) {
                        Remove-Item -Path $File.FullName -Force -ErrorAction Stop
                        $Result.FilesDeleted++
                        $Result.BytesFreed += $Size
                    }
                }
                catch {
                    Add-SMFResultWarning $Result "Failed: $($File.FullName)"
                }
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