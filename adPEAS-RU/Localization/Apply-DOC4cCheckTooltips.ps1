#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4c: индивидуальные русские описания всех 125 карточек «Об этой проверке».
.DESCRIPTION
    Читает девять предметных каталогов и встраивает в HTML полное соответствие
    исходным WhyItMatters/WhatWeCheck. Не меняет проверки Active Directory,
    finding definitions, команды, риск-баллы, машинные имена и сканируемые данные.
    Английский исходник сохраняется в originalEnglish для сверки, но не
    отображается в модальном окне, когда полный перевод подтверждён.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$translations=[ordered]@{}
$loadedFiles=0
foreach($n in 1..9){
 $filename='CheckTooltipDetails-{0:D2}.ru-RU.json' -f $n
 $file=Join-Path $ProjectRoot ('Localization/'+$filename)
 if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "DOC4c: отсутствует $filename"}
 $package=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8))
 if($package.schema -ne 'adPEAS-RU.DOC4c.CheckTooltipDetails.1' -or $package.locale -ne 'ru-RU'){
  throw "DOC4c: некорректная схема или язык $filename"
 }
 foreach($entry in $package.translations.PSObject.Properties){
  $id=[string]$entry.Name
  if($translations.Contains($id)){throw "DOC4c: повтор ObjectType $id"}
  $ru=$entry.Value
  if(-not($ru.whyItMatters -is [string]) -or
     [string]::IsNullOrWhiteSpace([string]$ru.whyItMatters) -or
     [string]$ru.whyItMatters -notmatch '[А-Яа-яЁё]'){
   throw "DOC4c: отсутствует предметный перевод WhyItMatters для $id"
  }
  if($null -eq $ru.whatWeCheck -or @($ru.whatWeCheck).Count -lt 1){
   throw "DOC4c: нет критериев WhatWeCheck для $id"
  }
  foreach($bullet in @($ru.whatWeCheck)){
   if([string]::IsNullOrWhiteSpace([string]$bullet) -or
      [string]$bullet -notmatch '[А-Яа-яЁё]' -or
      [string]$bullet -match 'Проверенные параметры и обнаруженные объекты приведены'){
    throw "DOC4c: пропущен или шаблонный критерий $id"
   }
  }
  $translations[$id]=[ordered]@{
   whyItMatters=[string]$ru.whyItMatters
   whatWeCheck=@($ru.whatWeCheck)
  }
 }
 $loadedFiles++
}
if($translations.Count -ne 125 -or $loadedFiles -ne 9){
 throw "DOC4c: неполный каталог, обнаружено $($translations.Count)/125 типов, $loadedFiles/9 файлов"
}

# A fail-closed build guard on source object type identifiers, without
# parsing or executing the scanner and without connecting to AD.
$defs=[IO.File]::ReadAllText(
 (Join-Path $ProjectRoot 'src/modules/Core/adPEAS-ObjectTypes.ps1'),
 [Text.Encoding]::UTF8)
$originalIds=@([regex]::Matches($defs,"(?m)^    '([^']+)'\s*=\s*@\{") |
 ForEach-Object {$_.Groups[1].Value})
if($originalIds.Count -ne 125){throw "DOC4c: исходный каталог ObjectType изменился ($($originalIds.Count))"}
foreach($id in $originalIds){
 if(-not $translations.Contains($id)){throw "DOC4c: нет русского описания для ObjectType $id"}
}

$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(([regex]::Matches($js,[regex]::Escape($mark))).Count -ne 1){
 throw 'DOC4c: точка вставки справочных описаний отсутствует либо неоднозначна'
}
if($js.Contains('const ruDetailedCheckTooltips = ')){
 throw 'DOC4c: подробный перевод карточек уже установлен'
}
$json=ConvertTo-Json -InputObject $translations -Depth 20 -Compress
# The JSON is embedded in an HTML <script>; no source string may close the tag.
# Encode markup characters as JSON unicode escapes (JSON values stay equivalent).
$json=$json.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$inject=@'
        // DOC4c: complete human-reviewed RU descriptions and criterion-by-criterion
        // parity with checkDescriptions. Original EN remains available for audit only.
        const ruDetailedCheckTooltips = __DOC4C_JSON__;
        const ruDetailedKeys = Object.keys(ruDetailedCheckTooltips);
        if (ruDetailedKeys.length !== 125 || Object.keys(checkDescriptions).length !== 125) {
            throw new Error('DOC4c: check-description catalog count mismatch');
        }
        ruDetailedKeys.forEach(function(id) {
            const check = checkDescriptions[id];
            const ru = ruDetailedCheckTooltips[id];
            if (!check || !check.originalEnglish ||
                !Array.isArray(check.originalEnglish.whatWeCheck) ||
                !Array.isArray(ru.whatWeCheck) ||
                check.originalEnglish.whatWeCheck.length !== ru.whatWeCheck.length ||
                typeof check.originalEnglish.whyItMatters !== 'string' ||
                !ru.whyItMatters) {
                throw new Error('DOC4c: detailed criterion count or type differs: ' + id);
            }
            // Validate the pinned originalEnglish saved by Apply-Catalogs, NOT its\n            // temporary two-item RU summary. Preserve all original EN for audit.
            check.whyItMatters = ru.whyItMatters;
            check.whatWeCheck = ru.whatWeCheck.slice();
            // The English panel is suppressed only after complete 1:1 parity.
            check.ruDetailedCheckReady = true;
        });
        window.adPEASRUCheckTooltipAudit = Object.freeze({
            translatedObjectTypes: ruDetailedKeys.length,
            translatedCriteria: ruDetailedKeys.reduce(function(sum,id) {
                return sum + ruDetailedCheckTooltips[id].whatWeCheck.length;
            }, 0)
        });

'@
$inject=$inject.Replace('__DOC4C_JSON__',$json)
$js=$js.Replace($mark,$inject+$mark)

# Keep the precise upstream original in the embedded model, but stop showing
# it to end users once every original criterion has its Russian equivalent.
$before='if (check.originalEnglish && check.originalEnglish.whyItMatters) {'
$after='if (!check.ruDetailedCheckReady && check.originalEnglish && check.originalEnglish.whyItMatters) {'
$count=([regex]::Matches($js,[regex]::Escape($before))).Count
if($count -ne 1){throw "DOC4c: неожиданный HTML-блок оригинала EN: $count"}
$js=$js.Replace($before,$after)

[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
$criteria=0
foreach($item in $translations.Values){$criteria+=@($item.whatWeCheck).Count}
Write-Host "[RU] PASS DOC4c: 125 оригинальных типов, $criteria подробных критериев, EN сохранён для аудита и скрыт после полного перевода" -ForegroundColor Green
