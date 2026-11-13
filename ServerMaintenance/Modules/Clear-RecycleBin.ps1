#requires -Version 5.1

function global:Get-SMFModuleInfo {
    return [pscustomobject]@{
        Name = 'Clear-RecycleBin'
        Version = '1.1.0'
        Description = 'Analyze and empty recycle bins for all local user SIDs'
    }
}

function global:Get-SMFRecycleRoots {
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -eq [System.IO.DriveType]::Fixed -and $drive.IsReady -and $drive.Name -match '^[A-Za-z]:\\$') {
            Write-Output $drive.Name
        }
    }
}

function global:Invoke-SMFRecycleFolder {
    param($Folder, $Context, $Result, [string]$UserName)

    try {
        if (($Folder.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Recycle bin SID folder is a reparse point: $($Folder.FullName)"
        }

        $files = New-Object System.Collections.ArrayList
        $directories = New-Object System.Collections.ArrayList
        $pending = New-Object System.Collections.Stack
        $pending.Push($Folder.FullName)
        while ($pending.Count -gt 0) {
            $current = [string]$pending.Pop()
            foreach ($entry in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
                if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Recycle bin contains a reparse point: $($entry.FullName)"
                }
                if ($entry.PSIsContainer) {
                    [void]$directories.Add($entry)
                    $pending.Push($entry.FullName)
                } else {
                    [void]$files.Add($entry)
                }
            }
        }

        [long]$totalSize = 0
        foreach ($file in $files) { $totalSize += [long]$file.Length }
        $Result.FilesFound += $files.Count
        $Result.BytesBefore += $totalSize
        $Result.DirectoriesScanned++

        if ($Context.WhatIf -or -not $Context.ProfileSettings.Delete) {
            $mode = if ($Context.WhatIf) { 'WhatIf' } else { 'Analyze' }
            Add-SMFResultDetail $Result "$mode`: Found $($files.Count) files in $UserName recycle bin"
            return
        }

        foreach ($file in $files) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $Result.FilesDeleted++
                $Result.BytesFreed += [long]$file.Length
            } catch {
                Add-SMFResultWarning $Result "Cannot delete recycle bin file $($file.FullName): $($_.Exception.Message)"
            }
        }

        foreach ($directory in @($directories | Sort-Object { $_.FullName.Length } -Descending)) {
            try {
                Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
            } catch {
                Add-SMFResultWarning $Result "Cannot remove recycle bin directory $($directory.FullName): $($_.Exception.Message)"
            }
        }
        Add-SMFResultDetail $Result "Cleaned $($files.Count) eligible files from $UserName recycle bin"
    } catch {
        Add-SMFResultWarning $Result "Cannot scan recycle bin for $UserName`: $($_.Exception.Message)"
    }
}

function global:Invoke-ClearRecycleBin {
    param($Context)

    $Result = New-SMFResult -ModuleName 'Clear-RecycleBin'
    try {
        $settings = $Context.Config.Settings.RecycleBin
        if (-not $settings.Enabled) {
            Add-SMFResultDetail $Result 'Recycle bin module disabled'
            Complete-SMFResult $Result
            return $Result
        }

        $usersMap = @{}
        try {
            $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)
            foreach ($profile in $profiles) {
                if ($profile.Special -or -not $profile.SID) { continue }
                try {
                    $sidObject = New-Object System.Security.Principal.SecurityIdentifier($profile.SID)
                    $usersMap[$profile.SID] = $sidObject.Translate([System.Security.Principal.NTAccount]).Value
                } catch {
                    $usersMap[$profile.SID] = $profile.SID
                }
            }
        } catch {
            Add-SMFResultWarning $Result "Cannot resolve profile names: $($_.Exception.Message)"
        }

        $roots = @(Get-SMFRecycleRoots)
        if ($roots.Count -eq 0) { throw 'No fixed local drive roots were discovered' }
        $excluded = @($settings.ExcludedUsers | Where-Object { $null -ne $_ -and [string]$_ -ne '' })

        foreach ($root in $roots) {
            $recyclePath = Join-Path $root '$Recycle.Bin'
            if (-not (Test-Path -LiteralPath $recyclePath)) { continue }
            try {
                $recycleItem = Get-Item -LiteralPath $recyclePath -Force -ErrorAction Stop
                if (($recycleItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Recycle root is a reparse point: $recyclePath"
                }
                $sidFolders = @(Get-ChildItem -LiteralPath $recyclePath -Directory -Force -ErrorAction Stop)
                foreach ($folder in $sidFolders) {
                    $sid = $folder.Name
                    if ($sid -notmatch '^S-\d+-\d+(-\d+)+$' -or $sid -match '^S-1-5-(18|19|20)$') { continue }
                    $expected = [System.IO.Path]::GetFullPath((Join-Path $recyclePath $sid))
                    $actual = [System.IO.Path]::GetFullPath($folder.FullName)
                    if (-not [string]::Equals($expected, $actual, [StringComparison]::OrdinalIgnoreCase)) {
                        Add-SMFResultWarning $Result "Unexpected recycle bin folder path: $actual"
                        continue
                    }
                    $userName = if ($usersMap.ContainsKey($sid)) { $usersMap[$sid] } else { $sid }
                    $isExcluded = $false
                    foreach ($item in $excluded) {
                        if ([string]::Equals([string]$item, $sid, [StringComparison]::OrdinalIgnoreCase) -or
                            [string]::Equals([string]$item, $userName, [StringComparison]::OrdinalIgnoreCase)) {
                            $isExcluded = $true
                            break
                        }
                    }
                    if ($isExcluded) {
                        Add-SMFResultDetail $Result "Skipping excluded user: $userName"
                        continue
                    }
                    Invoke-SMFRecycleFolder -Folder $folder -Context $Context -Result $Result -UserName $userName
                }
            } catch {
                Add-SMFResultWarning $Result "Cannot scan recycle root $recyclePath`: $($_.Exception.Message)"
            }
        }
        Complete-SMFResult $Result
    } catch {
        Add-SMFResultError $Result $_.Exception.Message
        Complete-SMFResult $Result 'Failed'
    }
    return $Result
}
