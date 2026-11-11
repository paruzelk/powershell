#Requires -Version 5.1
<#
.SYNOPSIS
    Автономные регрессионные проверки русификации команд устранения.
.DESCRIPTION
    Без подключения к AD и без запуска изменяющих команд.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$n=0
function Assert-RU([bool]$Condition,[string]$Title){
 if(-not $Condition){throw "FAIL: $Title"}
 $script:n++
 Write-Host "PASS: $Title"
}
$file=Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'
$text=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
$compiled=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'adPEAS.ps1'),[Text.Encoding]::UTF8)
$labels=[regex]::Matches($text,'(?m)^[ ]{16}Description\s*=\s*"([^"]*)"')
Assert-RU ($labels.Count -eq 586) 'Сохранены 586 описаний команд'
Assert-RU (([regex]::Matches($text,"(?m)^[ ]{16}Command\s*=\s*@'")).Count -eq 52) 'Сохранены 52 многострочные команды'
Assert-RU (([regex]::Matches($text,'(?m)^[ ]{16}Command\s*=\s*"')).Count -eq 487) 'Сохранены 487 однострочных команд'
$required=@(
 'Вывести всех участников группы «Администраторы домена» (Domain Admins), включая вложенные группы',
 'Вывести всех участников группы «Администраторы предприятия» (Enterprise Admins), включая вложенные группы',
 'Вывести всех участников группы «Администраторы схемы» (Schema Admins), включая вложенные группы',
 'Удалить указанного пользователя из группы «Администраторы домена» (Domain Admins)',
 'Проверить членство во всех привилегированных группах уровня Tier 0',
 'Добавить пользователя Tier 0 в группу Protected Users только после проверки зависимостей его аутентификации',
 'Удалить опасные права непривилегированных пользователей',
 'Показать текущую парольную политику домена',
 'Показать текущие разрешения GPO',
 'Проверить текущие параметры подписи SMB',
 'Настроить обязательную подпись LDAP через GPO',
 'Найти все учётные записи с ограниченным делегированием',
 'Проверить ACL всех шаблонов сертификатов на опасные разрешения',
 'Сбросить пароль DSRM контроллера домена',
 'Показать субъектов с правом чтения ключей восстановления BitLocker в OU'
)
foreach($v in $required){Assert-RU ($text.Contains($v)) ('Переведено: '+$v)}
Assert-RU (-not $text.Contains('Description = "List all members of Domain Admins group (including nested)"')) 'Удалена английская подпись Domain Admins'
Assert-RU (-not $text.Contains('Description = "Remove specific user from Domain Admins group"')) 'Удалена английская подпись удаления участника'
$comments=@(
 '# Группа Protected Users запрещает NTLM, CredSSP, Digest, RC4 и делегирование',
 '# для своих членов, а также кэширование их учётных данных.',
 '# для компьютерных учётных записей и gMSA защита не действует, и Microsoft не советует',
 '# добавлять их в группу. Находка относится ко всем трём типам учётных записей.',
 '# Для компьютера или gMSA вместо добавления в Protected Users используйте:',
 '# Только AES128 и AES256',
 '# После MS16-072 / KB3163622 групповая политика запрашивается от имени',
 '# GPMC →',
 '# Проверить настройки',
 '# Удалить CT_FLAG_NO_SECURITY_EXTENSION (0x80000)'
)
foreach($c in $comments){Assert-RU ($text.Contains($c)) ('Переведён комментарий: '+$c)}
Assert-RU (-not $text.Contains('# Protected Users ends NTLM, CredSSP, Digest, RC4')) 'Английский комментарий Protected Users отсутствует'
Assert-RU (-not $text.Contains('# its credentials being cached. For a user account')) 'Английский комментарий о кэшировании отсутствует'
# Все следующие команды остаются исполняемыми и должны сохранять точные параметры.
$commands=@(
 "Get-ADGroupMember -Identity 'Domain Admins' -Recursive",
 "Get-ADGroupMember -Identity 'Enterprise Admins' -Recursive",
 "Get-ADGroupMember -Identity 'Schema Admins' -Recursive",
 "Remove-ADGroupMember -Identity 'Domain Admins' -Members 'USERNAME'",
 "Add-ADGroupMember -Identity 'Protected Users' -Members 'TIER0_USER_ACCOUNT'",
 "Set-ADAccountControl -Identity 'TIER0_COMPUTER$' -AccountNotDelegated",
 "Set-ADComputer -Identity 'TIER0_COMPUTER$' -Replace @{ 'msDS-SupportedEncryptionTypes' = 24 }",
 "Select-Object Name,SamAccountName,ObjectClass,DistinguishedName"
)
foreach($cmd in $commands){Assert-RU ($text.Contains($cmd)) ('Исходная PowerShell-команда сохранена: '+$cmd)}
Assert-RU ($compiled.Contains('Вывести всех участников группы «Администраторы домена»')) 'Русская подпись встроена в автономную сборку'
Assert-RU ($compiled.Contains('# Группа Protected Users запрещает NTLM')) 'Русский комментарий встроен в автономную сборку'
Assert-RU ($compiled.Contains('Get-ADGroupMember -Identity ''Domain Admins'' -Recursive')) 'Команда ADGroupMember не изменена в автономной сборке'
Assert-RU (Test-Path (Join-Path $ProjectRoot 'license/LICENSE.md')) 'Оригинальная лицензия сохранена'
Write-Host "PASS: $n проверок русского текста и целостности команд; AD не затронут" -ForegroundColor Green
