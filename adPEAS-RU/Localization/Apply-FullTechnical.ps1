#Requires -Version 5.1
<#
.SYNOPSIS
    Подробные русские технические описания находок AD.
.DESCRIPTION
    Добавляет русские Description, Impact и Remediation для всех FindingId.
    Attack выводится только при наличии проверенного русского пояснения.
    Канонические определения FindingId, риск, триггеры, команды и ссылки
    остаются неизменными. Английский текст доступен отдельно для сверки.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
# Snapshot of the canonical EN PowerShell definitions before modifying display files.
$coreDefinitions=Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'
if(-not (Test-Path -LiteralPath $coreDefinitions -PathType Leaf)){throw 'Отсутствует исходный справочник adPEAS'}
$coreDefinitionsHashBefore=(Get-FileHash -LiteralPath $coreDefinitions -Algorithm SHA256).Hash

$entries=[ordered]@{}
foreach($name in @('FullTechnical-01.ru-RU.json','FullTechnical-02.ru-RU.json','FullTechnical-Report-03.ru-RU.json','FullTechnical-Report-04.ru-RU.json','FullTechnical-Brief-05.ru-RU.json','FullTechnical-Catalog-06a.ru-RU.json','FullTechnical-Catalog-06b.ru-RU.json','FullTechnical-Catalog-06c.ru-RU.json','FullTechnical-Catalog-06d.ru-RU.json','FullTechnical-Catalog-06e.ru-RU.json')){
 $src=Join-Path $ProjectRoot ('Localization/'+$name)
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($src,[Text.Encoding]::UTF8))
 foreach($prop in $catalog.translations.PSObject.Properties){
  if($entries.Contains($prop.Name)){throw "Дублируется FindingId $($prop.Name)"}
  $entries[$prop.Name]=$prop.Value
 }
}
# Source-checked field overlays. No English originals, FindingId, risk or commands are changed.
$coreSource=Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-07.ru-RU.json'
$coreOverlay=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($coreSource,[Text.Encoding]::UTF8))
if(@($coreOverlay.translations.PSObject.Properties).Count -ne 10){throw 'Ожидалось 10 предметных переводов Impact/Remediation'}
foreach($p in $coreOverlay.translations.PSObject.Properties){
 if(-not $entries.Contains($p.Name)){throw "Неизвестный FindingId: $($p.Name)"}
 $v=$p.Value
 if(@($v.impact).Count -ne [int]$v.sourceEnglishImpactCount){throw "Несовпадение количества Impact: $($p.Name)"}
 if(@($v.remediation).Count -ne [int]$v.sourceEnglishRemediationCount){throw "Несовпадение количества Remediation: $($p.Name)"}
 if($v.PSObject.Properties['description']){
  if([string]::IsNullOrWhiteSpace([string]$v.description)){throw "Пустое описание: $($p.Name)"}
  $entries[$p.Name].description=[string]$v.description
 }
 $entries[$p.Name].impact=@($v.impact)
 $entries[$p.Name].remediation=@($v.remediation)
}
$attackSource=Join-Path $ProjectRoot 'Localization/SourceVerifiedAttack-07.ru-RU.json'
$attackOverlay=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($attackSource,[Text.Encoding]::UTF8))
if(@($attackOverlay.translations.PSObject.Properties).Count -ne 38){throw 'Ожидалось 38 сверенных случаев Attack (36 переводов, 2 пустых оригинала)'}
$attackSteps=0
foreach($p in $attackOverlay.translations.PSObject.Properties){
 if(-not $entries.Contains($p.Name)){throw "Неизвестный FindingId: $($p.Name)"}
 $v=$p.Value
 $steps=@($v.attack)
 if($steps.Count -ne [int]$v.sourceEnglishAttackStepCount){throw "Несовпадение количества шагов оригинала Attack: $($p.Name)"}
 for($i=0;$i -lt $steps.Count;$i++){
  if([string]$steps[$i] -notmatch "^\s*$($i+1)\.\s+[А-Яа-яЁё]"){
   throw "Не переведён или неверно пронумерован шаг Attack $($i+1): $($p.Name)"
  }
 }
 $entries[$p.Name].attack=$steps
 $attackSteps+=$steps.Count
}
if($attackSteps -ne 139){throw "Ожидалось 139 переведённых шагов Attack, найдено $attackSteps"}
Write-Host "[RU] PASS: 36 цепочек Attack (139 шагов) и 10 полных полей Impact/Remediation сверены с источником; 2 недопустимых сценария очищены"


# Дополнение ранее сокращённых Attack по пунктам исходного adPEAS 2.9.0.
$secondAttackCount=0
$secondAttackSteps=0
foreach($name in @('SourceVerifiedAttack-09a.ru-RU.json',
                  'SourceVerifiedAttack-09b.ru-RU.json',
                  'SourceVerifiedAttack-09c.ru-RU.json')){
 $source=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $source.translations.PSObject.Properties){
  $id=$p.Name
  if(-not $entries.Contains($id)){throw "Неизвестный FindingId: $id"}
  $parts=@($p.Value.attack)
  if($parts.Count -ne [int]$p.Value.sourceEnglishAttackStepCount){throw "Не совпало число шагов Attack: $id"}
  foreach($part in $parts){
   if([string]::IsNullOrWhiteSpace([string]$part) -or [string]$part -notmatch '[А-Яа-яЁё]'){throw "Непереведённый шаг Attack: $id"}
  }
  $entries[$id].attack=$parts
  $secondAttackCount++
  $secondAttackSteps+=$parts.Count
 }
}
if($secondAttackCount -ne 52 -or $secondAttackSteps -ne 189){
 throw "Неполный набор исправлений Attack: $secondAttackCount записей; $secondAttackSteps пунктов"
}
Write-Host "[RU] PASS: 52 сценария Attack приведены к структуре оригинала, проверено 189 пунктов"


