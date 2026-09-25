#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [PSCustomObject]@{
        Name        = "Clear-Temp"
        Version     = "1.0.0"
        Description = "Cleanup temporary files"
    }
}

function global:Invoke-ClearTemp {
    param($Context)

    $Result = New-SMFResult -ModuleName "Clear-Temp"

    try {
        $TempSettings = $Context.Config.Settings.Temp
        $MaxAgeDays = $TempSettings.MaxAgeDays
        $CutoffDate = (Get-Date).AddDays(-$MaxAgeDays)
        $Paths = @()

        if ($TempSettings.IncludeWindowsTemp) {
            $Paths += "$env:windir\Temp"
        }
        if ($TempSettings.IncludeUserTemp) {
            $Profiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
            foreach ($UserProfile in $Profiles) {
                if ($TempSettings.ExcludedUsers -contains $UserProfile.Name) { continue }
                $Paths += "$($UserProfile.FullName)\AppData\Local\Temp"
            }
        }

        foreach ($Path in $Paths) {
            if (!(Test-Path $Path)) { continue }
            Add-SMFResultDetail $Result "Scanning: $Path"
            try {
                $Files = Get-ChildItem -Path $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
                         Where-Object { $_.LastWriteTime -lt $CutoffDate }

                foreach ($File in $Files) {
                    $Result.FilesFound++
                    try {
                        $Size = $File.Length
                        $Result.BytesBefore += $Size
                        $Result.FilesProcessed++

                        if ($Context.WhatIf) {
                            Add-SMFResultDetail $Result "WhatIf: Would delete $($File.FullName)"
                        } elseif ($Context.ProfileSettings.Delete) {
                            Remove-Item -Path $File.FullName -Force -ErrorAction Stop
                            $Result.FilesDeleted++
                            $Result.BytesFreed += $Size
                        }
                    }
                    catch {
                        if ($TempSettings.SkipLockedFiles) {
                            Add-SMFResultWarning $Result "Locked file skipped: $($File.FullName)"
                        } else {
                            Add-SMFResultError $Result $_.Exception.Message
                        }
                    }
                }
            }
            catch {
                Add-SMFResultWarning $Result "Scan failed: $Path"
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