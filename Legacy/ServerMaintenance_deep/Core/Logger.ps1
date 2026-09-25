#requires -Version 5.1

# =====================================
# Server Maintenance Framework
# Logger
# =====================================

function Initialize-SMFLogger
{
    param
    (
        [string]$Path
    )

    try
    {
        $Directory = Split-Path $Path

        if (!(Test-Path $Directory))
        {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        if (!(Test-Path $Path))
        {
            New-Item -Path $Path -ItemType File -Force | Out-Null
        }

        $global:SMFLogPath = $Path

        Write-SMFLog "========== SMF START =========="
    }
    catch
    {
        # Если инициализация логгера не удалась, пишем в консоль и не устанавливаем глобальную переменную
        Write-Host "WARNING: Failed to initialize logger: $($_.Exception.Message)" -ForegroundColor Yellow
        $global:SMFLogPath = $null
    }
}

function Write-SMFLog
{
    param
    (
        [string]$Message,
        [string]$Level = "INFO"
    )

    # Если логгер не инициализирован, выводим в консоль (без записи в файл)
    if ($null -eq $global:SMFLogPath)
    {
        Write-Host "[$Level] $Message" -ForegroundColor Gray
        return
    }

    $Line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    try
    {
        Add-Content -Path $global:SMFLogPath -Value $Line -Encoding UTF8 -ErrorAction Stop
    }
    catch
    {
        # Если запись в файл не удалась, выводим сообщение в консоль и сбрасываем путь, чтобы не повторять ошибки
        Write-Host "WARNING: Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "[$Level] $Message" -ForegroundColor Gray
        # Сбрасываем путь, чтобы дальнейшие попытки не вызывали ошибок
        $global:SMFLogPath = $null
    }
}

function Write-SMFException
{
    param
    (
        [System.Exception]$Exception
    )

    Write-SMFLog $Exception.Message "ERROR"
}