<#
.SYNOPSIS
    HTML-отчёт по SMB-шарам / произвольным путям: share-права + NTFS-права (дерево) + состав AD-групп.
.DESCRIPTION
    Без -Drives: собирает все файловые SMB-шары локального сервера.
    С -Drives: сканирует только указанные диски/пути (локальные, сетевые, UNC).
    Для каждой шары/пути выводит:
      - права уровня шары (Get-SmbShareAccess, если это реальная шара);
      - NTFS-права корня и подпапок (Get-Acl) в виде дерева;
      - для доменных групп — раскрывает состав участников (рекурсивно).
    По умолчанию показывает только папки с явными (не наследуемыми) ACE.
.PARAMETER OutputPath
    Путь к итоговому HTML-файлу.
.PARAMETER Drives
    Массив дисков/путей для сканирования. Примеры: 'C','D','Z:','C:\Data','\\srv\share'.
    Если не указан — сканируются все SMB-шары.
.PARAMETER ResolveGroups
    Раскрывать ли состав AD-групп. По умолчанию $true.
.PARAMETER IncludeSystemAccounts
    Включать ли служебные учётки (SYSTEM, Administrators, Everyone и т.п.). По умолчанию $true: для аудита важно видеть все ACE.
.PARAMETER MaxDepth
    На сколько уровней вглубь обходить подпапки (0 = только корень).
.PARAMETER OnlyExplicitAcl
    $true — показывать только папки с явными (не наследуемыми) ACE.
.PARAMETER ScanSubfolders
    $false — вообще не обходить подпапки.
.NOTES
    Запускать от администратора на файловом сервере.
    Файл сохранять в UTF-8 with BOM (PowerShell ISE делает это по умолчанию).
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\SMB_Shares_AD_Report.html",
    [string[]]$Drives = @(),
    [bool]$ResolveGroups = $true,
    [bool]$IncludeSystemAccounts = $true,
    [ValidateRange(0, 64)][int]$MaxDepth = 5,
    [bool]$OnlyExplicitAcl = $true,
    [bool]$ScanSubfolders = $true
)

Add-Type -AssemblyName System.Web
$scanWarnings = New-Object 'System.Collections.Generic.List[string]'

$adAvailable = $false
if ($ResolveGroups) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $adAvailable = $true
    } catch {
        $message = "Модуль ActiveDirectory не найден. Состав групп раскрываться не будет."
        $scanWarnings.Add($message)
        Write-Warning $message
        $ResolveGroups = $false
    }
}

# --- Служебные учётки по SID ---
$wellKnownSids = @(
    'S-1-5-18',        # SYSTEM
    'S-1-5-32-544',    # Administrators
    'S-1-5-32-545',    # Users
    'S-1-5-11',        # Authenticated Users
    'S-1-1-0',         # Everyone
    'S-1-3-0',         # CREATOR OWNER
    'S-1-5-32-546',    # Guests
    'S-1-5-32-547',    # Power Users
    'S-1-5-32-555',    # Remote Desktop Users
    'S-1-5-32-562'     # Distributed COM Users
)

function Test-IsSystemAccount {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $false }
    try {
        $sid = (New-Object System.Security.Principal.NTAccount($Name)).Translate(
            [System.Security.Principal.SecurityIdentifier]
        ).Value
        return ($wellKnownSids -contains $sid)
    } catch {
        return ($Name -match '^(NT AUTHORITY|NT SERVICE|BUILTIN)\\' -or
                $Name -eq 'Everyone' -or
                $Name -eq 'CREATOR OWNER' -or
                $Name -eq 'Все' -or
                $Name -eq 'СОЗДАТЕЛЬ-ВЛАДЕЛЕЦ')
    }
}

# --- Кэши ---
$groupMembersCache = @{}
$adGroupCache = @{}