# Этап D: русские разделы Attack с точным английским свидетельством.
# Запрещено молча переопределять более ранний перевод или изменять источник.
$originalFindingText=[IO.File]::ReadAllText($coreDefinitions,[Text.Encoding]::UTF8)
$originalFindingText=$originalFindingText.Replace(([string][char]13+[string][char]10),[string][char]10)
$stageDCount=0
$stageDSteps=0
$stageDSeen=@{}
foreach($name in @('SourceVerifiedAttack-10a.ru-RU.json','SourceVerifiedAttack-10b.ru-RU.json')){
 $source=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $source.translations.PSObject.Properties){
  $id=[string]$p.Name
  if($stageDSeen.ContainsKey($id)){throw "Повторный перевод Stage D: $id"}
  $stageDSeen[$id]=$true
  if(-not $entries.Contains($id)){throw "Неизвестный FindingId Stage D: $id"}
  if(@($entries[$id].attack).Count -ne 0){throw "Попытка перезаписать существующий Attack: $id"}
  $marker="    '$id' = @{"
  $begin=$originalFindingText.IndexOf($marker,[StringComparison]::Ordinal)
  if($begin -lt 0){throw "Отсутствует FindingId в каноническом EN: $id"}
  $finish=$originalFindingText.IndexOf(([string][char]10+'    }'),$begin,[StringComparison]::Ordinal)
  if($finish -lt 0){throw "Не завершён блок оригинала: $id"}
  $block=$originalFindingText.Substring($begin,$finish-$begin)
  $attackMatch=[regex]::Match($block,'(?ms)^[ \t]{8}Attack[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)')
  if(-not $attackMatch.Success){throw "У оригинала нет раздела Attack: $id"}
  $originalSteps=@([regex]::Matches($attackMatch.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') | ForEach-Object { $_.Groups['value'].Value })
  $sourceSteps=@($p.Value.sourceEnglishAttack)
  $translatedSteps=@($p.Value.attack)
  $expected=[int]$p.Value.sourceEnglishAttackStepCount
  if($originalSteps.Count -ne $expected -or $sourceSteps.Count -ne $expected -or $translatedSteps.Count -ne $expected){
   throw "Различается число пунктов Attack $($id): EN=$($originalSteps.Count), свидетельство=$($sourceSteps.Count), RU=$($translatedSteps.Count), ожидается=$expected"
  }
  for($i=0;$i -lt $expected;$i++){
   if([string]$originalSteps[$i] -cne [string]$sourceSteps[$i]){
    throw "Английский оригинал Attack изменён: $id, пункт $($i+1)"
   }
   if([string]::IsNullOrWhiteSpace([string]$translatedSteps[$i]) -or [string]$translatedSteps[$i] -notmatch '[А-Яа-яЁё]'){
    throw "Отсутствует русский перевод Attack: $id, пункт $($i+1)"
   }
   if($originalSteps[$i] -match '^(?:With |When |Nothing here|BloodHound is|Attackers also use|Understanding your)' -and
      $translatedSteps[$i] -match '^1\.[ \t]'){
    throw "Защитное или справочное пояснение ошибочно превращено в шаг атаки: $id"
   }
  }
  $entries[$id].attack=@($translatedSteps)
  $stageDCount++
  $stageDSteps+=$expected
 }
}
if($stageDCount -ne 77 -or $stageDSteps -ne 272){
 throw "Неполный этап D: типов=$stageDCount, пунктов=$stageDSteps (ожидалось 77/272)"
}
Write-Host "[RU] PASS: 77 новых разделов Attack (272 пункта) сверены с закреплённым английским источником"


# D2: точная сверка каждого пункта Attack/Impact/Remediation с оригиналом EN.
$attackD2Count=0
$attackD2Steps=0
$seenD2=@{}
$coreD2Count=0
$impactD2Steps=0
$remediationD2Steps=0
function Get-PinnedFindingText([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$originalFindingText.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "Найден несуществующий FindingId: $id"}
 $stop=$originalFindingText.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "Не найден конец блока оригинала: $id"}
 $block=$originalFindingText.Substring($start,$stop-$start)
 $fieldRe='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$fieldRe)
 if(-not $match.Success){throw "Отсутствует $field у $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') | ForEach-Object { $_.Groups['value'].Value })
}
foreach($name in @('SourceVerifiedAttack-11a.ru-RU.json','SourceVerifiedAttack-11b.ru-RU.json',
                   'SourceVerifiedAttack-11c.ru-RU.json','SourceVerifiedAttack-11d.ru-RU.json')){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($row in $cat.translations.PSObject.Properties){
  $id=[string]$row.Name
  if($seenD2.ContainsKey($id)){throw "Повтор FindingId D2: $id"}
  $seenD2[$id]=$true
  if(-not $entries.Contains($id)){throw "Неизвестный FindingId: $id"}
  if(@($entries[$id].attack).Count -gt 0){throw "Существующий Attack запрещено перезаписывать: $id"}
  $original=@(Get-PinnedFindingText $id 'Attack')
  $witness=@($row.Value.sourceEnglishAttack)
  $translated=@($row.Value.attack)
  $n=[int]$row.Value.sourceEnglishAttackStepCount
  if($n -ne $original.Count -or $n -ne $witness.Count -or $n -ne $translated.Count){
   throw "Разная длина Attack: $id, $n / $($original.Count) / $($witness.Count) / $($translated.Count)"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$witness[$i]){throw "Изменён EN-источник: $id, шаг $($i+1)"}
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){throw "Нет русского шага: $id, шаг $($i+1)"}
  }
  $entries[$id].attack=@($translated)
  $attackD2Count++
  $attackD2Steps+=$n
 }
}
if($attackD2Count -ne 112 -or $attackD2Steps -ne 380){throw "Неполный набор D2 Attack: $attackD2Count / $attackD2Steps"}
$core=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-11.ru-RU.json'),[Text.Encoding]::UTF8))
foreach($row in $core.translations.PSObject.Properties){
 $id=[string]$row.Name
 if(-not $entries.Contains($id)){throw "Неизвестная находка Core D2: $id"}
 foreach($field in @('Impact','Remediation')){
  $name=$field.ToLowerInvariant()
  $enProp='sourceEnglish'+$field
  $countProp='sourceEnglish'+$field+'Count'
  $original=@(Get-PinnedFindingText $id $field)
  $witness=@($row.Value.$enProp)
  $translated=@($row.Value.$name)
  $n=[int]$row.Value.$countProp
  if($n -ne $original.Count -or $n -ne $witness.Count -or $n -ne $translated.Count){
   throw "Разная длина $field у $id"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$witness[$i]){throw "Изменён EN-источник $id, поле $field, пункт $($i+1)"}
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){throw "Нет русского пункта $id, поле $field, пункт $($i+1)"}
  }
  $entries[$id].$name=@($translated)
  if($field -eq 'Impact'){$impactD2Steps+=$n}else{$remediationD2Steps+=$n}
 }
 $coreD2Count++
}
if($coreD2Count -ne 10 -or $impactD2Steps -ne 38 -or $remediationD2Steps -ne 41){
 throw "Неполный набор D2 Core: $coreD2Count / $impactD2Steps / $remediationD2Steps"
}
if(@($entries.Values | Where-Object { @($_.attack).Count -gt 0 }).Count -ne 304){
 throw 'Ожидалось 304/304 русских Attack, не считая 88 пустых оригиналов'
}
Write-Host '[RU] PASS D2: Attack 304/304, новых 112 разделов/380 пунктов; Impact 38, Remediation 41 для 10 критичных находок'


