#Requires -Version 5.1
<#
.SYNOPSIS
    Русификация всех подписей к командам устранения и комментариев PowerShell.
.DESCRIPTION
    Локализует только RemediationCommands.Description и текст комментариев в
    RemediationCommands.Command. Исполняемые PowerShell-команды не изменяет.
    Пять каталогов подписей, каталог комментариев here-string и каталог
    однострочных комментариев проверяются на полное совпадение с исходником.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$encoding=New-Object System.Text.UTF8Encoding($true)
function Read-Catalog([string]$Path){
 $full=Join-Path $ProjectRoot ('Localization/'+$Path)
 if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw "Отсутствует каталог $Path"}
 return ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($full,[Text.Encoding]::UTF8))
}
$descriptions=@{}
foreach($file in @(
 'RemediationLabels-01.ru-RU.json',
 'RemediationLabels-02.ru-RU.json',
 'RemediationLabels-03.ru-RU.json',
 'RemediationLabels-04.ru-RU.json',
 'RemediationLabels-05.ru-RU.json'
)){
 $catalog=Read-Catalog $file
 foreach($item in $catalog.PSObject.Properties){
   if(-not $descriptions.ContainsKey($item.Name)){
     $descriptions[$item.Name]=[string]$item.Value
   }
 }
}
$here=Read-Catalog 'RemediationComments.ru-RU.json'
$inline=Read-Catalog 'RemediationInlineComments.ru-RU.json'
$hereMap=@{};foreach($p in $here.PSObject.Properties){$hereMap[$p.Name]=[string]$p.Value}
$inlineMap=@{};foreach($p in $inline.PSObject.Properties){$inlineMap[$p.Name]=[string]$p.Value}
$path=Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'
if(-not (Test-Path -LiteralPath $path)){throw 'Файл исходных определений находок отсутствует'}
$lines=[IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)
$originalLines=[string[]]$lines.Clone()

