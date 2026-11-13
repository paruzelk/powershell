#Requires -Version 5.1
<#
.SYNOPSIS
  DOC2a: проверка полного русского справочника Core Functions.
.DESCRIPTION
  Только чтение файлов, без подключения к AD или выполнения команд из документации.
  Сохраняет набор параметров, синтаксис примеров, LDAP-фильтры и ссылки оригинала.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$enPath=Join-Path $ProjectRoot 'docs/06-Core-Functions.md'
$ruPath=Join-Path $ProjectRoot 'docs/ru-RU/06-Core-Functions.md'
if(-not (Test-Path -LiteralPath $enPath) -or -not (Test-Path -LiteralPath $ruPath)){
 throw 'DOC2a: не найден английский оригинал или русский справочник'
}
$en=[IO.File]::ReadAllText($enPath,[Text.Encoding]::UTF8)
$ru=[IO.File]::ReadAllText($ruPath,[Text.Encoding]::UTF8)
if($ru.Length -lt 25000){throw 'DOC2a: русский справочник неполон'}
$functions=@('Get-DomainUser','Get-DomainComputer','Get-DomainGroup','Get-DomainGPO',
 'Get-DomainObject','Get-ObjectACL','Get-CertificateTemplate')
foreach($name in $functions){
 foreach($doc in @($en,$ru)){
  $pattern='(?m)^## '+[regex]::Escape($name)+'\r?$'
  if(([regex]::Matches($doc,$pattern)).Count -ne 1){
   throw "DOC2a: отсутствует или повторён раздел $name"
  }
 }
}
$regex='(?m)^\| (-[A-Za-z][A-Za-z0-9]*) \| (String(?:\[\])?|Switch|Int|PSCredential) \| (.+) \|\r?$'
# Отдельно допускается оформление имени в Markdown как inline code.
$regex='(?m)^\| ' + [char]96 + '(-[A-Za-z][A-Za-z0-9]*)' + [char]96 + ' \| (String(?:\[\])?|Switch|Int|PSCredential) \| (.+) \|\r?$'
$enRows=@([regex]::Matches($en,$regex))
$ruRows=@([regex]::Matches($ru,$regex))
if($enRows.Count -ne 146 -or $ruRows.Count -ne 146){
 throw "DOC2a: ожидались 146 параметров, найдено EN=$($enRows.Count) RU=$($ruRows.Count)"
}
for($i=0;$i -lt $enRows.Count;$i++){
 if($enRows[$i].Groups[1].Value -cne $ruRows[$i].Groups[1].Value -or
    $enRows[$i].Groups[2].Value -cne $ruRows[$i].Groups[2].Value){
  throw "DOC2a: изменён ключ или тип параметра на строке $i"
 }
 if($ruRows[$i].Groups[3].Value -cnotmatch '[А-Яа-яЁё]'){
  throw "DOC2a: не переведено описание $($ruRows[$i].Groups[1].Value)"
 }
}
# Примеры можно локализовать только в комментариях. Командные строки, фильтры и значения не меняются.
$blockRegex='(?ms)^' + [char]96 + [char]96 + [char]96 + 'powershell[ \t]*\r?\n(.*?)^' + [char]96 + [char]96 + [char]96
$enBlocks=@([regex]::Matches($en,$blockRegex))
$ruBlocks=@([regex]::Matches($ru,$blockRegex))
if($enBlocks.Count -ne 15 -or $ruBlocks.Count -ne $enBlocks.Count){
 throw "DOC2a: ожидались 15 блоков PowerShell, EN=$($enBlocks.Count) RU=$($ruBlocks.Count)"
}
$totalComments=0
for($i=0;$i -lt $enBlocks.Count;$i++){
 $s=[regex]::Replace($enBlocks[$i].Groups[1].Value,'(?m)^[ \t]*#[^\r\n]*(\r?\n|$)','')
 $t=[regex]::Replace($ruBlocks[$i].Groups[1].Value,'(?m)^[ \t]*#[^\r\n]*(\r?\n|$)','')
 if($s -cne $t){throw "DOC2a: изменился исполняемый синтаксис в блоке $($i+1)"}
 $comments=@([regex]::Matches($ruBlocks[$i].Groups[1].Value,'(?m)^# (.*)$'))
 foreach($comment in $comments){
  if($comment.Groups[1].Value -cnotmatch '[А-Яа-яЁё]'){throw "DOC2a: английский комментарий в блоке $($i+1)"}
 }
 $totalComments+=$comments.Count
}
if($totalComments -ne 74){throw "DOC2a: число комментариев $totalComments вместо 74"}
$linksPattern='\]\(([^)]+)\)'
$enLinks=@([regex]::Matches($en,$linksPattern) | ForEach-Object {$_.Groups[1].Value})
$ruLinks=@([regex]::Matches($ru,$linksPattern) | ForEach-Object {$_.Groups[1].Value})
if(($enLinks -join "`n") -cne ($ruLinks -join "`n")){
 throw 'DOC2a: изменились ссылки или якоря в документации'
}
foreach($marker in @('memberOfNested' ,'Не обнаруживаются локальные группы','флаг NOT_DELEGATED',
 'глобального каталога','Primary group','-IncludeDeleted','flags=3',
 'szOID_NTDS_CA_SECURITY_EXT','ESC9/ESC10','GenericAll','WriteDacl','WriteOwner')){
 if(-not $ru.Contains($marker)){throw "DOC2a: утеряно существенное условие: $marker"}
}
foreach($englishHeading in @('### Syntax','### Parameters','### Examples','### Output Properties',
 '### KnownSPN Values','## LDAP Filter Reference')){
 if($ru.Contains($englishHeading)){throw "DOC2a: остался английский заголовок: $englishHeading"}
}
Write-Host "PASS DOC2a: 7 функций, 146 параметров, 74 комментария, 15 примеров PowerShell; LDAP и ссылки сохранены" -ForegroundColor Green
