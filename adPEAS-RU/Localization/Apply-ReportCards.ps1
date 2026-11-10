#Requires -Version 5.1
<#
.SYNOPSIS
  Локализация реальных заголовков карточек, Windows User Rights и типовых выводов проверок.
.DESCRIPTION
  Меняются только текстовые свойства представления (TitleFormat, Name, Why) и
  человекочитаемые строки в выбранных проверках. Ключи Se..., SID, ACL, LDAP,
  FindingId и объекты результата не изменяются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($true)
function Get-Text([string]$Relative) {
 [IO.File]::ReadAllText((Join-Path $ProjectRoot $Relative),[Text.Encoding]::UTF8)
}
function Save-Text([string]$Relative,[string]$Value) {
 [IO.File]::WriteAllText((Join-Path $ProjectRoot $Relative),$Value,$utf8)
}
# Заголовки всех реальных объектов отчёта (не только SectionTitle).
$sections=(ConvertFrom-Json (Get-Text 'Localization/ObjectTypes.ru-RU.json')).translations
$objRel='src/modules/Core/adPEAS-ObjectTypes.ps1'
$lines=[IO.File]::ReadAllLines((Join-Path $ProjectRoot $objRel),[Text.Encoding]::UTF8)
$objectType=''
$renamed=0
$special=@{
 'DangerousACL'='Опасные разрешения ACL: {Name}'
 'GPOUserRights'='Право пользователя в GPO: {UserRightName}'
 'GPO'='Групповая политика: {Name}'
 'GPOPermission'='Разрешение на GPO: {Name}'
}
for($i=0;$i -lt $lines.Length;$i++){
 if($lines[$i] -match "^    '([^']+)'\s*=\s*@\{"){$objectType=$Matches[1]}
 if($objectType -and $lines[$i] -match '^(        )TitleFormat(\s*=\s*)"([^"]*)"\s*$'){
  $prefix=$Matches[1];$spacing=$Matches[2];$english=$Matches[3]
  $prop=$sections.PSObject.Properties[$objectType]
  if($null -eq $prop){throw "Нет русского описания для ObjectType $objectType"}
  $ru=[string]$prop.Value.SectionTitle
  if([string]::IsNullOrWhiteSpace($ru)){throw "Пустой заголовок для $objectType"}
  $holders=[regex]::Matches($english,'\{[A-Za-z][A-Za-z0-9_]*\}')
  $suffix=''
  foreach($h in $holders){$suffix+=$h.Value}
  $title=if($special.ContainsKey($objectType)){$special[$objectType]}
         elseif($english -like 'Exchange Group: *'){'Группа Exchange: '+$english.Substring(16)}
         elseif($suffix){$ru+': '+$suffix}
         else{$ru}
  $originalHolders=@([regex]::Matches($english,'\{[A-Za-z][A-Za-z0-9_]*\}') | ForEach-Object {$_.Value})
  $translatedHolders=@([regex]::Matches($title,'\{[A-Za-z][A-Za-z0-9_]*\}') | ForEach-Object {$_.Value})
  if(($originalHolders -join '|') -ne ($translatedHolders -join '|')){
   throw "Изменены подстановки заголовка $objectType : $english -> $title"
  }
  $safe=$title.Replace([string][char]96,([string][char]96)+([string][char]96)).Replace('$',([string][char]96)+'$')
  $lines[$i]=$prefix+'TitleFormat'+$spacing+'"'+$safe+'"'
  $renamed++
 }
}
if($renamed -ne 124){throw "Ожидалось 124 названия карточек, обработано $renamed"}
[IO.File]::WriteAllLines((Join-Path $ProjectRoot $objRel),$lines,$utf8)
Write-Host "[RU] Названия объектов отчёта: $renamed переведены"