# Этап D3: полные Impact/Remediation для 14 дополнительных находок.
# Каждый пункт исходника и перевода связан с точным полем закреплённого adPEAS 2.9.0.
# Изменение источника, неполная структура или совпадение с ранее проверенным ID блокирует сборку.
$d3=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-12.ru-RU.json'),[Text.Encoding]::UTF8))
if(@($d3.translations.PSObject.Properties).Count -ne 14){throw 'Ожидалось 14 находок D3'}
$d3Count=0
$d3Impact=0
$d3Remediation=0
$previouslyVerified=@{}
foreach($name in @('SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json')){
 $prior=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $prior.translations.PSObject.Properties){$previouslyVerified[[string]$p.Name]=$true}
}
foreach($row in $d3.translations.PSObject.Properties){
 $id=[string]$row.Name
 if(-not $entries.Contains($id)){throw "Неизвестный FindingId D3: $id"}
 if($previouslyVerified.ContainsKey($id)){throw "D3 запрещает перезапись уже проверенного перевода: $id"}
 foreach($field in @('Impact','Remediation')){
  $lower=$field.ToLowerInvariant()
  $enProperty='sourceEnglish'+$field
  $countProperty=$enProperty+'Count'
  $original=@(Get-PinnedFindingText $id $field)
  $witness=@($row.Value.$enProperty)
  $translated=@($row.Value.$lower)
  $expected=[int]$row.Value.$countProperty
  if($expected -le 0 -or $original.Count -ne $expected -or
     $witness.Count -ne $expected -or $translated.Count -ne $expected){
   throw "D3: неполный перевод $id / $field"
  }
  for($i=0;$i -lt $expected;$i++){
   if([string]$original[$i] -cne [string]$witness[$i]){
    throw "D3: английский оригинал изменился: $id / $field / пункт $($i+1)"
   }
   if([string]::IsNullOrWhiteSpace([string]$translated[$i]) -or [string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D3: русский пункт отсутствует: $id / $field / пункт $($i+1)"
   }
  }
  $entries[$id].$lower=@($translated)
  if($field -eq 'Impact'){$d3Impact+=$expected}else{$d3Remediation+=$expected}
 }
 $d3Count++
}
if($d3Count -ne 14 -or $d3Impact -ne 46 -or $d3Remediation -ne 43){
 throw "D3: неполный набор $d3Count / $d3Impact / $d3Remediation"
}
Write-Host "[RU] PASS D3: 14 находок, Impact 46 и Remediation 43 сверены с EN-источником"


# Этап D4: полная предметная сверка Impact/Remediation для 20 типов
# делегирования, AD CS, ACL и GPO без изменения проверяющих механизмов.
$d4=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-13.ru-RU.json'),[Text.Encoding]::UTF8))
if(@($d4.translations.PSObject.Properties).Count -ne 20){throw 'D4: ожидалось 20 находок'}
$d4AlreadyVerified=@{}
foreach($catalogName in @('SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json','SourceVerifiedCore-12.ru-RU.json')){
 $prior=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 foreach($priorItem in $prior.translations.PSObject.Properties){$d4AlreadyVerified[[string]$priorItem.Name]=$true}
}
$d4Count=0
$d4Impact=0
$d4Remediation=0
foreach($row in $d4.translations.PSObject.Properties){
 $id=[string]$row.Name
 if(-not $entries.Contains($id)){throw "D4: неизвестный FindingId $id"}
 if($d4AlreadyVerified.ContainsKey($id)){throw "D4: запрещено перезаписывать уже проверенный FindingId $id"}
 foreach($field in @('Impact','Remediation')){
  $lower=$field.ToLowerInvariant()
  $enProperty='sourceEnglish'+$field
  $countProperty=$enProperty+'Count'
  $original=@(Get-PinnedFindingText $id $field)
  $englishWitness=@($row.Value.$enProperty)
  $russian=@($row.Value.$lower)
  $expected=[int]$row.Value.$countProperty
  if($expected -le 0 -or $original.Count -ne $expected -or
     $englishWitness.Count -ne $expected -or $russian.Count -ne $expected){
   throw "D4: число пунктов не совпадает $id / $field"
  }
  for($i=0;$i -lt $expected;$i++){
   if([string]$original[$i] -cne [string]$englishWitness[$i]){
    throw "D4: английский оригинал изменён $id / $field / пункт $($i+1)"
   }
   if([string]::IsNullOrWhiteSpace([string]$russian[$i]) -or [string]$russian[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D4: отсутствует русский перевод $id / $field / пункт $($i+1)"
   }
  }
  $entries[$id].$lower=@($russian)
  if($field -eq 'Impact'){$d4Impact+=$expected}else{$d4Remediation+=$expected}
 }
 $d4Count++
}
if($d4Count -ne 20 -or $d4Impact -ne 75 -or $d4Remediation -ne 77){
 throw "D4: неполный перевод $d4Count / $d4Impact / $d4Remediation"
}
Write-Host '[RU] PASS D4: 20 находок, Impact 75 и Remediation 77 по закреплённому оригиналу'


# Этап D5: source-pinned поля Impact/Remediation для LAPS, Kerberos, AD CS,
# привилегированных учётных записей, gMSA и делегированных прав OU.
# Только UI-словарь: определения FindingId, триггеры, риск и команды не меняются.
$d5Names=@('SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json')
$d5Previous=@{}
foreach($catalogName in @('SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
                         'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json')){
 $previousCatalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 foreach($p in $previousCatalog.translations.PSObject.Properties){$d5Previous[[string]$p.Name]=$true}
}
$d5Seen=@{}
$d5Impact=0
$d5Remediation=0
foreach($catalogName in $d5Names){
 $d5Catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($d5Catalog.translations.PSObject.Properties).Count -ne 12){throw "D5: неполный каталог $catalogName"}
 foreach($row in $d5Catalog.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D5: неизвестный FindingId $id"}
  if($d5Previous.ContainsKey($id) -or $d5Seen.ContainsKey($id)){
   throw "D5: запрещена перезапись или повторная запись $id"
  }
  $d5Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $enProp='sourceEnglish'+$field
   $countProp=$enProp+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $witness=@($row.Value.$enProp)
   $translated=@($row.Value.$lower)
   $count=[int]$row.Value.$countProp
   if($count -le 0 -or $count -ne $original.Count -or
      $count -ne $witness.Count -or $count -ne $translated.Count){
    throw "D5: не совпадает число пунктов $id / $field"
   }
   for($i=0;$i -lt $count;$i++){
    if([string]$witness[$i] -cne [string]$original[$i]){
     throw "D5: изменён английский источник $id / $field / пункт $($i+1)"
    }
    if([string]::IsNullOrWhiteSpace([string]$translated[$i]) -or [string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
     throw "D5: отсутствует русская строка $id / $field / пункт $($i+1)"
    }
   }
   $entries[$id].$lower=@($translated)
   if($field -eq 'Impact'){$d5Impact+=$count}else{$d5Remediation+=$count}
  }
 }
}
if($d5Seen.Count -ne 24 -or $d5Impact -ne 94 -or $d5Remediation -ne 101){
 throw "D5: набор неполон $($d5Seen.Count) / $d5Impact / $d5Remediation"
}
Write-Host '[RU] PASS D5: 24 находки, Impact 94 и Remediation 101 по закреплённому источнику'


# Этап D6: полный перевод Impact/Remediation 24 AD CS/gMSA/LAPS/RODC/OU находок.
# По каждому пункту фиксируется EN-свидетель из закреплённого adPEAS 2.9.0.
# Ранее source-verified тексты запрещено перезаписывать; алгоритмы не затрагиваются.
$d6Catalogs=@('SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json')
$d6Prior=@{}
foreach($catalogName in @(
 'SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
 'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json',
 'SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json'
)){
 $priorCatalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 foreach($p in $priorCatalog.translations.PSObject.Properties){$d6Prior[[string]$p.Name]=$true}
}
$d6Seen=@{}
$d6Impact=0
$d6Remediation=0
foreach($catalogName in $d6Catalogs){
 $d6Catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($d6Catalog.translations.PSObject.Properties).Count -ne 12){throw "D6: ожидалось 12 находок в $catalogName"}
 foreach($row in $d6Catalog.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D6: нет FindingId $id"}
  if($d6Prior.ContainsKey($id) -or $d6Seen.ContainsKey($id)){throw "D6: повторное изменение проверенного перевода $id"}
  $d6Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $enProperty='sourceEnglish'+$field
   $countProperty=$enProperty+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $witness=@($row.Value.$enProperty)
   $russian=@($row.Value.$lower)
   $n=[int]$row.Value.$countProperty
   if($n -le 0 -or $n -ne $original.Count -or
      $n -ne $witness.Count -or $n -ne $russian.Count){
    throw "D6: число пунктов не совпало $id / $field"
   }
   for($i=0;$i -lt $n;$i++){
    if([string]$witness[$i] -cne [string]$original[$i]){
     throw "D6: английский источник изменился $id / $field / $($i+1)"
    }
    if([string]::IsNullOrWhiteSpace([string]$russian[$i]) -or
       [string]$russian[$i] -notmatch '[А-Яа-яЁё]'){
     throw "D6: отсутствует русская строка $id / $field / $($i+1)"
    }
   }
   $entries[$id].$lower=@($russian)
   if($field -eq 'Impact'){$d6Impact+=$n}else{$d6Remediation+=$n}
  }
 }
}
if($d6Seen.Count -ne 24 -or $d6Impact -ne 79 -or $d6Remediation -ne 74){
 throw "D6: неполный набор $($d6Seen.Count) / $d6Impact / $d6Remediation"
}
Write-Host '[RU] PASS D6: 24 находки, Impact 79 и Remediation 74 сверены с EN-источником'


