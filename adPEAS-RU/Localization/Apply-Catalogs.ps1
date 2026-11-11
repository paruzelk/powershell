#Requires -Version 5.1
<#
.SYNOPSIS
    Русские заголовки разделов, справочные тексты и названия находок.
.NOTES
    Не изменяет машинные идентификаторы, оценки риска или LDAP-атрибуты.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$enc=New-Object System.Text.UTF8Encoding($true)
$dir=Join-Path $ProjectRoot 'Localization'
function Load-RU([string]$Name){
    $file=Join-Path $dir $Name
    if(-not(Test-Path -LiteralPath $file)){throw "Не найден ресурс $Name"}
    ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8))
}
function Escape-PS([string]$Text){
    $bt=[string][char]96
    '"' + $Text.Replace($bt,$bt+$bt).Replace('"',$bt+'"').Replace('$',$bt+'$') + '"'
}
$sections=(Load-RU 'ObjectTypes.ru-RU.json').translations
$path=Join-Path $ProjectRoot 'src/modules/Core/adPEAS-ObjectTypes.ps1'
$lines=[IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)
$id=''
$modules=@{}
$count=0
for($i=0;$i -lt $lines.Length;$i++){
    $line=$lines[$i]
    if($line -match "^    '([^']+)' *= *@\{"){$id=$Matches[1]}
    if($id -and $line -match '^\s+Module\s*=\s*"([^"]+)"'){$modules[$id]=$Matches[1]}
    if($id -and $line -match '^(        )(SectionTitle|Summary)(\s*=\s*)".*"$'){
        $indent=$Matches[1];$field=$Matches[2];$eq=$Matches[3]
        $p=$sections.PSObject.Properties[$id]
        if($null -ne $p){
            $translation=[string]$p.Value.$field
            if($translation){
                $lines[$i]=$indent+$field+$eq+(Escape-PS $translation)
                $count++
            }
        }
    }
}
if($count -ne 250){throw "Неполная локализация разделов: $count из 250"}
[IO.File]::WriteAllLines($path,$lines,$enc)
$titles=[ordered]@{}
foreach($part in @('01','02','03','04')){
    $json=Load-RU ("Findings-Titles-$part.ru-RU.json")
    foreach($p in $json.PSObject.Properties){
        if($titles.Contains($p.Name)){throw "Дублируется $($p.Name)"}
        $titles[$p.Name]=[string]$p.Value
    }
}
if($titles.Count -ne 392){throw "Не все FindingId переведены: $($titles.Count)/392"}
$expl=(Load-RU 'FindingExplanations.ru-RU.json').translations
$labels=Load-RU 'AttributeLabels.ru-RU.json'
$why=@{
 Domain='Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.'
 Accounts='Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.'
 Rights='Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.'
 GPO='Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.'
 Computer='Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.'
 Creds='Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.'
 Delegation='Ошибки делегирования Kerberos могут позволять действия от имени других пользователей. Проверяйте доверенные службы и субъектов.'
 ADCS='Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.'
 Application='Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.'
 Shares='Доступ к общим ресурсам и сценариям может раскрывать секреты или позволять изменять выполняемые файлы.'
 Bloodhound='Граф отношений выявляет возможные цепочки доступа и повышения привилегий. Данные о структуре домена следует защищать.'
}
$ctx=[ordered]@{}
foreach($p in $sections.PSObject.Properties){
    $id=$p.Name;$ru=$p.Value
    $mod=[string]$modules[$id]
    $whyText=if($why.ContainsKey($mod)){$why[$mod]}else{'Оцените фактические значения и применимость рекомендаций к архитектуре вашего домена.'}
    $ctx[$id]=@{
      title=[string]$ru.SectionTitle;summary=[string]$ru.Summary
      whyItMatters=$whyText
      whatWeCheck=@([string]$ru.Summary,'Проверенные параметры и обнаруженные объекты приведены в карточках результатов.')
      secureMessage=''
      filteringNote='Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.'
    }
}

# Индивидуальные сообщения о результате проверки: отсутствие находки != полнота проверки.
$secureTexts=@{}
foreach($name in @('CheckSecureMessages-08a.ru-RU.json','CheckSecureMessages-08b.ru-RU.json',
                  'CheckSecureMessages-08c.ru-RU.json','CheckSecureMessages-08d.ru-RU.json')){
 $source=Load-RU $name
 foreach($p in $source.translations.PSObject.Properties){
  $id=$p.Name
  if($secureTexts.ContainsKey($id)){throw "Дублируется перевод результата проверки: $id"}
  if(-not $ctx.Contains($id)){throw "Неизвестная проверка: $id"}
  $message=[string]$p.Value
  if([string]::IsNullOrWhiteSpace($message) -or $message -notmatch '[А-Яа-яЁё]'){throw "Нет русского сообщения: $id"}
  $secureTexts[$id]=$message
  $ctx[$id].secureMessage=$message
 }
}
if($secureTexts.Count -ne 94){throw "Ожидалось 94 проверенных secureMessage, найдено $($secureTexts.Count)"}
Write-Host "[RU] PASS: 94 результата проверок переведены без подмены статуса и области оценки"

