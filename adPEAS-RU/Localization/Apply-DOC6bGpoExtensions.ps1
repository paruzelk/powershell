#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6b: локализация только отображаемых названий расширений GPO.
.DESCRIPTION
    По двум отчётам DOC6a от 19.11.2026 оставались английские пользовательские
    имена расширений групповой политики (GPO CSE). Реальные GUID, исходные
    атрибуты AD и технические коды не изменяются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$anchor='        // DOC6a END: verified report display translations.'
if(([regex]::Matches($js,[regex]::Escape($anchor))).Count -ne 1){throw 'DOC6b: исходный якорь DOC6a отсутствует или неоднозначен'}
if($js.Contains('function ruDOC6bGpoExtensions')){throw 'DOC6b: повторное применение запрещено'}
$block=@'
        // DOC6b BEGIN: field-scoped, human-readable GPO CSE labels.
        document.addEventListener('DOMContentLoaded', function ruDOC6bGpoExtensions() {
            const exact=Object.freeze({
                'Registry (Wireless Group Policy)':'Реестр (групповая политика беспроводной сети)',
                'Security (Security Settings)':'Безопасность (параметры безопасности)'
            });
            let translated=0;
            const guid='\\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\}';
            const gpoSoftware=new RegExp('^('+guid+') \\(Software Installation\\)$');
            const gpoRegistry=new RegExp('^Registry \\(('+guid+')\\)$');
            const gpoRecovery=new RegExp('^EFS Recovery \\(('+guid+')\\)$');
            function localized(raw) {
                if(Object.prototype.hasOwnProperty.call(exact,raw)) return exact[raw];
                let m=gpoSoftware.exec(raw);
                if(m) return m[1]+' (установка программного обеспечения)';
                m=gpoRegistry.exec(raw);
                if(m) return 'Реестр ('+m[1]+')';
                m=gpoRecovery.exec(raw);
                if(m) return 'Восстановление EFS ('+m[1]+')';
                return raw;
            }
            function visit(node) {
                if(node.nodeType===Node.TEXT_NODE) {
                    const raw=node.nodeValue;
                    const prefix=(/^\s*/.exec(raw)||[''])[0];
                    const suffix=(/\s*$/.exec(raw)||[''])[0];
                    const core=raw.slice(prefix.length,raw.length-suffix.length);
                    const next=localized(core);
                    if(next!==core) {
                        node.nodeValue=prefix+next+suffix;
                        translated++;
                    }
                    return;
                }
                if(node.nodeType!==Node.ELEMENT_NODE ||
                   /^(CODE|PRE|SCRIPT|STYLE|A)$/.test(node.tagName))return;
                Array.from(node.childNodes).forEach(visit);
            }
            document.querySelectorAll('.attr-row[data-attr-name="gpcmachineextensionnames"] .attr-value')
                .forEach(visit);
            window.adPEASRUDOC6b=Object.freeze({translatedTextNodes:translated});
        });
        // DOC6b END: no raw AD mutations.

'@
$js=$js.Replace($anchor,$anchor+[Environment]::NewLine+$block)
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC6b: GPO CSE display names translated, GUIDs and AD data unchanged'