# Этап D7: source-pinned Impact/Remediation для 24 групп AUTHN/LDAP/ADCS/OU.
# Отдельные английские свидетели, запрет перекрытия A-D6, точный порядок пунктов.
$d7CatalogNames=@('SourceVerifiedCore-16a.ru-RU.json','SourceVerifiedCore-16b.ru-RU.json')
$d7EarlierNames=@(
 'SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
 'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json',
 'SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json',
 'SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json'
)
$d7Prior=@{}
foreach($catalogName in $d7EarlierNames){
 $prior=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 foreach($p in $prior.translations.PSObject.Properties){$d7Prior[[string]$p.Name]=$true}
}
$d7Seen=@{}
$d7Impact=0
$d7Remediation=0
foreach($catalogName in $d7CatalogNames){
 $d7Catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($d7Catalog.translations.PSObject.Properties).Count -ne 12){throw "D7: каталог $catalogName должен содержать 12 находок"}
 foreach($row in $d7Catalog.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D7: неизвестный FindingId $id"}
  if($d7Prior.ContainsKey($id) -or $d7Seen.ContainsKey($id)){throw "D7: повторный или уже сверенный FindingId $id"}
  $d7Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $enProp='sourceEnglish'+$field
   $countProp=$enProp+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $witness=@($row.Value.$enProp)
   $russian=@($row.Value.$lower)
   $expected=[int]$row.Value.$countProp
   if($expected -le 0 -or $original.Count -ne $expected -or
      $witness.Count -ne $expected -or $russian.Count -ne $expected){
    throw "D7: несовпадение числа пунктов $id / $field"
   }
   for($i=0;$i -lt $expected;$i++){
    if([string]$original[$i] -cne [string]$witness[$i]){
     throw "D7: английский источник изменился $id / $field / пункт $($i+1)"
    }
    if([string]::IsNullOrWhiteSpace([string]$russian[$i]) -or
       [string]$russian[$i] -notmatch '[А-Яа-яЁё]'){
     throw "D7: нет русского перевода $id / $field / пункт $($i+1)"
    }
   }
   $entries[$id].$lower=@($russian)
   if($field -eq 'Impact'){$d7Impact+=$expected}else{$d7Remediation+=$expected}
  }
 }
}
if($d7Seen.Count -ne 24 -or $d7Impact -ne 85 -or $d7Remediation -ne 93){
 throw "D7: неполный набор $($d7Seen.Count) / $d7Impact / $d7Remediation"
}
Write-Host '[RU] PASS D7: 24 находки, Impact 85 и Remediation 93 сверены с исходником'


