#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4b: безопасный перевод отображаемых значений отчёта из HTML-примера.
.DESCRIPTION
    Меняет только текстовые узлы .attr-value (набор выбран по
    data-attr-name). Никаких изменений LDAP, SID, JSON, risk scoring,
    классов, атрибутов и команд. Технические имена прав AD сохраняются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(([regex]::Matches($js,[regex]::Escape($mark))).Count -ne 1){
 throw 'DOC4b: точка безопасной вставки JS отсутствует или неоднозначна'
}
if($js.Contains('ruDOC4bVisibleValue')){throw 'DOC4b: повторное добавление обработчика'}
$block=@'
        // DOC4b: translate rendered attribute values only. No data-* or finding metadata.
        document.addEventListener('DOMContentLoaded', function ruDOC4bVisibleValue() {
            const exact = {
                'Not locked out':'Не заблокирована',
                'Never':'Никогда',
                'All settings disabled':'Все настройки отключены',
                'Not configured (not required before Server 2025)':
                    'Не настроено (до Windows Server 2025 по умолчанию не требуется)',
                'Global Security Group':'Глобальная группа безопасности',
                'Universal Security Group':'Универсальная группа безопасности',
                'Domain Local Security Group':'Локальная группа безопасности домена',
                'Yes - wins precedence on the Domain Controllers OU':
                    'Да — имеет приоритет для OU контроллеров домена'
            };
            const gpoEffective = {
                'LDAP signing':'подпись LDAP',
                'anonymous SID/name translation':'анонимное сопоставление SID и имени',
                'server signing':'подпись SMB на сервере'
            };
            // Descriptions of effective ACL rights, NOT the permission names themselves.
            const aclPhrases = [
                ['WriteProperty on member - may add a member to every protected group',
                 'WriteProperty для member — позволяет менять состав всех защищённых групп'],
                ['Self on member - may add itself to every protected group',
                 'Self для member — позволяет добавлять себя в любую защищённую группу'],
                ['All extended rights - may reset the password of every protected account',
                 'Все расширенные права — позволяют сбрасывать пароли защищённых учётных записей'],
                ['Owner of the group - may rewrite its DACL',
                 'Владелец группы — может изменять её DACL'],
                ['Owner of the domain object',
                 'Владелец объекта домена'],
                ['DS-Replication-Get-Changes - replicates the directory except secrets but is one right short of DCSync',
                 'DS-Replication-Get-Changes — репликация каталога без секретов, для DCSync не хватает одного права'],
                ['DS-Replication-Get-Changes-All - inert without DS-Replication-Get-Changes and one ACE short of DCSync',
                 'DS-Replication-Get-Changes-All — без DS-Replication-Get-Changes не действует, для DCSync требуется ещё одна ACE'],
                ['CreateChild (Computer) in the computer container',
                 'CreateChild (Computer) — создание объектов в контейнере компьютеров'],
                ['GenericAll (Full Control)', 'GenericAll (полный контроль)'],
                ['WriteDacl (Modify Permissions)', 'WriteDacl (изменение разрешений)'],
                ['WriteOwner (Take Ownership)', 'WriteOwner (смена владельца)']
            ];
            const roles = {
                'PDC Emulator':'эмулятор PDC',
                'Schema Master':'мастер схемы',
                'Infrastructure Master':'мастер инфраструктуры',
                'Domain Naming Master':'мастер именования доменов',
                'RID Master':'мастер RID'
            };
            const groups = new Set(['grouptype']);
            let changed = 0, evaluated = 0;
            function translateValue(source, key) {
                const lead=(source.match(/^\s*/) || [''])[0];
                const tail=(source.match(/\s*$/) || [''])[0];
                let t=source.slice(lead.length,source.length-tail.length);
                if(!t) return source;
                if(key==='grouptype' && Object.prototype.hasOwnProperty.call(exact,t)) {
                    t=exact[t];
                } else if(key==='activityStatus') {
                    const m=t.match(/^INACTIVE \(no login for >(\d+) days\)$/);
                    if(m) t='НЕАКТИВНА (нет входа более '+m[1]+' дней)';
                } else if(key==='EffectiveSetting') {
                    if(t==='Yes - wins precedence on the Domain Controllers OU') t=exact[t];
                    else {
                        const m=t.match(/^Yes - in force on the domain controllers: (.+)$/);
                        if(m && Object.prototype.hasOwnProperty.call(gpoEffective,m[1])) {
                            t='Да — действует на контроллерах домена: '+gpoEffective[m[1]];
                        }
                    }
                } else if(key==='domainControllers') {
                    for(const [english,russian] of Object.entries(roles)){
                        t=t.split(english).join(russian);
                    }
                } else if(key==='dangerousRights') {
                    for(const [english,russian] of aclPhrases){
                        t=t.split(english).join(russian);
                    }
                } else if(t==='Not locked out'||t==='Never'||t==='All settings disabled' ||
                          t==='Not configured (not required before Server 2025)') {
                    t=exact[t];
                }
                if(key==='userparameters') {
                    const m=t.match(/^\[userParameters blob: (\d+) bytes, no recognised TSPropertyArray signature\]$/);
                    if(m) t='[данные userParameters: '+m[1]+' байт; сигнатура TSPropertyArray не распознана]';
                }
                return lead+t+tail;
            }
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key=row.getAttribute('data-attr-name');
                const value=row.querySelector('.attr-value');
                if(!value) return;
                const walker=document.createTreeWalker(value,NodeFilter.SHOW_TEXT);
                let node;
                while((node=walker.nextNode())){
                    if(!node.parentElement || node.parentElement.closest('code,pre,a,script,style')) continue;
                    evaluated++;
                    const translated=translateValue(node.nodeValue,key);
                    if(translated!==node.nodeValue){
                        node.nodeValue=translated;
                        changed++;
                    }
                }
            });
            // Local-only diagnostic; no telemetry or network access.
            window.adPEASRUDOC4b = Object.freeze({ evaluated:evaluated, translated:changed });
        });

'@
$js=$js.Replace($mark,$block+$mark)
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC4b: защищённый обработчик значений атрибутов, прав и GPO добавлен'
