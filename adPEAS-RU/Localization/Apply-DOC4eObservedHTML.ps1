#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4e: локализация подтверждённых английских пояснений в двух HTML.
.DESCRIPTION
    Только текстовые узлы DOM. Не изменяет исходные объекты AD,
    структуру отчёта, идентификаторы, права или внутренние атрибуты.
    Имена GPO, DN, SID и обозначения прав сохраняются дословно.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(([regex]::Matches($js,[regex]::Escape($mark))).Count -ne 1) {
    throw 'DOC4e: маркер вставки JS отсутствует или неоднозначен'
}
if($js.Contains('function ruDOC4eObservedPhrases')) {
    throw 'DOC4e: повторное добавление обработчика'
}
$inject=@'
        // DOC4e: only field-scoped human-readable suffixes and grammar.
        // Preserve GPO names, DNs, account names, SIDs and permission IDs.
        document.addEventListener('DOMContentLoaded', function ruDOC4eObservedPhrases() {
            const countWords = {
                'server(s)': ['сервер', 'сервера', 'серверов'],
                'client(s)': ['клиентская ОС', 'клиентские ОС', 'клиентских ОС'],
                'other': ['другая ОС', 'другие ОС', 'других ОС']
            };
            function plural(n, forms) {
                const r100=n%100, r10=n%10;
                if (r100>=11 && r100<=14) return forms[2];
                if (r10===1) return forms[0];
                if (r10>=2 && r10<=4) return forms[1];
                return forms[2];
            }
            function translate(text,key) {
                const m=text.match(/^(\s*)([\s\S]*?)(\s*)$/);
                if(!m) return text;
                const input=m[2];
                let output=input;
                if(key==='operatingSystems') {
                    // Source is a list of counts, e.g. 2 server(s), 4 client(s), 2 other.
                    const chunks=input.split(', ');
                    if(chunks.length>0 && chunks.every(function(item) {
                        return /^(\d+) (server\(s\)|client\(s\)|other)$/.test(item);
                    })) {
                        output=chunks.map(function(item) {
                            const parts=item.match(/^(\d+) (server\(s\)|client\(s\)|other)$/);
                            const count=Number(parts[1]);
                            return parts[1]+' '+plural(count,countWords[parts[2]]);
                        }).join(', ');
                    }
                } else if(key==='privilegeGrantedBy') {
                    const found=input.match(/^GPO '([^']+)' grants (Se[A-Za-z0-9_]+Privilege) to (.+)$/);
                    if(found) {
                        output='Групповая политика «'+found[1]+'» предоставляет право '+
                            found[2]+' субъекту '+found[3];
                    }
                } else if(key==='affectedGroups') {
                    if(input.endsWith(' (privileged group)')) {
                        output=input.slice(0,-' (privileged group)'.length)+' (привилегированная группа)';
                    }
                } else if(key==='affectedOUs') {
                    if(/^(?:OU|CN|DC)=/.test(input) && input.endsWith(' (set here)')) {
                        output=input.slice(0,-' (set here)'.length)+' (назначено непосредственно здесь)';
                    }
                } else if(key==='LinkedOUs') {
                    if(/^(?:OU|CN|DC)=/.test(input) && input.endsWith(' (link enforced)')) {
                        output=input.slice(0,-' (link enforced)'.length)+' (принудительная связь GPO)';
                    }
                }
                return m[1]+output+m[3];
            }
            let inspected=0, translated=0;
            const byField=Object.create(null);
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key=row.getAttribute('data-attr-name');
                if(!Object.prototype.hasOwnProperty.call({
                    operatingSystems:1, privilegeGrantedBy:1, affectedGroups:1,
                    affectedOUs:1, LinkedOUs:1
                },key)) return;
                const root=row.querySelector('.attr-value');
                if(!root) return;
                const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
                let node;
                while((node=walker.nextNode())) {
                    if(!node.parentElement ||
                        node.parentElement.closest('pre,code,textarea,script,style,a')) continue;
                    inspected++;
                    const after=translate(node.nodeValue,key);
                    if(after!==node.nodeValue) {
                        node.nodeValue=after;
                        translated++;
                        byField[key]=(byField[key]||0)+1;
                    }
                }
            });
            window.adPEASRUDOC4e=Object.freeze({
                inspected:inspected, translated:translated,
                byField:Object.freeze(byField)
            });
        });

'@
$js=$js.Replace($mark,$inject+$mark)
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC4e: UI-пояснения 5 полей, русские числительные, сохранность GPO/DN/разрешений'