function Resolve-AdGroup {
    param([string]$AccountName)
    if ($adGroupCache.ContainsKey($AccountName)) { return $adGroupCache[$AccountName] }
    $group = $null
    try {
        $sid = if ($AccountName -match '^S-\d+(?:-\d+)+$') {
            $AccountName
        } else {
            (New-Object System.Security.Principal.NTAccount($AccountName)).Translate(
                [System.Security.Principal.SecurityIdentifier]
            ).Value
        }
        $group = Get-ADGroup -Identity $sid -ErrorAction Stop
    } catch {
        Write-Verbose "Не удалось определить AD-группу для $AccountName : $_"
    }
    $adGroupCache[$AccountName] = $group
    return $group
}

function Get-GroupMembersRecursive {
    param(
        [string]$GroupIdentity,
        [System.Collections.Generic.HashSet[string]]$Visited
    )
    if (-not $ResolveGroups -or -not $adAvailable) { return @() }
    if ($Visited.Contains($GroupIdentity)) { return @() }
    [void]$Visited.Add($GroupIdentity)

    $members = @()
    try {
        if ($groupMembersCache.ContainsKey($GroupIdentity)) {
            $raw = $groupMembersCache[$GroupIdentity]
        } else {
            $raw = @(Get-ADGroupMember -Identity $GroupIdentity -ErrorAction Stop)
            $groupMembersCache[$GroupIdentity] = $raw
        }
        foreach ($m in $raw) {
            $memberIdentity = if ($m.DistinguishedName) { $m.DistinguishedName } elseif ($m.SID) { $m.SID.Value } else { $m.SamAccountName }
            switch ($m.objectClass) {
                'user' {
                    $display = $m.SamAccountName
                    try {
                        $user = Get-ADUser -Identity $memberIdentity -Properties DisplayName -ErrorAction Stop
                        if ($user.DisplayName) { $display = "$($user.DisplayName) ($($m.SamAccountName))" }
                    } catch {
                        Write-Verbose "Не удалось получить имя пользователя $memberIdentity : $_"
                    }
                    $members += [PSCustomObject]@{
                        Name = $display
                        Type = 'Пользователь'
                        Sam  = $m.SamAccountName
                        Identity = $memberIdentity
                    }
                }
                'group' {
                    $members += [PSCustomObject]@{
                        Name = $m.SamAccountName
                        Type = 'Группа (вложенная)'
                        Sam  = $m.SamAccountName
                        Identity = $memberIdentity
                    }
                    $sub = @(Get-GroupMembersRecursive -GroupIdentity $memberIdentity -Visited $Visited)
                    foreach ($s in $sub) { $members += $s }
                }
                'computer' {
                    $members += [PSCustomObject]@{
                        Name = $m.SamAccountName
                        Type = 'Компьютер'
                        Sam  = $m.SamAccountName
                        Identity = $memberIdentity
                    }
                }
                default {
                    $members += [PSCustomObject]@{
                        Name = $m.SamAccountName
                        Type = $m.objectClass
                        Sam  = $m.SamAccountName
                        Identity = $memberIdentity
                    }
                }
            }
        }
    } catch {
        $message = "Не удалось получить членов группы $GroupIdentity : $_"
        $scanWarnings.Add($message)
        Write-Warning $message
    } finally {
        [void]$Visited.Remove($GroupIdentity)
    }

    return @($members | Sort-Object Identity -Unique)
}

# --- ACE для одной папки ---
function Get-AcesForPath {
    param(
        [string]$Path,
        [bool]$OnlyExplicitAcl,
        [bool]$ResolveGroups,
        [bool]$AdAvailable,
        [bool]$IncludeSystemAccounts
    )

    $aces = @()
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    } catch {
        $message = "Не удалось прочитать ACL: $Path — $_"
        $scanWarnings.Add($message)
        Write-Warning $message
        return $aces
    }

    foreach ($ace in $acl.Access) {
        $identity    = $ace.IdentityReference.Value
        $isInherited = $ace.IsInherited

        if ($OnlyExplicitAcl -and $isInherited) { continue }
        if (-not $IncludeSystemAccounts -and (Test-IsSystemAccount $identity)) { continue }

        $members = @()
        if ($ResolveGroups -and $AdAvailable) {
            $adGroup = Resolve-AdGroup -AccountName $identity
            if ($adGroup) {
                $visited = New-Object 'System.Collections.Generic.HashSet[string]'
                $members = @(Get-GroupMembersRecursive -GroupIdentity $adGroup.DistinguishedName -Visited $visited)
            }
        }

        $aces += [PSCustomObject]@{
            Identity    = $identity
            AccessType  = $ace.AccessControlType
            Rights      = $ace.FileSystemRights
            Inheritance = $isInherited
            Members     = $members
        }
    }

    return $aces
}

