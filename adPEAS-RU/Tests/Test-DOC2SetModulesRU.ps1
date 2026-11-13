#Requires -Version 5.1
<#
.SYNOPSIS
  DOC2c: офлайн-проверка русского справочника изменяющих функций AD.
.DESCRIPTION
  Сопоставляет зафиксированный EN-источник и русскую страницу.
  Не подключается к AD и никогда не выполняет приведённые команды.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $ProjectRoot 'docs/07-Set-Modules.md'
$targetPath = Join-Path $ProjectRoot 'docs/ru-RU/07-Set-Modules.md'
if (-not (Test-Path -LiteralPath $sourcePath) -or -not (Test-Path -LiteralPath $targetPath)) {
 throw 'DOC2c: необходимый справочник отсутствует'
}
$source = [IO.File]::ReadAllText($sourcePath,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$target = [IO.File]::ReadAllText($targetPath,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$srcLines = @($source.Split([char]10))
$dstLines = @($target.Split([char]10))
if ($srcLines.Count -ne 1593 -or $dstLines.Count -ne $srcLines.Count) {
 throw "DOC2c: изменено число исходных строк: EN=$($srcLines.Count) RU=$($dstLines.Count)"
}
$commands = @('Set-DomainUser','Set-DomainComputer','Set-DomainGroup',
 'Set-CertificateTemplate','Request-ADCSCertificate','Set-DomainGPO',
 'Set-DomainObject','Move-DomainObject','New-DomainUser','New-DomainComputer',
 'New-DomainGroup','New-DomainGPO')
foreach ($command in $commands) {
 $header = '## '+$command
 if (@($srcLines | Where-Object { $_ -ceq $header }).Count -ne 1 -or
     @($dstLines | Where-Object { $_ -ceq $header }).Count -ne 1) {
  throw "DOC2c: удалён или дублирован раздел $command"
 }
}
$marker = ([string][char]96) * 3
$tick = [string][char]96
$tokenPattern = $tick + '([^' + $tick + ']+)' + $tick
$plainNarrativeChanged = 0
$commentCount = 0
$blockCount = 0
$powershellBlocks = 0
$insideBlock = $false
$blockLanguage = ''
$diagramChanges = @(300,302,304,306,308,310,609,611,617,619)
for ($i=0; $i -lt $srcLines.Count; $i++) {
 $en = $srcLines[$i]
 $ru = $dstLines[$i]
 if ($en.TrimStart().StartsWith($marker)) {
  if ($en -cne $ru) { throw "DOC2c: изменена граница блока на строке $($i+1)" }
  if (-not $insideBlock) {
   $blockCount++
   $blockLanguage = $en.Trim().Substring(3).Trim()
   if ($blockLanguage -ceq 'powershell') { $powershellBlocks++ }
  }
  $insideBlock = -not $insideBlock
  continue
 }
 if ($insideBlock) {
  if ($en -match '^\s*#') {
   $commentCount++
   if (($ru -cne $en) -and ($ru -cnotmatch '[А-Яа-яЁё]')) {
    throw "DOC2c: комментарий не переведён на строке $($i+1)"
   }
   continue
  }
  if ($en -cne $ru) {
   if ($blockLanguage -ceq 'powershell' -or (($i+1) -notin $diagramChanges)) {
    throw "DOC2c: исполняемый код или технический образец изменён на строке $($i+1)"
   }
  }
  continue
 }
 if ($en.StartsWith('|') -ne $ru.StartsWith('|')) {
  throw "DOC2c: нарушена структура таблицы на строке $($i+1)"
 }
 $enTokens = @([regex]::Matches($en,$tokenPattern) | ForEach-Object { $_.Groups[1].Value })
 $ruTokens = @([regex]::Matches($ru,$tokenPattern) | ForEach-Object { $_.Groups[1].Value })
 if (($enTokens -join [char]31) -cne ($ruTokens -join [char]31)) {
  throw "DOC2c: изменён параметр или иной технический токен на строке $($i+1)"
 }
 if ($en -cne $ru) { $plainNarrativeChanged++ }
}
if ($insideBlock -or $blockCount -ne 53 -or $powershellBlocks -ne 45 -or $commentCount -ne 148) {
 throw "DOC2c: нарушена структура примеров: blocks=$blockCount ps=$powershellBlocks comments=$commentCount"
}
if ($plainNarrativeChanged -lt 440) {
 throw "DOC2c: описание переведено недостаточно полно: $plainNarrativeChanged"
}
$hrefPattern = '\]\(([^)]+)\)'
$srcLinks = @([regex]::Matches($source,$hrefPattern) | ForEach-Object {$_.Groups[1].Value})
$ruLinks = @([regex]::Matches($target,$hrefPattern) | ForEach-Object {$_.Groups[1].Value})
if (($srcLinks -join [char]31) -cne ($ruLinks -join [char]31)) {
 throw 'DOC2c: изменены ссылки на исходные документы или якоря'
}
foreach ($term in @('ЮРИДИЧЕСКОЕ ПРЕДУПРЕЖДЕНИЕ','ЭКСПЕРИМЕНТАЛЬНЫЙ СТАТУС',
 'план отката','письменное разрешение','DONT_REQ_PREAUTH','NOT_DELEGATED',
 'ESC4','CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT','WriteDACL','WriteProperty',
 'GenericAll','SYSVOL','Group Policy Preferences','не отменяют изменения',
 'ModifyDN','атомарен','SID','Delete Child','Create Child','NoSYSVOL',
 'Credential','Password','Shadow Credentials','msDS-KeyCredentialLink',
 'PKINIT','MachineAccountQuota','20 символов','отзыва','PassThru')) {
 if ($target.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0) {
  throw "DOC2c: утеряно критическое условие: $term"
 }
}
Write-Host "PASS DOC2c: $($commands.Count) API-разделов; $blockCount блоков, $powershellBlocks PowerShell, $commentCount комментариев, $plainNarrativeChanged строк; код и ссылки неизменны" -ForegroundColor Green
