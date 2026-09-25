#requires -Version 5.1

# =====================================
# Server Maintenance Framework
# Clear Recycle Bin Module
# =====================================

function global:Get-SMFModuleInfo
{
    return [PSCustomObject]@{
        Name        = "Clear-RecycleBin"
        Version     = "1.0.0"
        Description = "Analyze and clear user recycle bins"
    }
}

function global:Invoke-ClearRecycleBin
{
    param
    (
        $Context
    )

    $Result = New-SMFResult "Clear-RecycleBin"

    try
    {
        $Settings = $Context.Config.Settings.RecycleBin
        if (-not $Settings.Enabled)
        {
            Add-SMFResultDetail $Result "Recycle bin module disabled"
            Complete-SMFResult $Result
            return $Result
        }

        # Получаем список пользователей и их SID из профилей
        $profiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop
        $usersMap = @{}
        foreach ($p in $profiles)
        {
            if ($p.Special -eq $true) { continue } # пропускаем системные профили
            $sid = $p.SID
            # Попробуем получить имя пользователя из SID
            try
            {
                $objSid = New-Object System.Security.Principal.SecurityIdentifier($sid)
                $user = $objSid.Translate([System.Security.Principal.NTAccount]).Value
                $usersMap[$sid] = $user
            }
            catch
            {
                # Не удалось получить имя – оставляем SID как есть
                $usersMap[$sid] = $sid
            }
        }

        # Список исключённых пользователей (из конфига)
        $excludedUsers = $Settings.ExcludedUsers
        if ($null -eq $excludedUsers) { $excludedUsers = @() }

        # Получаем все диски с файловой системой
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }

        foreach ($drive in $drives)
        {
            $recyclePath = Join-Path $drive.Root '$Recycle.Bin'
            if (-not (Test-Path $recyclePath)) { continue }

            Add-SMFResultDetail $Result "Scanning: $recyclePath"

            # Получаем все папки с SID внутри
            $sidFolders = Get-ChildItem -Path $recyclePath -Directory -Force -ErrorAction SilentlyContinue

            foreach ($folder in $sidFolders)
            {
                $sid = $folder.Name
                # Пропускаем системные SID
                if ($sid -match '^S-1-5-(18|19|20)$') { continue }

                # Получаем имя пользователя, если есть
                $userName = if ($usersMap.ContainsKey($sid)) { $usersMap[$sid] } else { $sid }

                # Проверяем, исключён ли пользователь
                $isExcluded = $false
                foreach ($excl in $excludedUsers)
                {
                    if ($userName -like "*$excl*" -or $sid -eq $excl)
                    {
                        $isExcluded = $true
                        break
                    }
                }
                if ($isExcluded)
                {
                    Add-SMFResultDetail $Result "Skipping excluded user: $userName"
                    continue
                }

                # Подсчёт файлов в корзине
                $files = Get-ChildItem -Path $folder.FullName -File -Recurse -Force -ErrorAction SilentlyContinue
                $fileCount = $files.Count
                $totalSize = ($files | Measure-Object -Property Length -Sum).Sum

                $Result.FilesFound += $fileCount
                $Result.BytesBefore += $totalSize

                if ($Context.WhatIf)
                {
                    Add-SMFResultDetail $Result "WhatIf: Would delete $fileCount files from $userName recycle bin ($([math]::Round($totalSize/1MB,2)) MB)"
                    continue
                }

                if ($Context.ProfileSettings.Delete)
                {
                    # Удаляем все файлы внутри папки корзины (но не саму папку)
                    $deletedCount = 0
                    $freedSize = 0
                    foreach ($file in $files)
                    {
                        try
                        {
                            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                            $deletedCount++
                            $freedSize += $file.Length
                        }
                        catch
                        {
                            Add-SMFResultWarning $Result "Locked file: $($file.FullName)"
                        }
                    }
                    $Result.FilesDeleted += $deletedCount
                    $Result.BytesFreed += $freedSize
                    Add-SMFResultDetail $Result "Cleaned $deletedCount files from $userName recycle bin"
                }
                else
                {
                    Add-SMFResultDetail $Result "Analyze: Found $fileCount files in $userName recycle bin ($([math]::Round($totalSize/1MB,2)) MB)"
                }
            }
        }

        Complete-SMFResult $Result
    }
    catch
    {
        Add-SMFResultError $Result $_.Exception.Message
        Complete-SMFResult $Result "Failed"
    }

    return $Result
}