$jsPath=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($jsPath,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(-not $js.Contains($mark)){throw 'Маркер JavaScript не найден'}
$ruTitlesJson=ConvertTo-Json -InputObject $titles -Depth 12 -Compress
$ruExplJson=ConvertTo-Json -InputObject $expl -Depth 12 -Compress
$ruLabelsJson=ConvertTo-Json -InputObject $labels -Depth 12 -Compress
$ruCtxJson=ConvertTo-Json -InputObject $ctx -Depth 12 -Compress
$injection=@"
        // RU display catalog. Canonical IDs, data attributes and scoring remain unchanged.
        const ruFindingTitles = $ruTitlesJson;
        const ruFindingExplanations = $ruExplJson;
        const ruAttributeLabels = $ruLabelsJson;
        const ruCheckContext = $ruCtxJson;
        Object.keys(ruCheckContext).forEach(function(id) {
            const check = checkDescriptions[id];
            const ru = ruCheckContext[id];
            if (!check) return;
            check.originalEnglish = {
                whyItMatters: check.whyItMatters,
                whatWeCheck: check.whatWeCheck,
                secureMessage: check.secureMessage,
                filteringNote: check.filteringNote
            };
            check.title = ru.title;
            check.summary = ru.summary;
            check.whyItMatters = ru.whyItMatters;
            check.whatWeCheck = ru.whatWeCheck;
            if (check.secureMessage) check.secureMessage = ru.secureMessage;
            if (check.filteringNote) check.filteringNote = ru.filteringNote;
        });
        document.addEventListener('DOMContentLoaded', function() {
            // Translate visible finding titles by exact text match. Never modify
            // LDAP/JSON data attributes, IDs, links, or code/command fragments.
            const englishTitleMap = Object.create(null);
            Object.keys(ruFindingTitles).forEach(function(fid) {
                const finding = findingDefinitions[fid];
                if (finding && typeof finding.title === 'string') {
                    englishTitleMap[finding.title.trim()] = ruFindingTitles[fid];
                }
            });
            const auditRoot = document.querySelector('.report-content') ||
                              document.querySelector('main') || document.body;
            const walker = document.createTreeWalker(auditRoot, NodeFilter.SHOW_TEXT);
            let textNode;
            while ((textNode = walker.nextNode())) {
                const parent = textNode.parentElement;
                if (!parent || parent.closest('script,style,pre,code,textarea')) continue;
                const original = textNode.nodeValue;
                const label = original.trim();
                if (Object.prototype.hasOwnProperty.call(englishTitleMap, label)) {
                    const prefix = original.slice(0, original.indexOf(label));
                    const suffix = original.slice(original.indexOf(label) + label.length);
                    textNode.nodeValue = prefix + englishTitleMap[label] + suffix;
                }
            }
            document.querySelectorAll('.attr-name').forEach(function(node) {
                const name = node.textContent.trim();
                const colon = name.endsWith(':') ? ':' : '';
                const key = colon ? name.slice(0,-1).trim() : name;
                if(Object.prototype.hasOwnProperty.call(ruAttributeLabels,key)) {
                    node.textContent = ruAttributeLabels[key] + colon;
                }
            });
            const statuses = {
                'Yes':'Да','No':'Нет','True':'Истина','False':'Ложь',
                'Enabled':'Включено','Disabled':'Отключено',
                'Not Set':'Не задано','Not Configured':'Не настроено',
                'Not Found':'Не найдено','Not Tested':'Не проверено',
                'Unknown':'Неизвестно','None':'Нет','N/A':'Н/Д',
                'Required':'Обязательно','Allowed':'Разрешено','Denied':'Запрещено'
            };
            document.querySelectorAll('.attr-value span').forEach(function(node) {
                if(node.children.length) return;
                const key = node.textContent.trim();
                if(Object.prototype.hasOwnProperty.call(statuses,key)){
                    node.textContent = statuses[key];
                }
            });
        });

"@
$js=$js.Replace($mark,$injection+$mark)
[IO.File]::WriteAllText($jsPath,$js,$enc)
Write-Host "[RU] PASS: 125 разделов, 392 находки, $($labels.PSObject.Properties.Count) названий полей"