# User Rights Assignment: перевести выводимые названия и смысл, НЕ имена Se* и ACL.
$rightsRel='src/modules/Core/adPEAS-UserRights.ps1'
$rights=(ConvertFrom-Json (Get-Text 'Localization/UserRights.ru-RU.json'))
$rightLines=[IO.File]::ReadAllLines((Join-Path $ProjectRoot $rightsRel),[Text.Encoding]::UTF8)
$right=''
$names=0;$reasons=0
for($i=0;$i -lt $rightLines.Length;$i++){
 if($rightLines[$i] -match "^    '(Se[A-Za-z0-9]+)'\s*=\s*@\{"){$right=$Matches[1]}
 if($right -and $rightLines[$i] -match '^(        )(Name|Why)(\s*=\s*)''.*''\s*$'){
  $indent=$Matches[1];$field=$Matches[2];$space=$Matches[3]
  $record=$rights.PSObject.Properties[$right]
  if($null -eq $record){throw "Не переведено право $right"}
  $value=if($field -eq 'Name'){[string]$record.Value[0]}else{[string]$record.Value[1]}
  if([string]::IsNullOrWhiteSpace($value)){throw "Пустой перевод $right.$field"}
  $rightLines[$i]=$indent+$field+$space+"'"+$value.Replace("'","''")+"'"
  if($field -eq 'Name'){$names++}else{$reasons++}
 }
}
if($names -ne 29 -or $reasons -ne 29){throw "Неполный перевод User Rights: Name=$names, Why=$reasons"}
[IO.File]::WriteAllLines((Join-Path $ProjectRoot $rightsRel),$rightLines,$utf8)
Write-Host '[RU] Права Windows: переведены 29 названий и 29 пояснений'

# Строки результата, которые содержат динамические числа и поэтому не могут
# быть найдены в предыдущем словаре дословных Show-Line.
$dynamic=@{
 'src/modules/Checks/Rights/Get-DangerousACLs.ps1'=@{
   'Show-Line "Found $countText with DCSync rights" -Class Finding'='Show-Line "Обнаружены субъекты с правами DCSync: $countText" -Class Finding'
   'Show-Line "Found $countText with dangerous rights on domain root" -Class Finding'='Show-Line "Обнаружены субъекты с опасными правами на корневой объект домена: $countText" -Class Finding'
 }
 'src/modules/Checks/Rights/Get-GPOUserRightsAssignment.ps1'=@{
   '$text = "$($removalsOnly.Count) assignment(s) only remove default holders - hardening, or a service about to break"'='$text = "Назначений, удаляющих только стандартных субъектов: $($removalsOnly.Count). Усиление защиты либо риск нарушения работы службы"'
   '$countText = "$($removalsOnly.Count) assignment(s)"'='$countText = "$($removalsOnly.Count) назначений"'
   '$text += " on $($removalPolicies.Count) GPO(s)"'='$text += " в $($removalPolicies.Count) GPO"'
   '$countText += " on $($removalPolicies.Count) GPO(s)"'='$countText += " в $($removalPolicies.Count) GPO"'
   "Show-GPOSuppressedGroup -Group 'Assignments that only remove default holders'"="Show-GPOSuppressedGroup -Group 'Назначения без дополнительных прав (исключены стандартные субъекты)'"
   "-Reason 'Hardening more often than not, occasionally a service about to break - never a grant.' "=" -Reason 'Обычно усиление защиты; проверьте влияние на работу служб. Новые права не выдаются.' "
   'Show-Line "Found $($deviations.Count) user right assignment(s) that depart from the Windows default:"'='Show-Line "Обнаружено назначений прав пользователя с отклонением от стандартных параметров Windows: $($deviations.Count)"'
   'Show-Line "No user right is granted beyond the Windows default by a policy that reaches a machine"'='Show-Line "В действующих GPO не обнаружено выдачи прав сверх стандартных настроек Windows"'
   'Show-Line "No user right is granted beyond the Windows default"'='Show-Line "Не обнаружено выдачи прав пользователя сверх стандартных настроек Windows"'
 }
}
$total=0
foreach($p in $dynamic.GetEnumerator()){
 $source=Get-Text $p.Key
 foreach($replacement in $p.Value.GetEnumerator()){
  if(-not $source.Contains([string]$replacement.Key)){
   throw "Исходная строка не найдена в $($p.Key): $($replacement.Key)"
  }
  $source=$source.Replace([string]$replacement.Key,[string]$replacement.Value)
  $total++
 }
 Save-Text $p.Key $source
}
Write-Host "[RU] Динамические сообщения: $total переводов"
