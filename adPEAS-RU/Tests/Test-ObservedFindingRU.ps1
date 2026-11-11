#Requires -Version 5.1
<#
.SYNOPSIS
    Проверка технической русификации находок на обезличенном наборе ID.
.DESCRIPTION
    Отчёт с данными домена не включается в репозиторий. Нет подключений к AD.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$full=@{}
foreach($name in @('FullTechnical-01.ru-RU.json','FullTechnical-02.ru-RU.json','FullTechnical-Report-03.ru-RU.json')){
 $obj=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $obj.translations.PSObject.Properties){
  if($full.ContainsKey($p.Name)){throw "Повторная запись $($p.Name)"}
  $full[$p.Name]=$p.Value
 }
}
$brief=(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/FindingExplanations.ru-RU.json'),[Text.Encoding]::UTF8))).translations
$ids=@('ACCOUNT_DISABLED','ADMINSDHOLDER_PROPAGATED_RIGHT','AD_RECYCLE_BIN_DISABLED','AGING_OS','ANONYMOUS_SID_NAME_TRANSLATION_ALLOWED','COMPUTER_CONTAINER_CREATE_PERMISSIONS','DANGEROUS_ACL_DCSYNC','DANGEROUS_ACL_GENERICALL','DANGEROUS_ACL_GENERICWRITE','DANGEROUS_ACL_GPO_DELETE','DANGEROUS_ACL_GPO_WRITEPROPERTY','DANGEROUS_ACL_REPLICATION_INERT_HALF','DANGEROUS_ACL_REPLICATION_NO_SECRETS','DANGEROUS_ACL_WRITEDACL','DANGEROUS_ACL_WRITEOWNER','DOMAIN_ROOT_GPLINK_WRITE','DOMAIN_ROOT_NON_DEFAULT_OWNER','GPO_LINK_REACHES_DC','GPO_SCOPE_DOMAIN_WIDE','GPO_SEMACHINEACCOUNTPRIVILEGE_BROAD','GPO_SYSVOL_WRITABLE','GPO_UNLINKED_BROAD_WRITE','GPO_USERRIGHT_SEASSIGNPRIMARYTOKEN','GPO_USERRIGHT_SEAUDIT','GPO_USERRIGHT_SEBACKUP','GPO_USERRIGHT_SEBATCHLOGON','GPO_USERRIGHT_SEDEBUG','GPO_USERRIGHT_SEENABLEDELEGATION','GPO_USERRIGHT_SEINTERACTIVELOGON','GPO_USERRIGHT_SELOADDRIVER','GPO_USERRIGHT_SEPROFILESINGLEPROCESS','GPO_USERRIGHT_SEREMOTESHUTDOWN','GPO_USERRIGHT_SERESTORE','GPO_USERRIGHT_SESECURITY','GPO_USERRIGHT_SESHUTDOWN','GPO_USERRIGHT_SESYSTEMENVIRONMENT','GPO_USERRIGHT_SESYSTEMPROFILE','GPO_USERRIGHT_SESYSTEMTIME','GPO_USERRIGHT_SETAKEOWNERSHIP','GPO_WIDE_IMPACT','INACTIVE_ACCOUNT','INACTIVE_PRIVILEGED_ACCOUNT','KRBTGT_PASSWORD_OLD','LDAP_ANONYMOUS_BINDING_RESTRICTED','LDAP_CHANNEL_BINDING_NOT_REQUIRED','LDAP_SIGNING_NOT_REQUIRED','MACHINE_QUOTA_UNRESTRICTED','NO_ACCOUNT_LOCKOUT','OPERATOR_GROUP_MEMBERS','OPERATOR_GROUP_MEMBERSHIP','OU_PERM_CREATE_CHILD','OU_PERM_GPLINK','OU_PERM_GPOPTIONS','OU_PERM_GROUP_MEMBERSHIP','OU_PERM_KEYCREDENTIALLINK_WRITE','OU_PERM_PASSWORD_RESET','PASSWORD_COMPLEXITY_ENABLED','PASSWORD_NEVER_EXPIRES','PASSWORD_NOT_REQUIRED','PREWIN2000_DEFAULT_MEMBER','PRIVILEGED_GROUP_ACL','PRIVILEGED_GROUP_MEMBERSHIP','SMB_SIGNING_DISABLED','SMB_SIGNING_REQUIRED','STALE_PASSWORD','STALE_PASSWORD_MEDIUM','TIER0_NOT_IN_PROTECTED_USERS','WEAK_PASSWORD_POLICY')
if($ids.Count -ne 68){throw "Ожидалось 68 контрольных FindingId, найдено $($ids.Count)"}
foreach($id in $ids){
 if(-not $full.ContainsKey($id) -and -not $brief.PSObject.Properties[$id]) { throw "Нет русского текста для $id" }
}
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
if($js.Contains('Исходное подробное описание EN (перевод пока не завершён)')){throw 'Осталась устаревшая пометка EN'}
if(-not $js.Contains('Сверить с исходным текстом на английском (EN)')){throw 'Недоступен оригинал для сверки'}
if(-not $js.Contains('ruPolishReportPresentation')){throw 'Нет русификации HTML-значений'}
Write-Host "PASS: $($ids.Count) типов находок имеют русский текст; расширенные переводы: $($full.Count)"
