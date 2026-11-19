# DOC6c — статический аудит языка исходников

Документ автоматически формируется в GitHub Actions после локализации закреплённых исходников adPEAS. Приватные доменные HTML-отчёты не используются.

## Охват

- Всего файлов исходников: **203** (PowerShell 200, JavaScript 1, HTML 2).
- Строк исходников: **156557**.
- Подтверждённые переводы DOC6c: **54** в 4 файлах подсистемы отчётов.
- Эвристические кандидаты на проверку: **3657** (вызовы PowerShell/HTML: 3497; JS-контексты: 160).

**Внимание:** это не число фактически непереведённых пользовательских строк. Среди кандидатов могут быть английские названия продуктов, технические идентификаторы, программные сообщения, значения протоколов, составные строки. Требуется ручная проверка контекста.

## Предварительная выборка для следующего этапа

| Файл | Строка | Контекст | Выдержка |
|---|---:|---|---|
| `src/adPEAS.ps1` | 147 | ps-diagnostic | $Script:ScriptPath\modules\Helpers\Write-Log.ps1 |
| `src/adPEAS.ps1` | 1067 | ps-diagnostic | LDAP Statistics for $displayName |
| `src/adPEAS.ps1` | 1070 | ps-diagnostic | Estimated Traffic |
| `src/adPEAS.ps1` | 1092 | ps-diagnostic | [adPEAS] Error executing Domain Module: $_ |
| `src/adPEAS.ps1` | 1114 | ps-diagnostic | [adPEAS] Error executing Creds Module: $_ |
| `src/adPEAS.ps1` | 1134 | ps-diagnostic | [adPEAS] Error executing Rights Module: $_ |
| `src/adPEAS.ps1` | 1150 | ps-diagnostic | [adPEAS] Error executing Delegation Module: $_ |
| `src/adPEAS.ps1` | 1165 | ps-diagnostic | [adPEAS] Error executing ADCS Module: $_ |
| `src/adPEAS.ps1` | 1190 | ps-diagnostic | [adPEAS] Error executing Accounts Module: $_ |
| `src/adPEAS.ps1` | 1209 | ps-diagnostic | [adPEAS] Error executing GPO Module: $_ |
| `src/adPEAS.ps1` | 1228 | ps-diagnostic | [adPEAS] Error executing Computer Module: $_ |
| `src/adPEAS.ps1` | 1245 | ps-diagnostic | [adPEAS] Error executing Application Module: $_ |
| `src/adPEAS.ps1` | 1259 | ps-diagnostic | [adPEAS] Error executing Shares Module: $_ |
| `src/adPEAS.ps1` | 1285 | ps-diagnostic | [adPEAS] Error executing Bloodhound Module: $_ |
| `src/modules/Checks/Accounts/Get-AdminPasswordNeverExpires.ps1` | 57 | ps-diagnostic | [Get-AdminPasswordNeverExpires] Starting check |
| `src/modules/Checks/Accounts/Get-AdminPasswordNeverExpires.ps1` | 92 | ps-diagnostic | [Get-AdminPasswordNeverExpires] Password age threshold: $PasswordAgeDays days (before $(Format-adPEASDate $thresholdDate 'yyyy-MM-dd')) |
| `src/modules/Checks/Accounts/Get-AdminPasswordNeverExpires.ps1` | 112 | ps-diagnostic | [Get-AdminPasswordNeverExpires] Found $(@($candidates).Count) candidate(s) with adminCount=1, verifying actual privilege status... |
| `src/modules/Checks/Accounts/Get-AdminPasswordNeverExpires.ps1` | 166 | ps-diagnostic | [Get-AdminPasswordNeverExpires] Verified: $($user.sAMAccountName) is $($privCheck.Category) via $($privCheck.MatchedGroup) |
| `src/modules/Checks/Accounts/Get-AdminPasswordNeverExpires.ps1` | 168 | ps-diagnostic | [Get-AdminPasswordNeverExpires] Filtered out: $($user.sAMAccountName) has orphaned adminCount (Category: $($privCheck.Category)) |
| `src/modules/Checks/Accounts/Get-AdminPasswordNeverExpires.ps1` | 209 | ps-diagnostic | [Get-AdminPasswordNeverExpires] Error: $_ |
| `src/modules/Checks/Accounts/Get-AdminPasswordNeverExpires.ps1` | 215 | ps-diagnostic | [Get-AdminPasswordNeverExpires] Check completed |
| `src/modules/Checks/Accounts/Get-AdminReversibleEncryption.ps1` | 42 | ps-diagnostic | [Get-AdminReversibleEncryption] Starting check |
| `src/modules/Checks/Accounts/Get-AdminReversibleEncryption.ps1` | 107 | ps-diagnostic | [Get-AdminReversibleEncryption] Error: $_ |
| `src/modules/Checks/Accounts/Get-AdminReversibleEncryption.ps1` | 115 | ps-diagnostic | [Get-AdminReversibleEncryption] Check completed |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 64 | ps-diagnostic | [Get-AuthenticationPolicySilos] Starting check |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 94 | ps-diagnostic | [Get-AuthenticationPolicySilos] The authentication policy configuration could not be read: $_ |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 114 | ps-diagnostic | [Get-AuthenticationPolicySilos] The built-in Administrator could not be looked up: $_ |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 284 | ps-diagnostic | [Get-AuthenticationPolicySilos] Error: $_ |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 290 | ps-diagnostic | [Get-AuthenticationPolicySilos] Check completed |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 401 | ps-diagnostic | [Get-AuthenticationPolicySilos] A condition could not be read: $_ |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 520 | ps-diagnostic | [Get-AuthenticationPolicySilos] The ACL of $DistinguishedName could not be read: $_ |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 601 | ps-diagnostic | [Get-AuthenticationPolicySilos] The GPOs could not be read: $_ |
| `src/modules/Checks/Accounts/Get-AuthenticationPolicySilos.ps1` | 633 | ps-diagnostic | [Get-AuthenticationPolicySilos] Could not read $($polFile.FullName): $($_.Exception.Message) |
| `src/modules/Checks/Accounts/Get-InactiveAdminAccounts.ps1` | 50 | ps-diagnostic | [Get-InactiveAdminAccounts] Starting check |
| `src/modules/Checks/Accounts/Get-InactiveAdminAccounts.ps1` | 210 | ps-diagnostic | [Get-InactiveAdminAccounts] Error: $_ |
| `src/modules/Checks/Accounts/Get-InactiveAdminAccounts.ps1` | 216 | ps-diagnostic | [Get-InactiveAdminAccounts] Check completed |
| `src/modules/Checks/Accounts/Get-LogonScriptPermissions.ps1` | 65 | ps-diagnostic | [Get-LogonScriptPermissions] Starting check |
| `src/modules/Checks/Accounts/Get-LogonScriptPermissions.ps1` | 153 | ps-diagnostic | [Get-LogonScriptPermissions] Could not tell the privileged accounts apart: $_ |
| `src/modules/Checks/Accounts/Get-LogonScriptPermissions.ps1` | 200 | ps-diagnostic | [Get-LogonScriptPermissions] Error: $_ |
| `src/modules/Checks/Accounts/Get-LogonScriptPermissions.ps1` | 208 | ps-diagnostic | [Get-LogonScriptPermissions] Check completed |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 81 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Starting check |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 100 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Checking gMSA password access permissions |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 107 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Found $($gmsaAccounts.Count) gMSA account(s) |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 159 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Failed to parse msDS-GroupMSAMembership for $gmsaName : $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 331 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Could not read accountExpires of $($gmsa.sAMAccountName): $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 348 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Attempting to read gMSA passwords |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 367 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Attempting to read password for $gmsaName |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 428 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Failed to parse password blob for $gmsaName |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 431 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Password blob is empty or invalid type for $gmsaName |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 434 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] No msDS-ManagedPassword returned for $gmsaName (access denied or not available) |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 438 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Error reading password for $gmsaName : $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 457 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Could not read the session's encryption state: $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 512 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Checking for standalone MSAs |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 557 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Checking delegated Managed Service Account links |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 574 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] No schema naming context - dMSA links not checked |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 684 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Could not read the dMSA $(@($linkedDMSAs)[0]): $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 733 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Failed to parse msDS-GroupMSAMembership for $dmsaName : $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 814 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Error: $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 820 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Check completed |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 953 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Could not read the managed service account membership descriptors: $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 1014 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Could not read the descriptor owner of $Name : $_ |
| `src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1` | 1093 | ps-diagnostic | [Get-ManagedServiceAccountSecurity] Could not classify password reader $readerSID : $_ |
| `src/modules/Checks/Accounts/Get-NonDefaultUserOwners.ps1` | 60 | ps-diagnostic | [Get-NonDefaultUserOwners] Starting check |
| `src/modules/Checks/Accounts/Get-NonDefaultUserOwners.ps1` | 94 | ps-diagnostic | [Get-NonDefaultUserOwners] Found $($usersWithOwner.Count) users, filtering non-default owners clientside... |
| `src/modules/Checks/Accounts/Get-NonDefaultUserOwners.ps1` | 118 | ps-diagnostic | [Get-NonDefaultUserOwners] Filtered Exchange Health Mailbox: $dn |
| `src/modules/Reporting/templates/report-scripts.js` | 36 | js-ui-candidate | aria-pressed |
| `src/modules/Reporting/templates/report-scripts.js` | 43 | js-ui-candidate | aria-expanded |
| `src/modules/Reporting/templates/report-scripts.js` | 85 | js-ui-candidate | data-theme |
| `src/modules/Reporting/templates/report-scripts.js` | 92 | js-ui-candidate | ).innerHTML = theme === |
| `src/modules/Reporting/templates/report-scripts.js` | 133 | js-ui-candidate | span:last-child |
| `src/modules/Reporting/templates/report-scripts.js` | 134 | js-ui-candidate | span:last-child |
| `src/modules/Reporting/templates/report-scripts.js` | 138 | js-ui-candidate | span:last-child |
| `src/modules/Reporting/templates/report-scripts.js` | 139 | js-ui-candidate | span:last-child |
| `src/modules/Reporting/templates/report-scripts.js` | 445 | js-ui-candidate | pre,code,textarea,script,style,.tooltip-section,.tooltip-content |
| `src/modules/Reporting/templates/report-scripts.js` | 452 | js-ui-candidate | pre,code,textarea,script,style,.tooltip-section,.tooltip-content |
| `src/modules/Reporting/templates/report-scripts.js` | 543 | js-ui-candidate | )===0)node.textContent= |
| `src/modules/Reporting/templates/report-scripts.js` | 544 | js-ui-candidate | Domain Controllers |
| `src/modules/Reporting/templates/report-scripts.js` | 546 | js-ui-candidate | [aria-label] |
| `src/modules/Reporting/templates/report-scripts.js` | 547 | js-ui-candidate | aria-label |
| `src/modules/Reporting/templates/report-scripts.js` | 548 | js-ui-candidate | aria-label |
| `src/modules/Reporting/templates/report-scripts.js` | 548 | js-ui-candidate | critical issues |
| `src/modules/Reporting/templates/report-scripts.js` | 549 | js-ui-candidate | aria-label |
| `src/modules/Reporting/templates/report-scripts.js` | 550 | js-ui-candidate | aria-label |
| `src/modules/Reporting/templates/report-scripts.js` | 551 | js-ui-candidate | aria-label |
| `src/modules/Reporting/templates/report-scripts.js` | 1108 | js-ui-candidate | .score-tooltip-label |
| `src/modules/Reporting/templates/report-scripts.js` | 1116 | js-ui-candidate | .score-tooltip-label .reason |
| `src/modules/Reporting/templates/report-scripts.js` | 1347 | js-ui-candidate | data-theme |
| `src/modules/Reporting/templates/report-scripts.js` | 1356 | js-ui-candidate | data-theme |
| `src/modules/Reporting/templates/report-scripts.js` | 1413 | js-ui-candidate | finding-tooltip |
| `src/modules/Reporting/templates/report-scripts.js` | 1415 | js-ui-candidate | aria-modal |
| `src/modules/Reporting/templates/report-scripts.js` | 1416 | js-ui-candidate | aria-label |
| `src/modules/Reporting/templates/report-scripts.js` | 1421 | js-ui-candidate | finding-tooltip-trigger |
| `src/modules/Reporting/templates/report-scripts.js` | 1424 | js-ui-candidate | aria-haspopup |
| `src/modules/Reporting/templates/report-scripts.js` | 1425 | js-ui-candidate | aria-expanded |
| `src/modules/Reporting/templates/report-scripts.js` | 1445 | js-ui-candidate | .finding-tooltip |

## Границы проверки

Сканируются только исходные файлы каталога `src/`: явные PowerShell-операции вывода, текстовые HTML-узлы и доступные подписи, литералы JS около UI-API. Скрытые динамически собранные строки, многорядные строковые выражения и косвенные ссылки могут остаться незамеченными. Каталоги документации, локализации и тестов не рассматриваются как исходный интерфейс.

Технические идентификаторы LDAP/AD, SID, GUID, DNS/DN, имена GPO, команды PowerShell и ключи JSON не переводить. Полный машинный реестр всех обнаруженных кандидатов: `Localization/DOC6c-StaticSourceAudit.json`.