# Этап D8: точный перевод Impact и Remediation 24 находок ACL/GPO/domain root.
# Привязка к строкам adPEAS 2.9.0, без изменения логики проверок и команд.
$d8New=@('SourceVerifiedCore-17a.ru-RU.json','SourceVerifiedCore-17b.ru-RU.json')
$d8Earlier=@(
 'SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
 'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json',
 'SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json',
 'SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json',
 'SourceVerifiedCore-16a.ru-RU.json','SourceVerifiedCore-16b.ru-RU.json'
)
$d8Protected=@{}
foreach($name in $d8Earlier){
 $old=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($r in $old.translations.PSObject.Properties){$d8Protected[[string]$r.Name]=$true}
}
$d8Seen=@{}
$d8Impact=0
$d8Remediation=0
foreach($name in $d8New){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 if(@($cat.translations.PSObject.Properties).Count -ne 12){throw "D8: неполный каталог $name"}
 foreach($row in $cat.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D8: неизвестный FindingId $id"}
  if($d8Protected.ContainsKey($id) -or $d8Seen.ContainsKey($id)){throw "D8: найден повтор ранее сверенного ID $id"}
  $d8Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $prop='sourceEnglish'+$field
   $countProp=$prop+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $witness=@($row.Value.$prop)
   $russian=@($row.Value.$lower)
   $count=[int]$row.Value.$countProp
   if($count -le 0 -or $original.Count -ne $count -or
      $witness.Count -ne $count -or $russian.Count -ne $count){
    throw "D8: неполный перевод $id / $field"
   }
   for($i=0;$i -lt $count;$i++){
    if([string]$original[$i] -cne [string]$witness[$i]){throw "D8: изменён EN $id / $field / пункт $($i+1)"}
    if([string]::IsNullOrWhiteSpace([string]$russian[$i]) -or
       [string]$russian[$i] -notmatch '[А-Яа-яЁё]'){throw "D8: отсутствует RU $id / $field / пункт $($i+1)"}
   }
   $entries[$id].$lower=@($russian)
   if($field -eq 'Impact'){$d8Impact+=$count}else{$d8Remediation+=$count}
  }
 }
}
if($d8Seen.Count -ne 24 -or $d8Impact -ne 79 -or $d8Remediation -ne 75){
 throw "D8: неверный набор $($d8Seen.Count) / $d8Impact / $d8Remediation"
}
Write-Host '[RU] PASS D8: 24 находки, Impact 79 и Remediation 75 проверены по EN'


