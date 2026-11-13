#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4f: завершающий точечный перевод наблюдавшихся пояснений ACL/Tier 0.
.DESCRIPTION
    Применяется исключительно к текстовым узлам заранее определённых
    атрибутов HTML, не изменяет исходные сведения AD, имена пользователей,
    группы, DN, SID, RID, типы прав или риск находок.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(([regex]::Matches($js,[regex]::Escape($mark))).Count -ne 1) {
    throw 'DOC4f: отсутствует уникальный маркер JavaScript'
}
if($js.Contains('function ruDOC4fObservedSuffixes')) {
    throw 'DOC4f: обработчик уже установлен'
}
$block=@'
        // DOC4f: original HTML evidence identifies exactly three field-scoped
        // phrases; keep AD names, DNs and security identifiers untouched.
        document.addEventListener('DOMContentLoaded', function ruDOC4fObservedSuffixes() {
            const eligible={ privilegedGroups:1, affectedOUs:1, tier0Groups:1 };
            const stats={ inspected:0, translated:0, byField:Object.create(null) };
            function translate(source,key) {
                const parts=source.match(/^(\s*)([\s\S]*?)(\s*)$/);
                if(!parts) return source;
                let value=parts[2], output=value;
                if(key==='privilegedGroups') {
                    if(value.endsWith(' (direct)')) {
                        output=value.slice(0,-' (direct)'.length)+' (прямое членство)';
                    }
                } else if(key==='affectedOUs') {
                    // Source: DN (domain root, inherited by N OU и M контейнеров).
                    // These are displayed counts, not permissions to re-compute.
                    const match=value.match(/^((?:DC|OU|CN)=[^\r\n]+?) \(domain root, inherited by (\d+) OU и (\d+) контейнеров\)$/);
                    if(match) {
                        output=match[1]+' (корень домена; наследование распространяется на '+
                            match[2]+' OU и '+match[3]+' контейнеров)';
                    }
                } else if(key==='tier0Groups') {
                    // Built-in Administrator is a descriptive label, not a
                    // stored account name; preserve its security RID 500.
                    output=value.replaceAll('Built-in Administrator (RID 500)',
                        'Встроенная учётная запись администратора (RID 500)');
                }
                return parts[1]+output+parts[3];
            }
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key=row.getAttribute('data-attr-name');
                if(!Object.prototype.hasOwnProperty.call(eligible,key)) return;
                const root=row.querySelector('.attr-value');
                if(!root) return;
                const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
                let node;
                while((node=walker.nextNode())) {
                    if(!node.parentElement ||
                        node.parentElement.closest('pre,code,textarea,script,style,a')) continue;
                    stats.inspected++;
                    const after=translate(node.nodeValue,key);
                    if(after!==node.nodeValue) {
                        node.nodeValue=after;
                        stats.translated++;
                        stats.byField[key]=(stats.byField[key]||0)+1;
                    }
                }
            });
            window.adPEASRUDOC4f=Object.freeze({
                inspected:stats.inspected,
                translated:stats.translated,
                byField:Object.freeze(stats.byField)
            });
        });

'@
$js=$js.Replace($mark,$block+$mark)
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC4f: 3 уточнения ACL/Tier 0; RID 500, DN, имена и права сохранены'
