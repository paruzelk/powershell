#Requires -Version 5.1
<#
.SYNOPSIS
    Отображаемые заголовки, значения параметров и доступные подписи HTML.
.DESCRIPTION
    JS-обработка только текстовых узлов; DOM-атрибуты data-*, FindingId,
    классы риска, ссылки, команды PowerShell и исходный JSON не меняются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$jsPath=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($jsPath,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(-not $js.Contains($mark)){throw 'Маркер JS для перевода HTML не найден'}
$inject=@'
        // ruPolishReportPresentation: display-only processing of safe text nodes.
        document.addEventListener('DOMContentLoaded', function ruPolishReportPresentation() {
            const sectionNames = {
                'Analyzing Domain Configuration':'Анализ параметров домена',
                'Analyzing Access Permissions':'Анализ прав доступа',
                'Analyzing Delegation Settings':'Анализ делегирования',
                'Analyzing Certificate Services':'Анализ служб сертификатов',
                'Analyzing Privileged Accounts':'Анализ привилегированных учётных записей',
                'Analyzing Group Policy Objects':'Анализ групповых политик'
            };
            document.querySelectorAll('.section-header .section-title').forEach(function(node) {
                const match = node.textContent.trim().match(/^(\[\d+\/\d+\])\s+(.+)$/);
                if(match && sectionNames[match[2]]) node.textContent = match[1] + ' ' + sectionNames[match[2]];
            });
            const labels = {
                'Enabled':'Включено', 'Disabled':'Отключено','Optional':'Необязательно',
                'Required':'Обязательно', 'Not Configured':'Не настроено',
                'Not configured':'Не настроено','Not set':'Не задано',
                'Refused':'Отклонено','Restricted':'Ограничено','Checked':'Проверяется',
                '(none)':'(нет)','None':'Нет', 'No':'Нет', 'Yes':'Да'
            };
            const attributeNames = {
                maxTicketAgeTGT:'Время действия TGT',maxRenewalAge:'Срок продления TGT',
                maxServiceTicketAge:'Срок действия билета службы',maxClockSkew:'Допустимое расхождение часов',
                krbtgtPasswordAge:'Возраст пароля krbtgt',domainControllerTime:'Время контроллера домена',
                minPwdLength:'Минимальная длина пароля',passwordComplexity:'Сложность пароля',
                minPwdAge:'Минимальный срок действия пароля',maxPwdAge:'Максимальный срок действия пароля',
                pwdHistoryLength:'История паролей',reversibleEncryption:'Обратимое шифрование',
                lockoutThreshold:'Порог блокировки',lockoutDuration:'Продолжительность блокировки',
                lockoutObservationWindow:'Окно наблюдения блокировки'
            };
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key = row.getAttribute('data-attr-name');
                const label = row.querySelector('.attr-name');
                if(label && attributeNames[key]) label.textContent = attributeNames[key];
            });
            function textRu(original) {
                const value = original.trim();
                if(Object.prototype.hasOwnProperty.call(labels,value)) return labels[value];
                let match = value.match(/^(\d+) (days|hours|minutes|characters)( \(default\))?$/i);
                if(match){
                    const units={days:'дн.',hours:'ч',minutes:'мин',characters:'символов'};
                    return match[1]+' '+units[match[2].toLowerCase()]+(match[3]?' (по умолчанию)':'');
                }
                match=value.match(/^(\d+) days \(last changed: (\d{4}-\d{2}-\d{2})\)$/);
                if(match) return match[1]+' дн. (последнее изменение: '+match[2]+')';
                match=value.match(/^(\d+) passwords remembered$/);
                if(match) return 'Запоминается паролей: '+match[1];
                return original;
            }
            document.querySelectorAll('.attr-value').forEach(function(root) {
                const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
                let node;
                while((node=walker.nextNode())){
                    if(node.parentElement && node.parentElement.closest('code,pre,a')) continue;
                    const translated=textRu(node.nodeValue);
                    if(translated !== node.nodeValue) node.nodeValue=translated;
                }
            });
            document.querySelectorAll('.finding-count').forEach(function(node){
                const match=node.textContent.trim().match(/^(\d+) элементов$/);
                if(!match)return;
                const n=parseInt(match[1],10),last=n%10,last2=n%100;
                const word=last2>=11&&last2<=14?'элементов':last===1?'элемент':last>=2&&last<=4?'элемента':'элементов';
                node.textContent=n+' '+word;
            });
            document.querySelectorAll('.object-header > span:first-child').forEach(function(node){
                if(node.textContent.indexOf('Domain: ')===0)node.textContent='Домен: '+node.textContent.slice(8);
                if(/^Domain Controllers \(\d+\)$/.test(node.textContent))node.textContent=node.textContent.replace('Domain Controllers','Контроллеры домена');
            });
            document.querySelectorAll('[aria-label]').forEach(function(node){
                const label=node.getAttribute('aria-label');
                if(/^Filter by Findings: \d+ critical issues$/.test(label))node.setAttribute('aria-label',label.replace(/^Filter by Findings:/,'Фильтр нарушений:').replace(' critical issues',''));
                if(/^Filter by Hints: \d+ items$/.test(label))node.setAttribute('aria-label',label.replace(/^Filter by Hints:/,'Фильтр предупреждений:').replace(' items',''));
                if(/^Filter by Notes: \d+ items$/.test(label))node.setAttribute('aria-label',label.replace(/^Filter by Notes:/,'Фильтр сведений:').replace(' items',''));
                if(/^Filter by Secure: \d+ items$/.test(label))node.setAttribute('aria-label',label.replace(/^Filter by Secure:/,'Фильтр безопасных результатов:').replace(' items',''));
            });
            const a11y={
                'Type to filter findings by text content':'Введите текст для поиска',
                'Toggle to show or hide findings marked as completed':'Показать или скрыть выполненные результаты'
            };
            document.querySelectorAll('.visually-hidden').forEach(function(node){
                const key=node.textContent.trim();
                if(a11y[key])node.textContent=a11y[key];
            });
        });

'@
if($js.Contains('ruPolishReportPresentation')){throw 'Повторная вставка HTML-перевода'}
$js=$js.Replace($mark,$inject+$mark)
[IO.File]::WriteAllText($jsPath,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS: заголовки разделов, значения и доступные подписи HTML переведены без изменения данных'
