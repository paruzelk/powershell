#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4d: исправление проверенных по двум реальным HTML видимых значений.
.DESCRIPTION
    Только презентационный слой DOM: не изменяет LDAP-атрибуты, Findings,
    риск, команды, первичные значения, SID или данные отчёта. Преобразуются
    строго определённые сочетания имени поля и английской строки.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(([regex]::Matches($js,[regex]::Escape($mark))).Count -ne 1){
 throw 'DOC4d: маркер вставки JS отсутствует или неоднозначен'
}
if($js.Contains('function ruDOC4dObservedValues')){
 throw 'DOC4d: обработчик отображаемых значений уже вставлен'
}
$block=@'
        // DOC4d: verified field-scoped display translations from two real
        // reports; never modify source attributes, risk or internal values.
        document.addEventListener('DOMContentLoaded', function ruDOC4dObservedValues() {
            const exact = {
                'logonhours': {
                    'All hours (no restriction)': 'Любое время (ограничений нет)'
                },
                'adSubnet': {
                    'Not in Sites and Services': 'Не задана в «Сайты и службы Active Directory»'
                },
                'whoCanAddComputers': {
                    'Any authenticated user, up to the quota':
                        'Любой прошедший проверку подлинности пользователь (в пределах квоты)'
                },
                'decidedBy': {
                    'None (signing is set on the DC OU only)':
                        'Нет (подпись задана только в OU контроллеров домена)'
                },
                'LinkedOUs': {
                    'Not linked': 'Не привязана'
                }
            };
            const gpoSuffix = {
                '(LDAP signing)': '(подпись LDAP)',
                '(anonymous SID/name translation)': '(анонимное сопоставление SID и имени)',
                '(server signing)': '(подпись SMB на сервере)'
            };
            function translate(source, key) {
                const m = source.match(/^(\s*)([\s\S]*?)(\s*)$/);
                if (!m) return source;
                const original = m[2];
                let replacement = original;
                if (Object.prototype.hasOwnProperty.call(exact,key) &&
                    Object.prototype.hasOwnProperty.call(exact[key],original)) {
                    replacement = exact[key][original];
                } else if(key==='activityStatus') {
                    const x=original.match(/^INACTIVE \(no logon recorded, password not changed for >(\d+) days\)$/);
                    if(x) replacement='НЕАКТИВНА (входы не зарегистрированы, пароль не менялся более '+x[1]+' дней)';
                } else if(key==='decidedBy') {
                    // Preserve the actual name of a GPO; translate its explanatory suffix.
                    for (const [english,russian] of Object.entries(gpoSuffix)) {
                        if(original.endsWith(' '+english)) {
                            replacement=original.slice(0,original.length-english.length)+russian;
                            break;
                        }
                    }
                } else if(key==='dangerousRights') {
                    const phrases={
                        'All Extended Rights (grants DS-Replication-Get-Changes and DS-Replication-Get-Changes-All)':
                            'Все расширенные права (включая DS-Replication-Get-Changes и DS-Replication-Get-Changes-All)',
                        'DS-Replication-Get-Changes-In-Filtered-Set - replicates the directory except secrets but is one right short of DCSync':
                            'DS-Replication-Get-Changes-In-Filtered-Set — репликация каталога без секретов; самого этого права для DCSync недостаточно',
                        'Owner of the account - may rewrite its DACL':
                            'Владелец учётной записи — может изменять её DACL'
                    };
                    if(Object.prototype.hasOwnProperty.call(phrases,original)) {
                        replacement=phrases[original];
                    }
                }
                return m[1]+replacement+m[3];
            }
            let inspected=0, translated=0;
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key=row.getAttribute('data-attr-name');
                const root=row.querySelector('.attr-value');
                if(!root) return;
                const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
                let node;
                while((node=walker.nextNode())){
                    if(!node.parentElement ||
                       node.parentElement.closest('pre,code,textarea,script,style,a')) continue;
                    inspected++;
                    const after=translate(node.nodeValue,key);
                    if(after!==node.nodeValue) {
                        node.nodeValue=after;
                        translated++;
                    }
                }
            });
            window.adPEASRUDOC4d=Object.freeze({ inspected:inspected, translated:translated });
        });

'@
$js=$js.Replace($mark,$block+$mark)
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC4d: 3 новых заголовка и точечный DOM-перевод проверенных LDAP/GPO/ACL значений'