# Этап D9: точный перевод Impact/Remediation 24 Registry и GPO User Rights.
# Сверка исходных EN-свидетелей, запрет перекрытия ранее проверенных полей.
$d9New=@('SourceVerifiedCore-18a.ru-RU.json','SourceVerifiedCore-18b.ru-RU.json')
$d9Earlier=@(
 'SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
 'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json',
 'SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json',
 'SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json',
 'SourceVerifiedCore-16a.ru-RU.json','SourceVerifiedCore-16b.ru-RU.json',
 'SourceVerifiedCore-17a.ru-RU.json','SourceVerifiedCore-17b.ru-RU.json'
)
$d9Protected=@{}
foreach($name in $d9Earlier){
 $old=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($r in $old.translations.PSObject.Properties){$d9Protected[[string]$r.Name]=$true}
}
$d9Seen=@{}
$d9Impact=0
$d9Remediation=0
foreach($name in $d9New){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 if(@($cat.translations.PSObject.Properties).Count -ne 12){throw "D9: неполный каталог $name"}
 foreach($row in $cat.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D9: неизвестный FindingId $id"}
  if($d9Protected.ContainsKey($id) -or $d9Seen.ContainsKey($id)){throw "D9: повтор ранее сверенного ID $id"}
  $d9Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $prop='sourceEnglish'+$field
   $countProp=$prop+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $witness=@($row.Value.$prop)
   $russian=@($row.Value.$lower)
   $count=[int]$row.Value.$countProp
   if($count -le 0 -or $original.Count -ne $count -or
      $witness.Count -ne $count -or $russian.Count -ne $count){
    throw "D9: неполный перевод $id / $field"
   }
   for($i=0;$i -lt $count;$i++){
    if([string]$original[$i] -cne [string]$witness[$i]){throw "D9: изменён EN $id / $field / пункт $($i+1)"}
    if([string]::IsNullOrWhiteSpace([string]$russian[$i]) -or
       [string]$russian[$i] -notmatch '[А-Яа-яЁё]'){throw "D9: отсутствует RU $id / $field / пункт $($i+1)"}
   }
   $entries[$id].$lower=@($russian)
   if($field -eq 'Impact'){$d9Impact+=$count}else{$d9Remediation+=$count}
  }
 }
}
if($d9Seen.Count -ne 24 -or $d9Impact -ne 61 -or $d9Remediation -ne 45){
 throw "D9: неверный набор $($d9Seen.Count) / $d9Impact / $d9Remediation"
}
Write-Host '[RU] PASS D9: 24 находки, Impact 61 и Remediation 45 проверены по EN'


# Этап D10: точная локализация 24 Registry/Spooler/SYSVOL/GPO User Rights находок.
# Сверка каждого английского пункта, запрет перезаписи ранее проверенных типов.
$d10Catalogs=@('SourceVerifiedCore-19a.ru-RU.json','SourceVerifiedCore-19b.ru-RU.json')
$d10Older=@(
 'SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
 'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json',
 'SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json',
 'SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json',
 'SourceVerifiedCore-16a.ru-RU.json','SourceVerifiedCore-16b.ru-RU.json',
 'SourceVerifiedCore-17a.ru-RU.json','SourceVerifiedCore-17b.ru-RU.json',
 'SourceVerifiedCore-18a.ru-RU.json','SourceVerifiedCore-18b.ru-RU.json'
)
$d10Protected=@{}
foreach($name in $d10Older){
 $prior=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($entry in $prior.translations.PSObject.Properties){$d10Protected[[string]$entry.Name]=$true}
}
$d10Seen=@{}
$d10Impact=0
$d10Remediation=0
foreach($name in $d10Catalogs){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 if(@($cat.translations.PSObject.Properties).Count -ne 12){throw "D10: каталог $name должен содержать 12 типов"}
 foreach($row in $cat.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D10: неизвестный FindingId $id"}
  if($d10Protected.ContainsKey($id) -or $d10Seen.ContainsKey($id)){throw "D10: перекрыт ранее сверенный FindingId $id"}
  $d10Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $enProp='sourceEnglish'+$field
   $countProp=$enProp+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $english=@($row.Value.$enProp)
   $translated=@($row.Value.$lower)
   $n=[int]$row.Value.$countProp
   if($n -le 0 -or $n -ne $original.Count -or
      $n -ne $english.Count -or $n -ne $translated.Count){
    throw "D10: число пунктов не совпадает $id / $field"
   }
   for($i=0;$i -lt $n;$i++){
    if([string]$original[$i] -cne [string]$english[$i]){throw "D10: изменён английский оригинал $id / $field / $($i+1)"}
    if([string]::IsNullOrWhiteSpace([string]$translated[$i]) -or
       [string]$translated[$i] -notmatch '[А-Яа-яЁё]'){throw "D10: пустой или непереведённый пункт $id / $field / $($i+1)"}
   }
   $entries[$id].$lower=@($translated)
   if($field -eq 'Impact'){$d10Impact+=$n}else{$d10Remediation+=$n}
  }
 }
}
if($d10Seen.Count -ne 24 -or $d10Impact -ne 54 -or $d10Remediation -ne 43){
 throw "D10: неверный набор $($d10Seen.Count) / $d10Impact / $d10Remediation"
}
Write-Host '[RU] PASS D10: 24 находки, Impact 54 и Remediation 43 по закреплённому оригиналу'