# --- Рекурсивное дерево папок ---
function Get-FolderAclTree {
    param(
        [string]$RootPath,
        [int]$MaxDepth,
        [bool]$OnlyExplicitAcl,
        [bool]$ResolveGroups,
        [bool]$AdAvailable,
        [bool]$IncludeSystemAccounts
    )

    $result = New-Object System.Collections.Generic.List[object]

    function Walk {
        param([string]$Path, [int]$Depth, [string]$RelativePath)

        $aces = @(Get-AcesForPath -Path $Path `
                                -OnlyExplicitAcl $OnlyExplicitAcl `
                                -ResolveGroups $ResolveGroups `
                                -AdAvailable $AdAvailable `
                                -IncludeSystemAccounts $IncludeSystemAccounts)

        if ($aces.Count -gt 0 -or -not $OnlyExplicitAcl) {
            $result.Add([PSCustomObject]@{
                Path         = $Path
                RelativePath = $RelativePath
                Depth        = $Depth
                Aces         = $aces
            }) | Out-Null
        }

        if ($Depth -ge $MaxDepth) { return }

        $subDirs = @()
        try {
            $subDirs = Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction Stop
        } catch {
            $message = "Не удалось прочитать содержимое: $Path — $_"
            $scanWarnings.Add($message)
            Write-Warning $message
            return
        }

        foreach ($d in $subDirs) {
            if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $rel = if ($RelativePath) { "$RelativePath\$($d.Name)" } else { $d.Name }
            Walk -Path $d.FullName -Depth ($Depth + 1) -RelativePath $rel
        }
    }

    Walk -Path $RootPath -Depth 0 -RelativePath ''
    return $result
}

# --- Формирование списка целей (шары или указанные пути) ---
$targets = @()
$modeLabel = ''

if ($Drives.Count -gt 0) {
    $modeLabel = 'Указанные пути'
    Write-Host "Режим: сканирование указанных путей" -ForegroundColor Cyan

    foreach ($d in $Drives) {
        $original = $d
        $normalized = $d.Trim()

        # 'C' / 'c' / 'C:' → 'C:\'
        if ($normalized -match '^([A-Za-z]):?$') {
            $normalized = "$($Matches[1].ToUpper()):\"
        }

        if (-not (Test-Path -LiteralPath $normalized -PathType Container)) {
            Write-Warning "Каталог не найден и будет пропущен: $original"
            continue
        }

        try {
            $resolved = (Resolve-Path -LiteralPath $normalized -ErrorAction Stop).ProviderPath
        } catch {
            $resolved = $normalized
        }

        Write-Host "  + $resolved" -ForegroundColor Gray

        $targets += [PSCustomObject]@{
            Name        = $normalized
            Path        = $resolved
            Description = 'Пользовательский путь'
            IsShare     = $false
        }
    }
} else {
    $modeLabel = 'SMB-шары локального сервера'
    Write-Host "Режим: сканирование SMB-шар" -ForegroundColor Cyan
    Import-Module SmbShare -ErrorAction Stop
    $smbShares = @(Get-SmbShare -ErrorAction Stop | Where-Object { $_.ShareType -eq 'FileSystemDirectory' })

    if (-not $smbShares) {
        Write-Warning "Файловых SMB-шар не найдено."
        return
    }

    foreach ($s in $smbShares) {
        $targets += [PSCustomObject]@{
            Name        = $s.Name
            Path        = $s.Path
            Description = $s.Description
            IsShare     = $true
        }
    }
}

if (-not $targets) {
    Write-Warning "Нечего сканировать."
    return
}

# --- Основной цикл ---
$report = @()

