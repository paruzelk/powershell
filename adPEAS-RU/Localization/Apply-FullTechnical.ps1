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