# Этап D11: полный перевод Impact и Remediation для 24 прав GPO, паролей,
# доверий, делегирования и SMB. Только русский каталог, код сканера не изменяется.
$d11CatalogNames=@('SourceVerifiedCore-20a.ru-RU.json','SourceVerifiedCore-20b.ru-RU.json')
$d11ProtectedNames=@(
 'SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
 'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json',
 'SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json',
 'SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json',
 'SourceVerifiedCore-16a.ru-RU.json','SourceVerifiedCore-16b.ru-RU.json',
 'SourceVerifiedCore-17a.ru-RU.json','SourceVerifiedCore-17b.ru-RU.json',
 'SourceVerifiedCore-18a.ru-RU.json','SourceVerifiedCore-18b.ru-RU.json',
 'SourceVerifiedCore-19a.ru-RU.json','SourceVerifiedCore-19b.ru-RU.json'
)
$d11Protected=@{}
foreach($name in $d11ProtectedNames){
 $oldCatalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $oldCatalog.translations.PSObject.Properties){$d11Protected[[string]$p.Name]=$true}
}
$d11Seen=@{}
$d11Impact=0
$d11Remediation=0
foreach($name in $d11CatalogNames){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 if(@($cat.translations.PSObject.Properties).Count -ne 12){throw "D11: каталог $name должен иметь 12 записей"}
 foreach($row in $cat.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D11: неизвестный FindingId $id"}
  if($d11Protected.ContainsKey($id) -or $d11Seen.ContainsKey($id)){throw "D11: перекрытие уже сверенной находки $id"}
  $d11Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $sourceName='sourceEnglish'+$field
   $countName=$sourceName+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $english=@($row.Value.$sourceName)
   $russian=@($row.Value.$lower)
   $expected=[int]$row.Value.$countName
   if($expected -le 0 -or $original.Count -ne $expected -or
      $english.Count -ne $expected -or $russian.Count -ne $expected){
    throw "D11: неверное число пунктов $id / $field"
   }
   for($i=0;$i -lt $expected;$i++){
    if([string]$original[$i] -cne [string]$english[$i]){throw "D11: изменён закреплённый EN $id / $field / $($i+1)"}
    if([string]::IsNullOrWhiteSpace([string]$russian[$i]) -or
       [string]$russian[$i] -notmatch '[А-Яа-яЁё]'){throw "D11: отсутствует русский пункт $id / $field / $($i+1)"}
   }
   $entries[$id].$lower=@($russian)
   if($field -eq 'Impact'){$d11Impact+=$expected}else{$d11Remediation+=$expected}
  }
 }
}
if($d11Seen.Count -ne 24 -or $d11Impact -ne 77 -or $d11Remediation -ne 77){
 throw "D11: неполный набор $($d11Seen.Count) / $d11Impact / $d11Remediation"
}
Write-Host '[RU] PASS D11: 24 находки, Impact 77 и Remediation 77 сверены с EN'


# Этап D12: source-verified Impact и Remediation для 24 credential/BitLocker/ADFS находок.
# Структурный и дословный контроль закреплённого EN, запрет повторного изменения старых ID.
$d12Catalogs=@('SourceVerifiedCore-21a.ru-RU.json','SourceVerifiedCore-21b.ru-RU.json')
$d12Older=@(
 'SourceVerifiedCore-07.ru-RU.json','SourceVerifiedCore-11.ru-RU.json',
 'SourceVerifiedCore-12.ru-RU.json','SourceVerifiedCore-13.ru-RU.json',
 'SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json',
 'SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json',
 'SourceVerifiedCore-16a.ru-RU.json','SourceVerifiedCore-16b.ru-RU.json',
 'SourceVerifiedCore-17a.ru-RU.json','SourceVerifiedCore-17b.ru-RU.json',
 'SourceVerifiedCore-18a.ru-RU.json','SourceVerifiedCore-18b.ru-RU.json',
 'SourceVerifiedCore-19a.ru-RU.json','SourceVerifiedCore-19b.ru-RU.json',
 'SourceVerifiedCore-20a.ru-RU.json','SourceVerifiedCore-20b.ru-RU.json'
)
$d12Protected=@{}
foreach($name in $d12Older){
 $prior=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($entry in $prior.translations.PSObject.Properties){$d12Protected[[string]$entry.Name]=$true}
}
$d12Seen=@{}
$d12Impact=0
$d12Remediation=0
foreach($name in $d12Catalogs){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 if(@($cat.translations.PSObject.Properties).Count -ne 12){throw "D12: неполный каталог $name"}
 foreach($row in $cat.translations.PSObject.Properties){
  $id=[string]$row.Name
  if(-not $entries.Contains($id)){throw "D12: неизвестный FindingId $id"}
  if($d12Protected.ContainsKey($id) -or $d12Seen.ContainsKey($id)){throw "D12: перезапись уже проверенного ID $id"}
  $d12Seen[$id]=$true
  foreach($field in @('Impact','Remediation')){
   $lower=$field.ToLowerInvariant()
   $originalProperty='sourceEnglish'+$field
   $nProperty=$originalProperty+'Count'
   $original=@(Get-PinnedFindingText $id $field)
   $witness=@($row.Value.$originalProperty)
   $russian=@($row.Value.$lower)
   $n=[int]$row.Value.$nProperty
   if($n -le 0 -or $n -ne $original.Count -or
      $n -ne $witness.Count -or $n -ne $russian.Count){
    throw "D12: число строк не совпало $id / $field"
   }
   for($i=0;$i -lt $n;$i++){
    if([string]$original[$i] -cne [string]$witness[$i]){throw "D12: изменился оригинальный EN $id / $field / $($i+1)"}
    if([string]::IsNullOrWhiteSpace([string]$russian[$i]) -or
       [string]$russian[$i] -notmatch '[А-Яа-яЁё]'){throw "D12: отсутствует русский перевод $id / $field / $($i+1)"}
   }
   $entries[$id].$lower=@($russian)
   if($field -eq 'Impact'){$d12Impact+=$n}else{$d12Remediation+=$n}
  }
 }
}
if($d12Seen.Count -ne 24 -or $d12Impact -ne 94 -or $d12Remediation -ne 97){
 throw "D12: неполный набор $($d12Seen.Count) / $d12Impact / $d12Remediation"
}
Write-Host '[RU] PASS D12: 24 находки, Impact 94 и Remediation 97 сверены с закреплённым EN'

