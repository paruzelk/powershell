#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [PSCustomObject]@{
        Name        = "Clear-YandexCache"
        Version     = "1.0.0"
        Description = "Analyze and clear Yandex Browser cache"
    }
}

function global:Invoke-ClearYandexCache {
    param($Context)

    $Result = New-SMFResult -ModuleName "Clear-YandexCache"

    try {
        $Settings = $Context.Config.Settings.BrowserCache.Yandex
        if (-not $Settings.Enabled) {
            Add-SMFResultDetail $Result "Yandex cache module disabled"
            Complete-SMFResult $Result
            return $Result
        }

        $Users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue

        foreach ($User in $Users) {
            if ($Context.Config.Settings.Temp.ExcludedUsers -contains $User.Name) { continue }

            $YandexRoot = Join-Path $User.FullName "AppData\Local\Yandex\YandexBrowser\User Data"
            if (-not (Test-Path $YandexRoot)) { continue }

            $Profiles = Get-ChildItem $YandexRoot -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile*" }

            foreach ($Profile in $Profiles) {
                $CachePaths = @(
                    "$($Profile.FullName)\Cache",
                    "$($Profile.FullName)\Code Cache",
                    "$($Profile.FullName)\GPUCache",
                    "$($Profile.FullName)\Service Worker\CacheStorage"
                )

                if ($Context.ProfileSettings.DeepClean) {
                    $CachePaths += "$($Profile.FullName)\IndexedDB"
                    $CachePaths += "$($Profile.FullName)\Service Worker\Database"
                }

                foreach ($Path in $CachePaths) {
                    if (-not (Test-Path $Path)) { continue }
                    Add-SMFResultDetail $Result "Scanning: $Path"

                    try {
                        $Files = Get-ChildItem -Path $Path -File -Recurse -Force -ErrorAction SilentlyContinue
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