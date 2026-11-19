#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6a: безопасный перевод подтверждённых значений двух HTML отчётов.
.DESCRIPTION
    Изменяет только текстовые узлы внутри attr-value для закрытого перечня
    data-attr-name и фраз. Не изменяет реальные значения AD, метаданные,
    risk score, коды прав, SID/DN/GPO, HTML-атрибуты или команды.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$anchor='        // Scoring context data for context-aware risk calculation'
$count=([regex]::Matches($js,[regex]::Escape($anchor))).Count
if($count -ne 1){throw "DOC6a: якорь найден $count раз(а), ожидалось 1"}
if($js.Contains('function ruDOC6aObservedReportValues')){throw 'DOC6a уже применён'}
$block=@'
        // DOC6a BEGIN: verified, field-scoped presentation translations only.
        document.addEventListener('DOMContentLoaded', function ruDOC6aObservedReportValues() {
            const exact=Object.freeze({
                'activityStatus':Object.freeze({
                    'INACTIVE (no login for >90 days)':'НЕАКТИВНА (нет входов более 90 дней)',
                    'INACTIVE (no logon recorded, password not changed for >90 days)':'НЕАКТИВНА (входы не зафиксированы, пароль не менялся более 90 дней)'
                }),
                'adSubnet':Object.freeze({
                    'Not in Sites and Services':'Отсутствует в «Сайты и службы Active Directory»'
                }),
                'EffectiveSetting':Object.freeze({
                    'Yes - in force on the domain controllers: LDAP signing':'Да — действует на контроллерах домена: подпись LDAP',
                    'Yes - in force on the domain controllers: anonymous SID/name translation':'Да — действует на контроллерах домена: анонимное преобразование SID/имени',
                    'Yes - in force on the domain controllers: server signing':'Да — действует на контроллерах домена: подпись SMB на сервере',
                    'Yes - wins precedence on the Domain Controllers OU':'Да — имеет приоритет в OU контроллеров домена'
                }),
                'ServerSigning':Object.freeze({
                    'Required':'Обязательна',
                    'Not configured':'Не настроена',
                    'Not configured (not required before Server 2025)':'Не настроена (не требовалась до Windows Server 2025)'
                }),
                'ClientSigning':Object.freeze({
                    'Required':'Обязательна',
                    'Not configured':'Не настроена'
                }),
                'decidedBy':Object.freeze({
                    'None (signing is set on the DC OU only)':'Нет (подпись настроена только в OU контроллеров домена)'
                }),
                'whoCanAddComputers':Object.freeze({
                    'Any authenticated user, up to the quota':'Любой аутентифицированный пользователь — в пределах квоты'
                }),
                'dangerousRights':Object.freeze({
                    'All Extended Rights (grants DS-Replication-Get-Changes and DS-Replication-Get-Changes-All)':'Все расширенные права (предоставляют DS-Replication-Get-Changes и DS-Replication-Get-Changes-All)',
                    'Owner of the domain object':'Владелец объекта домена',
                    'Owner of the OU':'Владелец OU',
                    'Owner of the group - may rewrite its DACL':'Владелец группы — может изменить её DACL',
                    'Owner of the account - may rewrite its DACL':'Владелец учётной записи — может изменить её DACL',
                    'WriteProperty on member - may add a member to the group':'WriteProperty для member — позволяет добавить участника в группу',
                    'WriteProperty on member - may add a member to every protected group':'WriteProperty для member — позволяет добавить участника в любую защищённую группу',
                    'Self on member - may add itself to the group':'Self для member — позволяет добавить себя в группу',
                    'Self on member - may add itself to every protected group':'Self для member — позволяет добавить себя в любую защищённую группу',
                    'All extended rights - may reset the password of every protected account':'Все расширенные права — позволяют сбросить пароль любой защищённой учётной записи',
                    'CreateChild (Computer) in the computer container':'CreateChild (Computer) в контейнере компьютеров',
                    'CreateChild (All Objects)':'CreateChild (все типы объектов)',
                    'WriteDacl (Modify Permissions)':'WriteDacl (изменение разрешений)',
                    'WriteOwner (Take Ownership)':'WriteOwner (смена владельца)',
                    'Reset Password (Extended Right)':'Сброс пароля (расширенное право)',
                    'GenericAll (Full Control)':'GenericAll (полный доступ)',
                    'DS-Replication-Get-Changes - replicates the directory except secrets but is one right short of DCSync':'DS-Replication-Get-Changes — репликация каталога без секретов; для DCSync не хватает ещё одного права',
                    'DS-Replication-Get-Changes-In-Filtered-Set - replicates the directory except secrets but is one right short of DCSync':'DS-Replication-Get-Changes-In-Filtered-Set — репликация каталога без секретов; для DCSync не хватает ещё одного права',
                    'DS-Replication-Get-Changes-All - inert without DS-Replication-Get-Changes and one ACE short of DCSync':'DS-Replication-Get-Changes-All — без DS-Replication-Get-Changes не действует для DCSync; не хватает одного ACE'
                })
            });
            const decidedSuffix=Object.freeze({
                ' (LDAP signing)':' (подпись LDAP)',
                ' (anonymous SID/name translation)':' (анонимное преобразование SID/имени)',
                ' (server signing)':' (подпись SMB на сервере)'
            });
            function localize(key,value) {
                if(Object.prototype.hasOwnProperty.call(exact,key) &&
                   Object.prototype.hasOwnProperty.call(exact[key],value))
                    return exact[key][value];
                if(key==='decidedBy') {
                    for(const suffix of Object.keys(decidedSuffix)) {
                        if(value.endsWith(suffix))
                            return value.slice(0,-suffix.length)+decidedSuffix[suffix];
                    }
                }
                if(key==='privilegeGrantedBy') {
                    const m=/^GPO '(.+)' grants SeMachineAccountPrivilege to (.+)$/.exec(value);
                    if(m) return "GPO '"+m[1]+"' предоставляет право SeMachineAccountPrivilege субъекту "+m[2];
                }
                if(key==='affectedOUs') {
                    if(value.endsWith(' (set here)'))
                        return value.slice(0,-' (set here)'.length)+' (назначено непосредственно)';
                    const m=/^(.*) \(domain root, inherited by (\d+) OU и (\d+) контейнеров\)$/.exec(value);
                    if(m) return m[1]+' (корень домена; наследуется '+m[2]+' OU и '+m[3]+' контейнерами)';
                }
                return value;
            }
            const counts=Object.create(null);
            let changed=0;
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key=row.getAttribute('data-attr-name');
                const field=row.querySelector('.attr-value');
                if(!key || !field) return;
                if(!Object.prototype.hasOwnProperty.call(exact,key) &&
                   key!=='decidedBy' && key!=='privilegeGrantedBy' && key!=='affectedOUs') return;
                function visit(node) {
                    if(node.nodeType===Node.TEXT_NODE) {
                        const raw=node.nodeValue;
                        if(!raw || !raw.trim()) return;
                        const prefix=(/^\s*/.exec(raw)||[''])[0];
                        const suffix=(/\s*$/.exec(raw)||[''])[0];
                        const core=raw.slice(prefix.length,raw.length-suffix.length);
                        const next=localize(key,core);
                        if(core!==next) {
                            node.nodeValue=prefix+next+suffix;
                            changed++;
                            counts[key]=(counts[key]||0)+1;
                        }
                        return;
                    }
                    if(node.nodeType!==Node.ELEMENT_NODE || /^(CODE|PRE|A|SCRIPT|STYLE)$/.test(node.tagName))return;
                    Array.from(node.childNodes).forEach(visit);
                }
                visit(field);
            });
            // DOC6a: correct only grammar in fixed object-count captions.
            // The number, severity/category, and all underlying data stay intact.
            let correctedCountLabels=0;
            document.querySelectorAll('.finding-count').forEach(function(label) {
                if(label.childNodes.length!==1 || !label.firstChild ||
                   label.firstChild.nodeType!==Node.TEXT_NODE) return;
                const raw=label.firstChild.nodeValue;
                const match=/^(\s*)(\d+) элементов(\s*)$/.exec(raw);
                if(!match) return;
                const n=Number(match[2]);
                if(!Number.isSafeInteger(n)) return;
                const lastTwo=n%100,last=n%10;
                const word=(lastTwo>=11 && lastTwo<=14) ? 'элементов' :
                    last===1 ? 'элемент' : (last>=2 && last<=4) ? 'элемента' : 'элементов';
                const revised=match[1]+match[2]+' '+word+match[3];
                if(revised!==raw) {
                    label.firstChild.nodeValue=revised;
                    correctedCountLabels++;
                }
            });
            window.adPEASRUDOC6a=Object.freeze({
                translatedTextNodes:changed,
                byAttribute:Object.freeze(counts),
                correctedCountLabels:correctedCountLabels
            });
        });
        // DOC6a END: verified report display translations.

'@
$js=$js.Replace($anchor,$anchor+[Environment]::NewLine+$block)
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC6a: field-scoped report values, AD identifiers and calculations unchanged'
