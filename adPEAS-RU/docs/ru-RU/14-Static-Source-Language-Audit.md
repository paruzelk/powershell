# DOC6c — статический аудит языка исходников

Документ автоматически формируется в GitHub Actions после локализации закреплённых исходников adPEAS. Приватные доменные HTML-отчёты не используются.

## Охват

- Всего файлов исходников: **203** (PowerShell 200, JavaScript 1, HTML 2).
- Строк исходников: **156557**.
- Подтверждённые переводы DOC6c: **54** в 4 файлах подсистемы отчётов.
- Эвристические кандидаты на проверку: **3969** (вызовы PowerShell/HTML: 3809; JS-контексты: 160).

**Внимание:** это не число фактически непереведённых пользовательских строк. Среди кандидатов могут быть английские названия продуктов, технические идентификаторы, программные сообщения, значения протоколов, составные строки. Требуется ручная проверка контекста.

## Предварительная выборка для следующего этапа

| Файл | Строка | Контекст | Выдержка |
|---|---:|---|---|
| `src/adPEAS.ps1` | 147 | ps-diagnostic | $Script:ScriptPath\modules\Helpers\Write-Log.ps1 |
| `src/adPEAS.ps1` | 585 | ps-diagnostic | [adPEAS] -OutputAppend requires -Outputfile. Ignoring -OutputAppend. |
| `src/adPEAS.ps1` | 591 | ps-diagnostic | [adPEAS] -OutputAppend requires JSON findings cache. Use -Format All or -Format JSON. Ignoring -OutputAppend. |
| `src/adPEAS.ps1` | 610 | ps-diagnostic | [adPEAS] -ExcludeModule leaves no module to run. Nothing to do. |
| `src/adPEAS.ps1` | 617 | ps-diagnostic | [adPEAS] Findings collection enabled (Format: $Format) |
| `src/adPEAS.ps1` | 641 | ps-diagnostic | [adPEAS] Directory '$OutputDir' did not exist and was created |
| `src/adPEAS.ps1` | 643 | ps-diagnostic | [adPEAS] Could not create directory '$OutputDir': $_ |
| `src/adPEAS.ps1` | 659 | ps-diagnostic | [adPEAS] Unable to write text output to '$textPath', please check path and permissions! |
| `src/adPEAS.ps1` | 675 | ps-diagnostic | [adPEAS] -VerboseLogging: File logging requires -Outputfile with Text format. Verbose messages will be shown in console only. |
| `src/adPEAS.ps1` | 695 | ps-diagnostic | [adPEAS] Script started: $StartTime |
| `src/adPEAS.ps1` | 696 | ps-diagnostic | [adPEAS] Version: $Script:adPEASVersion |
| `src/adPEAS.ps1` | 699 | ps-diagnostic | [adPEAS] OPSEC mode enabled: No ASREPRoast/Kerberoast/BloodHound |
| `src/adPEAS.ps1` | 726 | ps-diagnostic | [adPEAS] Reusing existing LDAP session |
| `src/adPEAS.ps1` | 746 | ps-diagnostic | Connected to domain '$($Script:LDAPContext.Domain)' on server '$($Script:LDAPContext.Server)' as '$AuthenticatedUser' via $AuthDisplay |
| `src/adPEAS.ps1` | 786 | ps-diagnostic | [adPEAS] Reusing credentials from existing session |
| `src/adPEAS.ps1` | 791 | ps-diagnostic | [adPEAS] Reusing certificate authentication from existing session |
| `src/adPEAS.ps1` | 799 | ps-diagnostic | [adPEAS] No authentication method specified - defaulting to Windows Authentication |
| `src/adPEAS.ps1` | 832 | ps-diagnostic | Successfully connected to domain '$($Connection.Domain)' on server '$($Connection.Server)' as '$AuthenticatedUser' via $AuthDisplay |
| `src/adPEAS.ps1` | 842 | ps-diagnostic | [adPEAS] Verifying Domain Controller connectivity... |
| `src/adPEAS.ps1` | 855 | ps-diagnostic | [adPEAS] Connection health check passed - DC is reachable |
| `src/adPEAS.ps1` | 863 | ps-diagnostic | [adPEAS] Cleared SessionInvalid flag from previous run |
| `src/adPEAS.ps1` | 889 | ps-diagnostic | [adPEAS] -OPSEC excludes BloodHound collection, which was the only module selected. Nothing to do. |
| `src/adPEAS.ps1` | 894 | ps-diagnostic | [adPEAS] Executing Modules: $($Module -join ', ') |
| `src/adPEAS.ps1` | 936 | ps-diagnostic | Appending to existing report: kept $($keptFindings.Count) of $($previousFindings.Count) previous findings, re-running $($Module -join ', ') |
| `src/adPEAS.ps1` | 939 | ps-diagnostic | [adPEAS] Could not load previous findings from '$appendCachePath': $_ |
| `src/adPEAS.ps1` | 940 | ps-diagnostic | [adPEAS] Continuing without append - creating fresh report |
| `src/adPEAS.ps1` | 943 | ps-diagnostic | [adPEAS] No previous cache found at '$appendCachePath' - first append run |
| `src/adPEAS.ps1` | 980 | ps-diagnostic | [adPEAS] Skipping checkpoint after module '$ModuleName' - session invalid |
| `src/adPEAS.ps1` | 998 | ps-diagnostic | [adPEAS] Checkpoint after module '$ModuleName' failed: $_ |
| `src/adPEAS.ps1` | 1012 | ps-diagnostic | [adPEAS] Skipping check '$CheckName' - session invalid |
| `src/adPEAS.ps1` | 1019 | ps-diagnostic | [adPEAS] Check '$CheckName' failed: $_ |
| `src/adPEAS.ps1` | 1020 | ps-diagnostic | [adPEAS] Check '$CheckName' failed: $_ |
| `src/adPEAS.ps1` | 1029 | ps-diagnostic | This check did not complete - its results are incomplete or absent. Reason: $($_.Exception.Message) |
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
| `src/adPEAS.ps1` | 1304 | ps-diagnostic | [adPEAS] HTML report generated: $($Script:HTMLOutputPath) |
| `src/adPEAS.ps1` | 1306 | ps-diagnostic | [adPEAS] Error generating HTML report: $_ |
| `src/adPEAS.ps1` | 1322 | ps-diagnostic | [adPEAS] Findings JSON saved to: $jsonPath |
| `src/adPEAS.ps1` | 1325 | ps-diagnostic | [adPEAS] Could not save JSON export to '$jsonPath': $_ |
| `src/adPEAS.ps1` | 1376 | ps-diagnostic | Partial JSON export from the modules that completed: $checkpointPath |
| `src/adPEAS.ps1` | 1377 | ps-diagnostic | Rebuild a report from it with: Convert-adPEASReport -InputJson '$checkpointPath' -OutputPath '$basePath' |
| `src/adPEAS.ps1` | 1384 | ps-diagnostic | $($incomplete.Count) check(s) did not complete - their sections are incomplete and must not be read as clean: |
| `src/adPEAS.ps1` | 1420 | ps-diagnostic | [adPEAS] Session kept alive - use Disconnect-adPEAS to close |
| `src/adPEAS.ps1` | 1421 | ps-diagnostic | [adPEAS] adPEAS v2 completed |
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

Технические идентификаторы LDAP/AD, SID, GUID, DNS/DN, имена GPO, команды PowerShell и ключи JSON не переводить. Машинный реестр (максимум 1200 кандидатов): `Localization/DOC6c-StaticSourceAudit.json`. При большем объёме указывается отсечение.
