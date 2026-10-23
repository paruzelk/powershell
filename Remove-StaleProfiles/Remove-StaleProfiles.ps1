#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Удаление устаревших профилей пользователей на терминальных серверах Windows Server.

.DESCRIPTION
    Version 1.1.1

    Основные отличия от 1.0.2:
      * проверка AD выполняется по SID (а не по имени) и только для кандидатов;
      * защита учётных записей: Domain/Enterprise/Schema Admins, Builtin\Administrators,
        локальная группа Администраторы сервера, текущий пользователь;
      * fail-safe: в режиме Delete скрипт останавливается, если AD или список
        защищённых пользователей недоступны;
      * размер профиля считается лениво и быстро (C#, без переходов по junction);
      * активность = max(LastUseTime, NTUSER.DAT, AD LastLogonDate);
      * отчёты формируются при доступном ReportRoot; код возврата отражает результат.

    ВАЖНО: файл должен быть сохранён в UTF-8 с BOM (иначе PowerShell 5.1 испортит кириллицу).

.PARAMETER Mode
    Audit (только анализ) или Delete (удаление). Переопределяет значение из $Config.

.PARAMETER ADMode
    Disabled / Enabled / All. Переопределяет значение из $Config.

.PARAMETER Days
    Возраст профиля в днях. Переопределяет значение из $Config.

.PARAMETER NoConfirm
    Не запрашивать подтверждение удаления (для запуска по расписанию).

.EXAMPLE
    .\Remove-StaleProfiles.ps1
    .\Remove-StaleProfiles.ps1 -Mode Delete -Days 120
    .\Remove-StaleProfiles.ps1 -Mode Delete -NoConfirm
#>

[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Delete')]
    [string]$Mode,

    [ValidateSet('Disabled', 'Enabled', 'All')]
    [string]$ADMode,

    [ValidateRange(1, 3650)]
    [int]$Days,

    [switch]$NoConfirm
)

Set-StrictMode -Version 1.0


#region Configuration

$Config = [PSCustomObject]@{

    ScriptVersion = '1.1.1'

    # Audit  - только анализ
    # Delete - удаление
    Mode = 'Audit'

    # Возраст профиля (дней без активности)
    Days = 90

    # Нижняя граница для Days (защита от опечаток)
    MinimumDays = 30

    # Профили меньше указанного размера не трогаем
    MinimumProfileSizeMB = 50

    # Статус AD-учётки: Disabled - только отключённые, Enabled - только активные, All - все
    ADMode = 'Disabled'

    # Корень отчётов
    ReportRoot = 'C:\Logs\ProfileCleanup'

    # Спрашивать подтверждение перед удалением
    # (в неинтерактивном запуске без -NoConfirm удаление будет отменено)
    ConfirmBeforeDelete = $true

    # Обрабатывать только доменные учётные записи
    DomainOnly = $true

    # Учитывать "осиротевшие" SID (учётки, удалённые из AD). По умолчанию пропускаются.
    IncludeOrphanedSIDs = $false

    # Считать профиль свежим, если в AD LastLogonDate моложе порога
    UseADLastLogon = $true

    # Учитывать дату изменения NTUSER.DAT (LastUseTime на практике часто "обновляется" сам)
    UseNtUserDatTime = $true

    # Конкретный DC / Global Catalog (например 'gc01.contoso.local:3268'). Пусто = авто
    ADServer = ''

    # Удалять профили только внутри этой папки
    ProfileRoot = (Join-Path $env:SystemDrive 'Users')

    # Разделитель CSV (для русской локали Excel - ';')
    CsvDelimiter = ';'

    # Если список защищённых пользователей собран не полностью - не удалять ничего
    AbortIfProtectionIncomplete = $true

    ExcludedUsers = @(
        'Administrator'
        'Default'
        'Default User'
        'Public'
        'Guest'
    )

    # RID защищённых доменных групп: 512 Domain Admins, 519 Enterprise Admins, 518 Schema Admins
    ProtectedGroupRIDs = @(512, 519, 518)

    # Защищённые встроенные группы (проверяются и в AD, и локально на сервере)
    ProtectedBuiltinSIDs = @('S-1-5-32-544')
}

# Переопределение параметрами командной строки
if ($PSBoundParameters.ContainsKey('Mode'))   { $Config.Mode   = $Mode }
if ($PSBoundParameters.ContainsKey('ADMode')) { $Config.ADMode = $ADMode }
if ($PSBoundParameters.ContainsKey('Days'))   { $Config.Days   = $Days }
if ($NoConfirm)                               { $Config.ConfirmBeforeDelete = $false }

#endregion Configuration


#region Validation

if ($Config.Mode -notin @('Audit', 'Delete')) {
    throw 'Invalid Mode. Allowed: Audit, Delete'
}
if ($Config.ADMode -notin @('Disabled', 'Enabled', 'All')) {
    throw 'Invalid ADMode. Allowed: Disabled, Enabled, All'
}
if ($Config.Days -lt $Config.MinimumDays) {
    throw "Days ($($Config.Days)) cannot be less than MinimumDays ($($Config.MinimumDays))."
}

#endregion Validation


#region State

$script:StartTime    = Get-Date
$script:ComputerName = $env:COMPUTERNAME
$script:Threshold    = $script:StartTime.AddDays(-$Config.Days)

$script:RunFolder = Join-Path $Config.ReportRoot ($script:StartTime.ToString('yyyy-MM-dd_HHmmss'))
$script:LogFile   = Join-Path $script:RunFolder 'ProfileCleanup.log'
$script:CsvFile   = Join-Path $script:RunFolder 'ProfileCleanup.csv'
$script:HtmlFile  = Join-Path $script:RunFolder 'ProfileCleanup.html'

$script:Results = New-Object 'System.Collections.Generic.List[object]'

$script:Stats = [PSCustomObject]@{
    ProfilesFound   = 0
    ProfilesChecked = 0
    WouldDelete     = 0
    Deleted         = 0
    Skipped         = 0
    Errors          = 0
    Warnings        = 0
    FreedBytes      = [long]0
}

$script:ADAvailable        = $false
$script:ProtectionComplete = $false
$script:ADParams           = @{}
if ($Config.ADServer) { $script:ADParams['Server'] = $Config.ADServer }

$script:ADCache        = @{}
$script:ProtectedSids  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:ActiveSessions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:LocalAccountDomainSid = $null

#endregion State


#region Logging

function Initialize-Environment {
    New-Item -Path $script:RunFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    New-Item -Path $script:LogFile   -ItemType File      -Force -ErrorAction Stop | Out-Null
    Add-Content -Path $script:LogFile -Value '' -Encoding UTF8 -ErrorAction Stop
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
}

# Вывод в консоль + лог. Счётчики Warnings/Errors ведутся здесь же.
function Write-Console {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    switch ($Level) {
        'OK'      { $tag = '[ OK ]'; $color = 'Green' }
        'WARNING' { $tag = '[WARN]'; $color = 'Yellow'; $script:Stats.Warnings++ }
        'ERROR'   { $tag = '[ERR ]'; $color = 'Red';    $script:Stats.Errors++ }
        default   { $tag = '[INFO]'; $color = 'Gray' }
    }

    Write-Host "$tag $Message" -ForegroundColor $color

    $logLevel = if ($Level -eq 'OK') { 'INFO' } else { $Level }
    Write-Log -Message $Message -Level $logLevel
}

#endregion Logging


#region Utility Functions

# Быстрый подсчёт размера папки: не заходит в junction/symlink (Application Data и т.п.),
# игнорирует недоступные каталоги. Пути длиннее MAX_PATH могут не учитываться (оценка снизу).
if (-not ([System.Management.Automation.PSTypeName]'ProfileSizeHelper').Type) {
    $csharp = @'
using System;
using System.Collections.Generic;
using System.IO;

public static class ProfileSizeHelper
{
    public static long GetSize(string path)
    {
        long total = 0;
        Stack<string> stack = new Stack<string>();
        stack.Push(path);

        while (stack.Count > 0)
        {
            string dir = stack.Pop();
            try
            {
                foreach (FileSystemInfo fsi in new DirectoryInfo(dir).EnumerateFileSystemInfos())
                {
                    try
                    {
                        if ((fsi.Attributes & FileAttributes.ReparsePoint) != 0) { continue; }

                        if ((fsi.Attributes & FileAttributes.Directory) != 0)
                        {
                            stack.Push(fsi.FullName);
                        }
                        else
                        {
                            total += ((FileInfo)fsi).Length;
                        }
                    }
                    catch { }
                }
            }
            catch { }
        }
        return total;
    }
}
'@
    Add-Type -TypeDefinition $csharp -ErrorAction Stop
}

function ConvertTo-HtmlSafe {
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Convert-SidToAccount {
    param([string]$Sid)
    try {
        $id = New-Object System.Security.Principal.SecurityIdentifier($Sid)
        return $id.Translate([System.Security.Principal.NTAccount]).Value
    }
    catch {
        return $null
    }
}

function Get-SamAccountName {
    param([string]$Account)
    if (-not $Account) { return $null }
    return $Account.Split('\')[-1]
}

function Test-ConfirmAnswer {
    param([string]$Answer)
    # \u0434 = "д", \u0434\u0430 = "да" (не зависит от кодировки файла)
    return ($Answer -match '^\s*(y|yes|\u0434|\u0434\u0430)\s*$')
}

#endregion Utility Functions


#region Active Directory / Protection

function Initialize-ActiveDirectory {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $p = $script:ADParams
        # Проверка, что DC реально отвечает
        $null = Get-ADDomain @p -ErrorAction Stop
        $script:ADAvailable = $true
        Write-Console 'Active Directory доступен.' 'OK'
    }
    catch {
        $script:ADAvailable = $false
        Write-Console "Active Directory недоступен: $($_.Exception.Message)" 'WARNING'
    }
}

# Кэшированный поиск пользователя AD по SID.
# Status: Found | NotFound | Error | Unavailable  (NotFound != Error: при сбое DC профиль не трогаем)
function Get-ADUserInfo {
    param([string]$Sid)

    if ($script:ADCache.ContainsKey($Sid)) { return $script:ADCache[$Sid] }

    $result = [PSCustomObject]@{ Status = 'Unavailable'; User = $null }

    if ($script:ADAvailable) {
        $p = $script:ADParams
        try {
            $u = Get-ADUser -Identity $Sid -Properties LastLogonDate @p -ErrorAction Stop
            $result = [PSCustomObject]@{ Status = 'Found'; User = $u }
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            $result = [PSCustomObject]@{ Status = 'NotFound'; User = $null }
        }
        catch {
            Write-Log "AD lookup failed for $Sid : $($_.Exception.Message)" 'WARNING'
            $result = [PSCustomObject]@{ Status = 'Error'; User = $null }
        }
    }

    $script:ADCache[$Sid] = $result
    return $result
}

# Добавляет в защищённые всех (рекурсивных) пользователей-членов AD-группы.
# Отсутствие ожидаемой группы делает список защиты неполным.
function Add-ProtectedFromAdGroup {
    param([string]$GroupSid)

    $p = $script:ADParams
    try {
        $group = Get-ADGroup -Identity $GroupSid @p -ErrorAction Stop
        foreach ($m in (Get-ADGroupMember -Identity $group -Recursive @p -ErrorAction Stop)) {
            if ($m.objectClass -eq 'user') {
                [void]$script:ProtectedSids.Add($m.SID.Value)
            }
        }
        return $true
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Console "Не найдена защищённая группа AD: $GroupSid" 'WARNING'
        return $false
    }
    catch {
        Write-Console "Не удалось прочитать группу ${GroupSid}: $($_.Exception.Message)" 'WARNING'
        return $false
    }
}

# Члены локальной группы сервера (например, Administrators) + раскрытие вложенных доменных групп
function Add-ProtectedFromLocalGroup {
    param([string]$GroupSid)

    try {
        $sidObj  = New-Object System.Security.Principal.SecurityIdentifier($GroupSid)
        $name    = $sidObj.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $group   = [ADSI]"WinNT://$($script:ComputerName)/$name,group"
        $success = $true

        foreach ($member in @($group.psbase.Invoke('Members'))) {
            try {
                $bytes = $member.GetType().InvokeMember('objectSid', 'GetProperty', $null, $member, $null)
                $msid  = (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
                [void]$script:ProtectedSids.Add($msid)

                if ($script:ADAvailable -and $msid -like 'S-1-5-21-*') {
                    if (-not (Add-ProtectedFromAdGroup $msid)) { $success = $false }
                }
            }
            catch {
                Write-Log "Cannot read member of local group ${name}: $($_.Exception.Message)" 'WARNING'
                $success = $false
            }
        }
        return $success
    }
    catch {
        Write-Console "Не удалось прочитать локальную группу ${GroupSid}: $($_.Exception.Message)" 'WARNING'
        return $false
    }
}

function Initialize-LocalAccountDomainSid {
    $script:LocalAccountDomainSid = $null
    try {
        $accounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount = TRUE' -ErrorAction Stop |
            Where-Object { $_.SID -like 'S-1-5-21-*' })
        if ($accounts.Count -eq 0) { throw 'No local user account SID found' }

        $domainSids = @($accounts | ForEach-Object {
            (New-Object System.Security.Principal.SecurityIdentifier($_.SID)).AccountDomainSid.Value
        } | Select-Object -Unique)
        if ($domainSids.Count -ne 1) { throw 'Local user account SIDs have different account domains' }

        $script:LocalAccountDomainSid = $domainSids[0]
    }
    catch {
        Write-Console "Не удалось определить SID локальных учётных записей: $($_.Exception.Message)" 'WARNING'
    }
}

function Initialize-Protection {
    Write-Console 'Формирование списка защищённых пользователей...'

    $complete = $true

    # Текущий пользователь
    [void]$script:ProtectedSids.Add([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)

    if ($script:ADAvailable) {
        $p = $script:ADParams
        try {
            $domainSids = @((Get-ADDomain @p -ErrorAction Stop).DomainSID.Value)

            # Enterprise/Schema Admins живут в корневом домене леса
            try {
                $rootName = (Get-ADForest @p -ErrorAction Stop).RootDomain
                $domainSids += (Get-ADDomain -Identity $rootName -ErrorAction Stop).DomainSID.Value
            }
            catch {
                Write-Console "Не удалось определить корневой домен леса: $($_.Exception.Message)" 'WARNING'
                $complete = $false
            }

            foreach ($ds in ($domainSids | Select-Object -Unique)) {
                foreach ($rid in $Config.ProtectedGroupRIDs) {
                    if (-not (Add-ProtectedFromAdGroup "$ds-$rid")) { $complete = $false }
                }
            }
            foreach ($bsid in $Config.ProtectedBuiltinSIDs) {
                if (-not (Add-ProtectedFromAdGroup $bsid)) { $complete = $false }
            }
        }
        catch {
            Write-Console "Ошибка получения защищённых групп AD: $($_.Exception.Message)" 'WARNING'
            $complete = $false
        }
    }
    else {
        $complete = $false
    }

    # Локальные администраторы терминального сервера
    foreach ($bsid in $Config.ProtectedBuiltinSIDs) {
        if (-not (Add-ProtectedFromLocalGroup $bsid)) { $complete = $false }
    }

    $script:ProtectionComplete = $complete

    $level = if ($complete) { 'OK' } else { 'WARNING' }
    Write-Console "Защищённых пользователей: $($script:ProtectedSids.Count) (список полный: $complete)" $level
}

# Активные/отключённые RDS-сессии (дополнительная защита; основная - флаг Win32_UserProfile.Loaded)
function Get-ActiveRDSSessions {
    Write-Console 'Проверка RDS-сессий...'

    try {
        $lines = @(quser 2>$null)

        # Первая строка - заголовок (на любом языке системы)
        foreach ($line in ($lines | Select-Object -Skip 1)) {
            $clean = ([string]$line).TrimStart('>', ' ')
            if ($clean -match '^(\S+)') {
                [void]$script:ActiveSessions.Add($Matches[1])
            }
        }
        Write-Console "Пользователей с сессиями: $($script:ActiveSessions.Count)" 'OK'
    }
    catch {
        Write-Console "Ошибка quser: $($_.Exception.Message)" 'WARNING'
    }
}

#endregion Active Directory / Protection


#region Profile Analysis

# Возвращает объект решения. Reason пустой => профиль подлежит удалению.
# Проверки упорядочены от дешёвых к дорогим: память -> файловая система -> AD -> размер.
function Get-ProfileDecision {
    param($Profile)

    $d = [PSCustomObject]@{
        Account       = ''
        User          = ''
        Enabled       = ''
        LastActivity  = $null
        LastLogonDate = $null
        SizeBytes     = $null
        Reason        = ''
    }

    $sid  = [string]$Profile.SID
    $path = [string]$Profile.LocalPath

    if (-not $sid)             { $d.Reason = 'No SID';                         return $d }
    if ($Profile.Special)      { $d.Reason = 'Special Windows profile';        return $d }
    if ($Profile.Loaded)       { $d.Reason = 'Profile currently loaded';       return $d }
    if ($sid -notlike 'S-1-5-21-*') { $d.Reason = 'Not a user account SID';    return $d }

    # Безопасность пути
    if (-not $path) { $d.Reason = 'No LocalPath'; return $d }
    $root = $Config.ProfileRoot.TrimEnd('\') + '\'
    if (-not $path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $d.Reason = 'Profile outside ProfileRoot'
        return $d
    }
    if (-not (Test-Path -LiteralPath $path)) {
        $d.Reason = 'Profile folder not found'
        return $d
    }

    # Имя учётной записи
    $account = Convert-SidToAccount $sid
    $sam     = Get-SamAccountName $account
    $d.Account = [string]$account
    $d.User    = [string]$sam

    $isLocal = $false
    if ($account) {
        $isLocal = $account.StartsWith("$($script:ComputerName)\", [System.StringComparison]::OrdinalIgnoreCase)
    }
    if ($script:LocalAccountDomainSid) {
        $localPrefix = $script:LocalAccountDomainSid + '-'
        if ($sid.StartsWith($localPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $isLocal = $true
        }
    }

    # Правила исключения (в памяти)
    if ($sam -and ($Config.ExcludedUsers -contains $sam)) { $d.Reason = 'Excluded user';           return $d }
    if ($script:ProtectedSids.Contains($sid))             { $d.Reason = 'Protected group member';  return $d }
    if ($sam -and $script:ActiveSessions.Contains($sam))  { $d.Reason = 'Active RDS session';      return $d }

    if ($isLocal -and $Config.DomainOnly)         { $d.Reason = 'Local account';                       return $d }
    if ($isLocal -and $Config.ADMode -ne 'All')   { $d.Reason = 'Local account (ADMode not applicable)'; return $d }
    if (-not $account -and $Config.DomainOnly -and -not $script:LocalAccountDomainSid) {
        $d.Reason = 'Account origin unknown'
        return $d
    }

    # Реальная активность: max(LastUseTime, NTUSER.DAT)
    $last = $Profile.LastUseTime
    if ($Config.UseNtUserDatTime) {
        $dat = Get-Item -LiteralPath (Join-Path $path 'NTUSER.DAT') -Force -ErrorAction SilentlyContinue
        if ($dat -and ((-not $last) -or ($dat.LastWriteTime -gt $last))) {
            $last = $dat.LastWriteTime
        }
    }
    $d.LastActivity = $last

    if (-not $last)                    { $d.Reason = 'No activity data'; return $d }
    if ($last -gt $script:Threshold)   { $d.Reason = 'Recently used';    return $d }

    # Проверка AD (только для кандидатов, по SID)
    if (-not $isLocal) {
        $ad = Get-ADUserInfo $sid

        if ($ad.Status -eq 'Found') {
            $u = $ad.User
            $d.Enabled       = $u.Enabled
            $d.LastLogonDate = $u.LastLogonDate

            if ($Config.ADMode -eq 'Disabled' -and $u.Enabled)  { $d.Reason = 'AD account enabled';  return $d }
            if ($Config.ADMode -eq 'Enabled'  -and -not $u.Enabled) { $d.Reason = 'AD account disabled'; return $d }

            if ($Config.UseADLastLogon -and $u.LastLogonDate -and ($u.LastLogonDate -gt $script:Threshold)) {
                $d.Reason = 'AD last logon is recent'
                return $d
            }
        }
        elseif ($ad.Status -eq 'NotFound') {
            if (-not $Config.IncludeOrphanedSIDs) {
                $d.Reason = 'Account not found in AD (orphaned SID)'
                return $d
            }
        }
        else {
            $d.Reason = "AD lookup unavailable ($($ad.Status))"
            return $d
        }
    }

    # Размер (самая дорогая операция - в самом конце)
    $d.SizeBytes = [ProfileSizeHelper]::GetSize($path)
    if (($d.SizeBytes / 1MB) -lt $Config.MinimumProfileSizeMB) {
        $d.Reason = 'Profile too small'
        return $d
    }

    return $d
}

function Invoke-ProfileScan {
    Write-Console 'Получение профилей Windows...'

    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop)
    $script:Stats.ProfilesFound = $profiles.Count
    Write-Console "Найдено профилей: $($profiles.Count)" 'OK'

    $i = 0
    foreach ($profile in $profiles) {
        $i++
        $script:Stats.ProfilesChecked++
        Write-Progress -Activity 'Анализ профилей' -Status ([string]$profile.LocalPath) `
            -PercentComplete ([int](100 * $i / [math]::Max(1, $profiles.Count)))

        $d = Get-ProfileDecision $profile

        if ($d.Reason) {
            $action = 'SKIP'
            $script:Stats.Skipped++
        }
        else {
            $action = 'WOULD_DELETE'
            $d.Reason = 'Older than threshold'
            $script:Stats.WouldDelete++
        }

        $sizeMB = ''
        if ($null -ne $d.SizeBytes) { $sizeMB = [math]::Round($d.SizeBytes / 1MB, 2) }

        $script:Results.Add([PSCustomObject]@{
            Computer      = $script:ComputerName
            User          = $d.User
            Account       = $d.Account
            SID           = [string]$profile.SID
            ProfilePath   = [string]$profile.LocalPath
            ProfileSizeMB = $sizeMB
            Enabled       = $d.Enabled
            LastUseTime   = $profile.LastUseTime
            LastActivity  = $d.LastActivity
            LastLogonDate = $d.LastLogonDate
            Action        = $action
            Reason        = $d.Reason
            SizeBytes     = $d.SizeBytes
        })

        $who = if ($d.User) { $d.User } else { $profile.SID }
        Write-Console ("{0} : {1} ({2})" -f $who, $action, $d.Reason)
    }

    Write-Progress -Activity 'Анализ профилей' -Completed
}

#endregion Profile Analysis


#region Delete Engine

function Remove-UserProfile {
    param(
        [Parameter(Mandatory)][string]$Sid,
        [string]$ExpectedPath,
        [long]$SizeBytes
    )

    try {
        # Повторная проверка актуального состояния непосредственно перед удалением
        $current = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$Sid'" -ErrorAction Stop

        if (-not $current)        { throw 'Profile not found by SID' }
        if ($current.Special)     { throw 'Profile is special' }
        if ($current.Loaded)      { throw 'Profile is currently loaded' }

        $path = [string]$current.LocalPath
        $root = $Config.ProfileRoot.TrimEnd('\') + '\'
        if (-not $path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Profile path outside ProfileRoot: $path"
        }
        if ($ExpectedPath -and -not $path.Equals($ExpectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Profile path changed since scan: $path"
        }

        # Use current AD and group membership data; the scan may have taken a long time.
        [void]$script:ADCache.Remove($Sid)
        Initialize-ActiveDirectory
        if (-not $script:ADAvailable) { throw 'Active Directory is no longer available' }
        Initialize-Protection
        if ($Config.AbortIfProtectionIncomplete -and -not $script:ProtectionComplete) {
            throw 'Protected user list is incomplete'
        }
        Get-ActiveRDSSessions
        $decision = Get-ProfileDecision $current
        if ($decision.Reason) { throw "Profile is no longer eligible: $($decision.Reason)" }

        Write-Console "Удаление профиля: $path"
        Remove-CimInstance -InputObject $current -ErrorAction Stop

        $script:Stats.Deleted++

        if (Test-Path -LiteralPath $path) {
            Write-Console "Профиль удалён из системы, но папка осталась (файлы заняты?): $path" 'WARNING'
        }
        else {
            $script:Stats.FreedBytes += $SizeBytes
        }
        return $true
    }
    catch {
        Write-Console "Ошибка удаления [$Sid]: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Set-DeletionCancelled {
    param($Items, [string]$Why)
    foreach ($item in $Items) {
        $item.Action = 'CANCELLED'
        $item.Reason = $Why
    }
}

function Invoke-Deletion {
    $list = @($script:Results | Where-Object { $_.Action -eq 'WOULD_DELETE' })

    if ($list.Count -eq 0) {
        Write-Console 'Нет профилей для удаления.' 'OK'
        return
    }

    $totalGB = [math]::Round((($list | Measure-Object -Property SizeBytes -Sum).Sum) / 1GB, 2)
    Write-Console "Профилей к удалению: $($list.Count) (около $totalGB GB)" 'WARNING'

    if ($Config.ConfirmBeforeDelete) {
        if (-not [Environment]::UserInteractive) {
            Write-Console 'Неинтерактивный запуск с ConfirmBeforeDelete: удаление отменено (используйте -NoConfirm).' 'WARNING'
            Set-DeletionCancelled $list 'Non-interactive run, confirmation required'
            return
        }

        $answer = Read-Host 'Продолжить удаление? (Y/N)'
        if (-not (Test-ConfirmAnswer $answer)) {
            Write-Console 'Удаление отменено пользователем.' 'WARNING'
            Set-DeletionCancelled $list 'User cancelled deletion'
            return
        }
    }

    foreach ($item in $list) {
        if (Remove-UserProfile -Sid $item.SID -ExpectedPath $item.ProfilePath -SizeBytes ([long]$item.SizeBytes)) {
            $item.Action = 'DELETED'
            $item.Reason = 'Successfully deleted'
        }
        else {
            $item.Action = 'ERROR'
            $item.Reason = 'Deletion failed'
        }
    }
}

#endregion Delete Engine


#region Reports

function Export-CsvReport {
    try {
        $script:Results |
            Select-Object -Property * -ExcludeProperty SizeBytes |
            Export-Csv -Path $script:CsvFile -NoTypeInformation -Encoding UTF8 -Delimiter $Config.CsvDelimiter -ErrorAction Stop

        Write-Console "CSV-отчёт: $script:CsvFile" 'OK'
    }
    catch {
        Write-Console "Ошибка экспорта CSV: $($_.Exception.Message)" 'ERROR'
    }
}

function Export-HtmlReport {
    try {
        $sb = New-Object System.Text.StringBuilder

        foreach ($item in $script:Results) {
            $class = switch ($item.Action) {
                'DELETED'      { 'deleted' }
                'WOULD_DELETE' { 'would' }
                'ERROR'        { 'error' }
                'CANCELLED'    { 'cancelled' }
                default        { 'skip' }
            }

            $values = @(
                $item.User, $item.Account, $item.ProfilePath, $item.ProfileSizeMB, $item.Enabled,
                $item.LastActivity, $item.LastLogonDate, $item.Action, $item.Reason
            )
            $cells = ($values | ForEach-Object { '<td>' + (ConvertTo-HtmlSafe $_) + '</td>' }) -join ''
            [void]$sb.AppendLine("<tr class=""$class"">$cells</tr>")
        }

        $freedMB = [math]::Round($script:Stats.FreedBytes / 1MB, 2)

        $summary = [ordered]@{
            'Server'         = $script:ComputerName
            'Start time'     = $script:StartTime
            'Mode'           = $Config.Mode
            'AD available'   = $script:ADAvailable
            'Protection OK'  = $script:ProtectionComplete
            'AD mode'        = $Config.ADMode
            'Age threshold'  = "$($Config.Days) days"
            'Profiles found' = $script:Stats.ProfilesFound
            'Checked'        = $script:Stats.ProfilesChecked
            'Would delete'   = $script:Stats.WouldDelete
            'Deleted'        = $script:Stats.Deleted
            'Skipped'        = $script:Stats.Skipped
            'Warnings'       = $script:Stats.Warnings
            'Errors'         = $script:Stats.Errors
            'Freed space'    = "$freedMB MB"
        }

        $summaryRows = ($summary.GetEnumerator() | ForEach-Object {
            '<tr><td>' + (ConvertTo-HtmlSafe $_.Key) + '</td><td>' + (ConvertTo-HtmlSafe $_.Value) + '</td></tr>'
        }) -join "`n"

        $title = ConvertTo-HtmlSafe "Remove-StaleProfiles v$($Config.ScriptVersion)"
        $rows  = $sb.ToString()

        $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>$title</title>
<style>
body { font-family: Segoe UI, Arial; background: #f5f5f5; margin: 30px; }
h1 { color: #333; }
.card { background: white; padding: 20px; margin-bottom: 20px; border-radius: 8px; }
table { width: 100%; border-collapse: collapse; background: white; }
th { background: #333; color: white; padding: 8px; text-align: left; }
td { padding: 8px; border-bottom: 1px solid #ddd; }
.deleted { background: #d8ffd8; }
.would { background: #fff3b0; }
.skip { background: #dcecff; }
.error { background: #ffd6d6; }
.cancelled { background: #eeeeee; }
</style>
</head>
<body>
<h1>$title</h1>
<div class="card">
<h2>Execution summary</h2>
<table>
$summaryRows
</table>
</div>
<div class="card">
<h2>Profiles</h2>
<table>
<tr><th>User</th><th>Account</th><th>Profile Path</th><th>Size MB</th><th>Enabled</th><th>Last Activity</th><th>AD Last Logon</th><th>Action</th><th>Reason</th></tr>
$rows
</table>
</div>
</body>
</html>
"@

        Set-Content -Path $script:HtmlFile -Value $html -Encoding UTF8 -ErrorAction Stop
        Write-Console "HTML-отчёт: $script:HtmlFile" 'OK'
    }
    catch {
        Write-Console "Ошибка экспорта HTML: $($_.Exception.Message)" 'ERROR'
    }
}

function Write-FinalSummary {
    $exec    = (Get-Date) - $script:StartTime
    $freedMB = [math]::Round($script:Stats.FreedBytes / 1MB, 2)
    $freedGB = [math]::Round($script:Stats.FreedBytes / 1GB, 2)

    Write-Console ''
    Write-Console '================ ИТОГ ================'
    Write-Console "Server        : $script:ComputerName"
    Write-Console "Mode          : $($Config.Mode)"
    Write-Console "AD available  : $script:ADAvailable"
    Write-Console "Found         : $($script:Stats.ProfilesFound)"
    Write-Console "Checked       : $($script:Stats.ProfilesChecked)"
    Write-Console "Would delete  : $($script:Stats.WouldDelete)"
    Write-Console "Deleted       : $($script:Stats.Deleted)"
    Write-Console "Skipped       : $($script:Stats.Skipped)"
    Write-Console "Warnings      : $($script:Stats.Warnings)"
    Write-Console "Errors        : $($script:Stats.Errors)"
    Write-Console "Freed         : $freedMB MB ($freedGB GB)"
    Write-Console "Runtime       : $exec"
    Write-Console "HTML report   : $script:HtmlFile"
    Write-Console "CSV report    : $script:CsvFile"
    Write-Console '======================================'
}

#endregion Reports


#region Main

$exitCode = 0
$environmentReady = $false

try {
    Initialize-Environment
    $environmentReady = $true

    Write-Console '=================================================='
    Write-Console "Remove-StaleProfiles v$($Config.ScriptVersion)"
    Write-Console "Server: $script:ComputerName | Mode: $($Config.Mode) | AD Mode: $($Config.ADMode) | Age: $($Config.Days) d"
    Write-Console '=================================================='

    Initialize-ActiveDirectory
    Initialize-LocalAccountDomainSid
    Initialize-Protection
    Get-ActiveRDSSessions

    # Fail-safe: удаление только при полной уверенности в защите
    if ($Config.Mode -eq 'Delete') {
        if (-not $script:ADAvailable) {
            throw 'Режим Delete требует доступного Active Directory. Удаление отменено.'
        }
        if ($Config.AbortIfProtectionIncomplete -and -not $script:ProtectionComplete) {
            throw 'Список защищённых пользователей собран не полностью. Удаление отменено (см. предупреждения выше).'
        }
    }

    Invoke-ProfileScan

    if ($Config.Mode -eq 'Delete') {
        Invoke-Deletion
    }
}
catch {
    $exitCode = 2
    $criticalMessage = "Критическая ошибка: $($_.Exception.Message)"
    try {
        if ($environmentReady) {
            Write-Console $criticalMessage 'ERROR'
        }
        else {
            Write-Host "[ERR] $criticalMessage" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[ERR] $criticalMessage" -ForegroundColor Red
        Write-Host "[ERR] Не удалось записать журнал: $($_.Exception.Message)" -ForegroundColor Red
    }
}
finally {
    if ($environmentReady) {
        try { Export-CsvReport } catch { $exitCode = 2; Write-Host "[ERR] Ошибка CSV-отчёта: $($_.Exception.Message)" -ForegroundColor Red }
        try { Export-HtmlReport } catch { $exitCode = 2; Write-Host "[ERR] Ошибка HTML-отчёта: $($_.Exception.Message)" -ForegroundColor Red }
        try { Write-FinalSummary } catch { $exitCode = 2; Write-Host "[ERR] Ошибка итогового отчёта: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

if ($exitCode -eq 0 -and $script:Stats.Errors -gt 0) { $exitCode = 1 }
exit $exitCode

#endregion Main
