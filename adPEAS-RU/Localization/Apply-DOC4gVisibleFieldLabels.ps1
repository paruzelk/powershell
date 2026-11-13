#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4g: русские подписи синтетических полей HTML, а не имена атрибутов AD.
.DESCRIPTION
    Переименовывает только отображаемый текст .attr-name для точно
    известных ключей из двух реальных HTML DOC4f; исходные data-attr-name,
    LDAP/MAPI/GPO имена, ссылки, команды и обнаруженные данные неизменны.
    Словарь не затрагивает реальные имена AD-схемы, GUID, SID и DN.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$path = Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
$mark = '        // Scoring context data for context-aware risk calculation'
if(([regex]::Matches($js,[regex]::Escape($mark))).Count -ne 1) {
    throw 'DOC4g: уникальная точка вставки не найдена'
}
if($js.Contains('function ruDOC4gVisibleFieldLabels')) {
    throw 'DOC4g: повторное добавление обработчика'
}
$block=@'
        // DOC4g: display labels for synthetic report fields only.
        // Field identities and AD/LDAP values are intentionally unchanged.
        document.addEventListener('DOMContentLoaded', function ruDOC4gVisibleFieldLabels() {
            const labels=Object.freeze({
                PrivilegeCategory: 'Категория учётной записи',
                privilegedGroups: 'Привилегированные группы',
                tier0Groups: 'Группы с привилегиями Tier 0',
                UserRight: 'Право пользователя',
                AppliesTo: 'Область применения',
                SourceFile: 'Исходный файл',
                IsDomainWide: 'Действует на весь домен',
                UserVersion: 'Версия настроек пользователей',
                ComputerVersion: 'Версия настроек компьютеров',
                affectedComputerCount: 'Количество затронутых компьютеров',
                PrivilegedGroup: 'Привилегированная группа',
                EffectiveSetting: 'Итоговое применённое значение',
                ServerSigning: 'Требование подписи SMB на сервере',
                ClientSigning: 'Требование подписи SMB на клиенте',
                decidedBy: 'Определяющая групповая политика',
                LDAPSigning: 'Требование подписи LDAP',
                ChannelBinding: 'Привязка канала LDAP',
                anonymousLDAPAccess: 'Анонимный доступ LDAP',
                anonymousSamEnumeration: 'Анонимное перечисление учётных записей SAM',
                anonymousSidNameTranslation: 'Анонимное преобразование SID в имя',
                Accounts: 'Учётные записи',
                targetContainer: 'Целевой контейнер',
                whoCanAddComputers: 'Кто может добавлять компьютеры в домен',
                privilegeGrantedBy: 'Назначение права через групповую политику',
                CoversDCs: 'Охватывает контроллеры домена',
                _PrecedenceRank: 'Ранг приоритета политики',
                _PrecedenceScope: 'Область приоритета политики',
                _PrecedenceOrder: 'Порядок применения политики',
                _HasAuthenticatedUsers: 'Включены Authenticated Users',
                _HasEveryone: 'Включена группа Everyone',
                accountsRead: 'Проверено учётных записей',
                protectedByAdminSDHolder: 'Записи под защитой AdminSDHolder',
                affectedAccounts: 'Затронутые учётные записи',
                prewin2000DefaultMember: 'Участник группы совместимости с Windows 2000 по умолчанию',
                MemberName: 'Имя участника',
                MemberSID: 'SID участника',
                siteName: 'Имя сайта AD',
                siteSubnets: 'Подсети сайта AD',
                siteDomainControllers: 'Контроллеры домена сайта',
                domainControllers: 'Контроллеры домена',
                domainNameDNS: 'DNS-имя домена',
                domainNameNetBIOS: 'NetBIOS-имя домена',
                domainSID: 'SID домена',
                domainFunctionalLevel: 'Функциональный уровень домена',
                forestFunctionalLevel: 'Функциональный уровень леса',
                forestName: 'Имя леса',
                tombstoneLifetime: 'Срок хранения удалённых объектов',
                recycleBin: 'Корзина Active Directory',
                sysvolReplication: 'Механизм репликации SYSVOL',
                accountStatus: 'Состояние учётной записи',
                adminSDHolderExclusion: 'Исключение из защиты AdminSDHolder',
                principalNameUniqueness: 'Проверка уникальности имени субъекта',
                anonymousNSPIAccess: 'Анонимный доступ NSPI',
                Policies: 'Связанные групповые политики'
            });
            let inspected=0, translatedLabels=0, translatedValues=0;
            const byField=Object.create(null);
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key=row.getAttribute('data-attr-name');
                if(!Object.prototype.hasOwnProperty.call(labels,key)) return;
                inspected++;
                const label=row.querySelector('.attr-name');
                // Never replace a DOM subtree: keep help icons and interactions.
                // Already-localized labels from earlier stages take precedence.
                if(label && label.textContent.trim()===key &&
                   label.childNodes.length===1 &&
                   label.firstChild && label.firstChild.nodeType===Node.TEXT_NODE) {
                    label.firstChild.nodeValue=labels[key];
                    translatedLabels++;
                    byField[key]=(byField[key]||0)+1;
                }
                // Only confirmed exact text value, never an AD object value.
                if(key==='PrivilegeCategory') {
                    const display=row.querySelector('.attr-value');
                    if(display && display.childNodes.length===1 &&
                       display.firstChild && display.firstChild.nodeType===Node.TEXT_NODE &&
                       display.textContent.trim()==='Privileged') {
                        display.firstChild.nodeValue='Привилегированная';
                        translatedValues++;
                    }
                }
            });
            window.adPEASRUDOC4g=Object.freeze({
                inspected:inspected,
                translatedLabels:translatedLabels,
                translatedValues:translatedValues,
                dictionaryEntries:Object.keys(labels).length,
                byField:Object.freeze(byField)
            });
        });

'@
$js=$js.Replace($mark,$block+$mark)
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC4g: метки синтетических полей без изменения AD, SID, GPO и data-attr-name'