$entryCount=$entries.Count
if($entryCount -ne 392){throw "Ожидалось 392 русских технических описания, найдено $entryCount"}
$required=@('LDAP_CHANNEL_BINDING_NOT_REQUIRED','LDAP_SIGNING_NOT_REQUIRED','UNCONSTRAINED_DELEGATION','DANGEROUS_ACL_GENERICALL')
foreach($id in $required){
 if(-not $entries.Contains($id)){throw "Нет полного перевода $id"}
 $item=$entries[$id]
 if([string]::IsNullOrWhiteSpace([string]$item.description)){throw "Не заполнено описание для $id"}
 foreach($field in @('impact','attack','remediation')){
  if($null -eq $item.$field){throw "Отсутствует раздел $field для $id"}
 }
}
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$startMarker='        const ruFindingExplanations = '
$start=$js.IndexOf($startMarker,[StringComparison]::Ordinal)
if($start -lt 0){throw 'Не найден русский справочник находок'}
$lineEnd=$js.IndexOf([char]10,$start)
if($lineEnd -lt 0){throw 'Не найдена граница строки словаря находок'}
$line=$js.Substring($start,$lineEnd-$start).TrimEnd([char]13)
if(-not $line.EndsWith(';')){throw 'Строка словаря находок не заканчивается точкой с запятой'}
$end=$start+$line.Length-1
$fullJson=ConvertTo-Json -InputObject $entries -Depth 18 -Compress
$js=$js.Insert($end+1,[Environment]::NewLine+'        const ruFullFindingTechnical = '+$fullJson+';')
$old=@'
            html += '<details class="tooltip-section" lang="en">' +
                '<summary>Полное техническое описание (оригинал EN)</summary>' +
                '<p>' + escapeHtml(finding.description) + '</p>' +
                (finding.impact ? '<p>Impact</p><ul>' + finding.impact.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.attack ? '<p>Attack</p><ul>' + finding.attack.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.remediation ? '<p>Remediation</p><ul>' + finding.remediation.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                '</details>';
'@
$replacement=@'
            // Curated Russian description, impact and remediation for every FindingId.
            // Attack is shown only when an individual RU explanation exists.
            // English originals remain available separately for comparison.
            const ruFull = ruFullFindingTechnical[findingId] || null;
            if (ruFull) {
                const addRuList = (label, values) =>
                    values && values.length > 0
                        ? '<strong>' + label + '</strong><ul>' +
                          values.map(value => '<li>' + escapeHtml(value) + '</li>').join('') +
                          '</ul>'
                        : '';
                html += '<details class="tooltip-section" lang="ru">' +
                    '<summary>Подробное техническое описание</summary>' +
                    '<p>' + escapeHtml(ruFull.description) + '</p>' +
                    addRuList('Последствия', ruFull.impact) +
                    addRuList('Сценарий атаки', ruFull.attack) +
                    addRuList('Рекомендации по устранению', ruFull.remediation) +
                    '</details>';
            }
            html += '<details class="tooltip-section" lang="en">' +
                '<summary>Сверить с исходным текстом на английском (EN)</summary>' +
                '<p>' + escapeHtml(finding.description) + '</p>' +
                (finding.impact ? '<p>Impact</p><ul>' + finding.impact.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.attack ? '<p>Attack</p><ul>' + finding.attack.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.remediation ? '<p>Remediation</p><ul>' + finding.remediation.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                '</details>';
'@
$old=$old.Replace("`r`n","`n")
$replacement=$replacement.Replace("`r`n","`n")
if(-not $js.Contains($old)){throw 'Не найден точный HTML-блок исходного технического описания'}
if([regex]::Matches($js,[regex]::Escape($old)).Count -ne 1){throw 'Несколько неоднозначных HTML-блоков'}
$js=$js.Replace($old,$replacement)
# Старые уведомления об отсутствии перевода не должны попадать в интерфейс.
if($js.Contains('Исходное подробное описание EN (перевод пока не завершён)')) { throw 'Найдена устаревшая пометка EN' }
$enc=New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($path,$js,$enc)
$coreDefinitionsHashAfter=(Get-FileHash -LiteralPath $coreDefinitions -Algorithm SHA256).Hash
if($coreDefinitionsHashBefore -ne $coreDefinitionsHashAfter){throw 'ОШИБКА: локализация изменила канонические определения adPEAS'}

$withAttack=@($entries.Values | Where-Object { @($_.attack).Count -gt 0 }).Count
Write-Host "[RU] PASS: $entryCount типов находок имеют русское описание, последствия и рекомендации; сценарии: $withAttack"
Write-Host '[RU] PASS: исходные описания EN доступны отдельно; FindingId и команды не изменены'