function Get-ExecutableSource([string[]]$TextLines){
  # Сравнение двух версий: игнорируются только переведённые человекочитаемые
  # Description и комментарии. Все исполняемые строки сверяются побайтно.
  $buf=New-Object System.Text.StringBuilder
  $inHere=$false
  foreach($line in $TextLines){
    $canonical=$line
    if($inHere){
      if($line -match "^'@\s*$"){$inHere=$false}
      elseif($line -match '^\s*#'){$canonical='<COMMENT-IN-HERE-STRING>'}
      else {
        $canonical=$canonical.Replace('  # AES128 + AES256 only','  #<COMMENT>')
        $canonical=$canonical.Replace('  # Только AES128 и AES256','  #<COMMENT>')
      }
    } else {
      if($line -match "^\s*Command\s*=\s*@'\s*$"){$inHere=$true}
      elseif($line -match '^[ ]{16}Description\s*=\s*"'){
        $canonical='Description=<LOCALIZED-COMMAND-LABEL>'
      }
      elseif($line -match '^[ ]{16}Command\s*=\s*"#'){
        $canonical='Command=<LOCALIZED-COMMENT-ONLY>'
      }
      else {
        $canonical=$canonical.Replace(' # Use ADSI to remove specific extended rights',' #<COMMENT>')
        $canonical=$canonical.Replace(' # Используйте ADSI для удаления конкретных расширенных прав',' #<COMMENT>')
      }
    }
    [void]$buf.AppendLine($canonical)
  }
  return $buf.ToString()
}
$changedLabels=0
$translatedHere=0
$translatedInline=0
$hereBlocks=0
$inCommandHereString=$false
$seenLabels=@{}
$seenHere=@{}
$seenInline=@{}
for($i=0;$i -lt $lines.Length;$i++){
 $line=$lines[$i]
 if($line -match "^\s*Command\s*=\s*@'\s*$"){
  if($inCommandHereString){throw "Неожиданное вложение здесь-строки в строке $($i+1)"}
  $inCommandHereString=$true
  $hereBlocks++
  continue
 }
 if($inCommandHereString){
  if($line -match "^'@\s*$"){
   $inCommandHereString=$false
   continue
  }
  if($line -match '^\s*#'){
   if(-not $hereMap.ContainsKey($line)){throw "Отсутствует перевод комментария в строке $($i+1): $line"}
   $lines[$i]=$hereMap[$line]
   $seenHere[$line]=$true
   if($lines[$i] -ne $line){$translatedHere++}
   continue
  }
  # Допускается только перевод существующего завершающего комментария.
  # Вся команда слева от комментария должна остаться неизменной.
  if($line.Contains('  # AES128 + AES256 only')){
   $lines[$i]=$line.Replace('  # AES128 + AES256 only','  # Только AES128 и AES256')
   $translatedHere++
  }
  continue
 }
 if($line -match '^(\s{16}Description\s*=\s*)"([^"]*)"(\s*)$'){
  $english=[string]$Matches[2]
  if(-not $descriptions.ContainsKey($english)){
    throw "Нет русского описания команды, строка $($i+1): $english"
  }
  $ru=[string]$descriptions[$english]
  if([string]::IsNullOrWhiteSpace($ru)){throw "Пустой перевод описания: $english"}
  if($ru.Contains('"') -or $ru.Contains([string][char]96) -or $ru.Contains('$')){
    throw "Недопустимый специальный символ в описании: $english"
  }
  $lines[$i]=[string]$Matches[1]+'"'+$ru+'"'+[string]$Matches[3]
  $seenLabels[$english]=$true
  $changedLabels++
  continue
 }
 if($line -match '^(\s{16}Command\s*=\s*)"(#.*)"(\s*)$'){
   $english=[string]$Matches[2]
   if(-not $inlineMap.ContainsKey($english)){
     throw "Нет русского текста команды-комментария, строка $($i+1): $english"
   }
   $ru=[string]$inlineMap[$english]
   if($ru.Contains('"')){throw "Недопустимая кавычка в переводе команды-комментария: $english"}
   $lines[$i]=[string]$Matches[1]+'"'+$ru+'"'+[string]$Matches[3]
   $seenInline[$english]=$true
   if($ru -ne $english){$translatedInline++}
   continue
 }
 if($line.Contains(' # Use ADSI to remove specific extended rights')){
  $lines[$i]=$line.Replace(' # Use ADSI to remove specific extended rights',' # Используйте ADSI для удаления конкретных расширенных прав')
  $translatedInline++
 }
}
if($inCommandHereString){throw 'Незакрытая здесь-строка PowerShell'}
if($changedLabels -ne 586){throw "Не все подписи локализованы: $changedLabels вместо 586"}
if($hereBlocks -ne 52){throw "Количество многострочных команд изменилось: $hereBlocks вместо 52"}
if($seenLabels.Count -ne $descriptions.Count){throw "Неприменённых русских описаний: $($descriptions.Count-$seenLabels.Count)"}
if($seenHere.Count -ne $hereMap.Count){throw "Неприменённых комментариев: $($hereMap.Count-$seenHere.Count)"}
if($seenInline.Count -ne $inlineMap.Count){throw "Неприменённых однострочных комментариев: $($inlineMap.Count-$seenInline.Count)"}
$originalCanonical=Get-ExecutableSource -TextLines $originalLines
$translatedCanonical=Get-ExecutableSource -TextLines $lines
if([string]::CompareOrdinal($originalCanonical,$translatedCanonical) -ne 0){
 throw 'Запрещено: перевод изменил исполняемую часть или технические идентификаторы команд'
}
Write-Host '[RU] PASS: все исполняемые строки команд посимвольно идентичны исходнику'
$updated=[string]::Join([Environment]::NewLine,$lines)+[Environment]::NewLine
$tokenStream=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseInput($updated,[ref]$tokenStream,[ref]$parseErrors)
if($parseErrors -and $parseErrors.Count -gt 0){
 throw "Ошибка синтаксиса PowerShell после перевода: $($parseErrors[0].Message)"
}
[IO.File]::WriteAllText($path,$updated,$encoding)
Write-Host "[RU] PASS: переведены все $changedLabels подписей команд"
Write-Host "[RU] PASS: $hereBlocks блоков многострочных команд, $translatedHere строк комментариев"
Write-Host "[RU] PASS: $translatedInline однострочных подсказок и комментариев"
Write-Host '[RU] PASS: параметры команд и машинные идентификаторы не изменялись'
