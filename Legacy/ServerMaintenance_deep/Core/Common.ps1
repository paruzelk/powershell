#requires -Version 5.1

function Format-SMFSize
{
    param
    (
        [long]$Bytes
    )

    if ($Bytes -ge 1GB)
    {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB)
    {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB)
    {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else
    {
        return "$Bytes Bytes"
    }
}

function Get-SMFFolderSize
{
    param
    (
        [string]$Path
    )

    if (!(Test-Path $Path))
    {
        return 0
    }

    try
    {
        $totalSize = 0L
        # Используем перечисление файлов без рекурсивного создания объектов
        $files = [System.IO.Directory]::EnumerateFiles($Path, "*", [System.IO.SearchOption]::AllDirectories)
        foreach ($file in $files)
        {
            try
            {
                $totalSize += (Get-Item -LiteralPath $file -ErrorAction Stop).Length
            }
            catch
            {
                # Пропускаем файлы, к которым нет доступа
                continue
            }
        }
        return $totalSize
    }
    catch
    {
        Write-SMFLog "Failed to calculate folder size: $Path" "WARNING"
        return 0
    }
}

function Get-SMFFileCount
{
    param
    (
        [string]$Path
    )

    if (!(Test-Path $Path))
    {
        return 0
    }

    try
    {
        $count = 0
        $files = [System.IO.Directory]::EnumerateFiles($Path, "*", [System.IO.SearchOption]::AllDirectories)
        foreach ($file in $files)
        {
            # Просто считаем файлы, не проверяя доступ – перечисление уже даёт только доступные
            $count++
        }
        return $count
    }
    catch
    {
        return 0
    }
}

function Test-SMFLocalPath
{
    param
    (
        [string]$Path
    )

    if (!$Path)
    {
        return $false
    }

    try
    {
        $Item = Get-Item $Path -Force -ErrorAction Stop
        if ($Item.PSDrive.Provider.Name -ne "FileSystem")
        {
            return $false
        }
        if ($Item.PSDrive.DriveType -eq "Network")
        {
            return $false
        }
        return $true
    }
    catch
    {
        return $false
    }
}

function Remove-SMFFileSafe
{
    param
    (
        [string]$Path
    )

    if (!(Test-Path $Path))
    {
        return $false
    }

    try
    {
        Remove-Item -Path $Path -Force -ErrorAction Stop
        Write-SMFLog "Deleted: $Path" "INFO"
        return $true
    }
    catch
    {
        Write-SMFLog "Failed delete: $Path" "WARNING"
        return $false
    }
}