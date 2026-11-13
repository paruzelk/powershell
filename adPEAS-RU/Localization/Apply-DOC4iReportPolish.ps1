#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4i: исправление отображаемых названий GPO и строк окна риска.
.DESCRIPTION
    Переводит только текстовые узлы DOM в точных пользовательских контекстах.
    Расчёт риска, исходные breakdown/JSON, имена GPO, GUID, DN и LDAP остаются неизменными.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$anchor='        // Scoring context data for context-aware risk calculation'
$render='            tooltip.innerHTML = formatScoreBreakdownHtml(breakdown);'
foreach($gate in @($anchor,$render)) {
    $n=([regex]::Matches($js,[regex]::Escape($gate))).Count
    if($n -ne 1){throw "DOC4i: ${gate}: ожидалось 1 совпадение, найдено $n"}
}
if($js.Contains('function ruDOC4iGpoHeaders')){throw 'DOC4i уже применён'}
$block=@'
        // DOC4i: context-specific GPO display labels; do not rewrite GPO identity.
        document.addEventListener('DOMContentLoaded', function ruDOC4iGpoHeaders() {
            const target=Object.freeze({
                'Настройки подписи LDAP в GPO':'Параметры подписи LDAP в GPO: ',
                'Настройки подписи SMB':'Параметры подписи SMB в GPO: '
            });
            const original='Параметры GPO для добавления компьютеров: ';
            let changed=0;
            const byCheck=Object.create(null);
            document.querySelectorAll('.finding-card').forEach(function(card) {
                const title=card.querySelector('.finding-title');
                const key=title ? title.textContent.trim() : '';
                if(!Object.prototype.hasOwnProperty.call(target,key)) return;
                card.querySelectorAll('.object-detail .object-header > span:first-child')
                    .forEach(function(label) {
                        if(label.childNodes.length!==1 || !label.firstChild ||
                           label.firstChild.nodeType!==Node.TEXT_NODE) return;
                        const text=label.firstChild.nodeValue;
                        if(typeof text!=='string' || !text.startsWith(original)) return;
                        label.firstChild.nodeValue=target[key]+text.slice(original.length);
                        changed++;
                        byCheck[key]=(byCheck[key]||0)+1;
                    });
            });
            window.adPEASRUDOC4i=Object.freeze({
                correctedGpoHeaders:changed,
                byCheck:Object.freeze(byCheck)
            });
        });

        // DOC4i: only alter the rendered risk tooltip DOM. No score formula
        // and no persisted score-breakdown or numerical values are modified.
        function ruDOC4iLocalizeScoreTooltip(tooltip) {
            const labels=Object.freeze({
                'Impact':'Влияние',
                'Correlation':'Корреляция',
                'Security':'Защитные меры'
            });
            const reasons=Object.freeze({
                'Standard':'Стандартный уровень',
                'Maximum (DCSync)':'Максимальный риск (DCSync)',
                'Tier 0 (Domain Admin)':'Tier 0 (администратор домена)',
                'Tier 1 (Server Admin)':'Tier 1 (администратор сервера)',
                'Tier 2 (Workstation Admin)':'Tier 2 (администратор рабочей станции)',
                'Non-Admin':'Без административных привилегий',
                'hint (informational)':'Предупреждение (информационный результат)',
                'Appears in multiple findings':'Обнаружено в нескольких результатах',
                'RC4 encryption':'Шифрование RC4',
                'Easier to exploit':'Проще эксплуатировать',
                'Harder to exploit':'Сложнее эксплуатировать',
                'Disabled':'Отключена',
                'Smartcard required':'Требуется смарт-карта',
                'Mitigated':'Риск снижен',
                'Vulnerable':'Уязвима'
            });
            let translatedLabels=0, translatedReasons=0;
            tooltip.querySelectorAll('.score-tooltip-label').forEach(function(node) {
                if(!node.firstChild || node.firstChild.nodeType!==Node.TEXT_NODE) return;
                const raw=node.firstChild.nodeValue;
                if(Object.prototype.hasOwnProperty.call(labels,raw)) {
                    node.firstChild.nodeValue=labels[raw];
                    translatedLabels++;
                }
            });
            tooltip.querySelectorAll('.score-tooltip-label .reason').forEach(function(node) {
                if(node.childNodes.length!==1 || !node.firstChild ||
                   node.firstChild.nodeType!==Node.TEXT_NODE) return;
                const raw=node.firstChild.nodeValue;
                const localized=raw.split(', ').map(function(part) {
                    if(Object.prototype.hasOwnProperty.call(reasons,part)) return reasons[part];
                    const old=/^Old password \((\d+)y\)$/.exec(part);
                    if(old) return 'Пароль не менялся '+old[1]+' г.';
                    return part;
                }).join(', ');
                if(raw!==localized) {
                    node.firstChild.nodeValue=localized;
                    translatedReasons++;
                }
            });
            window.adPEASRUDOC4iScoreLast=Object.freeze({
                translatedLabels:translatedLabels,
                translatedReasons:translatedReasons
            });
        }

'@
$js=$js.Replace($anchor,$block+$anchor)
$js=$js.Replace($render,$render+[Environment]::NewLine+'            ruDOC4iLocalizeScoreTooltip(tooltip);')
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC4i: контекстные GPO и пользовательское окно риска без изменения AD или risk-score'