foreach ($t in $targets) {
    Write-Host "  Обработка: $($t.Name) -> $($t.Path)" -ForegroundColor Gray

    # Share Permissions (только для реальных SMB-шар)
    $sharePerms = @()
    if ($t.IsShare) {
        try {
            $shareAces = Get-SmbShareAccess -Name $t.Name -ErrorAction Stop
            $sharePerms = @(foreach ($ace in $shareAces) {
                if (-not $IncludeSystemAccounts -and (Test-IsSystemAccount $ace.AccountName)) { continue }
                [PSCustomObject]@{
                    Account     = $ace.AccountName
                    AccessType  = $ace.AccessControlType
                    AccessRight = $ace.AccessRight
                }
            })
        } catch {
            $message = "Не удалось прочитать share-права для $($t.Name): $_"
            $scanWarnings.Add($message)
            Write-Warning $message
        }
    }

    # NTFS tree
    $ntfsTree = @()
    if (Test-Path -LiteralPath $t.Path -PathType Container) {
        $effectiveDepth = if ($ScanSubfolders) { $MaxDepth } else { 0 }
        if ($ScanSubfolders) {
            Write-Host "    Обход подпапок (глубина $effectiveDepth)..." -ForegroundColor DarkGray
        }
        $ntfsTree = @(Get-FolderAclTree -RootPath $t.Path `
                                      -MaxDepth $effectiveDepth `
                                      -OnlyExplicitAcl $OnlyExplicitAcl `
                                      -ResolveGroups $ResolveGroups `
                                      -AdAvailable $adAvailable `
                                      -IncludeSystemAccounts $IncludeSystemAccounts)
    } else {
        $message = "Каталог не найден: $($t.Path)"
        $scanWarnings.Add($message)
        Write-Warning $message
    }

    $report += [PSCustomObject]@{
        Name        = $t.Name
        Path        = $t.Path
        Description = $t.Description
        IsShare     = $t.IsShare
        SharePerms  = $sharePerms
        NtfsTree    = $ntfsTree
    }
}

# --- HTML ---
Write-Host "`nФормирование HTML..." -ForegroundColor Cyan

function ConvertTo-HtmlEncoded {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return [System.Web.HttpUtility]::HtmlEncode($Text)
}

$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine(@"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>Отчёт: SMB-шары и права доступа (AD)</title>
<style>
    body { font-family: 'Segoe UI', Arial, sans-serif; margin: 24px; background: #f5f7fa; color: #1e293b; }
    h1 { color: #0f172a; border-bottom: 3px solid #3b82f6; padding-bottom: 8px; }
    h3 { color: #334155; margin: 16px 0 8px; font-size: 1em; text-transform: uppercase; letter-spacing: 0.05em; }
    .meta { color: #64748b; font-size: 0.9em; margin-bottom: 24px; }
    .share-block { background: #fff; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); margin-bottom: 32px; overflow: hidden; }
    .share-header { background: #1e293b; color: #f8fafc; padding: 14px 20px; }
    .share-header .title { font-size: 1.15em; font-weight: 600; }
    .share-header .path  { font-size: 0.88em; color: #94a3b8; margin-top: 4px; }
    .share-body { padding: 16px 20px; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 8px; }
    th { background: #e2e8f0; color: #334155; text-align: left; padding: 9px 12px; font-weight: 600; font-size: 0.85em; }
    td { padding: 8px 12px; border-bottom: 1px solid #e2e8f0; font-size: 0.9em; vertical-align: top; }
    tr:last-child td { border-bottom: none; }
    .allow { color: #16a34a; font-weight: 600; }
    .deny  { color: #dc2626; font-weight: 600; }
    .right-full   { background: #fef2f2; color: #b91c1c; font-weight: 600; padding: 2px 8px; border-radius: 4px; white-space: nowrap; }
    .right-change { background: #fefce8; color: #a16207; font-weight: 600; padding: 2px 8px; border-radius: 4px; white-space: nowrap; }
    .right-read   { background: #f0fdf4; color: #15803d; font-weight: 600; padding: 2px 8px; border-radius: 4px; white-space: nowrap; }
    .right-other  { background: #eef2ff; color: #3730a3; font-weight: 600; padding: 2px 8px; border-radius: 4px; white-space: nowrap; }
    .inherited { color: #94a3b8; font-size: 0.85em; }
    .members { margin-top: 6px; padding-left: 12px; border-left: 3px solid #cbd5e1; color: #475569; font-size: 0.85em; }
    .members li { margin: 2px 0; }
    .badge { display: inline-block; padding: 1px 6px; border-radius: 4px; font-size: 0.75em; background: #e2e8f0; color: #475569; margin-left: 6px; }
    details summary { cursor: pointer; color: #2563eb; font-size: 0.85em; }

    .folder-node { margin: 8px 0; padding: 8px 12px; border-left: 3px solid #94a3b8; background: #f8fafc; border-radius: 4px; }
    .folder-node.depth-0 { border-left-color: #3b82f6; background: #eff6ff; }
    .folder-node.depth-1 { margin-left: 18px; }
    .folder-node.depth-2 { margin-left: 36px; }
    .folder-node.depth-3 { margin-left: 54px; }
    .folder-node.depth-4 { margin-left: 72px; }
    .folder-node.depth-5 { margin-left: 90px; }
    .folder-node.depth-6 { margin-left: 108px; }
    .folder-node.depth-7 { margin-left: 126px; }
    .folder-node.depth-8 { margin-left: 144px; }
    .folder-name { font-weight: 600; color: #1e293b; margin-bottom: 6px; font-size: 0.92em; word-break: break-all; }

    .no-share-perms { color: #94a3b8; font-style: italic; padding: 8px 0; }
</style>
</head>
<body>
<h1>Отчёт: SMB-шары и права доступа</h1>
<div class="meta">
    Сервер: <strong>$(ConvertTo-HtmlEncoded $env:COMPUTERNAME)</strong> &nbsp;|&nbsp;
    Домен: <strong>$(ConvertTo-HtmlEncoded $env:USERDOMAIN)</strong> &nbsp;|&nbsp;
    Дата: <strong>$(Get-Date -Format 'dd.MM.yyyy HH:mm')</strong> &nbsp;|&nbsp;
    Режим: <strong>$(ConvertTo-HtmlEncoded $modeLabel)</strong> &nbsp;|&nbsp;
    Объектов: <strong>$($report.Count)</strong> &nbsp;|&nbsp;
    Раскрытие AD-групп: <strong>$(if($ResolveGroups){'включено'}else{'выключено'})</strong> &nbsp;|&nbsp;
    Глубина обхода: <strong>$(if($ScanSubfolders){$MaxDepth}else{'только корень'})</strong> &nbsp;|&nbsp;
    Только явные ACL: <strong>$(if($OnlyExplicitAcl){'да'}else{'нет'})</strong>
</div>
"@)

if ($scanWarnings.Count -gt 0) {
    [void]$sb.AppendLine('<h3>Предупреждения при сканировании</h3><ul>')
    foreach ($warningText in $scanWarnings) {
        [void]$sb.AppendLine("<li>$(ConvertTo-HtmlEncoded $warningText)</li>")
    }
    [void]$sb.AppendLine('</ul>')
}

foreach ($r in $report) {

    # --- Share permissions block ---
    if ($r.IsShare) {
        $shareRows = foreach ($p in $r.SharePerms) {
            $cls = if ($p.AccessType -eq 'Allow') { 'allow' } else { 'deny' }
            $rightCls = switch ($p.AccessRight) {
                'Full'   { 'right-full' }
                'Change' { 'right-change' }
                'Read'   { 'right-read' }
                default  { 'right-other' }
            }
            "<tr><td>$(ConvertTo-HtmlEncoded $p.Account)</td><td class='$cls'>$($p.AccessType)</td><td><span class='$rightCls'>$($p.AccessRight)</span></td></tr>"
        }
        if (-not $shareRows) { $shareRows = "<tr><td colspan='3' class='inherited'>Нет данных</td></tr>" }

        $shareSection = @"
        <h3>Права на уровне шары (Share Permissions)</h3>
        <table>
            <thead><tr><th style="width:55%">Учётная запись</th><th>Тип</th><th>Права</th></tr></thead>
            <tbody>$($shareRows -join "`n")</tbody>
        </table>
"@
    } else {
        $shareSection = "<h3>Права на уровне шары (Share Permissions)</h3><div class='no-share-perms'>Не применимо — это не SMB-шара, а указанный путь.</div>"
    }

    # --- NTFS tree ---
    $treeHtml = New-Object System.Text.StringBuilder
    $sortedNodes = $r.NtfsTree | Sort-Object { $_.Path }

    foreach ($node in $sortedNodes) {

        $folderLabel = if ($node.Depth -eq 0) {
            "<strong>📁 [корень] $([System.Web.HttpUtility]::HtmlEncode($r.Path))</strong>"
        } else {
            "📁 $([System.Web.HttpUtility]::HtmlEncode($node.RelativePath))"
        }

        if ($node.Aces.Count -gt 0) {
            $aceRows = foreach ($p in $node.Aces) {
                $cls = if ($p.AccessType -eq 'Allow') { 'allow' } else { 'deny' }
                $rights = $p.Rights.ToString()
                $rightCls = 'right-other'
                if ($rights -match 'FullControl') { $rightCls = 'right-full' }
                elseif ($rights -match 'Modify') { $rightCls = 'right-change' }
                elseif ($rights -match 'ReadAndExecute|Read\b') { $rightCls = 'right-read' }

                $inh = if ($p.Inheritance) { "<span class='inherited'>наследуется</span>" } else { "" }

                $membersHtml = ''
                if ($p.Members -and $p.Members.Count -gt 0) {
                    $items = foreach ($m in $p.Members) {
                        $enc = ConvertTo-HtmlEncoded $m.Name
                        if ($m.Type -eq 'Пользователь') {
                            "<li>$enc</li>"
                        } else {
                            "<li>$enc <span class='badge'>$(ConvertTo-HtmlEncoded $m.Type)</span></li>"
                        }
                    }
                    $membersHtml = "<details><summary>Состав группы ($($p.Members.Count))</summary><ul class='members'>$($items -join '')</ul></details>"
                }

                "<tr><td>$(ConvertTo-HtmlEncoded $p.Identity) $inh $membersHtml</td><td class='$cls'>$($p.AccessType)</td><td><span class='$rightCls'>$(ConvertTo-HtmlEncoded $rights)</span></td></tr>"
            }

            [void]$treeHtml.AppendLine(@"
<div class="folder-node depth-$($node.Depth)">
    <div class="folder-name">$folderLabel</div>
    <table>
        <thead><tr><th style="width:55%">Учётная запись / группа</th><th>Тип</th><th>Права</th></tr></thead>
        <tbody>$($aceRows -join "`n")</tbody>
    </table>
</div>
"@)
        }
    }

    if ($treeHtml.Length -eq 0) {
        $emptyMessage = if ($OnlyExplicitAcl) {
            'Отображаемых явных ACE не найдено. При ошибках чтения ACL см. предупреждения выше.'
        } else {
            'Отображаемых ACE не найдено. При ошибках чтения ACL см. предупреждения выше.'
        }
        [void]$treeHtml.AppendLine("<div class='inherited'>$emptyMessage</div>")
    }

    [void]$sb.AppendLine(@"
<div class="share-block">
    <div class="share-header">
        <div class="title">$(ConvertTo-HtmlEncoded $r.Name)</div>
        <div class="path">$(ConvertTo-HtmlEncoded $r.Path)</div>
    </div>
    <div class="share-body">
        $shareSection

        <h3>Права NTFS — дерево папок</h3>
        $($treeHtml.ToString())
    </div>
</div>
"@)
}

[void]$sb.AppendLine("</body></html>")

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "Каталог для отчёта не существует: $outputDirectory"
}
$sb.ToString() | Out-File -LiteralPath $OutputPath -Encoding UTF8 -ErrorAction Stop

Write-Host "`nГотово: $OutputPath" -ForegroundColor Green
