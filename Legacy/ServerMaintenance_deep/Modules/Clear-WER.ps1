#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [PSCustomObject]@{
        Name        = "Clear-WER"
        Version     = "1.0.0"
        Description = "Analyze and clear Windows Error Reporting files"
    }
}

function global:Invoke-ClearWER {
    param($Context)

    $Result = New-SMFResult -ModuleName "Clear-WER"

    try {
        $Settings = $Context.Config.Settings.WER
        if (-not $Settings.Enabled) {
            Add-SMFResultDetail $Result "WER module disabled"
            Complete-SMFResult $Result
            return $Result
        }

        $KeepDays = $Settings.KeepDays
        $CutoffDate = (Get-Date).AddDays(-$KeepDays)
        Add-SMFResultDetail $Result "Keep days: $KeepDays"

        $Paths = @(
            "C:\ProgramData\Microsoft\Windows\WER\ReportArchive",
            "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"
        )

        $Users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
        foreach ($User in $Users) {
            if ($Context.Config.Settings.Temp.ExcludedUsers -contains $User.Name) { continue }
            $Paths += "$($User.FullName)\AppData\Local\Microsoft\Windows\WER"
        }

        foreach ($Path in $Paths) {
            if (-not (Test-Path $Path)) { continue }
            Add-SMFResultDetail $Result "Scanning: $Path"

            try {
                $Files = Get-ChildItem -Path $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
                         Where-Object { $_.LastWriteTime -lt $CutoffDate }

                foreach ($File in $Files) {
                    $Result.FilesFound++
                    $Size = $File.Length
                    $Result.BytesBefore += $Size

                    if ($Context.WhatIf) {
                        Add-SMFResultDetail $Result "WhatIf: Would delete $($File.FullName)"
                        continue
                    }

                    if ($Context.ProfileSettings.Delete) {
                        try {
                            Remove-Item -Path $File.FullName -Force -ErrorAction Stop
                            $Result.FilesDeleted++
                            $Result.BytesFreed += $Size
                        }
                        catch {
                            Add-SMFResultWarning $Result "Locked file: $($File.FullName)"
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