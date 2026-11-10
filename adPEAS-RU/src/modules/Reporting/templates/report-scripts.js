// ============================================================
        // CONSTANTS
        // ============================================================
        const UI_CONSTANTS = {
            KEYBOARD_FOCUS_DURATION: 2000,      // ms - how long keyboard focus highlight stays
            SEARCH_DEBOUNCE_DELAY: 150,         // ms - delay before search filter applies
            TOOLTIP_CLOSE_DELAY: 100,           // ms - delay before tooltip click-to-close activates
            SCROLL_DELAY: 100,                  // ms - delay before scrollIntoView after DOM changes
            VIEWPORT_PADDING: 20,               // px - padding from viewport edges for positioning
            COPY_FEEDBACK_DURATION: 2000,       // ms - how long "Copied!" feedback shows on copy button
            A11Y_ANNOUNCEMENT_DELAY: 100        // ms - delay before screen reader announcements
        };

        // ============================================================
        // ACCESSIBILITY HELPERS
        // ============================================================

        // Announce message to screen readers via live region
        function announceToScreenReader(message, priority = 'polite') {
            const liveRegion = document.getElementById('a11yAnnouncements');
            if (!liveRegion) return;

            // Set priority (polite or assertive)
            liveRegion.setAttribute('aria-live', priority);

            // Clear and set message (timing helps screen readers pick up the change)
            liveRegion.textContent = '';
            setTimeout(() => {
                liveRegion.textContent = message;
            }, UI_CONSTANTS.A11Y_ANNOUNCEMENT_DELAY);
        }

        // Update ARIA pressed state for toggle buttons
        function updateAriaPressed(element, isPressed) {
            if (element) {
                element.setAttribute('aria-pressed', isPressed ? 'true' : 'false');
            }
        }

        // Update ARIA expanded state for collapsible elements
        function updateAriaExpanded(element, isExpanded) {
            if (element) {
                element.setAttribute('aria-expanded', isExpanded ? 'true' : 'false');
            }
        }

        // Manage focus for modal-like elements (tooltips, help modal)
        let previouslyFocusedElement = null;

        function trapFocus(element) {
            previouslyFocusedElement = document.activeElement;
            const focusableElements = element.querySelectorAll(
                'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
            );
            const firstFocusable = focusableElements[0];
            const lastFocusable = focusableElements[focusableElements.length - 1];

            if (firstFocusable) {
                firstFocusable.focus();
            }

            element.addEventListener('keydown', function handleTab(e) {
                if (e.key === 'Tab') {
                    if (e.shiftKey && document.activeElement === firstFocusable) {
                        e.preventDefault();
                        lastFocusable.focus();
                    } else if (!e.shiftKey && document.activeElement === lastFocusable) {
                        e.preventDefault();
                        firstFocusable.focus();
                    }
                }
            });
        }

        function restoreFocus() {
            if (previouslyFocusedElement && previouslyFocusedElement.focus) {
                previouslyFocusedElement.focus();
                previouslyFocusedElement = null;
            }
        }

        function toggleTheme() {
            const html = document.documentElement;
            const newTheme = html.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
            html.setAttribute('data-theme', newTheme);
            safeSetItem('adpeas-theme', newTheme);
            updateThemeUI(newTheme);
            announceToScreenReader('Тема изменена: ' + newTheme + ' mode');
        }

        function updateThemeUI(theme) {
            document.getElementById('themeIcon').innerHTML = theme === 'dark' ? '&#9788;' : '&#9790;';
            document.getElementById('themeLabel').textContent = theme === 'dark' ? 'Светлая' : 'Тёмная';
            // Update ARIA state for theme toggle
            const themeToggle = document.querySelector('.theme-toggle');
            if (themeToggle) {
                updateAriaPressed(themeToggle, theme === 'dark');
            }
        }

        function toggleFinding(header) {
            // Don't toggle if the click was actually a text selection (allow copy)
            if (window.getSelection && window.getSelection().toString().length > 0) return;
            const card = header.closest('.finding-card');
            card.classList.toggle('expanded');

            // Highlight the category in the sidebar navigation
            highlightCategoryForCard(card);
        }

        function highlightCategoryForCard(card) {
            // Remove previous category highlight
            document.querySelectorAll('.category-filter.category-highlight').forEach(f => f.classList.remove('category-highlight'));

            if (!card.classList.contains('expanded')) return;

            // Get the card's category and highlight the matching nav item
            const category = card.dataset.category;
            if (category) {
                const navItem = document.querySelector('.category-filter[data-category="' + category + '"]');
                if (navItem) navItem.classList.add('category-highlight');
            }
        }

        function toggleExtendedAttrs(objectId) {
            const extSection = document.getElementById('ext-' + objectId);
            const toggleBtn = extSection.previousElementSibling;
            const icon = document.getElementById('icon-' + objectId);

            if (extSection.style.display === 'none') {
                extSection.style.display = 'block';
                toggleBtn.classList.add('expanded');
                toggleBtn.querySelector('span:last-child').textContent =
                    toggleBtn.querySelector('span:last-child').textContent.replace('Show', 'Hide');
            } else {
                extSection.style.display = 'none';
                toggleBtn.classList.remove('expanded');
                toggleBtn.querySelector('span:last-child').textContent =
                    toggleBtn.querySelector('span:last-child').textContent.replace('Hide', 'Show');
            }
        }

        // Toggle individual object card (collapsed/expanded)
        function toggleObjectCard(objectId) {
            // Don't toggle if the click was actually a text selection (allow copy)
            if (window.getSelection && window.getSelection().toString().length > 0) return;
            const card = document.getElementById('obj-' + objectId);
            if (card) {
                card.classList.toggle('expanded');
            }
        }

        // Expand all object cards in a finding-card
        function expandAllObjects(findingCardId) {
            const findingCard = document.getElementById(findingCardId);
            if (findingCard) {
                findingCard.querySelectorAll('.object-detail').forEach(obj => {
                    obj.classList.add('expanded');
                });
                updateExpandCollapseButton(findingCardId, true);
            }
        }

        // Collapse all object cards in a finding-card
        function collapseAllObjects(findingCardId) {
            const findingCard = document.getElementById(findingCardId);
            if (findingCard) {
                findingCard.querySelectorAll('.object-detail').forEach(obj => {
                    obj.classList.remove('expanded');
                });
                updateExpandCollapseButton(findingCardId, false);
            }
        }

        // Toggle all object cards in a finding-card
        function toggleAllObjects(findingCardId) {
            const findingCard = document.getElementById(findingCardId);
            if (findingCard) {
                const objects = findingCard.querySelectorAll('.object-detail');
                const expandedCount = findingCard.querySelectorAll('.object-detail.expanded').length;
                const shouldExpand = expandedCount < objects.length / 2;

                objects.forEach(obj => {
                    if (shouldExpand) {
                        obj.classList.add('expanded');
                    } else {
                        obj.classList.remove('expanded');
                    }
                });
                updateExpandCollapseButton(findingCardId, shouldExpand);
            }
        }

        // Update the expand/collapse button text
        function updateExpandCollapseButton(findingCardId, isExpanded) {
            const btn = document.querySelector(`#${findingCardId} .expand-collapse-btn`);
            if (btn) {
                btn.innerHTML = isExpanded
                    ? '<span>&#9660;</span> Свернуть всё'
                    : '<span>&#9654;</span> Развернуть всё';
            }
        }

        let currentSeverityFilter = 'all';
        let currentCategoryFilter = 'all';
        let currentSearchQuery = '';
        let hideCompletedEnabled = false;

        function filterBySeverity(severity) {
            currentSeverityFilter = severity;
            // Reset category filter when severity is clicked
            currentCategoryFilter = 'all';

            // Update active state and ARIA pressed - severity gets highlighted, categories reset
            document.querySelectorAll('.severity-filter').forEach(link => {
                const isActive = link.dataset.severity === severity;
                link.classList.toggle('active', isActive);
                updateAriaPressed(link, isActive);
            });
            // Remove active and card-highlight from ALL categories
            document.querySelectorAll('.category-filter').forEach(link => {
                link.classList.remove('active', 'category-highlight');
                updateAriaPressed(link, false);
            });

            applyFilters();

            // Announce filter change to screen readers
            const count = document.querySelectorAll('.finding-card:not([style*="display: none"])').length;
            const severityLabel = severity === 'all' ? 'all severities' : severity;
            announceToScreenReader('Filtered by ' + severityLabel + '. ' + count + ' findings shown.');
        }

        function filterByCategory(category) {
            currentCategoryFilter = category;
            // Reset severity filter when category is clicked
            currentSeverityFilter = 'all';

            // Update active state and ARIA pressed - category gets highlighted, severities reset
            // Also clear card-highlight since user is now actively filtering
            document.querySelectorAll('.category-filter').forEach(link => {
                const isActive = link.dataset.category === category;
                link.classList.toggle('active', isActive);
                link.classList.remove('category-highlight');
                updateAriaPressed(link, isActive);
            });
            // Remove active from ALL severities (no highlight)
            document.querySelectorAll('.severity-filter').forEach(link => {
                link.classList.remove('active');
                updateAriaPressed(link, false);
            });

            applyFilters();

            // Announce filter change to screen readers
            const count = document.querySelectorAll('.finding-card:not([style*="display: none"])').length;
            announceToScreenReader('Filtered by category ' + category + '. ' + count + ' findings shown.');
        }

        function updateItemCount(card, visible, total) {
            const countEl = card.querySelector('.finding-count');
            if (countEl) {
                if (!countEl.dataset.originalText) {
                    countEl.dataset.originalText = countEl.textContent;
                }
                countEl.textContent = visible + ' of ' + total + ' item(s)';
            }
        }

        function resetItemCount(card) {
            const countEl = card.querySelector('.finding-count');
            if (countEl && countEl.dataset.originalText) {
                countEl.textContent = countEl.dataset.originalText;
            }
        }

        function applyFilters() {
            // Filter finding cards with item-level search filtering
            document.querySelectorAll('.finding-card').forEach(card => {
                const cardSeverity = card.dataset.severity;
                const cardCategory = card.dataset.category;
                const cardId = card.dataset.cardId;

                const matchesSeverity = currentSeverityFilter === 'all' || cardSeverity === currentSeverityFilter;
                const matchesCategory = currentCategoryFilter === 'all' || cardCategory === currentCategoryFilter;
                const isCompleted = completedFindings[cardId] === true;
                const matchesCompleted = !hideCompletedEnabled || !isCompleted;

                // Non-search filters: card-level only
                if (!matchesSeverity || !matchesCategory || !matchesCompleted) {
                    card.style.display = 'none';
                    return;
                }

                // No search query: show card, reset all items to visible
                if (currentSearchQuery === '') {
                    card.style.display = '';
                    card.querySelectorAll('.object-detail, .finding-item, .section-scope').forEach(item => {
                        item.style.display = '';
                    });
                    resetItemCount(card);
                    return;
                }

                // Search active: filter individual items within card
                // .section-scope: the lines a card opens with, in one block - searched and
                // hidden as one item, like an object.
                const items = card.querySelectorAll(':scope > .finding-body > .object-detail, :scope > .finding-body > .finding-item, :scope > .finding-body > .section-scope');
                let visibleCount = 0;
                const totalCount = items.length;

                // Check if card header/title matches (show all items if card title matches)
                const header = card.querySelector('.finding-header');
                const headerMatches = header && header.textContent.toLowerCase().includes(currentSearchQuery);

                items.forEach(item => {
                    const itemText = item.textContent.toLowerCase();
                    if (itemText.includes(currentSearchQuery) || headerMatches) {
                        item.style.display = '';
                        visibleCount++;
                    } else {
                        item.style.display = 'none';
                    }
                });

                // Show card only if at least 1 item matches (or header matches)
                if (visibleCount > 0 || headerMatches) {
                    card.style.display = '';
                    if (visibleCount < totalCount && !headerMatches) {
                        updateItemCount(card, visibleCount, totalCount);
                    } else {
                        resetItemCount(card);
                    }
                } else {
                    card.style.display = 'none';
                }
            });
        }

        // Finding definitions (embedded from adPEAS-FindingDefinitions.ps1)
        const findingDefinitions = {{FINDING_DEFINITIONS_JSON}};

        // Check descriptions (embedded from adPEAS-ObjectTypes.ps1)
        const checkDescriptions = {{CHECK_DESCRIPTIONS_JSON}};

        // RU display catalog. Canonical IDs, data attributes and scoring remain unchanged.
        const ruFindingTitles = {"KERBEROASTABLE_SPN":"Учётная запись службы, уязвимая к Kerberoasting","ASREP_ROASTABLE":"Учётная запись без предварительной проверки подлинности Kerberos (AS-REP Roasting)","KERBEROAST_WITHOUT_PREAUTH":"Kerberoasting без учётных данных через запись без предварительной проверки подлинности","KERBEROS_HASH_CRACKABLE":"Хеш Kerberos, доступный для автономного подбора пароля","KRBTGT_PASSWORD_OLD":"Пароль учётной записи krbtgt давно не менялся","GUEST_ACCOUNT_ENABLED":"Встроенная учётная запись «Гость» включена","GUEST_ACCOUNT_DISABLED":"Встроенная учётная запись «Гость» отключена","UNCONSTRAINED_DELEGATION":"Разрешено неограниченное делегирование Kerberos","UNCONSTRAINED_DELEGATION_DC":"Неограниченное делегирование на контроллере домена","UNCONSTRAINED_DELEGATION_EXPOSED_ACCOUNTS":"Привилегированные учётные записи передают TGT узлам с неограниченным делегированием","CONSTRAINED_DELEGATION_PROTOCOL_TRANSITION":"Ограниченное делегирование с переходом протокола","GPO_NOT_CURRENTLY_EFFECTIVE":"Этот параметр групповой политики сейчас не применяется","PRIVILEGED_ACCOUNT_AFFECTED":"Затронута привилегированная учётная запись","ROASTABLE_PRIVILEGED_ACCOUNT":"Привилегированная учётная запись допускает подбор пароля по билетам Kerberos","CONSTRAINED_DELEGATION_TO_DC":"Ограниченное делегирование на контроллер домена","CONSTRAINED_DELEGATION_TRANSITION_NO_TARGET":"Переход протокола без указанной цели делегирования","RBCD_DANGEROUS_PRINCIPALS":"Опасные разрешения делегирования на основе ресурса (RBCD)","ESC1_TEMPLATE":"ESC1 — уязвимый шаблон сертификата","ESC_ENROLLMENT_RIGHTS_UNREAD":"Не удалось прочитать права регистрации по шаблону сертификата","ESC2_TEMPLATE":"ESC2 — шаблон сертификата «Любое назначение» или SubCA","ESC3_TEMPLATE":"ESC3 — шаблон сертификата агента запросов","ESC3_TARGET_TEMPLATE":"ESC3 — шаблон для выдачи сертификата от имени другого пользователя","ESC4_TEMPLATE":"ESC4 — опасные права доступа к шаблону сертификата","ESC5_PKI_CONTAINER_ACL":"ESC5 — опасные разрешения на контейнеры PKI","ESC8_WEB_ENROLLMENT":"ESC8 — возможность NTLM Relay к веб-регистрации сертификатов","ADCS_HTTP_AVAILABLE":"Доступна регистрация сертификатов ЦС по HTTP","ADCS_NONPRIV_ENROLLMENT":"Регистрация сертификатов доступна непривилегированным субъектам","ADCS_CLIENT_AUTH_EKU":"В шаблоне разрешено EKU «Проверка подлинности клиента»","ADCS_SMARTCARD_LOGON_EKU":"В шаблоне разрешено EKU «Вход со смарт-картой»","DANGEROUS_ACL_GENERICALL":"Право GenericAll на чувствительном объекте","DANGEROUS_ACL_GENERICWRITE":"Право GenericWrite на чувствительном объекте","DANGEROUS_ACL_WRITEDACL":"Право WriteDACL на чувствительном объекте","DANGEROUS_ACL_WRITEOWNER":"Право WriteOwner на чувствительном объекте","DANGEROUS_ACL_GPO_WRITEPROPERTY":"Право WriteProperty на объекте GPO","DANGEROUS_ACL_GPO_WRITEPROPERTY_SCOPED":"Право WriteProperty на атрибут GPO, не управляющий содержимым политики","DANGEROUS_ACL_GPO_DELETE":"Разрешение удаления объекта GPO","DANGEROUS_ACL_GPO_EXTENDED":"Право Self или ExtendedRight на объекте GPO","GPO_SYSVOL_WRITABLE":"Право записи в папку GPO в SYSVOL","GPO_NON_DEFAULT_OWNER":"Нестандартный владелец объекта групповой политики","GPO_SYSVOL_GPT_MISSING":"У объекта GPO отсутствует папка или gpt.ini в SYSVOL","GPO_SYSVOL_FOLDER_ORPHANED":"Папка SYSVOL не связана с объектом GPO","GPO_UNLINKED_BROAD_WRITE":"Широкая группа может изменить непривязанный объект GPO","DOMAIN_ROOT_GPLINK_WRITE":"Право записи в атрибут gPLink корневого объекта домена","DOMAIN_ROOT_SID_HISTORY_WRITE":"Право Migrate-SID-History на объекте домена","DOMAIN_ROOT_REPLICA_INSTALL":"Право DS-Install-Replica на объекте домена","CRITICAL_OBJECT_CONTROL":"Управление схемой, конфигурацией, разделами, ролями или сайтами AD","RODC_PRIVILEGED_PASSWORD_ALLOWED":"RODC может кэшировать пароли привилегированных учётных записей","RODC_PRIVILEGED_PASSWORD_REVEALED":"Привилегированные секреты уже кэшированы на RODC","RODC_DENIED_GROUP_MISSING":"Защищаемая группа отсутствует в списке запрета репликации паролей RODC","UNREGISTERED_DOMAIN_CONTROLLER":"Компьютер с ролью контроллера домена не зарегистрирован как контроллер","DOMAIN_ROOT_REANIMATE_TOMBSTONES":"Право Reanimate-Tombstones на объекте домена","DOMAIN_ROOT_MAQ_WRITE":"Право изменения ms-DS-MachineAccountQuota","DOMAIN_ROOT_FSMO_TRANSFER":"Право передачи роли эмулятора PDC на объекте домена","DOMAIN_ROOT_NON_DEFAULT_OWNER":"Нестандартный владелец корневого объекта домена","OU_NON_DEFAULT_OWNER":"Нестандартный владелец организационной единицы","DANGEROUS_ACL_REPLICATION_NO_SECRETS":"Права репликации без секретов: недостаточно одного разрешения для DCSync","DANGEROUS_ACL_REPLICATION_INERT_HALF":"Право репликации неактивно без парного разрешения","DANGEROUS_ACL_DCSYNC_BROAD":"Права DCSync предоставлены широкой группе","DANGEROUS_ACL_BROAD_GROUP":"Широкой группе предоставлены опасные права на объект домена","DANGEROUS_ACL_DCSYNC":"Права DCSync на репликацию данных каталога","OU_PERM_WRITEPROPERTY_ALL":"Разрешение WriteProperty на все свойства объектов OU","OU_PERM_PASSWORD_RESET":"Право сброса паролей в OU","OU_PERM_USERACCOUNTCONTROL":"Право изменения userAccountControl в OU","OU_PERM_USER_ACCOUNT_RESTRICTIONS":"Право изменения набора User-Account-Restrictions в OU","OU_PERM_GROUP_MEMBERSHIP":"Право изменения состава групп через атрибут member в OU","OU_PERM_SELF_ALL_VALIDATED":"Все проверяемые операции записи Validated Writes в OU","OU_PERM_SELF_MEMBERSHIP":"Право на самостоятельное изменение членства в группах OU","OU_PERM_SPN_WRITE":"Право изменения servicePrincipalName в OU","OU_PERM_VALIDATED_SPN":"Разрешение Validated-SPN в OU","OU_PERM_DNSHOSTNAME_WRITE":"Право изменения dNSHostName в OU","OU_PERM_KEYCREDENTIALLINK_WRITE":"Право изменения msDS-KeyCredentialLink в OU","ADMINSDHOLDER_PROPAGATED_RIGHT":"Право на AdminSDHolder, распространяемое SDProp на защищённые объекты","OU_PERM_DNS_HOST_NAME_ATTRIBUTES":"Право изменения DNS-Host-Name-Attributes в OU","OU_PERM_VALIDATED_DNS":"Разрешение Validated-DNS-Host-Name в OU","OU_PERM_SCRIPTPATH":"Право изменения scriptPath в OU","OU_PERM_CONSTRAINED_DELEGATION":"Право изменения msDS-AllowedToDelegateTo в OU","OU_PERM_RBCD":"Право изменения msDS-AllowedToActOnBehalfOfOtherIdentity в OU","OU_PERM_LAPS_READ":"Право чтения паролей LAPS в OU","OU_PERM_CREATE_CHILD":"Право создания дочерних объектов в OU","OU_PERM_CREATE_DMSA":"Право создания делегированных управляемых учётных записей dMSA","OU_PERM_GPLINK":"Право изменения привязок GPO через gPLink в OU","OU_PERM_GPOPTIONS":"Право изменения gPOptions в OU","OU_PERM_GENERICWRITE":"Право GenericWrite в OU","OU_PERM_READALL":"Право чтения всех свойств в OU","PASSWORD_NEVER_EXPIRES":"Срок действия пароля не ограничен","PASSWORD_NOT_REQUIRED":"Установлен флаг PASSWD_NOTREQD: пароль не обязателен","PRECREATED_COMPUTER_ACCOUNT":"Предварительно созданная учётная запись компьютера не использовалась","INTERDOMAIN_TRUST_ACCOUNT":"Учётная запись междоменного доверия","ESX_ADMINS_MEMBER":"Участник группы ESX Admins (администраторы VMware ESXi)","PRIVILEGED_GROUP_MEMBERSHIP":"Членство в привилегированной группе уровня Tier 0","OPERATOR_GROUP_MEMBERSHIP":"Членство в операторской группе или группе с широким доступом","EXCHANGE_GROUP_PERMISSIONS":"Штатные разрешения служебной группы Exchange","EXCHANGE_GROUP_LOW_PRIV_MEMBER":"Непривилегированная учётная запись в служебной группе Exchange","LDAP_SIGNING_NOT_REQUIRED":"Подпись LDAP не обязательна","LDAP_CHANNEL_BINDING_NOT_REQUIRED":"Привязка канала LDAP не обязательна","LDAP_ANONYMOUS_BINDING_ALLOWED":"Разрешены анонимные операции LDAP","DSHEURISTICS_ANONYMOUS_NSPI":"Разрешён анонимный доступ NSPI","DSHEURISTICS_ADMINSDHOLDER_EXCLUSION":"Операторские группы исключены из защиты AdminSDHolder","DSHEURISTICS_UNIQUENESS_DISABLED":"Отключена проверка уникальности UPN или SPN","SID_HISTORY_INJECTION":"Привилегированный SID этого домена в sIDHistory","SID_HISTORY_OWN_DOMAIN":"SID этого домена в атрибуте sIDHistory","SID_HISTORY_FOREIGN_PRIVILEGED":"Привилегированный SID другого домена в sIDHistory","SID_HISTORY_ORPHANED":"SID из недоверенного домена или домена вне леса в sIDHistory","GPO_DANGEROUS_PERMISSIONS":"Опасные разрешения на объект GPO","GPO_SCOPE_DOMAIN_WIDE":"Объект GPO привязан к корню домена и действует на весь домен","LAPS_NOT_DEPLOYED":"Защита LAPS не внедрена","LAPS_PASSWORD_READABLE":"Пароль LAPS доступен для чтения","BITLOCKER_KEY_READABLE":"Ключ восстановления BitLocker доступен для чтения","BITLOCKER_RECOVERY_DELEGATED":"Чтение пароля восстановления BitLocker делегировано субъекту","GPO_USERRIGHT_SEDEBUG":"Право «Отладка программ» (SeDebugPrivilege) назначено через GPO сверх стандартных значений","GPO_USERRIGHT_SETCB":"Право «Работа в режиме операционной системы» (SeTcbPrivilege) назначено через GPO","GPO_USERRIGHT_SECREATETOKEN":"Право «Создание объекта токена» (SeCreateTokenPrivilege) назначено через GPO","GPO_USERRIGHT_SEIMPERSONATE":"Право «Имитация клиента после проверки подлинности» (SeImpersonatePrivilege) выдано через GPO","GPO_USERRIGHT_SEASSIGNPRIMARYTOKEN":"Право «Замена токена уровня процесса» (SeAssignPrimaryTokenPrivilege) выдано через GPO","GPO_USERRIGHT_SELOADDRIVER":"Право «Загрузка и выгрузка драйверов устройств» (SeLoadDriverPrivilege) выдано через GPO","GPO_USERRIGHT_SEBACKUP":"Право «Архивирование файлов и каталогов» (SeBackupPrivilege) выдано через GPO","GPO_USERRIGHT_SERESTORE":"Право «Восстановление файлов и каталогов» (SeRestorePrivilege) выдано через GPO","GPO_USERRIGHT_SETAKEOWNERSHIP":"Право «Смена владельцев файлов и других объектов» (SeTakeOwnershipPrivilege) выдано через GPO","GPO_USERRIGHT_SEENABLEDELEGATION":"Право доверия учётных записей для делегирования (SeEnableDelegationPrivilege) выдано через GPO","GPO_USERRIGHT_SESYNCAGENT":"Право «Синхронизация данных службы каталогов» (SeSyncAgentPrivilege) выдано через GPO","GPO_USERRIGHT_SEMANAGEVOLUME":"Право обслуживания томов (SeManageVolumePrivilege) выдано через GPO","GPO_USERRIGHT_SESECURITY":"Право управления аудитом и журналом безопасности (SeSecurityPrivilege) выдано через GPO","GPO_USERRIGHT_SERELABEL":"Право изменения метки объекта (SeRelabelPrivilege) выдано через GPO","GPO_USERRIGHT_SETRUSTEDCREDMANACCESS":"Доступ к диспетчеру учётных данных как доверенного вызывающего (SeTrustedCredManAccessPrivilege)","GPO_USERRIGHT_SEREMOTEINTERACTIVELOGON":"Право входа через службы удалённых рабочих столов (SeRemoteInteractiveLogonRight) расширено через GPO","GPO_USERRIGHT_SEINTERACTIVELOGON":"Право локального входа (SeInteractiveLogonRight) расширено через GPO","GPO_USERRIGHT_SEBATCHLOGON":"Право пакетного входа (SeBatchLogonRight) расширено через GPO","GPO_USERRIGHT_SESERVICELOGON":"Право входа в качестве службы (SeServiceLogonRight) назначено через GPO","GPO_USERRIGHT_SESYSTEMTIME":"Право изменения системного времени (SeSystemtimePrivilege) расширено через GPO","GPO_USERRIGHT_SEREMOTESHUTDOWN":"Право принудительного удалённого завершения работы (SeRemoteShutdownPrivilege) расширено через GPO","GPO_USERRIGHT_SESHUTDOWN":"Право завершения работы системы (SeShutdownPrivilege) расширено через GPO","GPO_USERRIGHT_SECREATESYMBOLICLINK":"Право создания символических ссылок (SeCreateSymbolicLinkPrivilege) расширено через GPO","GPO_USERRIGHT_SEDELEGATESESSIONUSERIMPERSONATE":"Право получения токена другого пользователя в сеансе (SeDelegateSessionUserImpersonatePrivilege) выдано через GPO","GPO_USERRIGHT_SEAUDIT":"Право формирования аудита безопасности (SeAuditPrivilege) расширено через GPO","GPO_USERRIGHT_SESYSTEMENVIRONMENT":"Право изменения параметров среды микропрограммы (SeSystemEnvironmentPrivilege) расширено через GPO","GPO_USERRIGHT_SECREATEGLOBAL":"Право создания глобальных объектов (SeCreateGlobalPrivilege) расширено через GPO","GPO_USERRIGHT_SEPROFILESINGLEPROCESS":"Право профилирования отдельного процесса (SeProfileSingleProcessPrivilege) расширено через GPO","GPO_USERRIGHT_SESYSTEMPROFILE":"Право профилирования производительности системы (SeSystemProfilePrivilege) расширено через GPO","GPO_USERRIGHT_DEFAULT_REMOVED":"Групповая политика исключает стандартного владельца права пользователя","LAPS_ENCRYPTED_READ_NO_DECRYPTOR":"Доступно чтение зашифрованного пароля LAPS без возможности расшифрования","LAPS_PASSWORD_READ_ACCESS":"Разрешения на чтение пароля LAPS","LAPS_READ_BLOCKED_BY_CONFIDENTIAL":"Чтение всех свойств OU компьютеров ограничено флагом конфиденциальности","SMB_SIGNING_DISABLED":"Цифровая подпись SMB не обязательна","CREDENTIAL_IN_DESCRIPTION":"Учётные данные обнаружены в текстовом атрибуте","DELETED_OBJECT_CREDENTIAL":"Учётные данные сохранились в удалённом объекте","DELETED_OBJECTS_READ_DELEGATED":"Чтение удалённых объектов разрешено вне Tier 0","DELETED_OBJECTS_READ_BROAD":"Широкой группе разрешено читать удалённые объекты","CREDENTIAL_GPP_PASSWORD":"Пароль в предпочтениях групповой политики (GPP)","CREDENTIAL_AUTOADMINLOGON":"Учётные данные AutoAdminLogon в GPO","GPO_REGISTRY_PASSWORD":"Пароль в значении реестра, развёрнутом через GPO","CREDENTIAL_UNATTEND_PASSWORD":"Пароль в файле ответов установки Windows","CREDENTIAL_VNC_PASSWORD":"Пароль VNC доступен для чтения","CREDENTIAL_NET_USE":"Пароль указан прямо в команде net use","CREDENTIAL_SCRIPT_PASSWORD":"Пароль обнаружен в файле сценария","CREDENTIAL_CONNECTION_STRING":"Учётные данные в строке подключения к базе данных","CREDENTIAL_MENTION_REVIEW":"Возможное упоминание учётных данных — требуется проверка","REVERSIBLE_ENCRYPTION":"Пароль хранится с обратимым шифрованием","GMSA_PASSWORD_READABLE":"Управляемый пароль gMSA доступен для получения","SHADOW_CREDENTIALS":"Атрибут ключевых учётных данных msDS-KeyCredentialLink заполнен","TRUST_SID_FILTERING_DISABLED":"Фильтрация SID в доверительных отношениях отключена","RBCD_CONFIGURED":"Настроено ограниченное делегирование на основе ресурса (RBCD)","KERBEROS_TICKET_LIFETIME_EXTENDED":"Срок действия билета Kerberos превышает стандартный","TRUST_USES_RC4":"Доверительные отношения используют Kerberos без AES","TRUST_PASSWORD_STALE":"Пароль доверительных отношений давно не обновлялся","TRUST_BIDIRECTIONAL":"Двусторонние доверительные отношения","TRUST_TRANSITIVE":"Транзитивные доверительные отношения","TRUST_SELECTIVE_AUTH":"Включена выборочная проверка подлинности","TRUST_TREAT_AS_EXTERNAL":"Ослаблена фильтрация SID для лесного доверия","NETWORK_SUBNET_DOMAIN_CONTROLLERS":"Подсеть с контроллерами домена","OS_EXTENDED_SECURITY_UPDATES_ONLY":"ОС вне основной поддержки, доступны только платные ESU","OUTDATED_OS":"Операционная система снята с поддержки","AGING_OS":"Операционная система приближается к окончанию поддержки","EXCHANGE_VULNERABLE_VERSION":"Версия Exchange Server вышла из поддержки","EXCHANGE_SHARED_PERMISSIONS_MODEL":"Модель общих разрешений Exchange: WriteDACL на объекте домена","EXCHANGE_PERMISSIONS_MODEL_CLEAN":"Exchange не имеет действующих прав повышения привилегий на объекте домена","EXCHANGE_AD_SPLIT_PERMISSIONS":"В Exchange применяется разделённая модель разрешений AD","EXCHANGE_SMTP_OPEN_RELAY":"SMTP-соединитель Exchange ретранслирует сообщения анонимных отправителей","EXCHANGE_SMTP_ANONYMOUS_SPOOFING":"Анонимные отправители могут использовать внутренние адреса отправителя","EXCHANGE_SMTP_BROAD_RELAY":"SMTP-соединитель позволяет ретрансляцию всем прошедшим проверку подлинности","EXCHANGE_SMTP_ANONYMOUS_AUTHENTICATED":"Анонимная почта считается прошедшей проверку подлинности","EXCHANGE_SMTP_ANONYMOUS_BYPASS_ANTISPAM":"Анонимные сообщения могут обходить антиспам-защиту Exchange","EXCHANGE_SMTP_BROAD_SPOOFING":"Любая доменная учётная запись может подменить внутреннего отправителя","EXCHANGE_SMTP_CONNECTOR_AUTHENTICATED":"Принимающий SMTP-соединитель требует проверки подлинности","EXCHANGE_SMTP_CONNECTOR_UNREADABLE":"Не удалось прочитать разрешения принимающего SMTP-соединителя","EXCHANGE_HYBRID_DEPLOYMENT":"Гибридный Exchange: компрометация локальной инфраструктуры может затронуть облачный тенант","EXCHANGE_RBAC_MAILBOX_IMPORT_EXPORT":"Назначена роль Mailbox Import Export","EXCHANGE_RBAC_APPLICATION_IMPERSONATION":"Назначена роль ApplicationImpersonation","EXCHANGE_RBAC_ROLE_MANAGEMENT":"Роль Role Management назначена вне группы Organization Management","EXCHANGE_RBAC_UNSCOPED_ROLE_MANAGEMENT":"Назначена роль Unscoped Role Management","EXCHANGE_RBAC_MAILBOX_SEARCH":"Роль Mailbox Search назначена вне группы Discovery Management","EXCHANGE_RBAC_AD_PERMISSIONS":"Роль Active Directory Permissions назначена вне Organization Management","EXCHANGE_RBAC_DEFAULT_ASSIGNMENT":"Критически важная роль Exchange назначена стандартной группе ролей","COMPUTER_OBJECT_EXPLICIT_RIGHT":"Явное разрешение на объекте компьютера вне Tier 0","COMPUTER_PASSWORD_NOT_ROTATED":"Пароль компьютерной учётной записи давно не обновлялся","DC_PASSWORD_NOT_ROTATED":"Пароль учётной записи контроллера домена давно не обновлялся","MACHINE_QUOTA_UNRESTRICTED":"Квота создания компьютерных учётных записей не ограничена","INACTIVE_PRIVILEGED_ACCOUNT":"Неактивная привилегированная учётная запись","ORPHANED_ADMIN_ACCOUNT":"Осиротевшая административная запись: adminCount без членства в защищаемой группе","STALE_PASSWORD":"Пароль не менялся продолжительное время","STALE_PASSWORD_MEDIUM":"Предупреждение: пароль не менялся от одного года до пяти лет","WEAK_PASSWORD_POLICY":"Слабая доменная политика паролей","WEAK_FGPP":"Тонкая политика паролей слабее доменной политики по умолчанию","NO_MAX_PASSWORD_AGE":"Максимальный срок действия пароля не ограничен","WEAK_LOCKOUT_DURATION":"Недостаточная продолжительность блокировки учётной записи","NO_ACCOUNT_LOCKOUT":"Политика блокировки учётных записей отключена или слишком слабая","NO_MIN_PASSWORD_AGE":"Минимальный срок действия пароля не установлен","PASSWORD_HISTORY_DISABLED":"История паролей отключена","ESC9_CT_NO_SECURITY_EXTENSION":"ESC9 — шаблон сертификата без расширения безопасности","SCCM_SYSTEM_MANAGEMENT_ACL":"Право записи в контейнер SCCM System Management","SCOM_PRIVILEGED_SERVICE_ACCOUNT":"Привилегированная служебная учётная запись SCOM","SCCM_SITE_HIERARCHY":"Обнаружена иерархия SCCM с несколькими сайтами","SCCM_PXE_EXPOSURE":"Обнаружен сервер сетевой загрузки PXE","SCCM_SERVICE_ACCOUNT":"Служебная учётная запись SCCM с SPN","SCCM_GROUP_BROAD_MEMBER":"Широкая группа состоит в группе, связанной с SCCM","AZURE_AD_CONNECT_EXPOSED":"Возможное раскрытие доступа к серверу Microsoft Entra Connect","ADFS_DKM_CONTAINER":"AD FS развёрнут: ключ подписи токенов хранится в каталоге","MSSQL_SERVICE_ACCOUNT_PRIVILEGED":"SQL Server работает от привилегированной доменной учётной записи","LAPS_PASSWORD_NOT_ROTATED":"Пароль LAPS перестал регулярно обновляться","DSRM_PASSWORD_UNMANAGED":"Пароль DSRM не управляется Windows LAPS","NON_DEFAULT_COMPUTER_OWNERS":"Нестандартный владелец компьютерного объекта","COMPUTER_OWNERSHIP_REASSIGNED":"Владелец компьютерного объекта изменён после создания","NON_DEFAULT_USER_OWNERS":"Нестандартный владелец пользовательского объекта","READABLE_UNIX_PASSWORD_ATTRIBUTES":"Парольные атрибуты UNIX доступны для чтения","STANDALONE_MSA_LEGACY":"Устаревшая автономная управляемая учётная запись службы (sMSA)","GPO_TASK_SYSTEM_UNC_PATH":"Задача GPO запускается от SYSTEM или привилегированной записи по UNC-пути","GPO_TASK_UNQUOTED_PATH":"В задаче GPO не заключён в кавычки путь исполняемого файла","GPO_TASK_CMD_UNQUOTED_PATH":"Задача GPO передаёт cmd.exe путь без кавычек","ESC15_SCHEMA_V1_ENROLLEE_SUBJECT":"ESC15 — шаблон схемы v1 позволяет задавать субъект сертификата заявителю","CREDENTIAL_ROAMING_PRESENT":"Credential Roaming: закрытые ключи и мастер-ключи DPAPI хранятся в AD","CREDENTIAL_ROAMING_READABLE":"Credential Roaming: данные доступны всем прошедшим проверку подлинности","CREDENTIAL_ROAMING_DELEGATED":"Credential Roaming: чтение закрытых и мастер-ключей делегировано","ESC14_WEAK_EXPLICIT_MAPPING":"ESC14 — слабое явное сопоставление сертификатов","ESC14_WRITABLE_MAPPING":"ESC14 — непривилегированный субъект может изменить altSecurityIdentities","ESC13_ISSUANCE_POLICY_GROUP_LINK":"ESC13 — политика выдачи сертификата связана с группой AD","ADCS_CA_WEAK_SIGNATURE":"В сертификате ЦС используется слабый алгоритм подписи","ADCS_CA_SHORT_KEY":"Недостаточная длина ключа сертификата ЦС","ADCS_CA_CERT_EXPIRED":"Срок действия сертификата ЦС истёк","ADCS_CA_CROSS_DOMAIN":"Сервер центра сертификации находится в другом домене","PRIVILEGED_GROUP_ACL":"Возможность управления привилегированной группой вне защиты AdminSDHolder","PRIVILEGED_ACCOUNT_ACL":"Возможность управления привилегированной учётной записью","NTAUTH_FOREIGN_ISSUER":"Хранилище NTAuth содержит издателя вне корпоративных ЦС этого леса","PKI_WEAK_SIGNATURE_ALGORITHM":"В сертификате PKI используется слабый алгоритм подписи","PKI_SHORT_KEY_LENGTH":"Недостаточная длина ключа сертификата PKI","PKI_CERTIFICATE_EXPIRED":"Срок действия сертификата PKI истёк","COMPUTER_CONTAINER_CREATE_BROAD":"Широкой группе разрешено создавать компьютерные объекты","COMPUTER_CONTAINER_CREATE_PERMISSIONS":"Нестандартные разрешения на создание компьютерных объектов","GPO_SEMACHINEACCOUNTPRIVILEGE_BROAD":"Право SeMachineAccountPrivilege назначено через GPO","BLOODHOUND_COLLECTION_COMPLETE":"Сбор данных BloodHound","LDAP_SIGNING_REQUIRED":"Цифровая подпись LDAP обязательна","LDAP_CHANNEL_BINDING_ALWAYS":"Привязка канала LDAP обязательна всегда","LDAP_ANONYMOUS_BINDING_RESTRICTED":"Анонимные подключения LDAP ограничены","ANONYMOUS_SAM_ENUMERATION_ALLOWED":"Разрешено анонимное перечисление учётных записей SAM и общих ресурсов","ANONYMOUS_SID_NAME_TRANSLATION_ALLOWED":"Разрешено анонимное преобразование SID в имена","SMB_SIGNING_REQUIRED":"Цифровая подпись SMB обязательна","ENROLLMENT_REQUIRES_APPROVAL":"Для регистрации сертификата необходимо одобрение","ACCOUNT_DISABLED":"Учётная запись отключена","SMARTCARD_REQUIRED":"Для интерактивного входа обязательна смарт-карта","ACCOUNT_NOT_DELEGATED":"Учётная запись помечена как конфиденциальная и не допускает делегирования","WEB_ENDPOINT_EPA_ENABLED":"Включена расширенная защита проверки подлинности (EPA)","PKI_STRONG_SIGNATURE_ALGORITHM":"Сертификат PKI использует стойкий алгоритм подписи","PKI_STRONG_KEY_LENGTH":"Сертификат PKI использует достаточную длину ключа","PASSWORD_COMPLEXITY_ENABLED":"Требования к сложности пароля включены","LOCKOUT_DURATION_FOREVER":"Разблокировка учётной записи требует действий администратора","PRIMARY_GROUP_IS_DC_GROUP":"У некомуьпьютерной записи основная группа контроллеров домена","TIER0_NOT_IN_PROTECTED_USERS":"Учётная запись уровня Tier 0 отсутствует в группе Protected Users","OPERATOR_GROUP_MEMBERS":"В операторской группе есть активные участники","INACTIVE_ACCOUNT":"Обнаружена неактивная учётная запись","OLD_FUNCTIONAL_LEVEL":"Устаревший функциональный уровень домена или леса","AD_RECYCLE_BIN_DISABLED":"Корзина Active Directory не включена","SYSVOL_FRS_REPLICATION":"Репликация SYSVOL всё ещё использует FRS","TOMBSTONE_LIFETIME_SHORT":"Срок хранения удалённых объектов меньше 180 дней","PREWIN2000_ANONYMOUS_MEMBER":"Anonymous Logon состоит в группе Pre-Windows 2000 Compatible Access","PREWIN2000_DEFAULT_MEMBER":"Authenticated Users состоит в группе Pre-Windows 2000 Compatible Access","PREWIN2000_BROAD_MEMBER":"Широкая группа включена в Pre-Windows 2000 Compatible Access","ANON_LDAP_READABLE_ATTRS":"Атрибуты LDAP доступны анонимному чтению","LAPS_UNPROTECTED_COMPUTERS":"Компьютеры не защищены LAPS","LAPS_COVERAGE_NOT_IN_AD":"Не удаётся определить охват LAPS по данным Active Directory","GPO_WIDE_IMPACT":"Объект GPO влияет на большое количество компьютеров","LAPS_GPO_PASSWORD_LENGTH":"Длина пароля LAPS меньше стандартного значения","LAPS_GPO_PASSWORD_AGE":"Интервал смены пароля LAPS превышает стандартный","LAPS_GPO_DISABLED":"LAPS отключён групповой политикой","LAPS_GPO_NO_POST_AUTH_RESET":"Windows LAPS не сбрасывает пароль после использования","GMSA_ROTATION_INTERVAL_LONG":"Пароль gMSA меняется слишком редко","GMSA_MEMBERSHIP_OWNER":"Дескриптор доступа к паролю gMSA принадлежит непривилегированному субъекту","AUTHN_SILO_NOT_EFFECTIVE":"Хранилище политик проверки подлинности никого не ограничивает","AUTHN_SILO_INCOMPLETE_ENROLLMENT":"Учётная запись не включена в назначенное хранилище политики проверки подлинности","AUTHN_POLICY_EXEMPT_ADMINISTRATOR":"Встроенная запись «Администратор» подпадает под политику проверки подлинности","AUTHN_POLICY_NOT_EFFECTIVE":"Политика проверки подлинности работает в режиме аудита","AUTHN_POLICY_BROAD_CONDITION":"Условие политики проверки подлинности допускает широкую группу","AUTHN_POLICY_OBJECT_WRITABLE":"Объект политики проверки подлинности доступен для записи вне Tier 0","AUTHN_KDC_ARMORING_NOT_SUPPORTED":"Контроллеры домена не поддерживают утверждения и защищённый Kerberos (Armoring)","DMSA_LINK_IRREGULAR":"Учётная запись связана с dMSA вне штатной процедуры миграции","DMSA_LINK_ONE_SIDED":"Ссылка между dMSA и исходной записью существует только в одном направлении","DMSA_PRIVILEGED_PREDECESSOR":"Привилегированная учётная запись заменена на dMSA","DMSA_USABLE_BY_NONPRIVILEGED":"dMSA доступна непривилегированным субъектам","DMSA_MEMBERSHIP_OWNER":"Дескриптор использования dMSA принадлежит непривилегированному субъекту","GMSA_MEMBERSHIP_INFO":"Сведения о разрешениях использования gMSA","ACL_INHERITED_FROM":"Источник наследования ACL","ADMIN_COUNT_INDICATOR":"Установлен adminCount без членства в защищаемой группе","LAPS_ACCOUNT_INFO":"Управляемая учётная запись LAPS","DANGEROUS_RIGHTS_SEVERITY":"Классификация разрешений по уровню риска","DANGEROUS_RIGHTS_AFFECTED_OUS":"Организационные единицы, затронутые опасными разрешениями","ADCS_CLIENT_AUTH_SEVERITY":"Разрешена проверка подлинности клиента","ADCS_MANAGER_APPROVAL":"Состояние одобрения заявок администратором сертификатов","CERT_FLAG_SEVERITY":"Классификация флагов шаблона сертификата","EXCHANGE_WEB_ENDPOINTS":"Защищённость веб-интерфейсов Exchange","CONSTRAINED_DELEGATION":"Настроено ограниченное делегирование Kerberos","LAPS_INSTALLED":"Установлен Windows LAPS","LAPS_LEGACY":"Используется прежняя версия LAPS","META_SEVERITY_PASSTHROUGH":"Индикатор уровня опасности","META_STATUS_INDICATOR":"Индикатор состояния","CREDENTIAL_USERNAME_EXPOSED":"Имя пользователя обнаружено в раскрытых учётных данных","CREDENTIAL_PASSWORD_EXPOSED":"Пароль обнаружен в раскрытых учётных данных","CREDENTIAL_MATCHED_LINE":"Строка с найденными учётными данными","CREDENTIAL_TYPE_INFO":"Тип обнаруженных учётных данных","LAPS_ENCRYPTED_PASSWORD":"Доступно чтение зашифрованного пароля LAPS без ключа расшифрования","NON_DEFAULT_OWNER":"Нестандартный владелец объекта","ENCRYPTION_RC4_ONLY":"Учётная запись поддерживает только RC4 для Kerberos","ENCRYPTION_DES_ENABLED":"Для Kerberos разрешён алгоритм DES","ENCRYPTION_NOT_CONFIGURED":"Типы шифрования не заданы у учётной записи с SPN","ENCRYPTION_AES_ONLY":"Учётная запись Kerberos ограничена шифрованием AES","KERBEROASTABLE_USER_SPN":"Пользовательская учётная запись с SPN допускает Kerberoasting","DANGEROUS_RIGHTS_CONTEXT":"Опасные разрешения с учётом контекста","GPO_SCOPE_SEVERITY":"Состояние применения групповой политики","GPO_LOCAL_GROUP_RISKY_MEMBER":"Широкая группа добавлена в локальную группу через GPO","GPO_LOCAL_GROUP_MEMBER":"Учётная запись добавлена в привилегированную локальную группу через GPO","GPO_LINK_REACHES_DC":"Привязка GPO затрагивает контроллер домена","GPO_TASK_FIELD_SEVERITY":"Классификация параметра запланированного задания","GPO_LINKED_OUS_SEVERITY":"GPO привязан к корню домена","WEB_ENDPOINT_SECURITY":"Классификация защищённости веб-интерфейсов","REGISTRY_ESC10_KDC_BINDING":"ESC10 — Kerberos игнорирует SID-расширение сертификата из-за настройки GPO","REGISTRY_ESC10_KDC_BINDING_COMPAT":"ESC10 — Kerberos принимает сертификаты без SID-расширения из-за настройки GPO","REGISTRY_ESC10_SCHANNEL_UPN":"ESC10 — Schannel сопоставляет сертификаты по UPN из-за настройки GPO","REGISTRY_WDIGEST":"Кэширование учётных данных WDigest в открытом виде включено через GPO","REGISTRY_ONELOGON":"Уязвимый список разрешений защищённого канала Netlogon (Zerologon/OneLogon)","REGISTRY_AUTOLOGON":"Автоматический вход AutoAdminLogon включён через GPO","REGISTRY_LMCOMPAT":"Через GPO разрешена слабая проверка подлинности LM/NTLMv1","REGISTRY_NOLMHASH":"Сохранение LM-хешей разрешено через GPO","REGISTRY_REMOTEUAC":"Удалена фильтрация токенов Remote UAC через GPO","REGISTRY_ALWAYSINSTALLELEVATED":"Установка MSI с повышенными правами AlwaysInstallElevated включена через GPO","REGISTRY_ENABLELUA":"Контроль учётных записей (UAC) отключён через GPO","REGISTRY_RESTRICTEDADMIN":"Режим Restricted Admin для RDP включён через GPO","REGISTRY_WSUS_HTTP":"Сервер обновлений WSUS настроен по незашифрованному HTTP","REGISTRY_DEFENDER_DISABLED":"Антивирус Microsoft Defender отключён через GPO","REGISTRY_RUNASPPL":"Защита процесса LSA (RunAsPPL) явно отключена через GPO","REGISTRY_CREDGUARD":"Credential Guard явно отключён через GPO","REGISTRY_FILTERADMINTOKEN":"Фильтрация UAC для встроенного администратора RID 500 отключена через GPO","REGISTRY_CREDSSP_ORACLE":"Уязвимая настройка CredSSP Encryption Oracle задана через GPO","REGISTRY_MACHINE_PASSWORD_STATIC":"Смена пароля компьютерной учётной записи отключена через GPO","REGISTRY_NULL_SESSION":"Анонимный доступ (Null Session) расширен через GPO","REGISTRY_RDP_NLA":"Проверка подлинности на уровне сети (NLA) для RDP отключена через GPO","REGISTRY_RDP_SECURITYLAYER":"Уровень безопасности RDP понижен через GPO","REGISTRY_RDP_ENCRYPTION":"Для RDP установлен низкий уровень шифрования через GPO","REGISTRY_FIREWALL_DISABLED":"Брандмауэр Windows отключён через GPO","REGISTRY_INSECURE_GUEST_AUTH":"Небезопасный гостевой вход SMB разрешён через GPO","REGISTRY_SMB1_SERVER":"Серверный компонент SMBv1 включён через GPO","REGISTRY_SMB1_CLIENT":"Клиентский компонент SMBv1 включён через GPO","REGISTRY_SMB2_SERVER_DISABLED":"Серверный компонент SMBv2/v3 отключён через GPO","REGISTRY_SMB_UNENCRYPTED_ACCESS":"Разрешён доступ без шифрования к ресурсам SMB, требующим шифрования","REGISTRY_DSRM_ADMIN_LOGON":"Вход администратора DSRM разрешён в любое время через GPO","REGISTRY_PRINT_RPC_PRIVACY":"Усиленная защита конфиденциальности RPC службы печати отключена через GPO","REGISTRY_WSUS_USER_PROXY":"Проверка обновлений WSUS может использовать прокси пользователя","REGISTRY_MACHINE_PASSWORD_AGE":"Период смены пароля компьютера через GPO превышает 30 дней","REGISTRY_SCRIPTBLOCK_LOGGING_OFF":"Журналирование блоков сценариев PowerShell отключено через GPO","REGISTRY_UAC_NO_PROMPT":"Администраторы повышают привилегии без запроса UAC из-за GPO","REGISTRY_LEGACY_TLS":"SSL 3.0 или TLS 1.0 включён через GPO","REGISTRY_WINRM_UNENCRYPTED":"WinRM разрешает незашифрованные подключения через GPO","REGISTRY_WINRM_BASIC":"В WinRM разрешена базовая проверка подлинности через GPO","REGISTRY_CREDSSP_DELEGATE_ANY":"CredSSP делегирует учётные данные любому серверу через GPO","REGISTRY_LLMNR_ON":"Многоадресное разрешение имён LLMNR включено через GPO","REGISTRY_CACHED_LOGONS":"Число кэшируемых входов в домен превышает стандартное значение","REGISTRY_REMOTE_ASSISTANCE_OFFER":"Незапрошенная удалённая помощь разрешена через GPO","REGISTRY_LDAP_CLIENT_SIGNING_OFF":"Подпись LDAP на клиенте отключена через GPO","REGISTRY_KERBEROS_WEAK_ETYPES":"Kerberos разрешает шифрование DES или RC4 через GPO","REGISTRY_OFFICE_MACROS_ON":"Макросы Office запускаются без предупреждения из-за GPO","GPO_POINTANDPRINT_EXPLOITABLE":"Point and Print позволяет непривилегированным пользователям устанавливать драйверы без подтверждения (PrintNightmare)","GPO_POINTANDPRINT_NONADMIN_INSTALL":"Установка драйверов принтеров разрешена неадминистраторам","GPO_POINTANDPRINT_LATENT":"Запросы повышения прав Point and Print скрыты, но эксплуатация сейчас блокируется","GPO_POINTANDPRINT_USER_SCOPE":"Ограничения Point and Print заданы в конфигурации пользователя и игнорируются Windows","GPO_POINTANDPRINT_DRIVER_SOURCE":"Драйверы принтеров могут загружаться с любого сервера печати","GPO_PRINT_SPOOLER_RPC":"Диспетчер печати принимает удалённые RPC-подключения через GPO","GPO_PRINT_QUEUE_SPECIFIC_FILES":"Диспетчер печати может копировать произвольные файлы очереди печати","GPO_PRINT_DRIVER_HARDENING":"Усиленная защита доставки драйверов принтеров отключена","LAPS_GPO_ENCRYPTION_DISABLED":"Шифрование паролей Windows LAPS в AD отключено через GPO","LAPS_GPO_NO_AD_BACKUP":"Windows LAPS не сохраняет пароли в этой Active Directory","LAPS_GPO_EXPIRATION_PROTECTION_DISABLED":"Защита срока действия пароля Windows LAPS отключена через GPO","LAPS_GPO_WEAK_PASSWORD_COMPLEXITY":"Через GPO задана слабая сложность паролей LAPS","LAPS_GPO_NOT_LINKED":"Настройка LAPS содержится в непривязанном объекте GPO","GPO_SCRIPT_OUTSIDE_POLICY_STORE":"Сценарий GPO запускается вне хранилища групповых политик","LOGON_SCRIPT_WRITABLE":"Сценарий входа может изменить непривилегированный субъект","SCRIPTPATH_HARDCODED":"Путь сценария входа задан жёстко","UAC_SEVERITY_OVERRIDE":"Классификация риска параметров контроля учётных записей"};
        const ruFindingExplanations = {"KERBEROASTABLE_SPN":{"description":"Для пользовательской учётной записи задан SPN. Любой прошедший проверку подлинности пользователь домена может запросить билет службы TGS, зашифрованный ключом этой записи, и попытаться подобрать пароль вне домена.","impact":["Возможна компрометация служебной записи, особенно если у неё слабый пароль или повышенные полномочия."],"remediation":["По возможности используйте gMSA, задавайте длинные случайные пароли, включайте AES и контролируйте запросы TGS."]},"ASREP_ROASTABLE":{"description":"У учётной записи отключена предварительная проверка подлинности Kerberos (DONT_REQUIRE_PREAUTH). Посторонний субъект может запросить AS-REP и попытаться подобрать пароль автономно.","impact":["Подбор пароля возможен без предварительного входа в домен."],"remediation":["Включите предварительную проверку подлинности Kerberos и проверьте необходимость исключений."]},"KERBEROAST_WITHOUT_PREAUTH":{"description":"При наличии записи без предварительной проверки подлинности злоумышленник может запросить билеты служб других учётных записей с SPN без собственных доменных учётных данных.","impact":["Все доступные для Kerberoasting служебные записи оказываются под повышенным риском."],"remediation":["Включите предварительную проверку подлинности для всех записей и применяйте gMSA или длинные случайные пароли для служб."]},"KERBEROS_HASH_CRACKABLE":{"description":"Выделенный из билета Kerberos материал допускает автономную проверку вариантов пароля без новых обращений к контроллеру домена.","impact":["Подобранный пароль может дать доступ от имени соответствующей учётной записи."],"remediation":["Смените слабые пароли, применяйте AES и управляемые учётные записи служб."]},"KRBTGT_PASSWORD_OLD":{"description":"Пароль встроенной учётной записи krbtgt не обновлялся продолжительное время. Он используется в криптографических операциях Kerberos, связанных с билетами домена.","impact":["При компрометации ключей krbtgt возможны поддельные билеты Golden Ticket."],"remediation":["Планируйте штатную двойную смену пароля krbtgt по процедуре Microsoft с учётом репликации всех контроллеров домена."]},"GUEST_ACCOUNT_ENABLED":{"description":"Встроенная запись «Гость» (RID 501) активна и может предоставлять ненужную возможность доступа.","impact":["Дополнительная точка входа и риск анонимного или слабоконтролируемого доступа."],"remediation":["Отключите встроенную запись «Гость» и проверьте членство в группах и явные разрешения."]},"UNCONSTRAINED_DELEGATION":{"description":"На объекте разрешено неограниченное делегирование Kerberos. Узел может получать пересылаемые билеты TGT пользователей, подключающихся к его службам.","impact":["Компрометация узла позволяет злоупотреблять билетами пользователей, включая привилегированных."],"remediation":["Откажитесь от неограниченного делегирования; используйте ограниченное делегирование или RBCD и запретите делегирование привилегированных учётных записей."]},"UNCONSTRAINED_DELEGATION_EXPOSED_ACCOUNTS":{"description":"Привилегированные учётные записи могут передавать билеты TGT компьютерам с неограниченным делегированием.","impact":["Компрометация такого компьютера создаёт риск захвата привилегированных сеансов."],"remediation":["Ограничьте делегирование и пометьте критические записи как конфиденциальные, не допускающие делегирования."]},"CONSTRAINED_DELEGATION_PROTOCOL_TRANSITION":{"description":"Разрешено ограниченное делегирование с переходом протокола (S4U). При неверных границах доверия это может позволить выдавать себя за других пользователей при доступе к разрешённым службам.","impact":["Возможна подмена контекста пользователя на службе назначения."],"remediation":["Проверьте список служб msDS-AllowedToDelegateTo, учётную запись службы и необходимость перехода протокола."]},"RBCD_DANGEROUS_PRINCIPALS":{"description":"Разрешения на ограниченное делегирование на основе ресурса (RBCD) предоставлены субъектам, не соответствующим ожидаемой модели доверия.","impact":["Субъект с соответствующими полномочиями может получать доступ к ресурсу от имени других пользователей."],"remediation":["Ограничьте значения msDS-AllowedToActOnBehalfOfOtherIdentity только доверенными службами и контролируйте ACL объекта компьютера."]},"ESC1_TEMPLATE":{"description":"Шаблон сертификата может позволять заявителю задавать имя субъекта или альтернативные имена, а выданный сертификат — использоваться для проверки подлинности клиента.","impact":["При доступной регистрации возможно получение сертификата для чужой учётной записи."],"remediation":["Ограничьте права регистрации и изменение имени субъекта; проверьте EKU, требования одобрения и полномочия владельцев шаблона."]},"ESC2_TEMPLATE":{"description":"Шаблон AD CS допускает сертификаты для широкого набора назначений, включая Any Purpose или SubCA, при потенциально небезопасных правах регистрации.","impact":["Возможна выдача сертификатов с чрезмерно широкими возможностями использования."],"remediation":["Сузьте EKU и права регистрации; выдавайте такие сертификаты только после административного одобрения."]},"ESC3_TEMPLATE":{"description":"Шаблон выдаёт сертификаты агента запросов, позволяющие подавать запросы от имени других пользователей при наличии соответствующей конфигурации.","impact":["Ошибки прав на агентский шаблон могут привести к выдаче чужих удостоверений."],"remediation":["Ограничьте регистрацию сертификатов агента и настройте политики уполномоченных агентов."]},"ESC4_TEMPLATE":{"description":"На шаблоне AD CS присутствуют разрешения, позволяющие неподходящим субъектам изменять его параметры или список управления доступом.","impact":["Изменение шаблона может создать опасный сценарий регистрации сертификата."],"remediation":["Удалите избыточные WriteDACL, WriteOwner, GenericAll и права изменения параметров шаблона."]},"ESC5_PKI_CONTAINER_ACL":{"description":"Контейнеры PKI в Active Directory имеют опасные разрешения на изменение доверенной инфраструктуры.","impact":["Изменение критических объектов PKI может повлиять на доверие к сертификатам."],"remediation":["Разрешите управление контейнерами PKI только специально уполномоченным администраторам."]},"ESC8_WEB_ENROLLMENT":{"description":"Веб-службы регистрации сертификатов потенциально допускают ретрансляцию NTLM при недостаточной защите канала проверки подлинности.","impact":["В определённых условиях возможна выдача сертификата от имени другого субъекта."],"remediation":["Включите EPA, настройте HTTPS и ограничения NTLM; отключите ненужные службы веб-регистрации."]},"LDAP_SIGNING_NOT_REQUIRED":{"description":"Контроллер домена не требует обязательной подписи LDAP-запросов. Это снижает защиту от подмены и ретрансляции аутентификации.","impact":["Повышается риск атак на целостность LDAP-сеансов и NTLM Relay при наличии других условий."],"remediation":["Включите обязательную подпись LDAP на контроллерах и проверьте совместимость приложений."]},"LDAP_CHANNEL_BINDING_NOT_REQUIRED":{"description":"Для LDAPS не обеспечивается обязательная привязка канала TLS (LDAP Channel Binding).","impact":["При определённых схемах проверки подлинности возможны атаки ретрансляции."],"remediation":["Настройте LDAP Channel Binding на контроллерах домена и проверьте журналы совместимости клиентов."]},"LDAP_ANONYMOUS_BINDING_ALLOWED":{"description":"Некоторые операции LDAP доступны без проверки подлинности.","impact":["Анонимный доступ может раскрывать сведения о структуре домена и учётных записях."],"remediation":["Ограничьте анонимные LDAP-запросы, если они не требуются подтверждённым приложениям."]},"DANGEROUS_ACL_GENERICALL":{"description":"Субъекту предоставлен полный доступ GenericAll к чувствительному объекту каталога.","impact":["Возможны изменение объекта, его разрешений или использование полномочий для повышения привилегий."],"remediation":["Удалите ненужные разрешения GenericAll и делегируйте только конкретные необходимые операции."]},"DANGEROUS_ACL_WRITEDACL":{"description":"Субъект может менять список управления доступом (DACL) чувствительного объекта.","impact":["Право WriteDACL позволяет выдавать себе или другим дополнительные разрешения."],"remediation":["Ограничьте право WriteDACL доверенными администраторами и контролируйте изменения ACL."]},"DANGEROUS_ACL_WRITEOWNER":{"description":"Субъект может изменить владельца чувствительного объекта Active Directory.","impact":["Новый владелец в ряде случаев может изменить DACL и получить дополнительные права."],"remediation":["Ограничьте WriteOwner и пересмотрите нестандартное владение объектом."]},"DANGEROUS_ACL_DCSYNC":{"description":"Обнаружены права репликации, потенциально достаточные для DCSync — получения секретов каталога без входа на контроллер домена.","impact":["Возможна компрометация хешей и секретов учётных записей домена."],"remediation":["Ограничьте DS-Replication-Get-Changes и DS-Replication-Get-Changes-All контроллерами домена и доверенными службами."]},"DANGEROUS_ACL_DCSYNC_BROAD":{"description":"Права DCSync назначены группе с широким составом участников.","impact":["Члены группы могут получить доступ к реплицируемым секретам при наличии необходимых прав."],"remediation":["Отзовите полномочия репликации у широких групп и проверьте фактический состав через вложенные группы."]},"OU_PERM_PASSWORD_RESET":{"description":"На уровне организационной единицы делегировано право сбрасывать пароли учётных записей.","impact":["Неоправданно широкое делегирование позволяет захватить учётные записи в области действия."],"remediation":["Оставьте право сброса паролей только уполномоченным операторам и исключите привилегированные записи."]},"OU_PERM_SPN_WRITE":{"description":"Субъект может изменять servicePrincipalName у объектов в OU.","impact":["Изменение SPN может создать условия для злоупотребления Kerberos и атаки Kerberoasting."],"remediation":["Пересмотрите делегирование WriteProperty на servicePrincipalName и права наследования OU."]},"OU_PERM_KEYCREDENTIALLINK_WRITE":{"description":"Субъект может изменять msDS-KeyCredentialLink у объектов Active Directory.","impact":["Неправомерная запись ключевых учётных данных может позволить альтернативную аутентификацию от имени объекта."],"remediation":["Ограничьте запись msDS-KeyCredentialLink и контролируйте изменения атрибута."]},"PASSWORD_NOT_REQUIRED":{"description":"У учётной записи установлен флаг PASSWD_NOTREQD, который снимает требование наличия пароля на уровне атрибута userAccountControl.","impact":["При дополнительных небезопасных условиях запись может иметь слабую защиту."],"remediation":["Снимите флаг PASSWD_NOTREQD, если он не обоснован, и проверьте фактические параметры пароля."]},"PASSWORD_NEVER_EXPIRES":{"description":"Для учётной записи установлен запрет истечения срока действия пароля.","impact":["При компрометации длительно неизменяемый пароль расширяет период возможного злоупотребления."],"remediation":["Проверьте необходимость исключения и внедрите управляемую ротацию паролей, особенно для служебных записей."]},"GPO_DANGEROUS_PERMISSIONS":{"description":"Обнаружены разрешения на изменение объекта групповой политики, предоставленные субъектам вне ожидаемого административного круга.","impact":["Изменение GPO может затронуть пользователей и компьютеры в области её действия."],"remediation":["Пересмотрите права изменения GPO и связанные разрешения на каталог SYSVOL."]},"GPO_SYSVOL_WRITABLE":{"description":"Папка групповой политики в SYSVOL доступна на запись субъекту вне доверенного административного круга.","impact":["Изменённые сценарии и параметры политики могут выполниться на компьютерах и пользователях."],"remediation":["Ограничьте права NTFS и разрешения общего ресурса на папки политик SYSVOL."]},"GPO_SYSVOL_GPT_MISSING":{"description":"У объекта групповой политики отсутствует соответствующая папка SYSVOL или файл gpt.ini.","impact":["Политика может применяться неполностью или некорректно."],"remediation":["Проверьте репликацию SYSVOL и согласованность данных AD и файлов групповой политики."]},"GPO_NON_DEFAULT_OWNER":{"description":"У объекта GPO назначен владелец, отличный от ожидаемого.","impact":["Владелец может влиять на разрешения объекта даже без явного права изменения его настроек."],"remediation":["Проверьте происхождение владельца и восстановите штатное владение при отсутствии обоснования."]},"LAPS_NOT_DEPLOYED":{"description":"Для части инфраструктуры не обнаружено управление паролями локальных администраторов с помощью LAPS.","impact":["Повторяющиеся или неизменяемые локальные пароли повышают риск бокового перемещения."],"remediation":["Внедрите Windows LAPS и проверьте политику хранения, прав чтения и ротации паролей."]},"LAPS_PASSWORD_READABLE":{"description":"Текущему субъекту или указанной группе доступны пароли локальных администраторов, сохраняемые LAPS.","impact":["Обладатель разрешения может получить административный доступ к соответствующему компьютеру."],"remediation":["Ограничьте чтение атрибутов LAPS и регулярно проверяйте делегирование на OU."]},"BITLOCKER_KEY_READABLE":{"description":"Обнаружен доступ к сведениям восстановления BitLocker в Active Directory.","impact":["Доступ к ключу восстановления может позволить расшифровать защищённый том."],"remediation":["Ограничьте чтение данных восстановления BitLocker уполномоченным администраторам и журналируйте доступ."]},"SMB_SIGNING_DISABLED":{"description":"Цифровая подпись SMB не является обязательной для соответствующей системы или политики.","impact":["При наличии других условий возможны ретрансляция учётных данных и подмена SMB-трафика."],"remediation":["Включите требование подписи SMB на серверах и клиентах с учётом совместимости."]},"REVERSIBLE_ENCRYPTION":{"description":"Пароль учётной записи хранится с использованием обратимого шифрования.","impact":["Такая настройка ослабляет защиту парольных данных при компрометации хранилища."],"remediation":["Отключите обратимое шифрование и измените пароль после корректировки параметра."]},"CREDENTIAL_IN_DESCRIPTION":{"description":"В свободно заполняемом атрибуте объекта обнаружено содержимое, похожее на учётные данные.","impact":["Читающий атрибут субъект может получить доступ к секрету."],"remediation":["Удалите секрет из атрибута, смените затронутые учётные данные и используйте защищённое хранилище."]},"CREDENTIAL_GPP_PASSWORD":{"description":"В предпочтениях групповой политики обнаружены параметры, потенциально раскрывающие пароль.","impact":["Чтение файлов GPP может позволить восстановить секрет и скомпрометировать учётную запись."],"remediation":["Удалите сохранённые секреты из GPP, смените пароли и применяйте современные механизмы управления учётными данными."]},"CREDENTIAL_SCRIPT_PASSWORD":{"description":"В содержимом доступного сценария обнаружен пароль или похожий секрет.","impact":["Субъект с правом чтения файла может использовать обнаруженные учётные данные."],"remediation":["Удалите секрет из сценария и переместите его в защищённое хранилище; смените обнаруженный пароль."]},"RBCD_CONFIGURED":{"description":"Для объекта настроено ограниченное делегирование Kerberos на основе ресурса (RBCD).","impact":["Настройка безопасна только при корректно ограниченном перечне доверенных субъектов."],"remediation":["Проверьте msDS-AllowedToActOnBehalfOfOtherIdentity и соответствие настроек реальной архитектуре."]},"TRUST_SID_FILTERING_DISABLED":{"description":"На доверительных отношениях отключена фильтрация SID.","impact":["SID из внешних областей доверия могут влиять на вычисление прав в ресурсном домене."],"remediation":["Включите подходящие режимы SID Filtering и согласуйте исключения с архитектурой доверия."]},"WEAK_PASSWORD_POLICY":{"description":"Доменная политика паролей не соответствует рекомендуемым параметрам стойкости или защите от перебора.","impact":["Слабые пароли повышают риск несанкционированного доступа."],"remediation":["Пересмотрите длину, историю, сложность и блокировку учётных записей с учётом современных рекомендаций Microsoft."]},"NO_ACCOUNT_LOCKOUT":{"description":"Политика блокировки учётных записей отсутствует либо её параметры допускают слишком большое число попыток.","impact":["Повышается риск атак перебором и распылением паролей."],"remediation":["Настройте порог и длительность блокировки с учётом риска отказа в обслуживании и политики организации."]},"WEAK_FGPP":{"description":"Тонкая политика паролей задаёт менее строгие параметры, чем доменная политика по умолчанию.","impact":["Затронутые пользователи и группы могут иметь более слабые пароли или защиту от перебора."],"remediation":["Сопоставьте приоритеты FGPP, область применения и требования безопасности; скорректируйте ослабленные параметры."]},"INACTIVE_PRIVILEGED_ACCOUNT":{"description":"Привилегированная учётная запись не использовалась дольше установленного порога.","impact":["Неиспользуемые административные учётные записи создают лишнюю поверхность атаки."],"remediation":["Подтвердите владельца и назначение записи, отключите ненужные записи, пересмотрите членство в группах."]},"LAPS_GPO_DISABLED":{"description":"Групповая политика отключает или не активирует механизмы управления локальными паролями LAPS.","impact":["Локальный административный пароль может оставаться неизменным."],"remediation":["Исправьте политику Windows LAPS и проверьте фактическое применение на целевых компьютерах."]},"SYSVOL_FRS_REPLICATION":{"description":"Репликация SYSVOL всё ещё использует устаревшую службу FRS.","impact":["FRS усложняет поддержку и обновление контроллеров домена; возможны проблемы согласованности политик."],"remediation":["Проведите подготовленную миграцию репликации SYSVOL на DFSR согласно документации Microsoft."]},"OLD_FUNCTIONAL_LEVEL":{"description":"Функциональный уровень домена или леса устарел.","impact":["Могут быть недоступны современные возможности и механизмы защиты AD."],"remediation":["Проверьте совместимость всех контроллеров и приложений, после чего рассмотрите повышение функционального уровня."]},"AD_RECYCLE_BIN_DISABLED":{"description":"Корзина Active Directory для леса не включена.","impact":["Восстановление удалённых объектов с сохранением атрибутов и членства в группах затруднено."],"remediation":["Оцените возможность включения корзины AD на поддерживаемом функциональном уровне леса."]},"GPO_POINTANDPRINT_EXPLOITABLE":{"description":"Параметры Point and Print позволяют устанавливать драйверы принтеров без необходимого административного подтверждения.","impact":["При определённых условиях возможен запуск кода с повышенными привилегиями (семейство PrintNightmare)."],"remediation":["Ограничьте серверы печати, требуйте повышение привилегий и примените современные параметры защиты Point and Print."]},"REGISTRY_WDIGEST":{"description":"Политика допускает сохранение учётных данных WDigest в памяти в открытом виде.","impact":["Компрометация компьютера может раскрыть пароли вошедших пользователей."],"remediation":["Отключите хранение паролей WDigest в открытом виде и проверьте соответствующий параметр реестра."]},"REGISTRY_LLMNR_ON":{"description":"Многоадресное разрешение имён LLMNR разрешено политикой.","impact":["LLMNR может упрощать перехват или ретрансляцию аутентификации в локальной сети."],"remediation":["Отключите LLMNR там, где он не требуется, и обеспечьте корректное разрешение имён DNS."]},"REGISTRY_RDP_NLA":{"description":"Политика отключает проверку подлинности на уровне сети для RDP.","impact":["Служба RDP становится доступна до полноценной проверки подлинности пользователя."],"remediation":["Включите Network Level Authentication для RDP и ограничьте сетевой доступ к службе."]},"REGISTRY_SMB1_SERVER":{"description":"На сервере включён устаревший протокол SMBv1.","impact":["Устаревший протокол повышает риск эксплуатации известных уязвимостей и ошибок безопасности."],"remediation":["Отключите SMBv1 после проверки совместимости зависимых систем."]},"REGISTRY_FIREWALL_DISABLED":{"description":"Групповая политика отключает брандмауэр Windows.","impact":["Сетевые службы могут оказаться доступнее, чем предусмотрено политикой безопасности."],"remediation":["Включите профиль брандмауэра и настройте необходимые правила разрешения трафика."]},"REGISTRY_CREDGUARD":{"description":"Через групповую политику явно отключена защита Credential Guard.","impact":["Снижается защищённость секретов проверок подлинности на конечном устройстве."],"remediation":["Проверьте совместимость оборудования и включите Credential Guard для соответствующих систем."]},"GUEST_ACCOUNT_DISABLED":{"description":"Встроенная учётная запись «Гость» (RID 501) отключена. Это сокращает возможности несанкционированного входа с использованием общей учётной записи.","impact":["Отсутствует дополнительная точка входа через стандартную гостевую учётную запись."],"remediation":["Сохраняйте учётную запись отключённой и контролируйте её состояние через утверждённые политики."]},"UNCONSTRAINED_DELEGATION_DC":{"description":"Контроллер домена использует неограниченное делегирование Kerberos, что является особым штатным случаем для функций домена. Само по себе это не эквивалентно ошибке делегирования на обычном сервере.","impact":["Компрометация контроллера домена затрагивает критическую инфраструктуру аутентификации; вывод необходимо интерпретировать с учётом роли DC."],"remediation":["Не отключайте делегирование на DC без проверки зависимостей; обеспечьте защиту контроллеров домена как систем Tier 0."]},"GPO_NOT_CURRENTLY_EFFECTIVE":{"description":"Обнаруженная настройка содержится в объекте групповой политики, но в момент аудита не считается действующей для соответствующей области.","impact":["Неактивная настройка не обязательно влияет на текущие компьютеры или пользователей, однако может вступить в силу при изменении привязок GPO."],"remediation":["Проверьте привязку, состояние GPO, наследование и фильтры безопасности; контролируйте изменения области применения."]},"PRIVILEGED_ACCOUNT_AFFECTED":{"description":"Обнаруженный параметр затрагивает привилегированную учётную запись, права которой могут распространяться на критические объекты Active Directory.","impact":["Риск выше, чем для обычной записи, поскольку её компрометация может затронуть контроллеры домена и конфигурацию леса."],"remediation":["Определите фактические роли и доступ записи; применяйте изоляцию Tier 0, MFA и принцип минимально необходимых полномочий."]},"ROASTABLE_PRIVILEGED_ACCOUNT":{"description":"Привилегированная учётная запись имеет настройки, позволяющие получить материал Kerberos для автономного подбора пароля.","impact":["Подбор пароля может открыть доступ к административным полномочиям."],"remediation":["Исключите ненужные SPN и отсутствие предварительной проверки подлинности; применяйте gMSA и длинные случайные пароли."]},"CONSTRAINED_DELEGATION_TO_DC":{"description":"Указанной службе разрешено ограниченное делегирование Kerberos к службе на контроллере домена.","impact":["Компрометация делегирующей записи может затронуть защищённые операции, выполняемые от имени пользователя на DC."],"remediation":["Проверьте msDS-AllowedToDelegateTo, необходимость делегирования и защиту учётной записи службы."]},"CONSTRAINED_DELEGATION_TRANSITION_NO_TARGET":{"description":"У службы обнаружен признак перехода протокола Kerberos, но явная цель ограниченного делегирования не определена.","impact":["Сам признак не доказывает возможность доступа к другому сервису; он требует проверки совместно с другими настройками делегирования."],"remediation":["Сверьте userAccountControl и msDS-AllowedToDelegateTo с фактическим сценарием аутентификации."]},"ESC_ENROLLMENT_RIGHTS_UNREAD":{"description":"Права регистрации сертификатов для шаблона AD CS не удалось прочитать с учётными данными аудита.","impact":["Нельзя достоверно заключить, безопасен ли шаблон или кто может запросить сертификат."],"remediation":["Повторите чтение с учётной записью с разрешённым доступом и проверьте ACL шаблона и центра сертификации."]},"ESC3_TARGET_TEMPLATE":{"description":"Шаблон может участвовать в сценарии регистрации сертификата от имени другого субъекта, если разрешено использование агента запросов и отсутствуют достаточные ограничения.","impact":["Неправильное сочетание шаблонов агента и конечного сертификата создаёт риск выдачи сертификата для чужой учётной записи."],"remediation":["Ограничьте EKU Certificate Request Agent, права регистрации, требования одобрения и допустимые целевые шаблоны."]},"ADCS_HTTP_AVAILABLE":{"description":"Веб-интерфейс регистрации сертификатов доступен по HTTP. При отсутствии дополнительных защит запросы могут передаваться без TLS.","impact":["В некоторых конфигурациях возможны перехват данных или атаки ретрансляции NTLM к веб-регистрации AD CS."],"remediation":["По возможности используйте HTTPS, Extended Protection for Authentication и ограничение NTLM; проверьте IIS и настройки AD CS."]},"ADCS_NONPRIV_ENROLLMENT":{"description":"Право регистрации сертификатов предоставлено непривилегированным пользователям или группам.","impact":["Риск зависит от EKU, возможности указания имени субъекта, одобрения заявки и дополнительных разрешений шаблона."],"remediation":["Ограничьте регистрацию действительно необходимыми группами и проверьте сочетания настроек шаблона, создающие ESC-риски."]},"ADCS_CLIENT_AUTH_EKU":{"description":"Шаблон допускает расширенное назначение ключа Client Authentication (EKU). Это само по себе не является уязвимостью.","impact":["При неверных правах регистрации и настройках имени субъекта сертификат может использоваться для нежелательной проверки подлинности."],"remediation":["Проверьте EKU совместно с правами Enroll/Autoenroll, требованиями согласования и ограничениями имени субъекта."]},"ADCS_SMARTCARD_LOGON_EKU":{"description":"Шаблон допускает EKU Smart Card Logon, позволяющий применять сертификаты для доменной проверки подлинности при соответствующих условиях.","impact":["Опасность возникает в сочетании с широкими правами регистрации или возможностью указать чужую идентичность."],"remediation":["Проверьте соответствие выдачи сертификатов политике удостоверения личности и права регистрации."]},"DANGEROUS_ACL_GENERICWRITE":{"description":"Субъекту предоставлено право GenericWrite на важном объекте Active Directory. Оно позволяет менять некоторые свойства объекта в пределах выданных прав.","impact":["Изменяемые атрибуты могут использоваться для вмешательства в работу объекта или цепочки повышения привилегий."],"remediation":["Сопоставьте ACE с владельцем процесса и объёмом задач; уберите избыточные разрешения и проверьте наследование."]},"DANGEROUS_ACL_GPO_WRITEPROPERTY":{"description":"Субъект имеет право WriteProperty на объекте GPO, что может давать возможность изменять атрибуты групповой политики.","impact":["Изменение критичных атрибутов GPO иногда приводит к распространению нежелательных настроек на компьютеры и пользователей."],"remediation":["Проверьте конкретные GUID и свойства, на которые распространяется ACE, и ограничьте право доверенными администраторами GPO."]},"DANGEROUS_ACL_GPO_WRITEPROPERTY_SCOPED":{"description":"Право WriteProperty ограничено определённым атрибутом GPO, который сам по себе не управляет применяемым содержимым политики.","impact":["Такое разрешение нельзя приравнивать к полному контролю GPO; значимость зависит от конкретного атрибута."],"remediation":["Сохраните точный ObjectType ACE в аудите и оцените, требуется ли делегировать запись этого свойства."]},"DANGEROUS_ACL_GPO_DELETE":{"description":"Субъект может удалить объект групповой политики Active Directory при наличии соответствующего разрешения.","impact":["Удаление может нарушить применение настроек безопасности и доступность политик."],"remediation":["Ограничьте Delete/DeleteTree доверенными администраторами, контролируйте изменения и резервные копии GPO."]},"DANGEROUS_ACL_GPO_EXTENDED":{"description":"На объект GPO назначено разрешение Self либо ExtendedRight. Его фактическое действие зависит от ограничений ACE и конкретного объекта.","impact":["Без анализа GUID прав нельзя считать разрешение равным полному контролю над GPO."],"remediation":["Проверьте ObjectType, область действия и необходимость делегирования конкретной операции."]},"GPO_SYSVOL_FOLDER_ORPHANED":{"description":"В SYSVOL обнаружена папка групповой политики, которой не соответствует актуальный объект GPO в каталоге.","impact":["Осиротевшая папка может содержать устаревшие сценарии, настройки или лишние доступные файлы."],"remediation":["Сопоставьте GUID папки с объектами GPO, проверьте репликацию SYSVOL и удаляйте содержимое только после резервного копирования."]},"GPO_UNLINKED_BROAD_WRITE":{"description":"Непривязанный объект GPO допускает изменение со стороны широкой группы пользователей.","impact":["Хотя GPO не применяется сейчас, его последующая привязка может распространить изменённые настройки."],"remediation":["Ограничьте запись на объект и папку SYSVOL; учитывайте будущие изменения привязок."]},"DOMAIN_ROOT_GPLINK_WRITE":{"description":"Субъект может изменять атрибут gPLink корня домена, задающий связи групповых политик.","impact":["Право позволяет влиять на набор применяемых к домену GPO и потенциально на параметры множества компьютеров."],"remediation":["Ограничьте право изменения gPLink утверждёнными администраторами домена и контролируйте изменения."]},"DOMAIN_ROOT_SID_HISTORY_WRITE":{"description":"На объекте домена делегировано право, связанное с переносом SIDHistory.","impact":["При сочетании с другими необходимыми условиями некорректное делегирование может ослаблять границы доверия учётных записей."],"remediation":["Проверьте разрешения, процедуры миграции и аудирование изменений sIDHistory."]},"DOMAIN_ROOT_REPLICA_INSTALL":{"description":"Предоставлено право DS-Install-Replica, применяемое при установке дополнительных реплик каталога.","impact":["Неверное делегирование этого права требует оценки вместе с другими разрешениями на установку DC."],"remediation":["Ограничьте право доверенными административными ролями и проверьте необходимость."]},"CRITICAL_OBJECT_CONTROL":{"description":"Обнаружены права изменения критических объектов конфигурации AD, схемы, разделов, ролей или сайтов.","impact":["Неправомерное изменение этих объектов может затронуть весь лес или несколько доменов."],"remediation":["Сопоставьте ACL с моделью Tier 0; разрешайте запись только установленным административным ролям."]},"RODC_PRIVILEGED_PASSWORD_ALLOWED":{"description":"Политика репликации паролей контроллера домена только для чтения допускает кэширование паролей привилегированных субъектов.","impact":["При компрометации RODC кэшированные секреты могут быть раскрыты."],"remediation":["Запретите репликацию секретов административных групп и проверьте фактическую политику PRP."]},"RODC_PRIVILEGED_PASSWORD_REVEALED":{"description":"На RODC уже кэшированы секреты субъектов с повышенными полномочиями.","impact":["Компрометация этого контроллера может раскрыть данные, требующие замены учётных данных."],"remediation":["Проверьте Revealed List, запретите дальнейшее кэширование и выполните реагирование по процедуре для затронутых записей."]},"RODC_DENIED_GROUP_MISSING":{"description":"Ожидаемая группа защищаемых субъектов отсутствует в списке запрета кэширования паролей RODC.","impact":["Секреты этих субъектов могут оказаться разрешёнными к кэшированию при других условиях PRP."],"remediation":["Проверьте Denied RODC Password Replication Group и итоговые разрешения репликации."]},"DOMAIN_ROOT_MAQ_WRITE":{"description":"Субъект имеет право изменять атрибут ms-DS-MachineAccountQuota, задающий лимит создания компьютеров обычными пользователями.","impact":["Изменение квоты может расширить возможность создавать компьютерные учётные записи и использовать их в цепочках атак."],"remediation":["Ограничьте запись на атрибут и согласуйте допустимую квоту с моделью управления компьютерами."]},"DOMAIN_ROOT_NON_DEFAULT_OWNER":{"description":"Владельцем корневого объекта домена указан субъект, отличный от ожидаемого администратора или защищённой группы.","impact":["Владение объектом обычно позволяет изменять его DACL, поэтому отклонение требует проверки."],"remediation":["Установите происхождение владельца и при необходимости восстановите утверждённого владельца после резервного копирования."]},"OU_NON_DEFAULT_OWNER":{"description":"Организационная единица AD имеет владельца, отличающегося от обычной модели владения.","impact":["Владелец может обладать возможностью изменения разрешений на OU независимо от отдельных ACE."],"remediation":["Проверьте назначение владения, делегирование и необходимость изменения владельца."]},"DANGEROUS_ACL_REPLICATION_NO_SECRETS":{"description":"Обнаружено разрешение на репликацию отдельных данных каталога, не дающее само по себе репликацию секретных атрибутов.","impact":["Наличие одного такого разрешения нельзя автоматически считать полноценным DCSync."],"remediation":["Проверьте сочетание DS-Replication-Get-Changes, DS-Replication-Get-Changes-All и при необходимости In-Filtered-Set."]},"DANGEROUS_ACL_REPLICATION_INERT_HALF":{"description":"Назначена лишь часть набора разрешений на репликацию Active Directory, необходимого для соответствующего сценария.","impact":["Неполный набор сам по себе может не позволять DCSync, но расширение прав впоследствии изменит риск."],"remediation":["Проверьте совокупные разрешения субъекта с учётом вложенных групп и наследования."]},"DANGEROUS_ACL_BROAD_GROUP":{"description":"Опасные разрешения на объект AD предоставлены группе с широким составом участников.","impact":["Любой действующий участник группы может получить соответствующие полномочия в зависимости от ACL и области действия."],"remediation":["Замените широкую группу специальной группой делегирования с минимальным членством."]},"GPO_SCOPE_DOMAIN_WIDE":{"description":"Объект GPO привязан к корню домена и потенциально распространяется на большую часть доменных объектов.","impact":["Ошибочная настройка или компрометация редактора GPO может иметь доменный масштаб."],"remediation":["Проверьте связи, фильтрацию, наследование, административных редакторов и область фактического применения."]},"SID_HISTORY_INJECTION":{"description":"В атрибуте sIDHistory содержится привилегированный SID, который требует подтверждения законности происхождения.","impact":["При ошибках фильтрации SID или доверительных отношений такой SID может давать нежелательные права."],"remediation":["Сверьте SID с историей миграции, настройками доверий и выполненными административными операциями."]},"SID_HISTORY_FOREIGN_PRIVILEGED":{"description":"В атрибуте sIDHistory содержится привилегированный SID из другого домена.","impact":["При неправильной настройке доверий и фильтрации SID он может влиять на авторизацию."],"remediation":["Проверьте доверительные отношения, SID filtering и документированное происхождение sIDHistory."]},"SID_HISTORY_ORPHANED":{"description":"В sIDHistory присутствует SID, который не удаётся сопоставить с ожидаемым доверенным источником.","impact":["Неопознанный SID затрудняет аудит прав и может указывать на ошибочную миграцию или нетипичное изменение."],"remediation":["Проверьте источник SID, доверия и журналы миграции, прежде чем удалять значения."]},"BITLOCKER_RECOVERY_DELEGATED":{"description":"Права чтения объектов с данными восстановления BitLocker делегированы дополнительному субъекту.","impact":["Такой доступ позволяет получить ключи восстановления дисков затронутых компьютеров."],"remediation":["Ограничьте чтение доверенным администраторам восстановления, включите аудит и контролируйте членство групп."]},"EXCHANGE_GROUP_LOW_PRIV_MEMBER":{"description":"В административной группе Exchange обнаружен участник с недостаточно обоснованными повышенными полномочиями.","impact":["Назначения Exchange и связанные с ними ACL AD могут расширять возможности управления каталога."],"remediation":["Проверьте ролевую модель Exchange, вложенные группы и реальную необходимость членства."]},"PRIVILEGED_GROUP_MEMBERSHIP":{"description":"Учётная запись состоит в привилегированной группе Active Directory.","impact":["Полученные через группу полномочия могут давать управление защищёнными объектами и контроллерами домена."],"remediation":["Подтвердите служебную необходимость членства, обеспечьте отдельные административные записи и периодическую переаттестацию."]},"OPERATOR_GROUP_MEMBERSHIP":{"description":"Учётная запись состоит в операторской группе Windows или иной группе с расширенными системными полномочиями.","impact":["В зависимости от роли группы возможен доступ к критическим службам и конфигурациям."],"remediation":["Проверьте эффективные разрешения, вложенность и назначение членства."]},"OU_PERM_WRITEPROPERTY_ALL":{"description":"На объектах в организационной единице обнаружено разрешение изменять все свойства объектов в области действия OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно неавторизованное изменение атрибутов пользователей или компьютеров."],"remediation":["Ограничьте WriteProperty набором действительно изменяемых атрибутов и соответствующих групп."]},"OU_PERM_USERACCOUNTCONTROL":{"description":"На объектах в организационной единице обнаружено право изменять userAccountControl у объектов в OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно смену состояния учётных записей или отдельных параметров аутентификации."],"remediation":["Проверьте наследуемые ACE и ограничьте запись userAccountControl."]},"OU_PERM_GROUP_MEMBERSHIP":{"description":"На объектах в организационной единице обнаружено право изменять атрибут member у групп в OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно добавление нежелательных участников в группы, на которые распространяется разрешение."],"remediation":["Ограничьте изменение членства доверенными владельцами групп и отслеживайте события."]},"OU_PERM_SCRIPTPATH":{"description":"На объектах в организационной единице обнаружено право изменять scriptPath. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно подмену выполняемого при входе сценария при наличии доступа к его расположению."],"remediation":["Ограничьте изменение scriptPath и контролируйте ACL хранилища сценариев."]},"OU_PERM_CONSTRAINED_DELEGATION":{"description":"На объектах в организационной единице обнаружено право изменять msDS-AllowedToDelegateTo. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно расширение списка служб, к которым разрешено делегирование Kerberos."],"remediation":["Ограничьте изменение целей делегирования и проверьте переход протокола."]},"OU_PERM_RBCD":{"description":"На объектах в организационной единице обнаружено право изменять msDS-AllowedToActOnBehalfOfOtherIdentity. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно нежелательное предоставление делегирования Kerberos на основе ресурса (RBCD)."],"remediation":["Ограничьте запись RBCD только доверенными администраторами объекта."]},"OU_PERM_LAPS_READ":{"description":"На объектах в организационной единице обнаружено право чтения паролей LAPS у компьютеров в OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно получение локальных административных секретов при действительном доступе."],"remediation":["Проверьте ACL LAPS, конфиденциальные атрибуты и право расшифрования Windows LAPS."]},"OU_PERM_GPLINK":{"description":"На объектах в организационной единице обнаружено право изменять gPLink в OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно подключение или отключение групповых политик для объектов OU."],"remediation":["Ограничьте делегирование gPLink администраторам групповых политик."]},"OU_PERM_CREATE_CHILD":{"description":"На объектах в организационной единице обнаружено право создавать объекты в пределах OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно создание нежелательных пользователей, групп или компьютеров в зависимости от ObjectType ACE."],"remediation":["Уточните допустимые классы объектов в ACE и полномочия делегированной группы."]},"OU_PERM_GPOPTIONS":{"description":"На объектах в организационной единице обнаружено право изменять gPOptions в OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно изменение блокирования наследования групповых политик."],"remediation":["Ограничьте запись gPOptions доверенным администраторам OU."]},"OU_PERM_GENERICWRITE":{"description":"На объектах в организационной единице обнаружено право GenericWrite в области OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно несанкционированное изменение ряда свойств защищаемых объектов."],"remediation":["Проверьте объём ACE, наследование и минимальную достаточность разрешения."]},"OU_PERM_READALL":{"description":"На объектах в организационной единице обнаружено право чтения всех свойств объектов в OU. Важны конкретные ObjectType ACE, наследование и фактический состав субъектов.","impact":["При неверном делегировании возможно раскрытие данных, для которых атрибуты не имеют отдельных ограничений конфиденциальности."],"remediation":["Проверьте необходимость широкого чтения; отдельные конфиденциальные атрибуты могут требовать специальных прав."]},"GPO_USERRIGHT_SEDEBUG":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Отладка программ» (SeDebugPrivilege) назначено через GPO сверх стандартных значений». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SETCB":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Работа в режиме операционной системы» (SeTcbPrivilege) назначено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SECREATETOKEN":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Создание объекта токена» (SeCreateTokenPrivilege) назначено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEIMPERSONATE":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Имитация клиента после проверки подлинности» (SeImpersonatePrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEASSIGNPRIMARYTOKEN":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Замена токена уровня процесса» (SeAssignPrimaryTokenPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SELOADDRIVER":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Загрузка и выгрузка драйверов устройств» (SeLoadDriverPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEBACKUP":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Архивирование файлов и каталогов» (SeBackupPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SERESTORE":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Восстановление файлов и каталогов» (SeRestorePrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SETAKEOWNERSHIP":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Смена владельцев файлов и других объектов» (SeTakeOwnershipPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEENABLEDELEGATION":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право доверия учётных записей для делегирования (SeEnableDelegationPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SESYNCAGENT":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право «Синхронизация данных службы каталогов» (SeSyncAgentPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEMANAGEVOLUME":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право обслуживания томов (SeManageVolumePrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SESECURITY":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право управления аудитом и журналом безопасности (SeSecurityPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SERELABEL":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право изменения метки объекта (SeRelabelPrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SETRUSTEDCREDMANACCESS":{"description":"Одна или несколько групповых политик назначают право пользователя: «Доступ к диспетчеру учётных данных как доверенного вызывающего (SeTrustedCredManAccessPrivilege)». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEREMOTEINTERACTIVELOGON":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право входа через службы удалённых рабочих столов (SeRemoteInteractiveLogonRight) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEINTERACTIVELOGON":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право локального входа (SeInteractiveLogonRight) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEBATCHLOGON":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право пакетного входа (SeBatchLogonRight) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SESERVICELOGON":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право входа в качестве службы (SeServiceLogonRight) назначено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SESYSTEMTIME":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право изменения системного времени (SeSystemtimePrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEREMOTESHUTDOWN":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право принудительного удалённого завершения работы (SeRemoteShutdownPrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SESHUTDOWN":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право завершения работы системы (SeShutdownPrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SECREATESYMBOLICLINK":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право создания символических ссылок (SeCreateSymbolicLinkPrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEDELEGATESESSIONUSERIMPERSONATE":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право получения токена другого пользователя в сеансе (SeDelegateSessionUserImpersonatePrivilege) выдано через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEAUDIT":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право формирования аудита безопасности (SeAuditPrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SESYSTEMENVIRONMENT":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право изменения параметров среды микропрограммы (SeSystemEnvironmentPrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SECREATEGLOBAL":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право создания глобальных объектов (SeCreateGlobalPrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SEPROFILESINGLEPROCESS":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право профилирования отдельного процесса (SeProfileSingleProcessPrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_SESYSTEMPROFILE":{"description":"Одна или несколько групповых политик назначают право пользователя: «Право профилирования производительности системы (SeSystemProfilePrivilege) расширено через GPO». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]},"GPO_USERRIGHT_DEFAULT_REMOVED":{"description":"Одна или несколько групповых политик назначают право пользователя: «Групповая политика исключает стандартного владельца права пользователя». Аудит сопоставляет назначенных субъектов и стандартные параметры Windows.","impact":["Чрезмерное назначение может расширять административные возможности или поверхность атаки; значимость зависит от конкретного права и системы назначения."],"remediation":["Проверьте действующую GPO и область применения, сопоставьте группы с базовой политикой безопасности Microsoft, уберите неутверждённые назначения."]}};
        const ruAttributeLabels = {"Domain":"Домен","Domain Name":"Имя домена","Domain DNS Name":"DNS-имя домена","Domain DN":"Отличительное имя домена (DN)","Domain SID":"SID домена","Forest":"Лес","Forest Name":"Имя леса","Forest Root Domain":"Корневой домен леса","Forest Functional Level":"Функциональный уровень леса","Domain Functional Level":"Функциональный уровень домена","Functional Level":"Функциональный уровень","Domain Controller":"Контроллер домена","Domain Controllers":"Контроллеры домена","Domain Controller Name":"Имя контроллера домена","Domain Controller IP":"IP-адрес контроллера домена","Server":"Сервер","Server Name":"Имя сервера","Site":"Сайт","Site Name":"Имя сайта","Subnet":"Подсеть","IP Address":"IP-адрес","DNS Name":"DNS-имя","DNS Host Name":"DNS-имя узла","Operating System":"Операционная система","Operating System Version":"Версия операционной системы","OS Version":"Версия ОС","OS":"ОС","OS Name":"Название ОС","Version":"Версия","Status":"Состояние","State":"Состояние","Account Status":"Состояние учётной записи","Account":"Учётная запись","Account Name":"Имя учётной записи","User":"Пользователь","Username":"Имя пользователя","User Name":"Имя пользователя","Display Name":"Отображаемое имя","Description":"Описание","Comment":"Комментарий","Computer":"Компьютер","Computer Name":"Имя компьютера","Group":"Группа","Group Name":"Имя группы","Members":"Участники","Member":"Участник","Member Count":"Количество участников","Group Membership":"Членство в группах","Primary Group":"Основная группа","Distinguished Name":"Отличительное имя (DN)","Object DN":"Отличительное имя объекта","Object Name":"Имя объекта","Object Type":"Тип объекта","Object Class":"Класс объекта","Object SID":"SID объекта","Object GUID":"GUID объекта","Object Owner":"Владелец объекта","Owner":"Владелец","Creator":"Создатель","Created":"Создано","Creation Date":"Дата создания","Created On":"Дата создания","Modified":"Изменено","Last Modified":"Последнее изменение","Last Change":"Последнее изменение","Enabled":"Включено","Disabled":"Отключено","Locked":"Заблокировано","Unlocked":"Разблокировано","Active":"Активна","Inactive":"Неактивна","Account Enabled":"Учётная запись включена","Account Disabled":"Учётная запись отключена","Password":"Пароль","Password Age":"Возраст пароля","Password Last Set":"Дата последней смены пароля","Password Changed":"Пароль изменён","Password Expiration":"Истечение срока действия пароля","Password Expires":"Срок действия пароля","Password Never Expires":"Срок действия пароля не ограничен","Password Policy":"Политика паролей","Minimum Password Length":"Минимальная длина пароля","Min Password Length":"Минимальная длина пароля","Maximum Password Age":"Максимальный срок действия пароля","Minimum Password Age":"Минимальный срок действия пароля","Password History":"История паролей","Password History Length":"Длина истории паролей","Password Complexity":"Сложность пароля","Lockout Threshold":"Порог блокировки","Lockout Duration":"Продолжительность блокировки","Lockout Observation Window":"Окно наблюдения блокировки","Bad Password Count":"Число ошибочных попыток ввода пароля","Failed Logons":"Неудачные входы","Last Logon":"Последний вход","Last Logon Date":"Дата последнего входа","Last Login":"Последний вход","Last Seen":"Последняя активность","Last Logon Timestamp":"Отметка времени последнего входа","Logon Count":"Число входов","User Account Control":"Параметры контроля учётной записи","Account Flags":"Флаги учётной записи","Security Identifier":"Идентификатор безопасности (SID)","SID History":"История SID","SID History Count":"Число SID в истории","Privileges":"Привилегии","Privilege":"Привилегия","Permissions":"Разрешения","Permission":"Разрешение","Access Rights":"Права доступа","Effective Permissions":"Действующие разрешения","Explicit Permissions":"Явные разрешения","Inherited Permissions":"Унаследованные разрешения","Inheritance":"Наследование","Inherited From":"Наследуется от","Access Control List":"Список управления доступом (ACL)","Access Control Entry":"Запись управления доступом (ACE)","ACE Count":"Количество записей ACE","ACL":"Список управления доступом (ACL)","Risk":"Риск","Risk Level":"Уровень риска","Severity":"Уровень опасности","Critical":"Критический","High":"Высокий","Medium":"Средний","Low":"Низкий","Finding":"Нарушение","Findings":"Нарушения","Warning":"Предупреждение","Warnings":"Предупреждения","Hint":"Предупреждение","Note":"Примечание","Secure":"Безопасно","Not Applicable":"Неприменимо","N/A":"Н/Д","None":"Нет","Unknown":"Неизвестно","Not Found":"Не найдено","Not Tested":"Не проверено","Not Checked":"Не проверялось","Not Available":"Недоступно","Not Configured":"Не настроено","Not Set":"Не задано","Not Required":"Не требуется","Required":"Обязательно","Allowed":"Разрешено","Denied":"Запрещено","Read":"Чтение","Write":"Запись","Full Control":"Полный доступ","Read Access":"Доступ на чтение","Write Access":"Доступ на запись","Can Read":"Может читать","Can Write":"Может изменять","Read Permissions":"Разрешения на чтение","Write Permissions":"Разрешения на запись","Access":"Доступ","Access Type":"Тип доступа","Principal":"Субъект безопасности","Security Principal":"Субъект безопасности","Trust":"Доверие","Trust Type":"Тип доверия","Trust Direction":"Направление доверия","Trust Transitivity":"Транзитивность доверия","Trusting Domain":"Доверяющий домен","Trusted Domain":"Доверенный домен","Transitive":"Транзитивное","Non-transitive":"Нетранзитивное","Kerberos":"Kerberos","TGT Lifetime":"Срок действия TGT","Ticket Lifetime":"Срок действия билета","Renewal Lifetime":"Срок обновления билета","Encryption Type":"Тип шифрования","Encryption Types":"Типы шифрования","Service Principal Name":"Имя субъекта-службы (SPN)","Service Principal Names":"Имена субъектов-служб (SPN)","SPNs":"Имена SPN","Delegation":"Делегирование","Delegation Type":"Тип делегирования","Unconstrained Delegation":"Неограниченное делегирование","Constrained Delegation":"Ограниченное делегирование","Resource-Based Constrained Delegation":"Ограниченное делегирование на основе ресурса","Certificate":"Сертификат","Certificate Authority":"Центр сертификации","Certificate Authorities":"Центры сертификации","Certificate Template":"Шаблон сертификата","Template Name":"Имя шаблона","Template":"Шаблон","Issuer":"Издатель","Subject":"Субъект","Valid From":"Действует с","Valid To":"Действует до","Not Before":"Начало срока действия","Not After":"Конец срока действия","Expiration Date":"Дата окончания срока действия","Validity Period":"Срок действия","Key Length":"Длина ключа","Key Size":"Размер ключа","Signature Algorithm":"Алгоритм подписи","Enrollment Rights":"Права регистрации","Enrollment":"Регистрация сертификата","Manager Approval":"Одобрение администратором","Enhanced Key Usage":"Расширенное назначение ключа (EKU)","Authentication":"Проверка подлинности","Authentication Method":"Метод проверки подлинности","Authentication Policy":"Политика проверки подлинности","Client Authentication":"Проверка подлинности клиента","Smart Card Logon":"Вход со смарт-картой","GPO":"Объект групповой политики (GPO)","Group Policy Object":"Объект групповой политики","Group Policy Objects":"Объекты групповой политики","GPO Name":"Имя GPO","GPO GUID":"GUID объекта GPO","GPO Status":"Состояние GPO","GPO Link":"Привязка GPO","GPO Links":"Привязки GPO","Linked OUs":"Связанные OU","Linked OUs/Domain":"Привязанные OU и домен","Applied GPOs":"Применённые GPO","Policy":"Политика","Policy Name":"Имя политики","Policy Setting":"Параметр политики","Policy Value":"Значение политики","Effective Policy":"Действующая политика","Scope":"Область действия","Scope of Management":"Область управления","File Path":"Путь к файлу","Path":"Путь","Script Path":"Путь сценария","Logon Script":"Сценарий входа","Task Name":"Имя задачи","Scheduled Tasks":"Запланированные задания","Registry Key":"Раздел реестра","Registry Value":"Значение реестра","Registry Path":"Путь реестра","Shares":"Общие ресурсы","Share Name":"Имя общего ресурса","Share Path":"Путь общего ресурса","UNC Path":"UNC-путь","Readable":"Доступно для чтения","Writable":"Доступно для записи","Read Only":"Только чтение","Number of Objects":"Количество объектов","Object Count":"Количество объектов","Total Objects":"Всего объектов","Total Count":"Общее количество","Count":"Количество","Total":"Всего","Result":"Результат","Results":"Результаты","Value":"Значение","Values":"Значения","Type":"Тип","Name":"Имя","Source":"Источник","Target":"Назначение","Origin":"Происхождение","Reason":"Причина","Details":"Подробности","Recommendation":"Рекомендация","Recommendations":"Рекомендации","Remediation":"Меры по устранению","Impact":"Последствия","Attack Path":"Вектор атаки","Attack Steps":"Этапы атаки","Command":"Команда","Command Line":"Командная строка","References":"Источники","Tools":"Инструменты","Date":"Дата","Time":"Время","Duration":"Продолжительность","Last Updated":"Последнее обновление","Scan Time":"Время аудита","Scan Duration":"Продолжительность аудита","LDAP Queries":"LDAP-запросы","LDAP Statistics":"Статистика LDAP","Queries":"Запросы","Objects":"Объекты","Affected Objects":"Затронутые объекты","Status Code":"Код состояния"};
        const ruCheckContext = {"DomainBasicInfo":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Общие сведения о домене Active Directory, лесу, SID и функциональных уровнях.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Общие сведения о домене Active Directory, лесу, SID и функциональных уровнях.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Сведения о домене"},"KerberosPolicy":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Параметры времени действия билетов Kerberos и политики для учётной записи krbtgt.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Параметры времени действия билетов Kerberos и политики для учётной записи krbtgt.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Политика Kerberos"},"GuestAccount":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Проверка встроенной учётной записи «Гость» (RID 501) и её членства в группах.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка встроенной учётной записи «Гость» (RID 501) и её членства в группах.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Состояние учётной записи «Гость»"},"DomainControllers":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Список контроллеров домена и распределение ролей FSMO.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Список контроллеров домена и распределение ролей FSMO.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Контроллеры домена и роли FSMO"},"SitesAndSubnets":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Сопоставление сайтов AD, IP-подсетей и контроллеров домена.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Сопоставление сайтов AD, IP-подсетей и контроллеров домена.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Сайты и подсети Active Directory"},"DomainPasswordPolicy":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Проверка параметров парольной политики домена по умолчанию.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка параметров парольной политики домена по умолчанию.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доменная политика паролей"},"FineGrainedPasswordPolicy":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Анализ тонких политик паролей, переопределяющих доменную политику.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ тонких политик паролей, переопределяющих доменную политику.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Тонкие политики паролей (FGPP)"},"DomainTrust":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Проверка доверительных отношений с доменами и лесами.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка доверительных отношений с доменами и лесами.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доверительные отношения домена"},"ReadableShare":{"whyItMatters":"Доступ к общим ресурсам и сценариям может раскрывать секреты или позволять изменять выполняемые файлы.","whatWeCheck":["Общие папки компьютеров домена, к которым текущая учётная запись имеет доступ на чтение.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Общие папки компьютеров домена, к которым текущая учётная запись имеет доступ на чтение.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доступные для чтения общие ресурсы"},"ShareCredential":{"whyItMatters":"Доступ к общим ресурсам и сценариям может раскрывать секреты или позволять изменять выполняемые файлы.","whatWeCheck":["Поиск учётных данных в доступных скриптах и конфигурационных файлах.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск учётных данных в доступных скриптах и конфигурационных файлах.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Учётные данные в общих папках"},"NetworkSubnet":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Анализ IP-подсетей активных компьютеров домена и их организационных единиц.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ IP-подсетей активных компьютеров домена и их организационных единиц.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Карта сети"},"OpenPorts":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Список открытых TCP-портов просканированных адресов.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Список открытых TCP-портов просканированных адресов.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Открытые сетевые порты"},"LDAPConfigGPO":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Проверка подписи LDAP и привязки канала TLS по объектам групповой политики.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка подписи LDAP и привязки канала TLS по объектам групповой политики.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Настройки подписи LDAP в GPO"},"NullSessionGPO":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Анализ настроек анонимного перечисления SAM и сопоставления SID с именами.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ настроек анонимного перечисления SAM и сопоставления SID с именами.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Параметры анонимного доступа в GPO"},"DSHeuristics":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Проверка параметров службы каталогов, которые могут ослаблять защиту леса AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка параметров службы каталогов, которые могут ослаблять защиту леса AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Параметры dsHeuristics"},"SMBSigning":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Проверка требования цифровой подписи SMB на компьютерах домена.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка требования цифровой подписи SMB на компьютерах домена.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Настройки подписи SMB"},"EffectiveLDAPConfig":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Определение фактически применённых настроек подписи LDAP и привязки канала.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Определение фактически применённых настроек подписи LDAP и привязки канала.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Действующие настройки LDAP"},"EffectiveNullSession":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Определение действующих ограничений анонимных сеансов.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Определение действующих ограничений анонимных сеансов.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Действующие параметры анонимного доступа"},"EffectiveSMBSigning":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Определение фактических требований подписи SMB.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Определение фактических требований подписи SMB.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Действующие настройки подписи SMB"},"EffectiveSMBSigningMembers":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Перечень компьютеров, на которые распространяется политика подписи SMB.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Перечень компьютеров, на которые распространяется политика подписи SMB.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Подпись SMB: затронутые компьютеры"},"SMBSigningWeakened":{"whyItMatters":"Параметры домена влияют на доверие, проверку подлинности и репликацию. Сопоставьте конфигурацию с политикой защиты Active Directory.","whatWeCheck":["Выявление настроек, снижающих требования цифровой подписи SMB.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Выявление настроек, снижающих требования цифровой подписи SMB.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Ослабление защиты SMB"},"DomainController":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Перечень контроллеров домена и их основные параметры.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Перечень контроллеров домена и их основные параметры.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Контроллеры домена"},"ExchangeServer":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Инвентаризация серверов Microsoft Exchange и их настроек.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Инвентаризация серверов Microsoft Exchange и их настроек.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Серверы Exchange"},"ExchangeServerBasic":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Базовая инвентаризация серверов Microsoft Exchange.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Базовая инвентаризация серверов Microsoft Exchange.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Серверы Exchange: основные сведения"},"ExchangeOrganization":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Анализ объектов организации Microsoft Exchange в Active Directory.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ объектов организации Microsoft Exchange в Active Directory.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Организация Exchange"},"ExchangeConfigServer":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Параметры серверов Exchange в разделе конфигурации AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Параметры серверов Exchange в разделе конфигурации AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Сервер Exchange в разделе Configuration"},"ExchangeHybridConfiguration":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка конфигурации гибридного взаимодействия Exchange с облачными сервисами.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка конфигурации гибридного взаимодействия Exchange с облачными сервисами.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Гибридное развёртывание Exchange"},"ExchangeReceiveConnector":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка принимающих соединителей SMTP и параметров аутентификации.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка принимающих соединителей SMTP и параметров аутентификации.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Принимающие SMTP-соединители Exchange"},"ExchangePermissionsModel":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Анализ модели разрешений Exchange и связанных прав в Active Directory.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ модели разрешений Exchange и связанных прав в Active Directory.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Модель разрешений Exchange"},"ExchangeRoleAssignment":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка назначений ролей RBAC в Exchange.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка назначений ролей RBAC в Exchange.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Назначения ролей управления Exchange"},"MSSQLServer":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Инвентаризация серверов SQL Server и связанных служебных учётных записей.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Инвентаризация серверов SQL Server и связанных служебных учётных записей.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Серверы Microsoft SQL Server"},"SCCMServer":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка инфраструктуры Microsoft Configuration Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка инфраструктуры Microsoft Configuration Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Инфраструктура Configuration Manager (SCCM)"},"SCCMServerBasic":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Базовая инвентаризация серверов Microsoft Configuration Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Базовая инвентаризация серверов Microsoft Configuration Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Серверы SCCM: основные сведения"},"SCCMServiceAccount":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка учётных записей служб Configuration Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка учётных записей служб Configuration Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Служебные учётные записи SCCM"},"SCCMGroup":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Анализ групп и их участников в инфраструктуре Configuration Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ групп и их участников в инфраструктуре Configuration Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Группы SCCM"},"SCCMContainerPermission":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка прав доступа к контейнеру System Management в Active Directory.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка прав доступа к контейнеру System Management в Active Directory.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Разрешения контейнера System Management"},"SCCMSite":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Параметры сайтов Microsoft Configuration Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Параметры сайтов Microsoft Configuration Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Сайты SCCM"},"SCCMManagementPoint":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Инвентаризация точек управления Configuration Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Инвентаризация точек управления Configuration Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Точки управления SCCM"},"SCCMPXEServer":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка серверов сетевой загрузки PXE и служб WDS.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка серверов сетевой загрузки PXE и служб WDS.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Серверы загрузки PXE/WDS"},"SCOMServer":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка инфраструктуры Microsoft Operations Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка инфраструктуры Microsoft Operations Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Инфраструктура Operations Manager (SCOM)"},"SCOMServerBasic":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Инвентаризация серверов Microsoft Operations Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Инвентаризация серверов Microsoft Operations Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Серверы SCOM: основные сведения"},"SCOMServiceAccount":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка прав и настроек учётных записей служб Operations Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка прав и настроек учётных записей служб Operations Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Служебные учётные записи SCOM"},"SCOMGroup":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка групп Microsoft Operations Manager.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка групп Microsoft Operations Manager.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Группы SCOM"},"ADFSServer":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Инвентаризация серверов и конфигурации Active Directory Federation Services.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Инвентаризация серверов и конфигурации Active Directory Federation Services.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Службы федерации AD FS"},"EntraConnect":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка конфигурации синхронизации идентификаторов Microsoft Entra Connect.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка конфигурации синхронизации идентификаторов Microsoft Entra Connect.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Microsoft Entra Connect"},"ExchangeTrustedSubsystem":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка привилегий группы Exchange Trusted Subsystem.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка привилегий группы Exchange Trusted Subsystem.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Группа Exchange Trusted Subsystem"},"ExchangeWindowsPermissions":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Анализ полномочий группы Exchange Windows Permissions.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ полномочий группы Exchange Windows Permissions.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Группа Exchange Windows Permissions"},"ExchangeOrganizationManagement":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Анализ участников административной группы Organization Management в Exchange.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ участников административной группы Organization Management в Exchange.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Группа Organization Management"},"ExchangeServersGroup":{"whyItMatters":"Службы приложений могут обладать высокими правами AD. Применяйте минимальные привилегии и контролируйте служебные записи.","whatWeCheck":["Проверка состава и полномочий группы Exchange Servers.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка состава и полномочий группы Exchange Servers.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Группа Exchange Servers"},"CertificateAuthority":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Инвентаризация центров сертификации Active Directory Certificate Services.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Инвентаризация центров сертификации Active Directory Certificate Services.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Центры сертификации AD CS"},"CertificateTemplate":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Проверка шаблонов сертификатов, параметров выдачи и прав регистрации.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка шаблонов сертификатов, параметров выдачи и прав регистрации.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Шаблоны сертификатов AD CS"},"PKIContainer":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Проверка списков управления доступом к контейнерам инфраструктуры открытых ключей.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка списков управления доступом к контейнерам инфраструктуры открытых ключей.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Разрешения контейнеров PKI"},"PKIInfrastructure":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Анализ компонентов инфраструктуры открытых ключей и цепочек доверия.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ компонентов инфраструктуры открытых ключей и цепочек доверия.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Инфраструктура доверия PKI"},"RootCA":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Проверка сертификатов доверенных корневых центров сертификации.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка сертификатов доверенных корневых центров сертификации.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доверенные корневые центры сертификации"},"NTAuthCertificate":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Проверка сертификатов в хранилище NTAuth леса Active Directory.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка сертификатов в хранилище NTAuth леса Active Directory.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Хранилище NTAuth"},"AIACA":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Проверка опубликованных в Active Directory сертификатов центров сертификации.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка опубликованных в Active Directory сертификатов центров сертификации.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Центры сертификации в AIA"},"UnconstrainedDelegation":{"whyItMatters":"Ошибки делегирования Kerberos могут позволять действия от имени других пользователей. Проверяйте доверенные службы и субъектов.","whatWeCheck":["Поиск учётных записей и компьютеров с неограниченным делегированием.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск учётных записей и компьютеров с неограниченным делегированием.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Неограниченное делегирование Kerberos"},"ConstrainedDelegation":{"whyItMatters":"Ошибки делегирования Kerberos могут позволять действия от имени других пользователей. Проверяйте доверенные службы и субъектов.","whatWeCheck":["Проверка разрешённых служб и параметров ограниченного делегирования.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка разрешённых служб и параметров ограниченного делегирования.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Ограниченное делегирование Kerberos"},"RBCDelegation":{"whyItMatters":"Ошибки делегирования Kerberos могут позволять действия от имени других пользователей. Проверяйте доверенные службы и субъектов.","whatWeCheck":["Анализ разрешений RBCD на целевых компьютерных объектах.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ разрешений RBCD на целевых компьютерных объектах.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Ограниченное делегирование на основе ресурса (RBCD)"},"PasswordNeverExpires":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Поиск учётных записей с запретом истечения срока действия пароля.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск учётных записей с запретом истечения срока действия пароля.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Пароли с неограниченным сроком действия"},"ReversibleEncryption":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Выявление учётных записей с хранением паролей в обратимо зашифрованном виде.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Выявление учётных записей с хранением паролей в обратимо зашифрованном виде.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Обратимое шифрование паролей"},"ComputerObjectACL":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Проверка явных разрешений на объекты компьютеров в AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка явных разрешений на объекты компьютеров в AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Явно назначенные права на компьютеры"},"CriticalObjectACL":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Анализ ACL схемы, разделов каталога и объектов ролей.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ ACL схемы, разделов каталога и объектов ролей.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права на критически важные объекты каталога"},"RODCPasswordReplication":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка кэширования и репликации паролей на контроллерах домена только для чтения.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка кэширования и репликации паролей на контроллерах домена только для чтения.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Политика репликации паролей RODC"},"PasswordNotRequired":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Выявление учётных записей с флагом PASSWD_NOTREQD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Выявление учётных записей с флагом PASSWD_NOTREQD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Учётные записи без обязательного пароля"},"InactiveAdmin":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Поиск длительно неиспользуемых привилегированных учётных записей.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск длительно неиспользуемых привилегированных учётных записей.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Неактивные административные учётные записи"},"gMSA":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Анализ настроек и использования групповых управляемых учётных записей служб.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ настроек и использования групповых управляемых учётных записей служб.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Групповые управляемые учётные записи служб (gMSA)"},"gMSAPassword":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка субъектов, которым разрешено получать управляемые пароли gMSA.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка субъектов, которым разрешено получать управляемые пароли gMSA.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права чтения паролей gMSA"},"MSA":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка традиционных управляемых учётных записей служб (sMSA).","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка традиционных управляемых учётных записей служб (sMSA).","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Автономные управляемые учётные записи служб"},"AuthNPolicySilo":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка изолированных групп применения политик проверки подлинности.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка изолированных групп применения политик проверки подлинности.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Хранилища политик проверки подлинности"},"AuthNPolicy":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Анализ настроек и назначения политик проверки подлинности.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ настроек и назначения политик проверки подлинности.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Политики проверки подлинности"},"dMSA":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка делегированных управляемых учётных записей служб.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка делегированных управляемых учётных записей служб.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Делегированные управляемые учётные записи служб (dMSA)"},"dMSALink":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка связей между dMSA и заменяемыми учётными записями.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка связей между dMSA и заменяемыми учётными записями.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Связи делегированных учётных записей dMSA"},"NonDefaultOwner":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Поиск пользовательских объектов, у которых назначен нетипичный владелец.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск пользовательских объектов, у которых назначен нетипичный владелец.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Нестандартные владельцы учётных записей"},"Tier0Account":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Оценка защиты учётных записей с доступом к критически важной инфраструктуре AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Оценка защиты учётных записей с доступом к критически важной инфраструктуре AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Защита учётных записей уровня 0 (Tier 0)"},"PrivilegedGroupMember":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Анализ состава административных и других привилегированных групп.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ состава административных и других привилегированных групп.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Участники привилегированных групп"},"OperatorGroup":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка состава встроенных операторских и широких групп доступа.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка состава встроенных операторских и широких групп доступа.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Участники операторских групп"},"SIDHistory":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка атрибута sIDHistory и включённых в него идентификаторов безопасности.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка атрибута sIDHistory и включённых в него идентификаторов безопасности.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Возможное злоупотребление sIDHistory"},"AdminSDHolderACL":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Анализ ACL AdminSDHolder и распространяемых защитных разрешений.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ ACL AdminSDHolder и распространяемых защитных разрешений.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права на объект AdminSDHolder"},"PrivilegedGroupACL":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Поиск опасных разрешений на группах, не защищённых AdminSDHolder.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск опасных разрешений на группах, не защищённых AdminSDHolder.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"ACL привилегированных групп вне AdminSDHolder"},"UnprotectedPrivilegedGroups":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Поиск административных групп за пределами защиты AdminSDHolder.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск административных групп за пределами защиты AdminSDHolder.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Привилегированные группы без защиты AdminSDHolder"},"PrivilegedAccountACL":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка прав изменения и владения административными учётными записями.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка прав изменения и владения административными учётными записями.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права управления привилегированными учётными записями"},"PrivilegedAccountsRead":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка разрешений на чтение и управление защищаемыми учётными записями.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка разрешений на чтение и управление защищаемыми учётными записями.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доступ к объектам привилегированных учётных записей"},"LogonScriptPermission":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Анализ путей сценариев входа и прав их изменения.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ путей сценариев входа и прав их изменения.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Сценарии входа учётных записей"},"PreWindows2000Access":{"whyItMatters":"Избыточные права и неверные настройки учётных записей создают пути компрометации. Особое внимание уделяйте административным и служебным записям.","whatWeCheck":["Проверка состава группы совместимого доступа с Windows 2000 и её полномочий.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка состава группы совместимого доступа с Windows 2000 и её полномочий.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Группа Pre-Windows 2000 Compatible Access"},"Kerberoastable":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Поиск учётных записей служб, для которых доступны билеты Kerberos с возможностью автономного подбора пароля.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск учётных записей служб, для которых доступны билеты Kerberos с возможностью автономного подбора пароля.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Учётные записи, допускающие Kerberoasting"},"ASREPRoastable":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Поиск учётных записей без обязательной предварительной проверки подлинности Kerberos.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск учётных записей без обязательной предварительной проверки подлинности Kerberos.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Учётные записи, допускающие AS-REP Roasting"},"UnixPassword":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Поиск потенциально чувствительных парольных атрибутов UNIX в AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск потенциально чувствительных парольных атрибутов UNIX в AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Парольные атрибуты UNIX"},"CredentialRoaming":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Анализ сохранённых в AD данных Credential Roaming.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ сохранённых в AD данных Credential Roaming.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Перемещаемые учётные данные"},"CredentialRoamingPermission":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Проверка делегированных разрешений на чтение Credential Roaming.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка делегированных разрешений на чтение Credential Roaming.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права чтения перемещаемых учётных данных"},"GPPCredential":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Поиск раскрытия паролей и других секретов в Group Policy Preferences (GPP).","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск раскрытия паролей и других секретов в Group Policy Preferences (GPP).","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Учётные данные в предпочтениях групповой политики"},"SYSVOLCredential":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Поиск паролей и секретов в доступных сценариях SYSVOL.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск паролей и секретов в доступных сценариях SYSVOL.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Учётные данные в сценариях SYSVOL"},"LAPSCredential":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Проверка разрешений на чтение паролей локальных администраторов из LAPS.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка разрешений на чтение паролей локальных администраторов из LAPS.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доступ к паролям LAPS"},"BitLockerRecoveryKey":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Проверка доступа к ключам и паролям восстановления BitLocker в AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка доступа к ключам и паролям восстановления BitLocker в AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доступ к ключам восстановления BitLocker"},"BitLockerRecoveryPermission":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Проверка субъектов с делегированными правами чтения данных восстановления BitLocker.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка субъектов с делегированными правами чтения данных восстановления BitLocker.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Делегированное чтение ключей BitLocker"},"PasswordInDescription":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Поиск учётных данных в полях описания и других свободно заполняемых атрибутах.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск учётных данных в полях описания и других свободно заполняемых атрибутах.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Пароли в текстовых атрибутах объектов"},"DeletedObject":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Проверка чтения удалённых объектов и сохранённых атрибутов.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка чтения удалённых объектов и сохранённых атрибутов.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Доступные для чтения удалённые объекты"},"DeletedObjectsReader":{"whyItMatters":"Обнаруженные секреты и возможность автономного подбора паролей повышают риск компрометации. Ограничьте доступ к результатам аудита.","whatWeCheck":["Определение субъектов, имеющих право перечислять удалённые объекты.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Определение субъектов, имеющих право перечислять удалённые объекты.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права просмотра удалённых объектов"},"DangerousACL":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Проверка опасных разрешений на корневом объекте домена.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка опасных разрешений на корневом объекте домена.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права доступа к корню домена"},"DangerousOUPermission":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Анализ ACL организационных единиц и возможных путей повышения привилегий.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ ACL организационных единиц и возможных путей повышения привилегий.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Опасные разрешения на OU"},"WeakCertificateMapping":{"whyItMatters":"Ошибки регистрации сертификатов AD CS могут влиять на проверку подлинности. Проверяйте шаблоны, EKU, разрешения и цепочки доверия.","whatWeCheck":["Проверка явного сопоставления сертификатов и возможных слабых привязок к учётным записям.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка явного сопоставления сертификатов и возможных слабых привязок к учётным записям.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Небезопасное сопоставление сертификатов"},"PasswordResetRight":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Проверка субъектов с правом сброса паролей других учётных записей.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка субъектов с правом сброса паролей других учётных записей.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права сброса паролей"},"AddComputerRight":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Проверка прав создания объектов компьютеров.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка прав создания объектов компьютеров.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Права добавления компьютеров в домен"},"GPOUserRights":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Поиск отступлений от стандартных настроек прав пользователя Windows в GPO.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск отступлений от стандартных настроек прав пользователя Windows в GPO.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Назначение прав пользователя через GPO"},"MachineAccountQuota":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Проверка параметра ms-DS-MachineAccountQuota.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка параметра ms-DS-MachineAccountQuota.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Квота создания компьютерных учётных записей"},"AddComputerGPO":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Анализ групповых политик, влияющих на право добавлять компьютеры в домен.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ групповых политик, влияющих на право добавлять компьютеры в домен.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Параметры GPO для добавления компьютеров"},"LAPSPermission":{"whyItMatters":"Ошибки делегирования прав на объекты AD могут позволить несанкционированное изменение или повышение привилегий. Проверьте ACL, наследование и вложенные группы.","whatWeCheck":["Анализ ACL, позволяющих читать пароли LAPS.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ ACL, позволяющих читать пароли LAPS.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Разрешения на чтение LAPS"},"ComputerPasswordAge":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Проверка давности изменения паролей компьютеров домена.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка давности изменения паролей компьютеров домена.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Возраст паролей компьютерных учётных записей"},"OutdatedComputer":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Поиск неподдерживаемых и устаревающих версий Windows.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск неподдерживаемых и устаревающих версий Windows.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Устаревшие версии Windows на компьютерах"},"NonDefaultComputerOwner":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Проверка собственников компьютерных объектов в AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка собственников компьютерных объектов в AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Нестандартные владельцы объектов компьютеров"},"LAPSConfiguration":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Проверка политики и параметров Windows LAPS и прежней версии LAPS.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка политики и параметров Windows LAPS и прежней версии LAPS.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Конфигурация LAPS"},"LAPSCoverage":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Оценка доли компьютеров с управлением паролем локального администратора.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Оценка доли компьютеров с управлением паролем локального администратора.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Охват компьютеров защитой LAPS"},"GPOPermission":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Проверка списков управления доступом к объектам групповой политики.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка списков управления доступом к объектам групповой политики.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Разрешения на объекты GPO"},"GPOLocalGroup":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Анализ добавления учётных записей в локальные группы посредством GPO.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ добавления учётных записей в локальные группы посредством GPO.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Назначение участников локальных групп через GPO"},"GPOSuppressedGroup":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Перечень результатов, сознательно исключённых согласно условиям проверки.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Перечень результатов, сознательно исключённых согласно условиям проверки.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Объекты, исключённые из этой проверки"},"GPOScheduledTask":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Проверка задач, создаваемых и настраиваемых групповыми политиками.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка задач, создаваемых и настраиваемых групповыми политиками.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Запланированные задания в GPO"},"GPOScriptPath":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Проверка сценариев запуска и входа, заданных через GPO.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка сценариев запуска и входа, заданных через GPO.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Пути сценариев в GPO"},"GPORegistrySetting":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Анализ параметров реестра, устанавливаемых объектами групповой политики.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Анализ параметров реестра, устанавливаемых объектами групповой политики.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Параметры реестра в GPO"},"GPORegistryValue":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Проверка значений реестра, изменяемых групповыми политиками.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка значений реестра, изменяемых групповыми политиками.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Значения реестра в GPO"},"PointAndPrintPolicy":{"whyItMatters":"Параметры групповой политики действуют на множество компьютеров и пользователей. Оцените область действия, владельцев и права на SYSVOL.","whatWeCheck":["Проверка ограничений Point and Print для установки драйверов принтеров.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка ограничений Point and Print для установки драйверов принтеров.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Политики установки драйверов Point and Print"},"LAPSStalePassword":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Поиск паролей LAPS, не сменявшихся в установленный срок.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Поиск паролей LAPS, не сменявшихся в установленный срок.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Пароли LAPS, переставшие обновляться"},"LAPSGPOConfig":{"whyItMatters":"Настройки компьютеров и их учётных записей влияют на защиту паролей, администрирование и риск бокового перемещения.","whatWeCheck":["Проверка параметров Windows LAPS, заданных в GPO.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Проверка параметров Windows LAPS, заданных в GPO.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Параметры LAPS в групповых политиках"},"BloodHoundCollector":{"whyItMatters":"Граф отношений выявляет возможные цепочки доступа и повышения привилегий. Данные о структуре домена следует защищать.","whatWeCheck":["Сбор графа отношений между объектами, группами и разрешениями AD.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Сбор графа отношений между объектами, группами и разрешениями AD.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Сбор данных BloodHound"},"LDAPStatisticsModule":{"whyItMatters":"Оцените фактические значения и применимость рекомендаций к архитектуре вашего домена.","whatWeCheck":["Количество LDAP-запросов и объём данных по каждому модулю.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Количество LDAP-запросов и объём данных по каждому модулю.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Статистика LDAP по модулям"},"LDAPStatisticsTotal":{"whyItMatters":"Оцените фактические значения и применимость рекомендаций к архитектуре вашего домена.","whatWeCheck":["Сводное количество LDAP-запросов, результатов и переданных данных.","Проверенные параметры и обнаруженные объекты приведены в карточках результатов."],"secureMessage":"Проверяемая конфигурация классифицирована как безопасная.","summary":"Сводное количество LDAP-запросов, результатов и переданных данных.","filteringNote":"Некоторые штатные разрешения привилегированных записей скрыты; для их отображения включите -IncludePrivileged.","title":"Общая статистика LDAP"}};
        Object.keys(ruCheckContext).forEach(function(id) {
            const check = checkDescriptions[id];
            const ru = ruCheckContext[id];
            if (!check) return;
            check.originalEnglish = {
                whyItMatters: check.whyItMatters,
                whatWeCheck: check.whatWeCheck,
                secureMessage: check.secureMessage,
                filteringNote: check.filteringNote
            };
            check.title = ru.title;
            check.summary = ru.summary;
            check.whyItMatters = ru.whyItMatters;
            check.whatWeCheck = ru.whatWeCheck;
            if (check.secureMessage) check.secureMessage = ru.secureMessage;
            if (check.filteringNote) check.filteringNote = ru.filteringNote;
        });
        document.addEventListener('DOMContentLoaded', function() {
            // Translate visible finding titles by exact text match. Never modify
            // LDAP/JSON data attributes, IDs, links, or code/command fragments.
            const englishTitleMap = Object.create(null);
            Object.keys(ruFindingTitles).forEach(function(fid) {
                const finding = findingDefinitions[fid];
                if (finding && typeof finding.title === 'string') {
                    englishTitleMap[finding.title.trim()] = ruFindingTitles[fid];
                }
            });
            const auditRoot = document.querySelector('.report-content') ||
                              document.querySelector('main') || document.body;
            const walker = document.createTreeWalker(auditRoot, NodeFilter.SHOW_TEXT);
            let textNode;
            while ((textNode = walker.nextNode())) {
                const parent = textNode.parentElement;
                if (!parent || parent.closest('script,style,pre,code,textarea')) continue;
                const original = textNode.nodeValue;
                const label = original.trim();
                if (Object.prototype.hasOwnProperty.call(englishTitleMap, label)) {
                    const prefix = original.slice(0, original.indexOf(label));
                    const suffix = original.slice(original.indexOf(label) + label.length);
                    textNode.nodeValue = prefix + englishTitleMap[label] + suffix;
                }
            }
            document.querySelectorAll('.attr-name').forEach(function(node) {
                const name = node.textContent.trim();
                const colon = name.endsWith(':') ? ':' : '';
                const key = colon ? name.slice(0,-1).trim() : name;
                if(Object.prototype.hasOwnProperty.call(ruAttributeLabels,key)) {
                    node.textContent = ruAttributeLabels[key] + colon;
                }
            });
            const statuses = {
                'Yes':'Да','No':'Нет','True':'Истина','False':'Ложь',
                'Enabled':'Включено','Disabled':'Отключено',
                'Not Set':'Не задано','Not Configured':'Не настроено',
                'Not Found':'Не найдено','Not Tested':'Не проверено',
                'Unknown':'Неизвестно','None':'Нет','N/A':'Н/Д',
                'Required':'Обязательно','Allowed':'Разрешено','Denied':'Запрещено'
            };
            document.querySelectorAll('.attr-value span').forEach(function(node) {
                if(node.children.length) return;
                const key = node.textContent.trim();
                if(Object.prototype.hasOwnProperty.call(statuses,key)){
                    node.textContent = statuses[key];
                }
            });
        });
        // Scoring context data for context-aware risk calculation
        const scoringContext = {{SCORING_CONTEXT_JSON}};

        document.addEventListener('DOMContentLoaded', function() {
            // Favicon: adPEAS logo as 32x32 PNG via Blob URL (works on file:// protocol)
            (function() {
                try {
                    var b64 = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAKVSURBVFhH7dHJS9RhHMfxz0xjOjIzbjluiSaCYqBWmkqOhmmUW7hkOU3u5kxu4zb5y1HDMVxGC/diXDLNykuFWZpgZBch6A+I7gXRpVNB8gm9+YOiDtXl9zo+z5fnDd8HkEgkEsmfKwQQKj78l9IBzAA4AsAVQCKASPHQ35aLE4WzWPvyLmZqndp7b4mNLYd4aNuVSZfoi83u8QDcAIqvd6vsdktvGfFZNto0gjDhmTe+oTZahn2rC0xeMeVWz/AHrzIPTSwdS7bdDQyWR8Uvo6qHpwcfMrR3gUjVb7/eb7EnPOqaDV4vNLs/bhnz2hx54UNhPJDnajzfF1s83hha3DZzjMqD4vYO84B2uMqmYYnViVcd3px46cf2yQBmlaqpb1JvOdZieWs1muUdnt+CQkB9kTONgj+zz4PhYaDPfgVN1w7w+nwQLzTso6nLj2Z7APMvuzGzzJnZVXLqcrGq08FZ3N7ROLo3pXNORcuYB+v7fVnb488yQcvMIg/qzd6st/uxrs+PhkZvhkQoGZuiYYZBy4STGgaHuTLfqGVdbwBNNl+WCB4sqFcyq1LGjHLwVDE+pxSgw2qFTNzdpWMB5sHniq+DKwreWFHSvqRi96KKbTOutN5RsW1KTcGhZuOwiqXtziwSXFjW4coau5pNoyo2jijZMOpEYWYPqwdkzK3BpzQDhiLiEC5u/VRWBeIqbLA3jeN126z8Q+s0vjffBrsW5exbUrD/qYKd92W0zoEDzxQcXHFizxM5W6fBtlkZ2+flNPXhY5oeQxoNDgNwEjd+1/ZfBQZF4mhkEjJjUmGIT8elxGzUxqXDEn8aNl0ebiafxcTxAkwm5cChO4OBqCRUAogAIAd2Vv7rtUskEolE8j/9AG6P+zF32FIuAAAAAElFTkSuQmCC';
                    var byteStr = atob(b64);
                    var bytes = new Uint8Array(byteStr.length);
                    for (var i = 0; i < byteStr.length; i++) bytes[i] = byteStr.charCodeAt(i);
                    var blob = new Blob([bytes], { type: 'image/png' });
                    var url = URL.createObjectURL(blob);
                    var link = document.createElement('link');
                    link.rel = 'icon';
                    link.type = 'image/png';
                    link.href = url;
                    document.head.appendChild(link);
                } catch(e) { /* favicon setup failed, non-critical */ }
            })();

            // Theme: Check system preference first, then localStorage, then default
            let savedTheme = safeGetItem('adpeas-theme');
            if (!savedTheme) {
                // Auto-detect system preference
                if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
                    savedTheme = 'light';
                } else {
                    savedTheme = '{{DEFAULT_THEME}}';
                }
            }
            document.documentElement.setAttribute('data-theme', savedTheme);
            updateThemeUI(savedTheme);

            // Listen for system theme changes
            if (window.matchMedia) {
                window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', function(e) {
                    // Only auto-switch if user hasn't manually set a preference
                    if (!safeGetItem('adpeas-theme')) {
                        const newTheme = e.matches ? 'light' : 'dark';
                        document.documentElement.setAttribute('data-theme', newTheme);
                        updateThemeUI(newTheme);
                    }
                });
            }

            // Debounced search input to prevent performance issues on large reports
            let searchDebounceTimer = null;
            document.getElementById('searchInput').addEventListener('input', function(e) {
                clearTimeout(searchDebounceTimer);
                searchDebounceTimer = setTimeout(() => {
                    currentSearchQuery = e.target.value.toLowerCase();
                    applyFilters();
                }, UI_CONSTANTS.SEARCH_DEBOUNCE_DELAY);
            });

            // Initialize finding tooltips
            initFindingTooltips();

            // Initialize check help tooltips
            initCheckTooltips();

            // Initialize score breakdown tooltips
            initScoreTooltips();

            // Initialize draggable tooltips/popups
            initDraggableTooltips();

            // Initialize checkbox system
            initCheckboxSystem();

            // Initialize keyboard shortcuts
            initKeyboardShortcuts();

            // Create shortcut help modal
            createShortcutHelpModal();

            // Generate Top Priority Actions
            generateTopPriorityActions();

            // Populate score badges on finding cards, then sort by score
            populateCardScores();
            sortCardsByScore();

            // Initialize attribute drag & drop reordering
            initAttributeDragAndDrop();

            // Initialize per-card name-column resizing
            initColumnResize();
        });

        let activeTooltip = null;

        function initFindingTooltips() {
            // Create tooltip container
            const tooltipDiv = document.createElement('div');
            tooltipDiv.id = 'findingTooltip';
            tooltipDiv.className = 'finding-tooltip';
            tooltipDiv.setAttribute('role', 'dialog');
            tooltipDiv.setAttribute('aria-modal', 'false');
            tooltipDiv.setAttribute('aria-label', 'Подробности нарушения');
            document.body.appendChild(tooltipDiv);

            // Add event listeners to all finding triggers
            document.querySelectorAll('[data-finding-id]').forEach(trigger => {
                trigger.classList.add('finding-tooltip-trigger');
                trigger.setAttribute('role', 'button');
                trigger.setAttribute('tabindex', '0');
                trigger.setAttribute('aria-haspopup', 'dialog');
                trigger.setAttribute('aria-expanded', 'false');

                // Click handler
                trigger.addEventListener('click', function(e) {
                    e.stopPropagation();
                    showFindingTooltip(this, this.dataset.findingId);
                });

                // Keyboard handler for accessibility
                trigger.addEventListener('keydown', function(e) {
                    if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        e.stopPropagation();
                        showFindingTooltip(this, this.dataset.findingId);
                    }
                });
            });

            // Close tooltip when clicking outside
            document.addEventListener('click', function(e) {
                if (activeTooltip && !e.target.closest('.finding-tooltip') && !e.target.closest('[data-finding-id]')) {
                    hideTooltip();
                }
            });

            // Close on escape key
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape' && activeTooltip) {
                    hideTooltip();
                }
            });
        }

        let activeFindingTrigger = null;

        function showFindingTooltip(trigger, findingId) {
            const tooltip = document.getElementById('findingTooltip');
            const finding = findingDefinitions[findingId];

            if (!finding) {
                console.warn('Finding definition not found:', findingId);
                return;
            }

            // Close any previously open tooltip first
            if (activeFindingTrigger && activeFindingTrigger !== trigger) {
                activeFindingTrigger.setAttribute('aria-expanded', 'false');
            }

            // Get actual severity using hybrid approach (Option C):
            // 1. First: Check the trigger element itself for severity class (e.g., <span class="finding" data-finding-id="...">)
            // 2. Then: Check the attr-value div for severity class
            // 3. Fallback: Use parent card's severity
            // 4. Final fallback: Use static definition severity
            let actualSeverity = null;

            // Check severity class directly on the trigger element (most precise - for multi-value attributes)
            // HTML: <span class="finding" data-finding-id="PRIVILEGED_GROUP_MEMBERSHIP">Domain Admins</span>
            if (trigger.classList.contains('finding')) {
                actualSeverity = 'finding';
            } else if (trigger.classList.contains('hint')) {
                actualSeverity = 'hint';
            } else if (trigger.classList.contains('note')) {
                actualSeverity = 'note';
            } else if (trigger.classList.contains('secure')) {
                actualSeverity = 'secure';
            }

            // Check for attribute-level severity on attr-value div (for single-value attributes)
            if (!actualSeverity) {
                const attrValue = trigger.closest('.attr-value');
                if (attrValue) {
                    if (attrValue.classList.contains('finding')) {
                        actualSeverity = 'finding';
                    } else if (attrValue.classList.contains('hint')) {
                        actualSeverity = 'hint';
                    } else if (attrValue.classList.contains('note')) {
                        actualSeverity = 'note';
                    } else if (attrValue.classList.contains('secure')) {
                        actualSeverity = 'secure';
                    }
                }
            }

            // Fallback to card severity if no attribute severity found
            if (!actualSeverity) {
                const parentCard = trigger.closest('.finding-card');
                actualSeverity = parentCard?.dataset?.severity || null;
            }

            // Build tooltip HTML with actual severity override
            tooltip.innerHTML = buildTooltipHtml(finding, findingId, actualSeverity);

            // Make visible first (but off-screen) so we can measure
            tooltip.style.visibility = 'hidden';
            tooltip.classList.add('visible');

            // Position tooltip (now we can measure correctly)
            positionTooltip(tooltip, trigger);

            // Make fully visible
            tooltip.style.visibility = 'visible';
            activeTooltip = tooltip;
            activeFindingTrigger = trigger;

            // Update ARIA state
            trigger.setAttribute('aria-expanded', 'true');

            // Add section toggle listeners
            tooltip.querySelectorAll('.tooltip-section-title').forEach(title => {
                title.addEventListener('click', function() {
                    this.classList.toggle('collapsed');
                    const content = this.nextElementSibling;
                    content.classList.toggle('collapsed');
                });
            });
        }

        function hideTooltip() {
            const tooltip = document.getElementById('findingTooltip');
            tooltip.classList.remove('visible');
            activeTooltip = null;

            // Reset ARIA expanded state on trigger
            if (activeFindingTrigger) {
                activeFindingTrigger.setAttribute('aria-expanded', 'false');
                activeFindingTrigger = null;
            }
        }

        function positionTooltip(tooltip, trigger) {
            const rect = trigger.getBoundingClientRect();
            const viewportWidth = window.innerWidth;
            const viewportHeight = window.innerHeight;

            // Reset position for measurement
            tooltip.style.left = '0';
            tooltip.style.top = '0';

            // Get tooltip dimensions
            const tooltipRect = tooltip.getBoundingClientRect();

            // Calculate position - prefer below and to the right of trigger
            let left = rect.left;
            let top = rect.bottom + 8;

            // Adjust if too far right
            if (left + tooltipRect.width > viewportWidth - UI_CONSTANTS.VIEWPORT_PADDING) {
                left = viewportWidth - tooltipRect.width - 20;
            }

            // Adjust if too far left
            if (left < UI_CONSTANTS.VIEWPORT_PADDING) {
                left = UI_CONSTANTS.VIEWPORT_PADDING;
            }

            // Adjust if too far down - show above instead
            if (top + tooltipRect.height > viewportHeight - UI_CONSTANTS.VIEWPORT_PADDING) {
                top = rect.top - tooltipRect.height - 8;
            }

            // Ensure top is not negative
            if (top < UI_CONSTANTS.VIEWPORT_PADDING) {
                top = UI_CONSTANTS.VIEWPORT_PADDING;
            }

            tooltip.style.left = left + 'px';
            tooltip.style.top = top + 'px';
        }

        function buildTooltipHtml(finding, findingId, actualSeverity) {
            const ruExtra = ruFindingExplanations[findingId] || {};
            const titleRu = ruFindingTitles[findingId] || finding.title;
            const isSecureRu = actualSeverity === 'secure' ||
                (finding.risk && finding.risk.toLowerCase() === 'secure');
            const descriptionRu = ruExtra.description ||
                ('Краткое русское пояснение: ' + titleRu + '. Для оценки конкретных условий используйте данные карточки и полный технический оригинал EN.');
            const impactRu = ruExtra.impact || (isSecureRu ?
                ['Обнаруженный параметр соответствует ожидаемому безопасному состоянию.'] :
                ['Последствия зависят от полномочий затронутого субъекта и области действия настройки.']);
            const remediationRu = ruExtra.remediation || (isSecureRu ?
                ['Сохраните действующие защитные настройки и проверяйте их после изменений инфраструктуры.'] :
                ['Проверьте необходимость настройки и соответствие принципу минимальных привилегий. Для исправления опирайтесь на документацию Microsoft и действующие политики организации.']);
            const attackRu = ruExtra.attack || [];
            // Map card severity to display label and CSS class
            // actualSeverity comes from parent card's data-severity attribute
            // If provided, it overrides the static finding.risk from definition
            // Maps SeverityClasses (from adPEAS-Types.ps1) to display labels and CSS classes
            // These values are used for tooltip badges and match the central definitions
            const severityMap = {
                'finding': { label: 'НАРУШЕНИЕ', class: 'finding' },
                'hint': { label: 'ПРЕДУПРЕЖДЕНИЕ', class: 'hint' },
                'note': { label: 'СВЕДЕНИЯ', class: 'note' },
                'secure': { label: 'БЕЗОПАСНО', class: 'secure' }  // Blue in CSS
            };

            let riskLabel, riskClass;
            if (actualSeverity && severityMap[actualSeverity]) {
                // Use actual severity from parent card (dynamic)
                riskLabel = severityMap[actualSeverity].label;
                riskClass = severityMap[actualSeverity].class;
            } else {
                // Fallback to static definition
                riskLabel = finding.risk;
                riskClass = finding.risk.toLowerCase();
            }

            let html = `
                <div class="tooltip-header">
                    <div>
                        <div class="tooltip-title">${escapeHtml(ruFindingTitles[findingId] || finding.title)}</div>
                        <span class="tooltip-risk ${riskClass}">${escapeHtml(riskLabel)}</span>
                    </div>
                    <button class="tooltip-close" onclick="hideTooltip()">&times;</button>
                </div>
                <div class="tooltip-body">
            `;

            // Description
            html += `
                <div class="tooltip-section">
                    <div class="tooltip-section-title">
                        <span class="toggle-icon">&#9660;</span> Описание
                    </div>
                    <div class="tooltip-section-content">
                        ${escapeHtml(descriptionRu)}
                    </div>
                </div>
            `;

            // Impact (collapsed by default)
            if (impactRu && impactRu.length > 0) {
                html += `
                    <div class="tooltip-section">
                        <div class="tooltip-section-title collapsed">
                            <span class="toggle-icon">&#9660;</span> Последствия
                        </div>
                        <div class="tooltip-section-content collapsed">
                            <ul>
                                ${impactRu.map(i => `<li>${escapeHtml(i)}</li>`).join('')}
                            </ul>
                        </div>
                    </div>
                `;
            }

            // Attack/Protection section (collapsible by default)
            // For "Secure" findings, this section describes what attacks are prevented
            if (attackRu && attackRu.length > 0) {
                const isSecure = actualSeverity === 'secure' || (finding.risk && finding.risk.toLowerCase() === 'secure');
                const attackSectionTitle = isSecure ? 'Предотвращаемые угрозы' : 'Этапы атаки';
                html += `
                    <div class="tooltip-section">
                        <div class="tooltip-section-title collapsed">
                            <span class="toggle-icon">&#9660;</span> ${attackSectionTitle}
                        </div>
                        <div class="tooltip-section-content collapsed">
                            <ul>
                                ${attackRu.map(a => `<li>${escapeHtml(a)}</li>`).join('')}
                            </ul>
                        </div>
                    </div>
                `;
            }

            // Remediation / Best Practices section
            // For "Secure" findings, this section describes how to maintain the secure configuration
            if (remediationRu && remediationRu.length > 0) {
                const isSecureConfig = actualSeverity === 'secure' || (finding.risk && finding.risk.toLowerCase() === 'secure');
                const remediationTitle = isSecureConfig ? 'Поддержание защиты' : 'Меры по устранению';
                html += `
                    <div class="tooltip-section">
                        <div class="tooltip-section-title collapsed">
                            <span class="toggle-icon">&#9660;</span> ${remediationTitle}
                        </div>
                        <div class="tooltip-section-content collapsed">
                            <ul>
                                ${remediationRu.map(r => `<li>${escapeHtml(r)}</li>`).join('')}
                            </ul>
                        </div>
                    </div>
                `;
            }

            // Remediation Commands (PowerShell with Copy button)
            if (finding.remediationCommands && finding.remediationCommands.length > 0) {
                html += `
                    <div class="tooltip-section">
                        <div class="tooltip-section-title collapsed">
                            <span class="toggle-icon">&#9660;</span> Команды исправления
                        </div>
                        <div class="tooltip-section-content collapsed">
                            <div class="remediation-disclaimer">&#9888; Команды приведены как примеры. Перед применением проверьте их в тестовой среде и адаптируйте к вашей инфраструктуре.</div>
                            ${finding.remediationCommands.map(cmd => `
                                <div class="remediation-command">
                                    <div class="remediation-command-desc">${escapeHtml(cmd.description)}</div>
                                    <div class="remediation-code">
                                        <button class="copy-btn" onclick="copyToClipboard(this, \`${cmd.command.replace(/`/g, '\\`').replace(/\\/g, '\\\\')}\`)">Копировать</button>
                                        <pre>${escapeHtml(cmd.command)}</pre>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `;
            }

            // References (collapsible by default)
            if (finding.references && finding.references.length > 0) {
                html += `
                    <div class="tooltip-section">
                        <div class="tooltip-section-title collapsed">
                            <span class="toggle-icon">&#9660;</span> Источники
                        </div>
                        <div class="tooltip-section-content collapsed tooltip-references">
                            ${finding.references.map(r => `<a href="${escapeHtml(r.url)}" target="_blank" rel="noopener">${escapeHtml(r.title)}</a>`).join('')}
                        </div>
                    </div>
                `;
            }

            // Tools (collapsible by default) - supports both string and object format
            if (finding.tools && finding.tools.length > 0) {
                html += `
                    <div class="tooltip-section">
                        <div class="tooltip-section-title collapsed">
                            <span class="toggle-icon">&#9660;</span> Инструменты
                        </div>
                        <div class="tooltip-section-content collapsed tooltip-tools">
                            ${finding.tools.map(t => {
                                // Support both string (legacy) and object format {name, url}
                                if (typeof t === 'object' && t.name) {
                                    if (t.url) {
                                        return `<a href="${escapeHtml(t.url)}" target="_blank" rel="noopener" class="tooltip-tool tooltip-tool-link">${escapeHtml(t.name)}</a>`;
                                    } else {
                                        return `<span class="tooltip-tool">${escapeHtml(t.name)}</span>`;
                                    }
                                } else {
                                    return `<span class="tooltip-tool">${escapeHtml(t)}</span>`;
                                }
                            }).join('')}
                        </div>
                    </div>
                `;
            }

            html += '<details class="tooltip-section" lang="en">' +
                '<summary>Полное техническое описание (оригинал EN)</summary>' +
                '<p>' + escapeHtml(finding.description) + '</p>' +
                (finding.impact ? '<p>Impact</p><ul>' + finding.impact.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.attack ? '<p>Attack</p><ul>' + finding.attack.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.remediation ? '<p>Remediation</p><ul>' + finding.remediation.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                '</details>';
            // MITRE ATT&CK
            if (finding.mitre) {
                const mitreUrl = `https://attack.mitre.org/techniques/${finding.mitre.replace('.', '/')}/`;
                html += `
                    <div class="tooltip-section">
                        <div class="tooltip-section-content">
                            <span class="tooltip-mitre">
                                <a href="${mitreUrl}" target="_blank" rel="noopener">MITRE ATT&CK: ${escapeHtml(finding.mitre)}</a>
                            </span>
                        </div>
                    </div>
                `;
            }

            html += '</div>';
            return html;
        }

        function escapeHtml(text) {
            if (!text) return '';
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        // Escape JSON for use in HTML data attributes
        // Uses single quotes in HTML attribute, escapes single quotes in JSON
        function escapeJsonForAttr(obj) {
            if (!obj) return '';
            const json = JSON.stringify(obj);
            // Replace single quotes with escaped version for safe embedding
            return json.replace(/'/g, '&#39;');
        }

        // Decode HTML entities in a string (for parsing data attributes)
        function decodeHtmlEntities(str) {
            if (!str) return '';
            const txt = document.createElement('textarea');
            txt.innerHTML = str;
            return txt.value;
        }

        // Check description tooltip functionality
        let activeCheckTooltip = null;

        let activeCheckTrigger = null;

        function initCheckTooltips() {
            // Create check tooltip container
            const tooltipDiv = document.createElement('div');
            tooltipDiv.id = 'checkTooltip';
            tooltipDiv.className = 'check-tooltip';
            tooltipDiv.setAttribute('role', 'dialog');
            tooltipDiv.setAttribute('aria-modal', 'false');
            tooltipDiv.setAttribute('aria-label', 'Описание проверки');
            document.body.appendChild(tooltipDiv);

            // Add event listeners to all check help buttons
            document.querySelectorAll('.check-help-btn').forEach(btn => {
                btn.setAttribute('aria-haspopup', 'dialog');
                btn.setAttribute('aria-expanded', 'false');
                btn.setAttribute('aria-label', 'Описание проверки');

                btn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    // Prefer ObjectType over title for tooltip lookup (more reliable)
                    const objectType = btn.dataset.objectType;
                    const checkTitle = btn.dataset.checkTitle;
                    showCheckTooltip(this, objectType, checkTitle);
                });

                // Keyboard support
                btn.addEventListener('keydown', function(e) {
                    if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        e.stopPropagation();
                        const objectType = btn.dataset.objectType;
                        const checkTitle = btn.dataset.checkTitle;
                        showCheckTooltip(this, objectType, checkTitle);
                    }
                });
            });

            // Close tooltip when clicking outside
            document.addEventListener('click', function(e) {
                if (activeCheckTooltip && !e.target.closest('.check-tooltip') && !e.target.closest('.check-help-btn')) {
                    hideCheckTooltip();
                }
            });

            // Close on escape key (consistent with finding tooltip)
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape' && activeCheckTooltip) {
                    hideCheckTooltip();
                }
            });
        }

        function showCheckTooltip(trigger, objectType, checkTitle) {
            const tooltip = document.getElementById('checkTooltip');

            // Look up check description by ObjectType
            if (!objectType || !checkDescriptions[objectType]) {
                console.warn('Check description not found for ObjectType:', objectType);
                return;
            }

            const check = checkDescriptions[objectType];
            const lookupKey = objectType;

            // Get card severity from parent finding-card element
            const findingCard = trigger.closest('.finding-card');
            const cardSeverity = findingCard ? findingCard.dataset.severity : null;

            // Build tooltip HTML (pass severity for secure message display)
            tooltip.innerHTML = buildCheckTooltipHtml(check, checkTitle, cardSeverity);

            // Make visible first (but off-screen) so we can measure
            tooltip.style.visibility = 'hidden';
            tooltip.classList.add('visible');

            // Position tooltip (now we can measure correctly)
            positionCheckTooltip(tooltip, trigger);

            // Make fully visible
            tooltip.style.visibility = 'visible';
            activeCheckTooltip = tooltip;

            // Close any previous trigger and update ARIA
            if (activeCheckTrigger && activeCheckTrigger !== trigger) {
                activeCheckTrigger.setAttribute('aria-expanded', 'false');
            }
            activeCheckTrigger = trigger;
            trigger.setAttribute('aria-expanded', 'true');
        }

        function hideCheckTooltip() {
            const tooltip = document.getElementById('checkTooltip');
            tooltip.classList.remove('visible');

            // Reset ARIA state
            if (activeCheckTrigger) {
                activeCheckTrigger.setAttribute('aria-expanded', 'false');
                activeCheckTrigger = null;
            }
            activeCheckTooltip = null;
        }

        // Reuse the same positioning function for check tooltips
        function positionCheckTooltip(tooltip, trigger) {
            positionTooltip(tooltip, trigger);
        }

        // ============================================================
        // DRAGGABLE TOOLTIPS/POPUPS
        // ============================================================

        let dragState = {
            isDragging: false,
            tooltip: null,
            offsetX: 0,
            offsetY: 0
        };

        function initDraggableTooltips() {
            // Handle mousedown on tooltip headers
            document.addEventListener('mousedown', function(e) {
                const header = e.target.closest('.tooltip-header, .check-tooltip-header');
                if (!header) return;

                // Don't drag if clicking on close button
                if (e.target.closest('.tooltip-close, .check-tooltip-close')) return;

                const tooltip = header.closest('.finding-tooltip, .check-tooltip');
                if (!tooltip || !tooltip.classList.contains('visible')) return;

                e.preventDefault();
                dragState.isDragging = true;
                dragState.tooltip = tooltip;

                // Get current position (could be from CSS or previous drag)
                const rect = tooltip.getBoundingClientRect();
                dragState.offsetX = e.clientX - rect.left;
                dragState.offsetY = e.clientY - rect.top;

                tooltip.classList.add('dragging');
            });

            document.addEventListener('mousemove', function(e) {
                if (!dragState.isDragging || !dragState.tooltip) return;

                e.preventDefault();

                // Calculate new position
                let newX = e.clientX - dragState.offsetX;
                let newY = e.clientY - dragState.offsetY;

                // Keep within viewport bounds
                const tooltipRect = dragState.tooltip.getBoundingClientRect();
                const maxX = window.innerWidth - tooltipRect.width;
                const maxY = window.innerHeight - tooltipRect.height;

                newX = Math.max(0, Math.min(newX, maxX));
                newY = Math.max(0, Math.min(newY, maxY));

                dragState.tooltip.style.left = newX + 'px';
                dragState.tooltip.style.top = newY + 'px';
            });

            document.addEventListener('mouseup', function() {
                if (dragState.isDragging && dragState.tooltip) {
                    dragState.tooltip.classList.remove('dragging');
                }
                dragState.isDragging = false;
                dragState.tooltip = null;
            });

            // Prevent text selection while dragging
            document.addEventListener('selectstart', function(e) {
                if (dragState.isDragging) {
                    e.preventDefault();
                }
            });
        }

        function buildCheckTooltipHtml(check, checkTitle, cardSeverity) {
            let html = `
                <div class="check-tooltip-header">
                    <span class="check-tooltip-title">Об этой проверке</span>
                    <button class="check-tooltip-close" onclick="hideCheckTooltip()">&times;</button>
                </div>
                <div class="check-tooltip-body">
            `;

            // Summary
            html += `<div class="check-tooltip-summary">${escapeHtml(check.summary)}</div>`;

            // Secure Message (shown when card severity is 'secure')
            if (cardSeverity === 'secure' && check.secureMessage) {
                html += `
                    <div class="check-tooltip-section check-tooltip-secure">
                        <div class="check-tooltip-section-title">Безопасная конфигурация</div>
                        <div class="check-tooltip-section-content">
                            ${escapeHtml(check.secureMessage)}
                        </div>
                    </div>
                `;
            }

            // Why It Matters
            if (check.whyItMatters) {
                html += `
                    <div class="check-tooltip-section">
                        <div class="check-tooltip-section-title">Почему это важно</div>
                        <div class="check-tooltip-section-content">
                            ${escapeHtml(check.whyItMatters)}
                        </div>
                    </div>
                `;
            }

            // What We Check
            if (check.whatWeCheck && check.whatWeCheck.length > 0) {
                html += `
                    <div class="check-tooltip-section">
                        <div class="check-tooltip-section-title">Что проверяется</div>
                        <div class="check-tooltip-section-content">
                            <ul>
                                ${check.whatWeCheck.map(item => `<li>${escapeHtml(item)}</li>`).join('')}
                            </ul>
                        </div>
                    </div>
                `;
            }

            if (check.originalEnglish && check.originalEnglish.whyItMatters) {
                html += '<details class="check-tooltip-section" lang="en">' +
                    '<summary>Подробные критерии проверки (оригинал EN)</summary>' +
                    '<p>' + escapeHtml(check.originalEnglish.whyItMatters) + '</p>' +
                    (check.originalEnglish.whatWeCheck ?
                        '<ul>' + check.originalEnglish.whatWeCheck.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                    '</details>';
            }
            // Filtering Note (documents privilege filtering behavior)
            if (check.filteringNote) {
                html += `
                    <div class="check-tooltip-section check-tooltip-filtering">
                        <div class="check-tooltip-section-title">Фильтрация результатов</div>
                        <div class="check-tooltip-section-content">
                            ${escapeHtml(check.filteringNote)}
                        </div>
                    </div>
                `;
            }

            html += '</div>';
            return html;
        }

        // ============================================================
        // CHECKBOX SYSTEM - Mark findings as completed
        // ============================================================

        let completedFindings = {};
        let reportHash = '';
        let localStorageAvailable = true;
        let localStorageWriteAttempts = 0;
        const MAX_WRITE_FAILURES = 3;

        // Safe localStorage wrapper with differentiated error handling
        // - Security errors (privacy mode): Permanently disable localStorage
        // - Quota errors: Retry up to MAX_WRITE_FAILURES times, then disable writes only
        // - Transient errors: Log and continue
        function safeGetItem(key) {
            if (!localStorageAvailable) return null;
            try {
                return localStorage.getItem(key);
            } catch (e) {
                if (isSecurityError(e)) {
                    console.warn('localStorage blocked (privacy mode):', e.message);
                    localStorageAvailable = false;
                } else {
                    console.warn('localStorage read failed:', e.message);
                }
                return null;
            }
        }

        function safeSetItem(key, value) {
            if (!localStorageAvailable) return false;
            try {
                localStorage.setItem(key, value);
                localStorageWriteAttempts = 0; // Reset on success
                return true;
            } catch (e) {
                if (isSecurityError(e)) {
                    // Privacy mode or security restriction - permanently disable
                    console.warn('localStorage blocked (privacy mode):', e.message);
                    localStorageAvailable = false;
                    return false;
                } else if (isQuotaError(e)) {
                    // Quota exceeded - try to clean up old data
                    localStorageWriteAttempts++;
                    console.warn('localStorage quota exceeded, attempt', localStorageWriteAttempts);
                    if (localStorageWriteAttempts >= MAX_WRITE_FAILURES) {
                        console.warn('localStorage quota exceeded repeatedly, disabling writes');
                        localStorageAvailable = false;
                    }
                    return false;
                } else {
                    // Other transient error - log but don't disable
                    console.warn('localStorage write failed:', e.message);
                    return false;
                }
            }
        }

        function isSecurityError(e) {
            // SecurityError is thrown in privacy mode or when localStorage is blocked
            return e.name === 'SecurityError' ||
                   (e.name === 'Error' && e.message.includes('access'));
        }

        function isQuotaError(e) {
            // QuotaExceededError when storage is full
            return e.name === 'QuotaExceededError' ||
                   e.name === 'NS_ERROR_DOM_QUOTA_REACHED' ||
                   (e.code && e.code === 22);
        }

        function initCheckboxSystem() {
            // Generate a hash from the report content for localStorage key
            reportHash = generateReportHash();

            // Load saved state
            const savedState = safeGetItem('adpeas-completed-' + reportHash);
            if (savedState) {
                try {
                    completedFindings = JSON.parse(savedState);
                } catch (e) {
                    completedFindings = {};
                }
            }

            // Initialize checkboxes on all finding cards (checkbox is already in HTML)
            document.querySelectorAll('.finding-card').forEach((card, index) => {
                // Use existing data-card-id (set by PowerShell) or generate fallback
                const cardId = card.dataset.cardId || ('finding-' + index);
                card.dataset.cardId = cardId;  // Ensure it's set if missing

                // Find existing checkbox and initialize it
                const checkbox = card.querySelector('.finding-checkbox');
                if (checkbox) {
                    checkbox.checked = !!completedFindings[cardId];
                    // Re-bind onclick to ensure proper cardId reference
                    checkbox.onclick = function(e) {
                        e.stopPropagation();
                        toggleCompleted(cardId, this.checked);
                    };
                }

                // Apply initial state
                if (completedFindings[cardId]) {
                    card.classList.add('completed');
                }
            });

            // Update progress bar
            updateProgress();

            // Load hide completed state
            const hideCompleted = safeGetItem('adpeas-hide-completed') === 'true';
            if (hideCompleted) {
                document.getElementById('hideCompletedToggle').checked = true;
                document.body.classList.add('hide-completed');
            }
        }

        function generateReportHash() {
            // Generate hash based on domain, timestamp, and finding titles for uniqueness
            // This ensures different reports don't share completed-state even if same domain/count
            const infoItems = document.querySelectorAll('.info-item');
            let domain = 'unknown';
            let generated = '';

            infoItems.forEach(item => {
                const label = item.querySelector('.label')?.textContent?.trim();
                const value = item.querySelector('.value')?.textContent?.trim();
                if (label === 'Domain') domain = value || 'unknown';
                if (label === 'Generated') generated = value || '';
            });

            // Include first 3 finding titles for additional uniqueness
            const titles = Array.from(document.querySelectorAll('.finding-title'))
                .slice(0, 3)
                .map(t => t.textContent || '')
                .join('');

            const hashInput = domain + generated + titles;
            // Simple hash function
            let hash = 0;
            for (let i = 0; i < hashInput.length; i++) {
                const char = hashInput.charCodeAt(i);
                hash = ((hash << 5) - hash) + char;
                hash = hash & hash; // Convert to 32bit integer
            }
            return domain.replace(/[^a-z0-9]/gi, '') + '-' + Math.abs(hash).toString(36);
        }

        function toggleCompleted(cardId, isCompleted) {
            if (isCompleted) {
                completedFindings[cardId] = true;
            } else {
                delete completedFindings[cardId];
            }

            // Update Card View UI
            const card = document.querySelector(`.finding-card[data-card-id="${cardId}"]`);
            if (card) {
                card.classList.toggle('completed', isCompleted);
            }

            // Save state
            safeSetItem('adpeas-completed-' + reportHash, JSON.stringify(completedFindings));

            // Update progress bar
            updateProgress();

            // Re-apply filters (if hide completed is enabled)
            if (hideCompletedEnabled) {
                applyFilters();
            }
        }

        function updateProgress() {
            // Update sidebar counts to show remaining (non-completed) findings
            updateSidebarCounts();
        }

        function updateSidebarCounts() {
            // Count non-completed cards per severity and category
            const severityCounts = { all: 0, finding: 0, hint: 0, note: 0, secure: 0 };
            const categoryCounts = {};

            document.querySelectorAll('.finding-card').forEach(card => {
                const cardId = card.dataset.cardId;
                const isCompleted = completedFindings[cardId];

                if (!isCompleted) {
                    severityCounts.all++;
                    const severity = card.dataset.severity || 'note';
                    if (severityCounts[severity] !== undefined) {
                        severityCounts[severity]++;
                    }

                    // Count by category
                    const category = card.dataset.category || '';
                    if (category) {
                        categoryCounts[category] = (categoryCounts[category] || 0) + 1;
                    }
                }
            });

            // Update sidebar severity filter counts
            document.querySelectorAll('.severity-filter').forEach(filter => {
                const severity = filter.dataset.severity;
                const countSpan = filter.querySelector('.count');
                if (countSpan && severityCounts[severity] !== undefined) {
                    countSpan.textContent = severityCounts[severity];
                }
            });

            // Update sidebar category filter counts
            document.querySelectorAll('.nav-item[data-category]').forEach(navItem => {
                const category = navItem.dataset.category;
                const countSpan = navItem.querySelector('.count');
                if (countSpan) {
                    if (category === 'all') {
                        countSpan.textContent = severityCounts.all;
                    } else if (categoryCounts[category] !== undefined) {
                        countSpan.textContent = categoryCounts[category];
                    } else {
                        countSpan.textContent = '0';
                    }
                }
            });

            // Update summary cards at the top
            const summaryMapping = {
                'finding': '.summary-card.finding .value',
                'hint': '.summary-card.hint .value',
                'note': '.summary-card.note .value',
                'secure': '.summary-card.secure .value'
            };

            Object.keys(summaryMapping).forEach(severity => {
                const el = document.querySelector(summaryMapping[severity]);
                if (el) {
                    el.textContent = severityCounts[severity];
                }
            });
        }

        function toggleHideCompleted() {
            const isChecked = document.getElementById('hideCompletedToggle').checked;
            hideCompletedEnabled = isChecked;
            document.body.classList.toggle('hide-completed', isChecked);
            safeSetItem('adpeas-hide-completed', isChecked);
            // Re-apply filters
            applyFilters();

            // Announce to screen readers
            const visibleCount = document.querySelectorAll('.finding-card:not([style*="display: none"])').length;
            const message = isChecked
                ? 'Completed findings hidden. ' + visibleCount + ' findings visible.'
                : 'Showing all findings including completed. ' + visibleCount + ' findings visible.';
            announceToScreenReader(message);
        }

        // ============================================================
        // KEYBOARD SHORTCUTS
        // ============================================================

        let currentFocusIndex = -1;
        let visibleCards = [];

        function initKeyboardShortcuts() {
            document.addEventListener('keydown', function(e) {
                // Don't trigger shortcuts when typing in search
                if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
                    if (e.key === 'Escape') {
                        // Clear search filter if the search input has a value
                        if (e.target.id === 'searchInput' && e.target.value) {
                            e.target.value = '';
                            currentSearchQuery = '';
                            applyFilters();
                        }
                        e.target.blur();
                        clearKeyboardFocus();
                    }
                    return;
                }

                switch(e.key) {
                    // Navigation: Arrow keys (intuitive)
                    case 'ArrowDown':
                        e.preventDefault();
                        navigateFinding(1);
                        break;
                    case 'ArrowUp':
                        e.preventDefault();
                        navigateFinding(-1);
                        break;

                    // Enter: Expand/Collapse
                    case 'Enter':
                        e.preventDefault();
                        if (currentFocusIndex >= 0) {
                            toggleCurrentFinding();
                        }
                        break;

                    // Toggle completed: Space (standard checkbox behavior)
                    case ' ':
                        e.preventDefault();
                        if (currentFocusIndex >= 0 && visibleCards[currentFocusIndex]) {
                            const card = visibleCards[currentFocusIndex];
                            const checkbox = card.querySelector('.finding-checkbox');
                            if (checkbox) {
                                checkbox.checked = !checkbox.checked;
                                toggleCompleted(card.dataset.cardId, checkbox.checked);
                            }
                        }
                        break;

                    // Search: / (vim-like, common in web apps)
                    case '/':
                        e.preventDefault();
                        document.getElementById('searchInput').focus();
                        break;

                    // Hide completed toggle: h
                    case 'h':
                        e.preventDefault();
                        const toggle = document.getElementById('hideCompletedToggle');
                        toggle.checked = !toggle.checked;
                        toggleHideCompleted();
                        break;

                    // Help: ? or F1
                    case '?':
                        e.preventDefault();
                        toggleShortcutHelp();
                        break;
                    case 'F1':
                        e.preventDefault();
                        toggleShortcutHelp();
                        break;

                    // Close/Cancel: Escape (standard)
                    case 'Escape':
                        hideTooltip();
                        hideCheckTooltip();
                        hideShortcutHelp();
                        clearKeyboardFocus();
                        break;
                }
            });
        }

        function getVisibleCards() {
            return Array.from(document.querySelectorAll('.finding-card')).filter(card => {
                return card.style.display !== 'none' && !card.closest('.section[style*="display: none"]');
            });
        }

        function navigateFinding(direction) {
            visibleCards = getVisibleCards();
            if (visibleCards.length === 0) return;

            // Remove visual focus from previous card (don't reset index)
            document.querySelectorAll('.keyboard-focused').forEach(el => {
                el.classList.remove('keyboard-focused');
            });

            // Calculate new index
            currentFocusIndex += direction;
            if (currentFocusIndex < 0) currentFocusIndex = visibleCards.length - 1;
            if (currentFocusIndex >= visibleCards.length) currentFocusIndex = 0;

            // Apply focus
            const card = visibleCards[currentFocusIndex];
            card.classList.add('keyboard-focused');
            card.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }

        function clearKeyboardFocus() {
            document.querySelectorAll('.keyboard-focused').forEach(el => {
                el.classList.remove('keyboard-focused');
            });
            currentFocusIndex = -1;
        }

        function toggleCurrentFinding() {
            if (currentFocusIndex >= 0 && visibleCards[currentFocusIndex]) {
                visibleCards[currentFocusIndex].classList.toggle('expanded');
            }
        }

        let allExpanded = false;
        function toggleAllFindings() {
            allExpanded = !allExpanded;
            document.querySelectorAll('.finding-card').forEach(card => {
                card.classList.toggle('expanded', allExpanded);
            });
        }

        function createShortcutHelpModal() {
            const backdrop = document.createElement('div');
            backdrop.className = 'shortcut-help-backdrop';
            backdrop.id = 'shortcutBackdrop';
            backdrop.onclick = hideShortcutHelp;
            backdrop.setAttribute('aria-hidden', 'true');
            document.body.appendChild(backdrop);

            const modal = document.createElement('div');
            modal.className = 'shortcut-help';
            modal.id = 'shortcutHelp';
            modal.setAttribute('role', 'dialog');
            modal.setAttribute('aria-modal', 'true');
            modal.setAttribute('aria-labelledby', 'helpModalTitle');
            modal.innerHTML = `
                <div class="help-header">
                    <h2 id="helpModalTitle">Report Guide</h2>
                    <button class="help-close-btn" onclick="hideShortcutHelp()" aria-label="Close help dialog">&times;</button>
                </div>
                <div class="help-content">
                    <div class="help-section">
                        <h3>Report Structure</h3>
                        <p>The report is organized by security check categories (Domain, Accounts, Delegation, Rights, etc.). Each category contains multiple checks, and each check can have multiple findings.</p>
                        <div class="help-grid">
                            <div class="help-card">
                                <div class="help-card-title">Summary Cards</div>
                                <div class="help-card-desc">Quick overview at the top showing total counts by severity level. Click a card to filter.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title">Top Priority Actions</div>
                                <div class="help-card-desc">AI-scored findings ranked by risk. Start here for the most critical issues.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title">Categories</div>
                                <div class="help-card-desc">Expandable sections grouping related security checks together.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title">Finding Cards</div>
                                <div class="help-card-desc">Individual findings with details. Click to expand and see all attributes.</div>
                            </div>
                        </div>
                    </div>

                    <div class="help-section">
                        <h3>Severity Levels</h3>
                        <div class="help-grid">
                            <div class="help-card">
                                <div class="help-card-title"><span class="severity-sample finding"></span> Нарушение (красный)</div>
                                <div class="help-card-desc">Security vulnerability or misconfiguration requiring immediate attention.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title"><span class="severity-sample hint"></span> Предупреждение (жёлтый)</div>
                                <div class="help-card-desc">Potentially interesting finding that may warrant investigation.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title"><span class="severity-sample note"></span> Сведения (синий)</div>
                                <div class="help-card-desc">Informational finding providing context or general information.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title"><span class="severity-sample secure"></span> Безопасно (зелёный)</div>
                                <div class="help-card-desc">Security configuration is properly set - no action needed.</div>
                            </div>
                        </div>
                    </div>

                    <div class="help-section">
                        <h3>Interactive Features</h3>
                        <div class="help-grid">
                            <div class="help-card">
                                <div class="help-card-title">? Help Buttons</div>
                                <div class="help-card-desc">Click the blue ? buttons next to check titles or findings for detailed explanations and remediation steps.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title">Checkboxes</div>
                                <div class="help-card-desc">Mark findings as completed. Progress is saved in your browser and persists across sessions.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title">Score Badges</div>
                                <div class="help-card-desc">Each finding shows a calculated risk score badge. Findings are automatically sorted by score, highest first.</div>
                            </div>
                            <div class="help-card">
                                <div class="help-card-title">Filters</div>
                                <div class="help-card-desc">Use severity and category dropdowns to focus on specific finding types.</div>
                            </div>
                        </div>
                    </div>

                    <div class="help-section">
                        <h3>Keyboard Shortcuts</h3>
                        <div class="shortcut-grid">
                            <div class="shortcut-row">
                                <span class="shortcut-key">&uarr; / &darr;</span>
                                <span class="shortcut-desc">Navigate findings</span>
                            </div>
                            <div class="shortcut-row">
                                <span class="shortcut-key">Enter</span>
                                <span class="shortcut-desc">Expand / Collapse</span>
                            </div>
                            <div class="shortcut-row">
                                <span class="shortcut-key">Space</span>
                                <span class="shortcut-desc">Mark completed</span>
                            </div>
                            <div class="shortcut-row">
                                <span class="shortcut-key">h</span>
                                <span class="shortcut-desc">Hide completed</span>
                            </div>
                            <div class="shortcut-row">
                                <span class="shortcut-key">/</span>
                                <span class="shortcut-desc">Search</span>
                            </div>
                            <div class="shortcut-row">
                                <span class="shortcut-key">Esc</span>
                                <span class="shortcut-desc">Close / Clear</span>
                            </div>
                        </div>
                    </div>

                    <div class="help-section">
                        <h3>Tips</h3>
                        <p style="margin-bottom: 8px;"><strong>Start with Top Priority Actions</strong> - These are automatically ranked by exploitability and impact.</p>
                        <p style="margin-bottom: 8px;"><strong>Use the search</strong> - Quickly find specific accounts, computers, or groups by name.</p>
                        <p style="margin-bottom: 0;"><strong>Mark as you go</strong> - Check off findings as you remediate them to track progress.</p>
                    </div>

                    <div class="help-section data-management-section">
                        <h3>Data Management</h3>
                        <p style="margin-bottom: 12px;">This report stores preferences and progress in your browser's local storage:</p>
                        <div class="data-storage-info">
                            <div class="data-item"><span class="data-icon">&#9745;</span> Completed findings (checkboxes)</div>
                            <div class="data-item"><span class="data-icon">&#9788;</span> Theme preference (Dark/Light)</div>
                            <div class="data-item"><span class="data-icon">&#9744;</span> Hide completed toggle state</div>
                        </div>
                        <p style="margin: 12px 0; color: var(--text-muted); font-size: 12px;">Data is stored only in this browser and is not sent anywhere. Each report has its own completion tracking.</p>
                        <button class="clear-data-btn" onclick="clearAdPEASData()" title="Remove all adPEAS data from browser storage">
                            <span class="clear-data-icon">&#128465;</span> Очистить сохранённые данные
                        </button>
                    </div>
                </div>
            `;
            document.body.appendChild(modal);
        }

        // Clear all adPEAS data from localStorage
        function clearAdPEASData() {
            const keys = Object.keys(localStorage).filter(k => k.startsWith('adpeas-'));
            const count = keys.length;

            if (count === 0) {
                announceToScreenReader('No adPEAS data found in storage.');
                alert('No adPEAS data found in browser storage.');
                return;
            }

            const confirmMsg = 'This will remove all adPEAS data from your browser:\n\n' +
                '• Completed findings (checkboxes) for ALL reports\n' +
                '• Theme preference\n\n' +
                'Found ' + count + ' stored item(s).\n\n' +
                'The page will reload after clearing. Continue?';

            if (confirm(confirmMsg)) {
                keys.forEach(k => localStorage.removeItem(k));
                announceToScreenReader('All adPEAS data cleared. Reloading page.');
                location.reload();
            }
        }

        function toggleShortcutHelp() {
            const backdrop = document.getElementById('shortcutBackdrop');
            const modal = document.getElementById('shortcutHelp');
            const isOpening = !modal.classList.contains('visible');

            backdrop.classList.toggle('visible');
            modal.classList.toggle('visible');

            if (isOpening) {
                // Focus trap and announce
                trapFocus(modal);
                announceToScreenReader('Help dialog opened. Press Escape to close.');
            } else {
                restoreFocus();
            }
        }

        function hideShortcutHelp() {
            document.getElementById('shortcutBackdrop').classList.remove('visible');
            document.getElementById('shortcutHelp').classList.remove('visible');
            restoreFocus();
        }

        // ============================================================
        // TOP PRIORITY ACTIONS with Context-Aware Risk Scoring
        // ============================================================

        // ==========================================================================
        // CONTEXT-AWARE SCORING SYSTEM
        // ==========================================================================
        // Score = BASE_SCORE * IMPACT_MODIFIER * EXPLOITABILITY_MODIFIER * SECURITY_MODIFIER + CORRELATION
        //
        // Definitions are maintained centrally in: src/modules/Core/adPEAS-ScoringDefinitions.ps1
        // Documentation: docs/10-Risk-Scoring-System.md
        // ==========================================================================

        // ---- BEGIN AUTO-GENERATED SCORING DEFINITIONS ----
        // Source: adPEAS-ScoringDefinitions.ps1
{{SCORING_DEFINITIONS}}
        // ---- END AUTO-GENERATED SCORING DEFINITIONS ----

        // Exploitability modifiers for cracking-based attacks
        // Uses values from securityModifiers, passwordAgeModifiers, passwordLengthModifiers, etc.
        function getExploitabilityModifier(accountInfo, findingType) {
            let modifier = 1.0;

            // Only apply these modifiers to attacks that require cracking
            const crackingAttacks = ['kerberoast', 'asrep', 'preauth'];
            const isCrackingAttack = crackingAttacks.some(a => findingType.includes(a));

            if (!isCrackingAttack || !accountInfo) {
                return modifier;
            }

            // Get domain password policy for context-aware age evaluation
            const maxPwdAgeDays = scoringContext?.domainInfo?.maxPwdAgeDays || 0;
            const minPwdLength = scoringContext?.domainInfo?.minPwdLength || 0;

            // Password age factor - relative to policy, not absolute
            if (accountInfo.pwdAgeDays !== null && accountInfo.pwdAgeDays > 0) {
                const pwdAge = accountInfo.pwdAgeDays;

                if (maxPwdAgeDays > 0) {
                    // Policy exists - evaluate relative to policy
                    const policyMultiples = pwdAge / maxPwdAgeDays;

                    if (policyMultiples >= 10) {
                        modifier *= passwordAgeModifiers.multiplier_10x;
                    } else if (policyMultiples >= 5) {
                        modifier *= passwordAgeModifiers.multiplier_5x;
                    } else if (policyMultiples >= 3) {
                        modifier *= passwordAgeModifiers.multiplier_3x;
                    } else if (policyMultiples >= 2) {
                        modifier *= passwordAgeModifiers.multiplier_2x;
                    } else if (policyMultiples >= 1) {
                        modifier *= passwordAgeModifiers.multiplier_1x;
                    } else {
                        modifier *= passwordAgeModifiers.within_policy;
                    }
                } else {
                    // No policy (never expires) - use absolute thresholds
                    if (pwdAge > 365 * 5) {
                        modifier *= passwordAgeModifiers.multiplier_5x;
                    } else if (pwdAge > 365 * 2) {
                        modifier *= passwordAgeModifiers.multiplier_2x;
                    } else if (pwdAge > 365) {
                        modifier *= passwordAgeModifiers.multiplier_1x;
                    }
                }
            }

            // Password policy strength affects cracking difficulty
            const complexityEnabled = scoringContext?.domainInfo?.complexityEnabled || false;

            // Password length impact on cracking time
            if (minPwdLength > 0) {
                if (minPwdLength < 8) {
                    modifier *= passwordLengthModifiers.very_weak;
                } else if (minPwdLength < 12) {
                    modifier *= passwordLengthModifiers.weak;
                } else if (minPwdLength < 16) {
                    modifier *= passwordLengthModifiers.standard;
                } else {
                    modifier *= passwordLengthModifiers.strong;
                }
            }

            // Password complexity
            if (!complexityEnabled) {
                modifier *= passwordComplexityModifiers.disabled;
            } else {
                modifier *= passwordComplexityModifiers.enabled;
            }

            // Combined weak policy scenario (short + no complexity)
            if (minPwdLength > 0 && minPwdLength < 10 && !complexityEnabled) {
                modifier *= 1.15;  // Additional penalty for very weak combination
            }

            // Encryption type factor (RC4 = much easier to crack)
            if (accountInfo.encryptionTypes && accountInfo.encryptionTypes.length > 0) {
                const hasRC4Only = accountInfo.encryptionTypes.includes('RC4-HMAC') &&
                                   !accountInfo.encryptionTypes.includes('AES256') &&
                                   !accountInfo.encryptionTypes.includes('AES128');
                const hasAES = accountInfo.encryptionTypes.includes('AES256') ||
                               accountInfo.encryptionTypes.includes('AES128');

                if (hasRC4Only) {
                    modifier *= encryptionTypeModifiers.rc4_only;
                } else if (hasAES && !accountInfo.encryptionTypes.includes('RC4-HMAC')) {
                    modifier *= encryptionTypeModifiers.aes256;
                }
            }

            return modifier;
        }

        // Security configuration modifiers - REDUCE score for secure settings
        // Uses values from securityModifiers object
        function getSecurityModifier(accountInfo, findingType) {
            if (!accountInfo || !accountInfo.uacFlags) {
                return 1.0;
            }

            let modifier = 1.0;
            const flags = accountInfo.uacFlags;
            const isCrackingAttack = ['kerberoast', 'asrep', 'preauth'].some(a => findingType.includes(a));

            // ========================================
            // ACCOUNT STATUS FLAGS (affect ALL attacks)
            // ========================================

            if (flags.includes('ACCOUNTDISABLE') || flags.includes('Disabled')) {
                modifier *= securityModifiers.ACCOUNTDISABLE;
            }

            // No modifier for a locked-out account or an expired password. The DC
            // computes LOCKOUT and PASSWORD_EXPIRED into msDS-User-Account-Control-Computed
            // and never stores them in userAccountControl, where these flags come from -
            // the two modifiers that read them here never fired.

            // ========================================
            // KERBEROS SECURITY FLAGS (affect cracking attacks)
            // ========================================

            if (isCrackingAttack) {
                if (flags.includes('SMARTCARD_REQUIRED') || flags.includes('SmartcardRequired')) {
                    modifier *= securityModifiers.SMARTCARD_REQUIRED;
                }

                if (accountInfo.isProtectedUser) {
                    modifier *= securityModifiers.PROTECTED_USERS;
                }
            }

            // ========================================
            // DELEGATION FLAGS (affect delegation attacks)
            // ========================================
            //
            // Removed, not repaired. The flags here belong to the account the card is
            // about - the host that PERFORMS the delegation - and NOT_DELEGATED
            // ("Account is sensitive and cannot be delegated") protects the identity of
            // THAT account against being delegated by someone else. It has no effect on
            // the delegation this account carries out.
            //
            // So a hardened server whose computer account has the flag set, and which
            // also has unconstrained delegation, had its delegation finding multiplied by
            // 0.3 for a measure that does not touch the attack: the most dangerous
            // delegation object in the domain read as a medium problem. No modifier is
            // better than one that points the wrong way.
            //
            // A correct version would measure the Tier-0 coverage that
            // Get-ProtectedUsersStatus already computes - whether the accounts worth
            // impersonating are protected from delegation - rather than the UAC flags of
            // the delegating host.

            // ========================================
            // ENCRYPTION FLAGS (affect Kerberoast specifically)
            // ========================================

            if (flags.includes('USE_DES_KEY_ONLY') || flags.includes('DESKeyOnly')) {
                modifier *= securityModifiers.USE_DES_KEY_ONLY;
            }

            return modifier;
        }

        // Every account a card describes, in the order the card lists them.
        function getCardAccountInfos(card) {
            if (!scoringContext || !scoringContext.accounts) {
                return [];
            }

            const found = [];
            const seen = new Set();
            const addAccount = function (acct) {
                if (!acct) return;
                const key = acct.sid || acct.dn || acct.name;
                if (key && seen.has(key)) return;
                if (key) seen.add(key);
                found.push(acct);
            };

            const objectDetails = card.querySelectorAll('.object-detail');
            for (const detail of objectDetails) {
                const rows = detail.querySelectorAll('.attr-row');
                for (const row of rows) {
                    const nameEl = row.querySelector('.attr-name');
                    const valueEl = row.querySelector('.attr-value');
                    if (!nameEl || !valueEl) continue;

                    const attrName = nameEl.textContent.trim().toLowerCase();
                    const attrValue = valueEl.textContent.trim();

                    // objectSid first, it is the only identifier that cannot collide
                    if (attrName === 'objectsid' && scoringContext.accounts[attrValue]) {
                        addAccount(scoringContext.accounts[attrValue]);
                        continue;
                    }
                    if (attrName === 'distinguishedname' && scoringContext.accounts[attrValue]) {
                        addAccount(scoringContext.accounts[attrValue]);
                        continue;
                    }
                    if (attrName === 'samaccountname') {
                        for (const [key, acct] of Object.entries(scoringContext.accounts)) {
                            if (acct.name && acct.name.toLowerCase() === attrValue.toLowerCase()) {
                                addAccount(acct);
                                break;
                            }
                        }
                    }
                }
            }
            return found;
        }

        // Get account info from scoring context.
        //
        // One card per check, not per object: a Kerberoastable card lists every roastable
        // account in the domain, and this function used to return at the FIRST match and
        // score the whole card with it. A kerberoastable Domain Admin at position 17 did
        // not raise the card's score at all, and - the same mechanism in the other
        // direction - a disabled account at position 1 multiplied the card by 0.1.
        //
        // The card is scored by the worst of its accounts now, field by field, because
        // "worst" is not the same question for an aggravating and for a mitigating one:
        //
        //   adminTier / isAdmin   the highest tier any of them holds
        //   pwdAgeDays            the oldest password
        //   encryptionTypes       RC4-only if ANY of them is RC4-only, else the union
        //   uacFlags              the INTERSECTION: every flag the scorer reads here is a
        //                         mitigation (disabled, smartcard required),
        //                         so it may only count when it holds for all of them
        //   isProtectedUser       likewise, only when every account is protected
        //
        // Identity fields come from the worst-tier account, which is the one a reader
        // would name, and keeps the correlation bonus pointing at a real account.
        function getAccountInfoFromCard(card) {
            const accounts = getCardAccountInfos(card);
            if (accounts.length === 0) {
                return null;
            }
            if (accounts.length === 1) {
                return accounts[0];
            }

            const tierRank = { none: 0, tier2: 1, tier1: 2, tier0: 3 };
            let worst = accounts[0];
            for (const acct of accounts) {
                if ((tierRank[acct.adminTier] || 0) > (tierRank[worst.adminTier] || 0)) {
                    worst = acct;
                }
            }

            const aggregated = {
                sid: worst.sid,
                name: worst.name,
                dn: worst.dn,
                isAdmin: accounts.some(a => a.isAdmin),
                adminTier: worst.adminTier,
                pwdLastSet: worst.pwdLastSet,
                pwdAgeDays: null,
                encryptionTypes: [],
                uacFlags: [],
                isProtectedUser: accounts.every(a => a.isProtectedUser),
                memberOf: worst.memberOf
            };

            for (const acct of accounts) {
                if (acct.pwdAgeDays !== null && acct.pwdAgeDays !== undefined &&
                    (aggregated.pwdAgeDays === null || acct.pwdAgeDays > aggregated.pwdAgeDays)) {
                    aggregated.pwdAgeDays = acct.pwdAgeDays;
                    aggregated.pwdLastSet = acct.pwdLastSet;
                }
            }

            // An account that permits RC4 and no AES decides the card: the cheapest ticket
            // on it is what an attacker takes. Reporting the union instead would let one
            // AES-only account hide every RC4-only one behind it.
            const rc4Only = accounts.some(function (a) {
                const t = a.encryptionTypes || [];
                return t.includes('RC4-HMAC') && !t.includes('AES256') && !t.includes('AES128');
            });
            if (rc4Only) {
                aggregated.encryptionTypes = ['RC4-HMAC'];
            } else {
                const union = new Set();
                for (const acct of accounts) {
                    for (const t of (acct.encryptionTypes || [])) { union.add(t); }
                }
                aggregated.encryptionTypes = Array.from(union);
            }

            // The intersection, for the reason in the note above. Built from the union
            // rather than from the first account's list: starting there would make the
            // result depend on the order the card happens to list its accounts in, which
            // is the very thing this function exists to stop mattering.
            const allFlags = new Set();
            for (const acct of accounts) {
                for (const flag of (acct.uacFlags || [])) { allFlags.add(flag); }
            }
            aggregated.uacFlags = Array.from(allFlags).filter(function (flag) {
                return accounts.every(a => (a.uacFlags || []).includes(flag));
            });

            return aggregated;
        }

        // Check if account appears in multiple risky findings (correlation bonus)
        // Uses values from correlationBonus object
        // Non-admin accounts get ENHANCED correlation bonus - they represent potential attack paths
        function getCorrelationBonus(accountInfo) {
            if (!scoringContext || !scoringContext.correlations || !accountInfo) {
                return 0;
            }

            // Find correlations for this account
            const accountId = accountInfo.sid || accountInfo.dn || accountInfo.name;
            const correlation = scoringContext.correlations[accountId];

            if (!correlation) {
                return 0;
            }

            // Determine if this is a non-admin account
            const isNonAdmin = !accountInfo.isAdmin && accountInfo.adminTier === 'none';

            let bonus = 0;

            // Dangerous combinations get max bonus
            if (correlation.hasDCSync && (correlation.hasKerberoast || correlation.hasASREP)) {
                bonus = isNonAdmin ? correlationBonus.nonAdminMaxBonus : correlationBonus.maxBonus;
            } else if (correlation.hasDelegation && correlation.hasKerberoast) {
                const perFinding = isNonAdmin ? correlationBonus.nonAdminPerFinding : correlationBonus.perFinding;
                const maxBonus = isNonAdmin ? correlationBonus.nonAdminMaxBonus : correlationBonus.maxBonus;
                bonus = Math.min(perFinding * 2, maxBonus);
            } else if (correlation.count >= 2) {
                // Non-admin with 3+ findings = enhanced bonus (potential privilege escalation path)
                if (isNonAdmin && correlation.count >= correlationBonus.nonAdminThreshold) {
                    // Enhanced correlation for non-admins appearing in multiple findings
                    bonus = Math.min((correlation.count - 1) * correlationBonus.nonAdminPerFinding, correlationBonus.nonAdminMaxBonus);
                } else {
                    // Standard correlation for admins or non-admins below threshold
                    bonus = Math.min((correlation.count - 1) * correlationBonus.perFinding, correlationBonus.maxBonus);
                }
            }

            return bonus;
        }

        // Resolve the BASE score of a card from the finding IDs it actually carries.
        //
        // This replaces a substring match of the card TITLE against the finding IDs, which
        // could never match: titles are prose ("Certificate Templates"), IDs carry
        // underscores ("ESC1_TEMPLATE"). Every red finding therefore fell back to
        // severityBaseScores.finding (35) and the whole per-finding BaseScore table was
        // unreachable - DCSync (100) and ESC1 (90) scored the same as any other finding.
        //
        // Deliberately NOT the same selection as findBestFindingDefinition(): that one
        // returns the card's TOPIC for the tooltip and lets an ObjectType's
        // primaryFindingId win outright, so an incidental attribute trigger cannot
        // relabel the card. The SCORE answers a different question - how urgent is this
        // card - and the answer is its worst finding. So this takes the maximum over all
        // sources instead of the first authoritative one. Badge and tooltip can therefore
        // name different findings on the same card; that is intended.
        function resolveCardBaseScore(meta) {
            let bestKey = null;
            let bestScore = 0;

            const consider = (key) => {
                if (!key || !findingBaseScores.hasOwnProperty(key)) return;
                const score = findingBaseScores[key];
                if (score > bestScore) {
                    bestScore = score;
                    bestKey = key;
                }
            };

            // ObjectType-level primary finding
            if (meta.objectType && typeof checkDescriptions !== 'undefined' && checkDescriptions) {
                consider(checkDescriptions[meta.objectType]?.primaryFindingId);
            }

            // Finding IDs attached by attribute trigger matching
            if (Array.isArray(meta.findingIds)) {
                meta.findingIds.forEach(consider);
            }

            // Vulnerability tags, e.g. "ESC1" -> ESC1_TEMPLATE. A template tagged
            // "ESC1, ESC15" resolves to the higher of the two instead of whichever
            // trigger happened to match first.
            if (Array.isArray(meta.vulnerabilities) && meta.vulnerabilities.length > 0) {
                for (const vulnTag of meta.vulnerabilities) {
                    const vulnLower = String(vulnTag).toLowerCase();
                    if (!vulnLower) continue;
                    // ESC3-TARGET is tagged with a hyphen while its key is
                    // ESC3_TARGET_TEMPLATE, so neither comparison below matched and the
                    // card fell back to the severity base score - half of what the
                    // definition says the finding is worth.
                    const vulnKey = vulnLower.replace(/-/g, '_');
                    for (const key of Object.keys(findingBaseScores)) {
                        const keyLower = key.toLowerCase();
                        if (keyLower === vulnLower || keyLower.startsWith(vulnLower + '_') ||
                            keyLower === vulnKey || keyLower.startsWith(vulnKey + '_')) {
                            consider(key);
                        }
                    }
                }
            }

            return { key: bestKey, score: bestScore };
        }

        // The DOM card carries the same signals as the JSON metadata: its ObjectType as a
        // data attribute, and one data-finding-id per finding row inside it.
        function buildMetaFromCard(card) {
            let findingIds = [];
            try {
                findingIds = Array.from(card.querySelectorAll('[data-finding-id]'))
                    .map(el => el.dataset.findingId)
                    .filter(Boolean);
            } catch (e) {
                findingIds = [];
            }
            return {
                objectType: card.dataset.objectType || null,
                findingIds: Array.from(new Set(findingIds)),
                vulnerabilities: []
            };
        }

        // Calculate score with full breakdown for transparency
        function calculateFindingScoreWithBreakdown(card) {
            const severity = card.dataset.severity || 'note';
            const breakdown = {
                severity: severity,
                baseScore: 0,
                matchedPattern: null,
                impactMod: 1.0,
                impactReason: 'Standard',
                exploitMod: 1.0,
                exploitReasons: [],
                securityMod: 1.0,
                securityReasons: [],
                correlationBonus: 0,
                correlationReason: null,
                finalScore: 0
            };

            // Note and Secure = no security issue
            if (severity === 'note' || severity === 'secure') {
                breakdown.baseScore = 0;
                breakdown.finalScore = 0;
                return breakdown;
            }

            // HINT severity = informational findings
            if (severity === 'hint') {
                breakdown.baseScore = severityBaseScores['hint'] || 15;
                breakdown.finalScore = breakdown.baseScore;
                breakdown.matchedPattern = 'hint (informational)';
                return breakdown;
            }

            // Still needed below: getExploitabilityModifier/getSecurityModifier classify the
            // attack type from the title.
            const title = (card.querySelector('.finding-title')?.textContent || '').toLowerCase();

            // 1. Determine BASE score from the finding IDs on the card, not from its title
            breakdown.baseScore = severityBaseScores[severity] || 5;

            const resolved = resolveCardBaseScore(buildMetaFromCard(card));
            if (resolved.key && resolved.score > breakdown.baseScore) {
                breakdown.baseScore = resolved.score;
                breakdown.matchedPattern = resolved.key;
            }

            // DCSync/Replication Rights are ALWAYS maximum
            if (breakdown.matchedPattern === 'DANGEROUS_ACL_DCSYNC') {
                breakdown.finalScore = 100;
                breakdown.impactReason = 'Maximum (DCSync)';
                return breakdown;
            }

            // 2. Get account context
            const accountInfo = getAccountInfoFromCard(card);

            // 3. Apply IMPACT modifier
            if (accountInfo && accountInfo.adminTier) {
                breakdown.impactMod = impactMultipliers[accountInfo.adminTier] || impactMultipliers.none;
                const tierNames = { tier0: 'Tier 0 (Domain Admin)', tier1: 'Tier 1 (Server Admin)', tier2: 'Tier 2 (Workstation Admin)', none: 'Non-Admin' };
                breakdown.impactReason = tierNames[accountInfo.adminTier] || 'Standard';
            }

            // 4. Apply EXPLOITABILITY modifier with reasons
            breakdown.exploitMod = getExploitabilityModifier(accountInfo, title);
            if (accountInfo) {
                if (accountInfo.pwdAgeDays > 365) {
                    breakdown.exploitReasons.push('Old password (' + Math.round(accountInfo.pwdAgeDays / 365) + 'y)');
                }
                if (accountInfo.encryptionTypes && accountInfo.encryptionTypes.includes('RC4-HMAC') && !accountInfo.encryptionTypes.includes('AES256')) {
                    breakdown.exploitReasons.push('RC4 encryption');
                }
            }
            if (breakdown.exploitReasons.length === 0 && breakdown.exploitMod !== 1.0) {
                breakdown.exploitReasons.push(breakdown.exploitMod > 1 ? 'Easier to exploit' : 'Harder to exploit');
            }

            // 5. Apply SECURITY modifier with reasons
            breakdown.securityMod = getSecurityModifier(accountInfo, title);
            if (accountInfo && accountInfo.uacFlags) {
                const flags = accountInfo.uacFlags;
                if (flags.includes('ACCOUNTDISABLE') || flags.includes('Disabled')) {
                    breakdown.securityReasons.push('Disabled');
                }
                if (flags.includes('SMARTCARD_REQUIRED') || flags.includes('SmartcardRequired')) {
                    breakdown.securityReasons.push('Smartcard required');
                }
                if (accountInfo.isProtectedUser) {
                    breakdown.securityReasons.push('Protected Users');
                }
            }
            if (breakdown.securityReasons.length === 0 && breakdown.securityMod !== 1.0) {
                breakdown.securityReasons.push(breakdown.securityMod < 1 ? 'Mitigated' : 'Vulnerable');
            }

            // 6. Add correlation bonus
            breakdown.correlationBonus = getCorrelationBonus(accountInfo);
            if (breakdown.correlationBonus > 0) {
                breakdown.correlationReason = 'Appears in multiple findings';
            }

            // Calculate final score
            let rawScore = Math.round(breakdown.baseScore * breakdown.impactMod * breakdown.exploitMod * breakdown.securityMod) + breakdown.correlationBonus;
            breakdown.finalScore = Math.min(Math.max(rawScore, 0), 100);

            return breakdown;
        }

        // Simple wrapper for backwards compatibility
        function calculateFindingScore(card) {
            return calculateFindingScoreWithBreakdown(card).finalScore;
        }

        // Format score breakdown as tooltip text
        function formatScoreBreakdown(breakdown) {
            if (breakdown.finalScore === 0) {
                return 'Оценка риска не предусмотрена';
            }

            let lines = [];
            lines.push('Расчёт оценки риска:');
            lines.push('─────────────────');
            lines.push('Base: ' + breakdown.baseScore + (breakdown.matchedPattern ? ' (' + breakdown.matchedPattern + ')' : ''));

            if (breakdown.impactMod !== 1.0) {
                lines.push('Impact: ×' + breakdown.impactMod.toFixed(2) + ' (' + breakdown.impactReason + ')');
            }

            if (breakdown.exploitMod !== 1.0) {
                const reasons = breakdown.exploitReasons.length > 0 ? breakdown.exploitReasons.join(', ') : '';
                lines.push('Exploitability: ×' + breakdown.exploitMod.toFixed(2) + (reasons ? ' (' + reasons + ')' : ''));
            }

            if (breakdown.securityMod !== 1.0) {
                const reasons = breakdown.securityReasons.length > 0 ? breakdown.securityReasons.join(', ') : '';
                lines.push('Security: ×' + breakdown.securityMod.toFixed(2) + (reasons ? ' (' + reasons + ')' : ''));
            }

            if (breakdown.correlationBonus > 0) {
                lines.push('Correlation: +' + breakdown.correlationBonus + (breakdown.correlationReason ? ' (' + breakdown.correlationReason + ')' : ''));
            }

            lines.push('─────────────────');
            lines.push('Final: ' + breakdown.finalScore);

            return lines.join('\n');
        }

        // Format score breakdown as styled HTML tooltip content
        function formatScoreBreakdownHtml(breakdown) {
            if (breakdown.finalScore === 0) {
                return `
                    <div class="score-tooltip-header">
                        <span class="score-tooltip-title">Расчёт оценки риска</span>
                        <span class="score-tooltip-final info">0</span>
                    </div>
                    <div class="score-tooltip-body">
                        <div class="score-tooltip-row">
                            <span class="score-tooltip-label">Оценка риска не предусмотрена</span>
                        </div>
                    </div>
                `;
            }

            const scoreClass = breakdown.finalScore >= scoreThresholds.critical ? 'critical' :
                               breakdown.finalScore >= scoreThresholds.high ? 'high' :
                               breakdown.finalScore >= scoreThresholds.medium ? 'medium' :
                               breakdown.finalScore >= scoreThresholds.low ? 'low' : 'info';

            let rowsHtml = '';

            // Базовая оценка
            rowsHtml += `
                <div class="score-tooltip-row">
                    <span class="score-tooltip-label">Базовая оценка${breakdown.matchedPattern ? `<span class="reason">${escapeHtml(breakdown.matchedPattern)}</span>` : ''}</span>
                    <span class="score-tooltip-value positive">${breakdown.baseScore}</span>
                </div>
            `;

            // Impact Modifier
            if (breakdown.impactMod !== 1.0) {
                rowsHtml += `
                    <div class="score-tooltip-row">
                        <span class="score-tooltip-label">Impact<span class="reason">${escapeHtml(breakdown.impactReason)}</span></span>
                        <span class="score-tooltip-value modifier">×${breakdown.impactMod.toFixed(2)}</span>
                    </div>
                `;
            }

            // Exploitability Modifier
            if (breakdown.exploitMod !== 1.0) {
                const reasons = breakdown.exploitReasons.length > 0 ? breakdown.exploitReasons.join(', ') : '';
                rowsHtml += `
                    <div class="score-tooltip-row">
                        <span class="score-tooltip-label">Возможность эксплуатации${reasons ? `<span class="reason">${escapeHtml(reasons)}</span>` : ''}</span>
                        <span class="score-tooltip-value modifier">×${breakdown.exploitMod.toFixed(2)}</span>
                    </div>
                `;
            }

            // Security Modifier
            if (breakdown.securityMod !== 1.0) {
                const reasons = breakdown.securityReasons.length > 0 ? breakdown.securityReasons.join(', ') : '';
                rowsHtml += `
                    <div class="score-tooltip-row">
                        <span class="score-tooltip-label">Security${reasons ? `<span class="reason">${escapeHtml(reasons)}</span>` : ''}</span>
                        <span class="score-tooltip-value modifier">×${breakdown.securityMod.toFixed(2)}</span>
                    </div>
                `;
            }

            // Correlation Bonus
            if (breakdown.correlationBonus > 0) {
                rowsHtml += `
                    <div class="score-tooltip-row">
                        <span class="score-tooltip-label">Correlation${breakdown.correlationReason ? `<span class="reason">${escapeHtml(breakdown.correlationReason)}</span>` : ''}</span>
                        <span class="score-tooltip-value positive">+${breakdown.correlationBonus}</span>
                    </div>
                `;
            }

            return `
                <div class="score-tooltip-header">
                    <span class="score-tooltip-title">Расчёт оценки риска</span>
                    <span class="score-tooltip-final ${scoreClass}">${breakdown.finalScore}</span>
                </div>
                <div class="score-tooltip-body">
                    ${rowsHtml}
                </div>
            `;
        }

        // Active score tooltip reference
        let activeScoreTooltip = null;

        // Initialize score tooltips for styled display
        function initScoreTooltips() {
            // Create tooltip container
            const tooltipDiv = document.createElement('div');
            tooltipDiv.id = 'scoreTooltip';
            tooltipDiv.className = 'score-tooltip';
            tooltipDiv.setAttribute('role', 'tooltip');
            document.body.appendChild(tooltipDiv);

            // Close tooltip when clicking outside
            document.addEventListener('click', function(e) {
                if (activeScoreTooltip && !e.target.closest('.score-tooltip') && !e.target.closest('[data-score-breakdown]')) {
                    closeScoreTooltip();
                }
            });

            // Close on Escape key
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape' && activeScoreTooltip) {
                    closeScoreTooltip();
                }
            });
        }

        function showScoreTooltip(trigger, breakdown) {
            const tooltip = document.getElementById('scoreTooltip');
            if (!tooltip) return;

            // Close any previously open tooltip first
            if (activeScoreTooltip) {
                closeScoreTooltip();
            }

            // Build tooltip HTML
            tooltip.innerHTML = formatScoreBreakdownHtml(breakdown);

            // Make visible for positioning measurement
            tooltip.style.visibility = 'hidden';
            tooltip.classList.add('visible');

            // Position tooltip
            positionScoreTooltip(tooltip, trigger);

            // Show tooltip
            tooltip.style.visibility = 'visible';
            activeScoreTooltip = tooltip;
        }

        function closeScoreTooltip() {
            const tooltip = document.getElementById('scoreTooltip');
            if (tooltip) {
                tooltip.classList.remove('visible');
            }
            activeScoreTooltip = null;
        }

        function positionScoreTooltip(tooltip, trigger) {
            const triggerRect = trigger.getBoundingClientRect();
            const tooltipRect = tooltip.getBoundingClientRect();
            const viewportWidth = window.innerWidth;
            const viewportHeight = window.innerHeight;
            const padding = UI_CONSTANTS.VIEWPORT_PADDING;

            // Default: position below the trigger, centered
            let left = triggerRect.left + (triggerRect.width / 2) - (tooltipRect.width / 2);
            let top = triggerRect.bottom + 8;

            // Adjust horizontal position if tooltip would overflow
            if (left < padding) {
                left = padding;
            } else if (left + tooltipRect.width > viewportWidth - padding) {
                left = viewportWidth - tooltipRect.width - padding;
            }

            // If tooltip would overflow bottom, position above trigger
            if (top + tooltipRect.height > viewportHeight - padding) {
                top = triggerRect.top - tooltipRect.height - 8;
            }

            // Ensure not above viewport
            if (top < padding) {
                top = padding;
            }

            tooltip.style.left = left + 'px';
            tooltip.style.top = top + 'px';
        }

        // Calculate score from finding metadata (JSON-based, no DOM traversal)
        function calculateScoreFromMetadata(findingMeta) {
            const severity = findingMeta.severity || 'note';
            const breakdown = {
                severity: severity,
                baseScore: 0,
                matchedPattern: null,
                impactMod: 1.0,
                impactReason: 'Standard',
                exploitMod: 1.0,
                exploitReasons: [],
                securityMod: 1.0,
                securityReasons: [],
                correlationBonus: 0,
                correlationReason: null,
                finalScore: 0
            };

            // Note and Secure = no security issue
            if (severity === 'note' || severity === 'secure') {
                return breakdown;
            }

            // HINT severity = informational findings
            if (severity === 'hint') {
                breakdown.baseScore = severityBaseScores['hint'] || 15;
                breakdown.finalScore = breakdown.baseScore;
                breakdown.matchedPattern = 'hint (informational)';
                return breakdown;
            }

            // Still needed below: getExploitabilityModifier/getSecurityModifier classify the
            // attack type from the title.
            const title = (findingMeta.title || '').toLowerCase();

            // 1. Determine BASE score from the finding IDs this card carries, not from its title
            breakdown.baseScore = severityBaseScores[severity] || 5;

            const resolvedMeta = resolveCardBaseScore(findingMeta);
            if (resolvedMeta.key && resolvedMeta.score > breakdown.baseScore) {
                breakdown.baseScore = resolvedMeta.score;
                breakdown.matchedPattern = resolvedMeta.key;
            }

            // The former step 1b - vulnerability tags against findingBaseScores - now lives
            // in resolveCardBaseScore() together with the findingIds and the ObjectType's
            // primaryFindingId, so both score paths resolve a card the same way. The tag
            // route was the only one that ever reached this table; findingIds were never
            // consulted for the base score at all.

            // DCSync/Replication Rights are ALWAYS maximum
            if (breakdown.matchedPattern === 'DANGEROUS_ACL_DCSYNC') {
                breakdown.finalScore = 100;
                breakdown.impactReason = 'Maximum (DCSync)';
                return breakdown;
            }

            // 2. Get account context from scoringContext using accountSID
            const accountInfo = findingMeta.accountSID ? scoringContext?.accounts?.[findingMeta.accountSID] : null;

            // 3. Apply IMPACT modifier
            if (accountInfo && accountInfo.adminTier) {
                breakdown.impactMod = impactMultipliers[accountInfo.adminTier] || impactMultipliers.none;
                const tierNames = { tier0: 'Tier 0 (Domain Admin)', tier1: 'Tier 1 (Server Admin)', tier2: 'Tier 2 (Workstation Admin)', none: 'Non-Admin' };
                breakdown.impactReason = tierNames[accountInfo.adminTier] || 'Standard';
            }

            // 4. Apply EXPLOITABILITY modifier with reasons
            breakdown.exploitMod = getExploitabilityModifier(accountInfo, title);
            if (accountInfo) {
                if (accountInfo.pwdAgeDays > 365) {
                    breakdown.exploitReasons.push('Old password (' + Math.round(accountInfo.pwdAgeDays / 365) + 'y)');
                }
                if (accountInfo.encryptionTypes && accountInfo.encryptionTypes.includes('RC4-HMAC') && !accountInfo.encryptionTypes.includes('AES256')) {
                    breakdown.exploitReasons.push('RC4 encryption');
                }
            }
            if (breakdown.exploitReasons.length === 0 && breakdown.exploitMod !== 1.0) {
                breakdown.exploitReasons.push(breakdown.exploitMod > 1 ? 'Easier to exploit' : 'Harder to exploit');
            }

            // 5. Apply SECURITY modifier with reasons
            breakdown.securityMod = getSecurityModifier(accountInfo, title);
            if (accountInfo && accountInfo.uacFlags) {
                const flags = accountInfo.uacFlags;
                if (flags.includes('ACCOUNTDISABLE') || flags.includes('Disabled')) {
                    breakdown.securityReasons.push('Disabled');
                }
                if (flags.includes('SMARTCARD_REQUIRED') || flags.includes('SmartcardRequired')) {
                    breakdown.securityReasons.push('Smartcard required');
                }
                if (accountInfo.isProtectedUser) {
                    breakdown.securityReasons.push('Protected Users');
                }
            }
            if (breakdown.securityReasons.length === 0 && breakdown.securityMod !== 1.0) {
                breakdown.securityReasons.push(breakdown.securityMod < 1 ? 'Mitigated' : 'Vulnerable');
            }

            // 6. Add correlation bonus
            breakdown.correlationBonus = getCorrelationBonus(accountInfo);
            if (breakdown.correlationBonus > 0) {
                breakdown.correlationReason = 'Appears in multiple findings';
            }

            // Calculate final score
            let rawScore = Math.round(breakdown.baseScore * breakdown.impactMod * breakdown.exploitMod * breakdown.securityMod) + breakdown.correlationBonus;
            breakdown.finalScore = Math.min(Math.max(rawScore, 0), 100);

            return breakdown;
        }

        // Find the best matching findingDefinition for a given finding card metadata
        // Priority: 0) ObjectType primaryFindingId, 1) findingIds from metadata, 2) vulnerability tags, 3) title keyword matching
        function findBestFindingDefinition(meta) {
            if (!findingDefinitions || !meta) return null;
            let bestKey = null;
            let bestScore = 0;

            // 0. ObjectType-level primary finding (highest authority — prevents incidental attribute
            //    triggers from overriding the card's actual topic)
            if (meta.objectType && checkDescriptions) {
                const checkInfo = checkDescriptions[meta.objectType];
                if (checkInfo?.primaryFindingId && findingDefinitions[checkInfo.primaryFindingId]) {
                    return findingDefinitions[checkInfo.primaryFindingId];
                }
            }

            // 1. Direct FindingId lookup (most reliable — from attribute trigger matching)
            if (meta.findingIds && meta.findingIds.length > 0) {
                for (const fid of meta.findingIds) {
                    if (findingDefinitions[fid]) {
                        const score = findingBaseScores[fid] || 0;
                        if (score > bestScore || !bestKey) {
                            bestScore = score;
                            bestKey = fid;
                        }
                    }
                }
            }

            // 2. Vulnerability tags (e.g., "ESC1" → "ESC1_TEMPLATE")
            if (!bestKey && meta.vulnerabilities && meta.vulnerabilities.length > 0) {
                for (const vulnTag of meta.vulnerabilities) {
                    const vulnLower = vulnTag.toLowerCase();
                    // "ESC3-TARGET" against the key ESC3_TARGET_TEMPLATE - see the same
                    // normalisation in resolveCardBaseScore.
                    const vulnKey = vulnLower.replace(/-/g, '_');
                    for (const [key, score] of Object.entries(findingBaseScores)) {
                        if (key.toLowerCase().startsWith(vulnLower + '_') || key.toLowerCase() === vulnLower ||
                            key.toLowerCase().startsWith(vulnKey + '_') || key.toLowerCase() === vulnKey) {
                            if (score > bestScore && findingDefinitions[key]) {
                                bestScore = score;
                                bestKey = key;
                            }
                        }
                    }
                }
            }

            // 3. Fallback: title keyword matching
            if (!bestKey) {
                const titleLower = (meta.title || '').toLowerCase();
                for (const [key, score] of Object.entries(findingBaseScores)) {
                    if (titleLower.includes(key.toLowerCase()) && score > bestScore && findingDefinitions[key]) {
                        bestScore = score;
                        bestKey = key;
                    }
                }
            }

            return bestKey ? findingDefinitions[bestKey] : null;
        }

        function generateTopPriorityActions() {
            const container = document.getElementById('topActionsContainer');
            if (!container) return;

            // ========== OPTIMIZED: Use JSON-based scoring if available ==========
            // This avoids DOM traversal for initial score calculation
            let scoredFindings = [];
            let totalCriticalCount = 0;

            if (scoringContext?.findingCards?.length > 0) {
                // NEW: JSON-based scoring (no DOM traversal needed)
                const criticalFindings = scoringContext.findingCards.filter(f => f.severity === 'finding');
                totalCriticalCount = criticalFindings.length;

                if (criticalFindings.length > 0) {
                    scoredFindings = criticalFindings.map((meta, idx) => {
                        const breakdown = calculateScoreFromMetadata(meta);
                        return {
                            meta: meta,
                            index: idx,
                            score: breakdown.finalScore,
                            breakdown: breakdown,
                            title: meta.title || 'Unknown Finding',
                            section: meta.section || meta.category || 'Unknown'
                        };
                    }).sort((a, b) => b.score - a.score);
                }
            } else {
                // FALLBACK: DOM-based scoring (legacy behavior)
                const allCards = Array.from(document.querySelectorAll('.finding-card'));
                const findingCards = allCards.filter(card => card.dataset.severity === 'finding');
                totalCriticalCount = findingCards.length;

                if (findingCards.length > 0) {
                    scoredFindings = findingCards.map((card, idx) => {
                        const breakdown = calculateFindingScoreWithBreakdown(card);
                        return {
                            card: card,
                            index: idx,
                            score: breakdown.finalScore,
                            breakdown: breakdown,
                            title: card.querySelector('.finding-title')?.textContent || 'Unknown Finding',
                            section: card.closest('.section')?.querySelector('.section-title')?.textContent || 'Unknown'
                        };
                    }).sort((a, b) => b.score - a.score);
                }
            }

            if (totalCriticalCount === 0) {
                // No critical findings - show success message
                container.innerHTML = `
                    <div class="top-actions" style="border-color: var(--note); background: linear-gradient(135deg, var(--note-bg) 0%, var(--bg-card) 100%);">
                        <div class="top-actions-header">
                            <div class="top-actions-title" style="color: var(--note);">
                                <span class="icon">&#10003;</span>
                                Критических нарушений не обнаружено
                            </div>
                        </div>
                        <p style="margin: 0; color: var(--text-muted);">Критические нарушения не выявлены. Проверьте предупреждения и информационные результаты для дальнейшего улучшения защиты.</p>
                    </div>
                `;
                return;
            }

            // Take top 3
            const top3 = scoredFindings.slice(0, 3);

            // Generate HTML
            let actionsHTML = `
                <div class="top-actions">
                    <div class="top-actions-header">
                        <div class="top-actions-title">
                            <span class="icon">&#9889;</span>
                            Первоочередные меры по устранению рисков
                        </div>
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <span style="font-size: 12px; color: var(--text-muted);">${totalCriticalCount} критических нарушений всего</span>
                            <button class="top-actions-toggle" onclick="toggleTopActions()" title="Свернуть или развернуть приоритетные рекомендации">
                                <span class="toggle-icon">&#9660;</span>
                            </button>
                        </div>
                    </div>
                    <div class="top-actions-list">
            `;

            top3.forEach((item, index) => {
                // Resolve objectType and card ID from JSON metadata or DOM
                let cardId = '';
                let objectType = '';
                let checkTitle = item.title;

                if (item.meta) {
                    // JSON-based path: objectType from metadata
                    objectType = item.meta.objectType || '';
                    checkTitle = item.meta.title || item.title;
                } else if (item.card) {
                    // DOM-based fallback
                    cardId = item.card.dataset.cardId || '';
                    const checkHelpBtn = item.card.querySelector('.check-help-btn');
                    objectType = checkHelpBtn?.dataset.objectType || '';
                    checkTitle = checkHelpBtn?.dataset.checkTitle || item.title;
                }

                // Look up check description for professional title and impact text
                const checkInfo = (objectType && checkDescriptions) ? checkDescriptions[objectType] : null;

                // Professional title: checkDescriptions.title > internal check title
                const displayTitle = checkInfo?.title || item.title;

                // Prefer precise Russian security recommendations. Original definitions
                // remain intact for risk scoring and original-language reference.
                const findingDef = findBestFindingDefinition(item.meta || { title: item.title });
                const findingIdRu = findingDef
                    ? Object.keys(findingDefinitions).find(id => findingDefinitions[id] === findingDef)
                    : null;
                const explanationRu = findingIdRu ? (ruFindingExplanations[findingIdRu] || null) : null;
                const impactText = explanationRu?.impact?.[0] || checkInfo?.whyItMatters || '';
                const remediationText = explanationRu?.remediation?.[0] ||
                    'Откройте карточку нарушения, проверьте фактические права и область действия настройки; согласуйте изменение с владельцем системы.';
                const originalEnglishFix = explanationRu?.remediation?.length
                    ? '' : (findingDef?.remediation?.[0] || '');

                // Object count for "N affected" label
                const objectCount = item.meta?.objectCount || 0;

                // Build meta line: "N affected | Section"
                let metaHtml = '';
                if (objectCount > 0) {
                    metaHtml += `<span class="top-action-count">${objectCount} затронуто</span>`;
                }
                const ruModuleNames = {
                    domain:'Домен', accounts:'Учётные записи', rights:'Права доступа',
                    gpo:'Групповые политики', delegation:'Делегирование',
                    adcs:'AD CS', computer:'Компьютеры', creds:'Учётные данные',
                    application:'Приложения', shares:'Общие ресурсы',
                    bloodhound:'BloodHound'
                };
                const ruSection = ruModuleNames[String(item.section || '').toLowerCase()] || item.section;
                metaHtml += `<span class="top-action-section">${escapeHtml(ruSection)}</span>`;

                // Build buttons HTML (info button + score badge)
                let buttonsHtml = '';
                if (checkInfo) {
                    buttonsHtml += `<button class="top-action-info-btn" onclick="event.stopPropagation(); showTopActionInfo(this, '${escapeHtml(objectType)}', '${escapeHtml(checkTitle)}')" data-object-type="${escapeHtml(objectType)}" data-check-title="${escapeHtml(checkTitle)}" title="Подробности проверки">?</button>`;
                }
                const scoreClass = item.score >= scoreThresholds.critical ? 'score-critical' : item.score >= scoreThresholds.high ? 'score-high' : item.score >= scoreThresholds.medium ? 'score-medium' : item.score >= scoreThresholds.low ? 'score-low' : 'score-info';
                const breakdownJson = escapeJsonForAttr(item.breakdown);
                buttonsHtml += `<span class="top-action-score ${scoreClass}" data-score-breakdown='${breakdownJson}' onclick="event.stopPropagation(); showScoreTooltip(this, JSON.parse(this.dataset.scoreBreakdown));" style="cursor: pointer;">${item.score}</span>`;

                // Build detail lines (impact + remediation)
                let detailsHtml = '';
                if (impactText) {
                    detailsHtml += `<div class="top-action-details">${escapeHtml(impactText)}</div>`;
                }
                if (remediationText) {
                    detailsHtml += `<div class="top-action-fix">&rarr; ${escapeHtml(remediationText)}</div>`;
                }
                if (originalEnglishFix) {
                    detailsHtml += `<details class="top-action-original-en" lang="en" onclick="event.stopPropagation()"><summary>Точная рекомендация разработчика (оригинал EN)</summary><div>${escapeHtml(originalEnglishFix)}</div></details>`;
                }

                actionsHTML += `
                    <div class="top-action-item" data-target-card="${cardId}" data-target-title="${escapeHtml(checkTitle)}" data-target-index="${item.index}" onclick="scrollToFindingCard(this)" style="cursor: pointer;">
                        <div class="top-action-rank">${index + 1}</div>
                        <div class="top-action-content">
                            <div class="top-action-title">${escapeHtml(displayTitle)}</div>
                            <div class="top-action-meta">${metaHtml}</div>
                            ${detailsHtml}
                        </div>
                        <div class="top-action-buttons" onclick="event.stopPropagation()">${buttonsHtml}</div>
                    </div>
                `;
            });

            actionsHTML += `
                    </div>
                </div>
            `;

            container.innerHTML = actionsHTML;
        }

        function scrollToFindingCard(element) {
            const cardId = element.dataset.targetCard;
            const targetTitle = element.dataset.targetTitle;
            const targetIndex = parseInt(element.dataset.targetIndex);

            let card = cardId ? document.querySelector('.finding-card[data-card-id="' + cardId + '"]') : null;

            // Second try: find by data-check-title
            if (!card && targetTitle) {
                const allCards = Array.from(document.querySelectorAll('.finding-card'));
                card = allCards.find(c => {
                    const helpBtn = c.querySelector('.check-help-btn');
                    return helpBtn && helpBtn.dataset.checkTitle === targetTitle;
                });
            }

            // Fallback: find by index among finding cards
            if (!card && targetIndex >= 0) {
                const findingCards = Array.from(document.querySelectorAll('.finding-card')).filter(c => c.dataset.severity === 'finding');
                card = findingCards[targetIndex];
            }

            if (!card) return;

            // Reset filters to ensure the card is visible
            currentSeverityFilter = 'all';
            currentCategoryFilter = 'all';
            currentSearchQuery = '';

            // Update filter UI
            document.querySelectorAll('.severity-filter').forEach(f => f.classList.remove('active'));
            document.querySelectorAll('.nav-item[data-category]').forEach(f => f.classList.remove('active'));
            const allSeverityFilter = document.querySelector('.severity-filter[data-severity="all"]');
            const allCategoryFilter = document.querySelector('.nav-item[data-category="all"]');
            if (allSeverityFilter) allSeverityFilter.classList.add('active');
            if (allCategoryFilter) allCategoryFilter.classList.add('active');
            const searchInput = document.getElementById('searchInput');
            if (searchInput) searchInput.value = '';

            // Apply filters to show all cards and sections
            applyFilters();

            // Ensure the card is visible
            card.style.display = '';

            // Collapse all other cards first, then expand only the target card
            document.querySelectorAll('.finding-card.expanded').forEach(c => c.classList.remove('expanded'));
            card.classList.add('expanded');

            // Highlight the category in the sidebar
            highlightCategoryForCard(card);

            // Remove any previous highlight
            document.querySelectorAll('.finding-card.keyboard-focused').forEach(c => c.classList.remove('keyboard-focused'));

            // Use setTimeout to ensure the DOM has fully updated after view switch + filter changes
            setTimeout(() => {
                card.scrollIntoView({ behavior: 'auto', block: 'start' });
                card.classList.add('keyboard-focused');
                setTimeout(() => card.classList.remove('keyboard-focused'), UI_CONSTANTS.KEYBOARD_FOCUS_DURATION);
            }, 150);
        }

        function showTopActionInfo(btn, objectType, checkTitle) {
            // Look up check description by ObjectType
            if (!objectType || !checkDescriptions[objectType]) return;
            const checkInfo = checkDescriptions[objectType];

            // Build tooltip content similar to check tooltip
            let content = '<div class="top-action-tooltip-content">';
            content += '<div class="top-action-tooltip-header">' + escapeHtml(checkTitle) + '</div>';

            if (checkInfo.summary) {
                content += '<div class="top-action-tooltip-section">';
                content += '<div class="top-action-tooltip-label">Краткое описание</div>';
                content += '<div class="top-action-tooltip-text">' + escapeHtml(checkInfo.summary) + '</div>';
                content += '</div>';
            }

            if (checkInfo.whyItMatters) {
                content += '<div class="top-action-tooltip-section">';
                content += '<div class="top-action-tooltip-label">Почему это важно</div>';
                content += '<div class="top-action-tooltip-text">' + escapeHtml(checkInfo.whyItMatters) + '</div>';
                content += '</div>';
            }

            if (checkInfo.whatWeCheck && checkInfo.whatWeCheck.length > 0) {
                content += '<div class="top-action-tooltip-section">';
                content += '<div class="top-action-tooltip-label">Что проверяется</div>';
                content += '<ul class="top-action-tooltip-list">';
                checkInfo.whatWeCheck.forEach(item => {
                    content += '<li>' + escapeHtml(item) + '</li>';
                });
                content += '</ul>';
                content += '</div>';
            }

            if (checkInfo.filteringNote) {
                content += '<div class="top-action-tooltip-section top-action-tooltip-note">';
                content += '<div class="top-action-tooltip-label">Note</div>';
                content += '<div class="top-action-tooltip-text">' + escapeHtml(checkInfo.filteringNote) + '</div>';
                content += '</div>';
            }

            content += '</div>';

            // Show as tooltip near the button
            showTooltipAt(btn, content);
        }

        // Track active floating tooltip and its event listener for cleanup
        let activeFloatingTooltip = null;
        let activeFloatingTooltipListener = null;

        function showTooltipAt(element, content) {
            // Remove any existing tooltip and clean up its event listener
            if (activeFloatingTooltip) {
                activeFloatingTooltip.remove();
                if (activeFloatingTooltipListener) {
                    document.removeEventListener('click', activeFloatingTooltipListener);
                    activeFloatingTooltipListener = null;
                }
                activeFloatingTooltip = null;
            }

            // Create tooltip
            const tooltip = document.createElement('div');
            tooltip.className = 'remediation-floating-tooltip';
            tooltip.innerHTML = content;
            document.body.appendChild(tooltip);
            activeFloatingTooltip = tooltip;

            // Position near element with smart positioning
            const rect = element.getBoundingClientRect();
            const tooltipRect = tooltip.getBoundingClientRect();
            const viewportHeight = window.innerHeight;
            const viewportWidth = window.innerWidth;

            // Calculate vertical position - prefer below, but go above if not enough space
            let top;
            if (rect.bottom + tooltipRect.height + 20 > viewportHeight) {
                // Not enough space below - show above
                top = rect.top + window.scrollY - tooltipRect.height - 8;
            } else {
                // Show below
                top = rect.bottom + window.scrollY + 8;
            }

            // Calculate horizontal position
            let left = rect.left + window.scrollX - 100;
            if (left + tooltipRect.width > viewportWidth - UI_CONSTANTS.VIEWPORT_PADDING) {
                left = viewportWidth - tooltipRect.width - 20;
            }
            if (left < UI_CONSTANTS.VIEWPORT_PADDING) {
                left = UI_CONSTANTS.VIEWPORT_PADDING;
            }

            tooltip.style.top = top + 'px';
            tooltip.style.left = left + 'px';

            // Create named listener for proper cleanup
            activeFloatingTooltipListener = function closeTooltip(e) {
                if (!tooltip.contains(e.target) && e.target !== element) {
                    tooltip.remove();
                    document.removeEventListener('click', closeTooltip);
                    activeFloatingTooltip = null;
                    activeFloatingTooltipListener = null;
                }
            };

            // Close on outside click (with small delay to prevent immediate close)
            setTimeout(() => {
                if (activeFloatingTooltip === tooltip) {
                    document.addEventListener('click', activeFloatingTooltipListener);
                }
            }, UI_CONSTANTS.TOOLTIP_CLOSE_DELAY);
        }

        // ============================================================
        // SCORE SORT STATE
        // ============================================================

        // Populate score badges into finding card headers
        function populateCardScores() {
            const cards = document.querySelectorAll('.finding-card');
            if (!cards.length) return;

            cards.forEach((card, index) => {
                const severity = card.dataset.severity || 'note';

                // Note and Secure cards have no score
                if (severity === 'note' || severity === 'secure') return;

                // Calculate score from JSON metadata (preferred) or DOM fallback
                let breakdown;
                const cardIndex = parseInt(card.dataset.cardIndex);
                if (!isNaN(cardIndex) && scoringContext?.findingCards?.[cardIndex]) {
                    breakdown = calculateScoreFromMetadata(scoringContext.findingCards[cardIndex]);
                } else {
                    breakdown = calculateFindingScoreWithBreakdown(card);
                }

                if (breakdown.finalScore <= 0) return;

                // Determine score class
                const scoreClass = breakdown.finalScore >= scoreThresholds.critical ? 'score-critical' :
                                   breakdown.finalScore >= scoreThresholds.high ? 'score-high' :
                                   breakdown.finalScore >= scoreThresholds.medium ? 'score-medium' :
                                   breakdown.finalScore >= scoreThresholds.low ? 'score-low' : 'score-info';

                // Create score badge element
                const badge = document.createElement('span');
                badge.className = 'score-badge ' + scoreClass;
                badge.textContent = breakdown.finalScore;
                badge.dataset.scoreBreakdown = JSON.stringify(breakdown);
                badge.title = 'Risk Score (click for details)';
                badge.addEventListener('click', function(e) {
                    e.stopPropagation();
                    showScoreTooltip(this, breakdown);
                });

                // Insert badge into finding-meta area (before chevron, after count)
                const meta = card.querySelector('.finding-meta');
                const chevron = meta?.querySelector('.finding-toggle');
                if (meta && chevron) {
                    meta.insertBefore(badge, chevron);
                }

                // Store score on the card element for sorting
                card.dataset.score = breakdown.finalScore;
            });
        }

        // Severity order for sorting (lower = more critical)
        const SEVERITY_ORDER = { 'finding': 0, 'hint': 1, 'note': 2, 'secure': 3 };

        // Sort all finding cards by score (descending), then by severity
        // Called once after populateCardScores() — sections are hidden, cards are flat-sorted
        function sortCardsByScore() {
            const container = document.getElementById('cardViewContainer');
            if (!container) return;

            const allCards = Array.from(container.querySelectorAll('.finding-card'));
            if (allCards.length === 0) return;

            const scoredCards = allCards.map(card => ({
                element: card,
                score: parseInt(card.dataset.score) || 0,
                severity: SEVERITY_ORDER[card.dataset.severity] ?? 99
            }));

            // Sort by score descending, then by severity
            scoredCards.sort((a, b) => {
                if (b.score !== a.score) return b.score - a.score;
                return a.severity - b.severity;
            });

            // Hide all sections (cards are shown flat)
            container.querySelectorAll('.section').forEach(s => s.style.display = 'none');

            // Append sorted cards directly to container
            scoredCards.forEach(item => container.appendChild(item.element));
        }

        function expandAllCards() {
            // Expand all finding cards
            document.querySelectorAll('.finding-card').forEach(card => {
                card.classList.add('expanded');
            });
            // Expand top priority actions
            const topActions = document.querySelector('.top-actions');
            if (topActions) {
                topActions.classList.remove('collapsed');
                updateTopActionsToggleIcon(topActions);
            }
        }

        function collapseAllCards() {
            // Collapse all finding cards
            document.querySelectorAll('.finding-card').forEach(card => {
                card.classList.remove('expanded');
            });
            // Collapse top priority actions
            const topActions = document.querySelector('.top-actions');
            if (topActions) {
                topActions.classList.add('collapsed');
                updateTopActionsToggleIcon(topActions);
            }
        }

        function toggleTopActions() {
            const topActions = document.querySelector('.top-actions');
            if (topActions) {
                topActions.classList.toggle('collapsed');
                updateTopActionsToggleIcon(topActions);
            }
        }

        function updateTopActionsToggleIcon(topActions) {
            const toggleIcon = topActions.querySelector('.toggle-icon');
            if (toggleIcon) {
                toggleIcon.innerHTML = topActions.classList.contains('collapsed') ? '&#9654;' : '&#9660;';
            }
        }

        // ============================================================
        // COPY BUTTON for Remediation
        // ============================================================

        function copyToClipboard(button, text) {
            navigator.clipboard.writeText(text).then(() => {
                button.classList.add('copied');
                const originalText = button.textContent;
                button.textContent = 'Скопировано!';
                setTimeout(() => {
                    button.classList.remove('copied');
                    button.textContent = originalText;
                }, UI_CONSTANTS.COPY_FEEDBACK_DURATION);
            }).catch(err => {
                console.error('Failed to copy:', err);
                button.textContent = 'Failed';
                setTimeout(() => {
                    button.textContent = 'Copy';
                }, UI_CONSTANTS.COPY_FEEDBACK_DURATION);
            });
        }

        // ============================================================
        // Per-card name column resizing (Excel-like, not persisted)
        // ============================================================

        function initColumnResize() {
            const MIN_NAME_W = 120;   // px - keep the name column usable
            const MIN_VALUE_W = 140;  // px - keep the value column usable
            let resizer = null;
            let objectBody = null;
            let startX = 0;
            let startW = 0;
            let maxW = 0;

            document.addEventListener('mousedown', function(e) {
                const r = e.target.closest('.attr-col-resizer');
                if (!r) return;

                objectBody = r.closest('.object-body');
                if (!objectBody) return;

                e.preventDefault();
                resizer = r;

                // Current width from the CSS variable or the rendered name cell
                const nameCell = objectBody.querySelector('.attr-name');
                startW = nameCell ? nameCell.getBoundingClientRect().width : 280;
                startX = e.clientX;
                maxW = Math.max(MIN_NAME_W, objectBody.clientWidth - MIN_VALUE_W);

                resizer.classList.add('resizing');
                document.body.classList.add('col-resizing');
            });

            document.addEventListener('mousemove', function(e) {
                if (!resizer || !objectBody) return;
                e.preventDefault();
                let w = startW + (e.clientX - startX);
                w = Math.max(MIN_NAME_W, Math.min(w, maxW));
                objectBody.style.setProperty('--attr-name-w', w + 'px');
            });

            document.addEventListener('mouseup', function() {
                if (!resizer) return;
                resizer.classList.remove('resizing');
                document.body.classList.remove('col-resizing');
                resizer = null;
                objectBody = null;
            });
        }

        // ============================================================
        // DRAG & DROP Attribute Reordering
        // ============================================================

        function initAttributeDragAndDrop() {
            let draggedElement = null;

            // Only the dedicated drag handle starts a drag, so the rest of the
            // row text stays freely selectable / copyable.
            document.addEventListener('dragstart', function(e) {
                const handle = (e.target.classList && e.target.classList.contains('attr-drag-handle')) ? e.target : null;
                const row = handle ? handle.closest('.attr-row') : null;
                if (row) {
                    draggedElement = row;
                    row.classList.add('dragging');
                    e.dataTransfer.effectAllowed = 'move';
                    e.dataTransfer.setData('text/html', row.innerHTML);
                }
            });

            document.addEventListener('dragend', function() {
                if (draggedElement) {
                    draggedElement.classList.remove('dragging');
                    // Remove all drag-over indicators
                    document.querySelectorAll('.attr-row.drag-over').forEach(el => {
                        el.classList.remove('drag-over');
                    });
                    draggedElement = null;
                }
            });

            document.addEventListener('dragover', function(e) {
                if (!draggedElement) return;

                const target = e.target.closest('.attr-row');
                if (!target || target === draggedElement) return;

                e.preventDefault();
                e.dataTransfer.dropEffect = 'move';

                // Remove previous drag-over indicators
                document.querySelectorAll('.attr-row.drag-over').forEach(el => {
                    if (el !== target) el.classList.remove('drag-over');
                });

                // Add drag-over indicator to current target
                target.classList.add('drag-over');
            });

            document.addEventListener('drop', function(e) {
                if (!draggedElement) return;

                const target = e.target.closest('.attr-row');
                if (!target || target === draggedElement) return;

                e.preventDefault();
                e.stopPropagation();

                // Get target parent container
                const targetParent = target.parentNode;

                // Determine insertion position based on mouse Y position
                const targetRect = target.getBoundingClientRect();
                const midPoint = targetRect.top + (targetRect.height / 2);

                if (e.clientY < midPoint) {
                    // Insert before target
                    targetParent.insertBefore(draggedElement, target);
                } else {
                    // Insert after target
                    if (target.nextSibling) {
                        targetParent.insertBefore(draggedElement, target.nextSibling);
                    } else {
                        targetParent.appendChild(draggedElement);
                    }
                }

                // Remove drag-over indicator
                target.classList.remove('drag-over');

                // Update extended attributes counter after cross-container moves
                updateExtendedAttrCounters(draggedElement);
            });
        }

        // Update the "Show/Hide N more attribute(s)" counter after drag & drop
        function updateExtendedAttrCounters(movedElement) {
            // Find the closest object-body container
            const objectBody = movedElement.closest('.object-body');
            if (!objectBody) return;

            const extSection = objectBody.querySelector('.extended-attrs');
            const toggleBtn = objectBody.querySelector('.extended-attrs-toggle');
            if (!extSection || !toggleBtn) return;

            // Count remaining attr-rows in extended section
            const extCount = extSection.querySelectorAll(':scope > .attr-row').length;
            const textSpan = toggleBtn.querySelector('span:last-child');
            if (!textSpan) return;

            if (extCount === 0) {
                // No more extended attributes — hide toggle and section
                toggleBtn.style.display = 'none';
                extSection.style.display = 'none';
            } else {
                toggleBtn.style.display = '';
                // Update counter text, preserve Show/Hide prefix
                const currentText = textSpan.textContent;
                const prefix = currentText.startsWith('Hide') ? 'Hide' : 'Show';
                textSpan.textContent = prefix + ' ' + extCount + ' more attribute(s)';
            }
        }

        // ============================================================
        //  PRINT / PDF PREPARATION
        //  Ensures all content is expanded and a Table of Contents
        //  is generated before the browser renders the print layout.
        // ============================================================

        // State snapshot to restore after printing
        var printStateSnapshot = null;

        function preparePrint() {
            // Save current state so we can restore after printing
            printStateSnapshot = {
                expandedCards: [],
                collapsedTopActions: false,
                hiddenCompletedState: false
            };

            // Remember which cards were NOT expanded (so we can collapse them back)
            document.querySelectorAll('.finding-card:not(.expanded)').forEach(function(card) {
                printStateSnapshot.expandedCards.push(card);
            });

            // Remember top-actions state
            var topActions = document.querySelector('.top-actions');
            if (topActions && topActions.classList.contains('collapsed')) {
                printStateSnapshot.collapsedTopActions = true;
            }

            // Remember hide-completed state
            var hideToggle = document.getElementById('hideCompletedToggle');
            if (hideToggle && hideToggle.checked) {
                printStateSnapshot.hiddenCompletedState = true;
                hideToggle.checked = false;
                toggleHideCompleted();
            }

            // Expand ALL finding cards for print
            document.querySelectorAll('.finding-card').forEach(function(card) {
                card.classList.add('expanded');
            });

            // Expand top-actions
            if (topActions) {
                topActions.classList.remove('collapsed');
                updateTopActionsToggleIcon(topActions);
            }

            // Build Table of Contents from section headers
            buildPrintTOC();
        }

        function restoreAfterPrint() {
            if (!printStateSnapshot) return;

            // Collapse cards that were not expanded before print
            printStateSnapshot.expandedCards.forEach(function(card) {
                card.classList.remove('expanded');
            });

            // Restore top-actions collapsed state
            if (printStateSnapshot.collapsedTopActions) {
                var topActions = document.querySelector('.top-actions');
                if (topActions) {
                    topActions.classList.add('collapsed');
                    updateTopActionsToggleIcon(topActions);
                }
            }

            // Restore hide-completed state
            if (printStateSnapshot.hiddenCompletedState) {
                var hideToggle = document.getElementById('hideCompletedToggle');
                if (hideToggle) {
                    hideToggle.checked = true;
                    toggleHideCompleted();
                }
            }

            // Remove TOC
            var toc = document.getElementById('printTOC');
            if (toc) toc.remove();

            printStateSnapshot = null;
        }

        function buildPrintTOC() {
            // Remove existing TOC if any
            var existing = document.getElementById('printTOC');
            if (existing) existing.remove();

            var sections = document.querySelectorAll('.section');
            if (sections.length === 0) return;

            var toc = document.createElement('div');
            toc.id = 'printTOC';
            toc.className = 'print-toc';

            var tocTitle = document.createElement('div');
            tocTitle.className = 'print-toc-title';
            tocTitle.textContent = 'Table of Contents';
            toc.appendChild(tocTitle);

            // Build severity matrix table
            var table = document.createElement('table');
            table.className = 'print-toc-table';

            // Table header
            var thead = document.createElement('thead');
            var headerRow = document.createElement('tr');
            ['Section', 'Findings', 'Hints', 'Notes', 'Secure'].forEach(function(label) {
                var th = document.createElement('th');
                th.textContent = label;
                headerRow.appendChild(th);
            });
            thead.appendChild(headerRow);
            table.appendChild(thead);

            // Pre-build severity counts per section using data-category attribute
            // Note: Cards may be sorted flat outside their sections (sortCardsByScore),
            // so we use the card's data-category to map back to section IDs (cat-<category>)
            var sectionCounts = {};
            document.querySelectorAll('.finding-card[data-severity][data-category]').forEach(function(card) {
                var sid = 'cat-' + card.getAttribute('data-category');
                if (!sectionCounts[sid]) sectionCounts[sid] = { finding: 0, hint: 0, note: 0, secure: 0 };
                var sev = card.getAttribute('data-severity');
                if (sectionCounts[sid][sev] !== undefined) sectionCounts[sid][sev]++;
            });

            // Table body
            var tbody = document.createElement('tbody');
            var totals = { finding: 0, hint: 0, note: 0, secure: 0 };

            sections.forEach(function(section, index) {
                var titleEl = section.querySelector('.section-title');
                if (!titleEl) return;

                var sectionTitle = titleEl.textContent.trim();
                // Strip [N/M] prefix for cleaner display
                sectionTitle = sectionTitle.replace(/^\[\d+\/\d+\]\s*/, '');
                var sectionId = section.id;

                // Get pre-computed counts for this section
                var counts = sectionCounts[sectionId] || { finding: 0, hint: 0, note: 0, secure: 0 };

                // Accumulate totals
                totals.finding += counts.finding;
                totals.hint += counts.hint;
                totals.note += counts.note;
                totals.secure += counts.secure;

                // Determine highest severity for left border color
                var severity = counts.finding > 0 ? 'finding' : counts.hint > 0 ? 'hint' : counts.secure > 0 ? 'secure' : 'note';

                var row = document.createElement('tr');
                row.className = 'toc-severity-' + severity;

                // Section name cell with link
                var nameCell = document.createElement('td');
                nameCell.className = 'toc-section-name';
                var link = document.createElement('a');
                link.href = '#' + sectionId;
                link.textContent = (index + 1) + '. ' + sectionTitle;
                nameCell.appendChild(link);
                row.appendChild(nameCell);

                // Severity count cells
                [
                    { key: 'finding', cls: 'toc-cell-finding' },
                    { key: 'hint', cls: 'toc-cell-hint' },
                    { key: 'note', cls: 'toc-cell-note' },
                    { key: 'secure', cls: 'toc-cell-secure' }
                ].forEach(function(col) {
                    var td = document.createElement('td');
                    td.className = col.cls;
                    if (counts[col.key] > 0) {
                        td.textContent = counts[col.key];
                        td.classList.add('has-value');
                    } else {
                        td.textContent = '\u2013'; // en-dash
                        td.classList.add('no-value');
                    }
                    row.appendChild(td);
                });

                tbody.appendChild(row);
            });
            table.appendChild(tbody);

            // Table footer with totals
            var tfoot = document.createElement('tfoot');
            var footerRow = document.createElement('tr');

            var totalLabel = document.createElement('td');
            totalLabel.className = 'toc-section-name toc-total-label';
            totalLabel.textContent = 'Total';
            footerRow.appendChild(totalLabel);

            [
                { key: 'finding', cls: 'toc-cell-finding' },
                { key: 'hint', cls: 'toc-cell-hint' },
                { key: 'note', cls: 'toc-cell-note' },
                { key: 'secure', cls: 'toc-cell-secure' }
            ].forEach(function(col) {
                var td = document.createElement('td');
                td.className = col.cls;
                if (totals[col.key] > 0) {
                    td.textContent = totals[col.key];
                    td.classList.add('has-value');
                } else {
                    td.textContent = '\u2013';
                    td.classList.add('no-value');
                }
                footerRow.appendChild(td);
            });

            tfoot.appendChild(footerRow);
            table.appendChild(tfoot);

            toc.appendChild(table);

            // Insert TOC after info-bar, before card controls
            var infoBar = document.querySelector('.info-bar');
            if (infoBar && infoBar.parentNode) {
                infoBar.parentNode.insertBefore(toc, infoBar.nextSibling);
            }
        }

        // Register print event handlers
        window.addEventListener('beforeprint', preparePrint);
        window.addEventListener('afterprint', restoreAfterPrint);
