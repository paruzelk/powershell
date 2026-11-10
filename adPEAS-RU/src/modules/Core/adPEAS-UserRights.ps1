<#
.SYNOPSIS
    The user rights adPEAS evaluates, and who holds each of them by default.

.DESCRIPTION
    Get-GPOUserRightsAssignment used to decide by the identity of the holder: a right
    granted to a privileged SID, an operator group or a well-known service identity was
    hidden, everything else reported. That is the wrong question asked of the wrong half
    of the data, and it fails in both directions.

    It hides real findings. Backup Operators holding SeDebugPrivilege is not a Windows
    default and is a clean path to SYSTEM on every machine in scope - and it was silently
    suppressed, because the group is on the privileged list.

    It reports expected ones. Which principals hold a right by default depends on the
    right, not on how privileged the principal looks, and no identity list can express
    that.

    The question that actually matters is whether an assignment departs from what Windows
    ships, and this table is what makes that question answerable.

    WHY THE COMPARISON IS EXACT

    The [Privilege Rights] section of GptTmpl.inf is absolute, not additive: the principals
    listed for a right become the complete set of holders on every machine the GPO reaches.
    So the GPO's list and the default list are two sets describing the same thing, and the
    difference between them is meaningful in both directions:

      added   - holders beyond the default. The escalation risk, and the finding.
      removed - default holders the GPO drops. Usually deliberate hardening, occasionally
                an operational foot-gun; reported as a note, never as a finding.

    MEMBER AND DOMAIN CONTROLLER DEFAULTS DIFFER

    Server Operators hold rights on a domain controller that nobody holds on a member
    server, so each right carries both sets. The caller passes the scopes the GPO actually
    reaches and the union of those baselines is what counts as expected - a holder that is
    default somewhere the policy applies is not a deviation worth anyone's attention.

    WHERE THE DEFAULTS COME FROM, AND WHAT TO DO WHEN THEY ARE WRONG

    Every entry below is the documented Windows default. A wrong entry produces a false
    positive (a default reported) or a false negative (a deviation hidden), so a right
    whose default set is not established here carries $null rather than a guess. A $null
    baseline is not treated as "nobody holds this by default" - the check falls back to the
    identity filter for that right and says so in the finding, which keeps the uncertainty
    visible instead of silently deciding.

.NOTES
    Author: Alexander Sturz (@_61106960_)
    Reference: https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/user-rights-assignment
#>

# Well-known SIDs used below. Written out rather than referenced by name, because this
# table has to be readable next to the Windows documentation it mirrors.
#   S-1-1-0        Everyone                     S-1-5-32-544  Administrators
#   S-1-5-6        SERVICE                      S-1-5-32-545  Users
#   S-1-5-11       Authenticated Users          S-1-5-32-546  Guests
#   S-1-5-18       SYSTEM                       S-1-5-32-548  Account Operators
#   S-1-5-19       LOCAL SERVICE                S-1-5-32-549  Server Operators
#   S-1-5-20       NETWORK SERVICE              S-1-5-32-550  Print Operators
#   S-1-5-32-551   Backup Operators             S-1-5-32-555  Remote Desktop Users
#   S-1-5-32-559   Performance Log Users        S-1-5-32-568  IIS_IUSRS
#   S-1-5-90-0     Window Manager\Window Manager Group
#   S-1-5-80-0     NT SERVICE\ALL SERVICES
#   S-1-5-99-216390572-1995538116-3857911515-2404958512-2623887229
#                  RESTRICTED SERVICES\PrintSpoolerService

$Script:UserRightsBaseline = [ordered]@{

    # =========================================================================
    # Tier 1 - a direct route to SYSTEM, to credentials, or to the domain
    # =========================================================================

    'SeDebugPrivilege' = @{
        Name = 'Отладка программ'
        Tier = 'Finding'
        Why  = 'Позволяет открывать процессы, включая LSASS, и получать доступ к данным в памяти в пределах назначенной области.'
        # Administrators only, on a member and on a domain controller alike.
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeTcbPrivilege' = @{
        Name = 'Работа в режиме операционной системы'
        Tier = 'Finding'
        Why  = 'Даёт возможности, связанные с доверенной частью ОС и созданием маркеров доступа. Назначайте только в исключительных случаях.'
        # Nobody by default. Windows grants this to no principal out of the box.
        Member = @()
        DC     = @()
    }

    'SeCreateTokenPrivilege' = @{
        Name = 'Создание объекта токена'
        Tier = 'Finding'
        Why  = 'Позволяет создавать маркеры доступа. Ошибочное назначение создаёт высокий риск повышения привилегий.'
        Member = @()
        DC     = @()
    }

    'SeImpersonatePrivilege' = @{
        Name = 'Имитация клиента после проверки подлинности'
        Tier = 'Finding'
        Why  = 'Позволяет процессу действовать от имени проверенного клиента. При определённых условиях используется для локального повышения привилегий.'
        # Administrators and the three service identities.
        Member = @('S-1-5-32-544', 'S-1-5-6', 'S-1-5-19', 'S-1-5-20')
        DC     = @('S-1-5-32-544', 'S-1-5-6', 'S-1-5-19', 'S-1-5-20')
    }

    'SeAssignPrimaryTokenPrivilege' = @{
        Name = 'Замена токена уровня процесса'
        Tier = 'Finding'
        Why  = 'Позволяет процессу назначать основной маркер доступа. В сочетании с другими разрешениями может применяться для повышения привилегий.'
        Member = @('S-1-5-19', 'S-1-5-20')
        DC     = @('S-1-5-19', 'S-1-5-20')
    }

    'SeLoadDriverPrivilege' = @{
        Name = 'Загрузка и выгрузка драйверов устройств'
        Tier = 'Finding'
        Why  = 'Позволяет загружать драйверы ядра; эксплуатация уязвимого подписанного драйвера может привести к компрометации системы.'
        Member = @('S-1-5-32-544')
        # Print Operators hold it on a domain controller, for printer drivers.
        DC     = @('S-1-5-32-544', 'S-1-5-32-550')
    }

    'SeBackupPrivilege' = @{
        Name = 'Архивирование файлов и каталогов'
        Tier = 'Finding'
        Why  = 'Разрешает читать файлы в режиме резервного копирования в обход отдельных файловых ACL; на контроллере домена может затронуть базу NTDS.'
        Member = @('S-1-5-32-544', 'S-1-5-32-551')
        DC     = @('S-1-5-32-544', 'S-1-5-32-551', 'S-1-5-32-549')
    }

    'SeRestorePrivilege' = @{
        Name = 'Восстановление файлов и каталогов'
        Tier = 'Finding'
        Why  = 'Разрешает восстановление и запись файлов в обход части файловых ACL, включая операции над владельцем.'
        Member = @('S-1-5-32-544', 'S-1-5-32-551')
        DC     = @('S-1-5-32-544', 'S-1-5-32-551', 'S-1-5-32-549')
    }

    'SeTakeOwnershipPrivilege' = @{
        Name = 'Смена владельцев файлов и других объектов'
        Tier = 'Finding'
        Why  = 'Позволяет принять владение объектом и впоследствии изменить его разрешения, если применимы соответствующие права.'
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeEnableDelegationPrivilege' = @{
        Name = 'Разрешение доверия учётных записей для делегирования'
        Tier = 'Finding'
        Why  = 'Позволяет изменять параметры доверия к учётным записям для делегирования Kerberos. Ошибочная выдача расширяет риск подмены контекста пользователей.'
        # Administrators in both scopes, which takes the Default values table over the body
        # text where the two disagree. The table gives "Member Server Effective" and "Client
        # Computer Effective" as Administrators; the body says there is "no reason to assign
        # this user right to anyone on member servers and workstations ... because it has no
        # meaning in those contexts". That sentence is advice, not a statement of the default -
        # and it is the reason this list used to be empty.
        #
        # Empty made a member-scoped GPO that grants Administrators the right - a right the
        # local effective policy already gives them - a Tier-1 Finding. The union across scopes
        # masked it for any GPO that also reaches a domain controller, so what was exposed was
        # the member-only case. Granting it to anybody else there is still reported.
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/enable-computer-and-user-accounts-to-be-trusted-for-delegation
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeSyncAgentPrivilege' = @{
        Name = 'Синхронизация данных службы каталогов'
        Tier = 'Finding'
        Why  = 'Это право связано с получением данных службы каталогов и требует ограничения доверенными системными субъектами.'
        Member = @()
        DC     = @()
    }

    'SeManageVolumePrivilege' = @{
        Name = 'Обслуживание томов'
        Tier = 'Finding'
        Why  = 'Даёт доступ к операциям обслуживания тома, которые могут обходить обычные ограничения файловой системы.'
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeSecurityPrivilege' = @{
        Name = 'Управление аудитом и журналом безопасности'
        # Hint, not Finding. Every other right in the Finding tier hands the holder
        # SYSTEM, the contents of NTDS.dit, kernel code or ownership of any object.
        # This one is anti-forensics: it destroys the record of an intrusion rather
        # than enabling one, so it does not belong beside them.
        Tier = 'Hint'
        Why  = 'Позволяет управлять политикой аудита и журналом безопасности. Избыточные права могут затруднить расследование событий.'
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeRelabelPrivilege' = @{
        Name = 'Изменение метки объекта'
        Tier = 'Finding'
        Why  = 'Позволяет изменять метки целостности объектов и тем самым влиять на ограничения механизма контроля целостности Windows.'
        Member = @()
        DC     = @()
    }

    'SeTrustedCredManAccessPrivilege' = @{
        Name = 'Доступ к диспетчеру учётных данных в качестве доверенного вызывающего'
        Tier = 'Finding'
        Why  = 'Даёт расширенный доступ к сохранённым учётным данным пользователей на компьютере.'
        Member = @()
        DC     = @()
    }

    # =========================================================================
    # Tier 2 - a foothold or a way across, rather than straight up
    # =========================================================================

    'SeRemoteInteractiveLogonRight' = @{
        Name = 'Вход через службы удалённых рабочих столов'
        Tier = 'Hint'
        Why  = 'Разрешает интерактивный вход по RDP; оцените полномочия субъектов на соответствующих компьютерах.'
        Member = @('S-1-5-32-544', 'S-1-5-32-555')
        # A domain controller does not carry Remote Desktop Users in its default policy.
        DC     = @('S-1-5-32-544')
    }

    'SeInteractiveLogonRight' = @{
        Name = 'Локальный вход в систему'
        Tier = 'Hint'
        Why  = 'Разрешает интерактивный вход за консолью. Особенно критично для контроллеров домена и серверов Tier 0.'
        # Administrators, Backup Operators, Users - the three Microsoft documents for
        # workstations and servers. Guests (S-1-5-32-546) used to sit here and does not
        # belong: the same page names Guests as a candidate for "Deny log on locally", so
        # listing it as a default suppressed a finding on a GPO that genuinely grants Guests
        # a console session.
        Member = @('S-1-5-32-544', 'S-1-5-32-551', 'S-1-5-32-545')
        # Six on a domain controller, not five. S-1-5-9 ENTERPRISE DOMAIN CONTROLLERS is a
        # documented default here and was missing, which reported the untouched Default
        # Domain Controllers Policy of every domain as departing from the default.
        #
        # It reads like a mistake because a computer account does not open a console session,
        # but the default is the default: Microsoft names it both in the body text ("the
        # members of the following groups have this right on domain controllers") and in the
        # Default Domain Controller Policy row of the Default values table.
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/allow-log-on-locally
        DC     = @('S-1-5-32-544', 'S-1-5-32-548', 'S-1-5-32-551', 'S-1-5-9', 'S-1-5-32-550', 'S-1-5-32-549')
    }

    'SeBatchLogonRight' = @{
        Name = 'Вход в качестве пакетного задания'
        Tier = 'Hint'
        Why  = 'Разрешает запуск пакетных заданий и задач планировщика от имени данной учётной записи.'
        Member = @('S-1-5-32-544', 'S-1-5-32-551', 'S-1-5-32-559')
        DC     = @('S-1-5-32-544', 'S-1-5-32-551', 'S-1-5-32-559')
    }

    'SeServiceLogonRight' = @{
        Name = 'Вход в качестве службы'
        Tier = 'Hint'
        Why  = 'Разрешает запуск служб Windows от имени данной учётной записи.'
        # Deliberately no baseline. What holds this varies with every product installed on
        # the machine - SQL, Exchange and IIS each add their own service accounts - so any
        # list here would be wrong on most domains in one direction or the other. The
        # check falls back to the identity filter for this right and says so.
        Member = $null
        DC     = $null
    }

    'SeSystemtimePrivilege' = @{
        Name = 'Изменение системного времени'
        Tier = 'Hint'
        Why  = 'Позволяет изменять время системы, что может нарушить работу Kerberos и журналирование событий.'
        Member = @('S-1-5-32-544', 'S-1-5-19')
        DC     = @('S-1-5-32-544', 'S-1-5-19', 'S-1-5-32-549')
    }

    'SeRemoteShutdownPrivilege' = @{
        Name = 'Принудительное завершение работы из удалённой системы'
        Tier = 'Hint'
        Why  = 'Разрешает удалённое завершение работы компьютера и может использоваться для отказа в обслуживании.'
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544', 'S-1-5-32-549')
    }

    'SeShutdownPrivilege' = @{
        Name = 'Завершение работы системы'
        Tier = 'Hint'
        Why  = 'Позволяет выключать компьютер; на критических серверах влияет на доступность инфраструктуры.'
        # Users (S-1-5-32-545) is a CLIENT default, not a member-server one: Microsoft gives
        # "Member Server Effective" as Administrators and Backup Operators, and only "Client
        # Computer Effective" adds Users. adPEAS has one non-DC bucket for both, so it has to
        # pick, and it picks the wider one - dropping Users would report the untouched default
        # of every workstation baseline GPO, which is the far more common object.
        Member = @('S-1-5-32-544', 'S-1-5-32-545', 'S-1-5-32-551')
        # Four on a domain controller, not five. Account Operators (S-1-5-32-548) was here and
        # is not a documented holder: "By default this setting is Administrators, Backup
        # Operators, Server Operators, and Print Operators on domain controllers", and both
        # the Default Domain Controller Policy and the Domain Controller Effective rows name
        # those same four. The AD DS groups page gives Account Operators exactly one default
        # right, Allow log on locally - shutdown is not among them.
        #
        # The entry most likely came from the Windows Server 2003 page, which did list "Allow
        # log on locally; Shut down the system" for Account Operators. The modern pages dropped
        # the second while keeping it on Print, Backup and Server Operators.
        #
        # Direction matters: this was a false NEGATIVE. It silently accepted a GPO granting
        # Account Operators shutdown on domain controllers.
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/shut-down-the-system
        DC     = @('S-1-5-32-544', 'S-1-5-32-551', 'S-1-5-32-550', 'S-1-5-32-549')
    }

    # The seven below were not evaluated at all: a GPO granting one of them to Domain Users
    # passed without a word. Defaults from the "Default values" table of each right's
    # Microsoft page (Domain Controller and Member Server Effective Default Settings).

    'SeCreateSymbolicLinkPrivilege' = @{
        Name = 'Создание символических ссылок'
        Tier = 'Hint'
        Why  = 'Разрешает создавать символические ссылки, которые могут влиять на файловые операции других процессов.'
        # Administrators. The Hyper-V role adds NT VIRTUAL MACHINE\Virtual Machines on a host
        # where it is installed; that is the role, not the Windows default.
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/create-symbolic-links
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeDelegateSessionUserImpersonatePrivilege' = @{
        Name = 'Получение токена другого пользователя в том же сеансе'
        Tier = 'Hint'
        Why  = 'Даёт возможность получать маркер имитации другого пользователя того же сеанса при соблюдении условий Windows.'
        # Microsoft documents what the privilege does (Privilege Constants, winnt.h) and
        # publishes no default holder set for it, so the comparison falls back to the
        # identity filter and says so, rather than guessing a default.
        Member = $null
        DC     = $null
    }

    'SeAuditPrivilege' = @{
        Name = 'Формирование аудита безопасности'
        Tier = 'Hint'
        Why  = 'Позволяет формировать записи аудита безопасности. При злоупотреблении может затруднить анализ подлинных событий.'
        # LOCAL SERVICE and NETWORK SERVICE, on a member and on a domain controller alike.
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/generate-security-audits
        Member = @('S-1-5-19', 'S-1-5-20')
        DC     = @('S-1-5-19', 'S-1-5-20')
        # Accepted, not expected: the print spooler's restricted service SID. The Default
        # Domain Controllers Policy a Windows Server 2025 domain is created with grants it -
        # measured - and one created earlier has the same policy without it, which is no
        # deviation either. Not on a member, where it has not been measured.
        Optional = @{ DC = @('S-1-5-99-216390572-1995538116-3857911515-2404958512-2623887229') }
    }

    'SeSystemEnvironmentPrivilege' = @{
        Name = 'Изменение параметров среды микропрограммы'
        Tier = 'Hint'
        Why  = 'Позволяет изменять настройки среды UEFI/микропрограммы, в том числе влияющие на загрузку системы.'
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/modify-firmware-environment-values
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeCreateGlobalPrivilege' = @{
        Name = 'Создание глобальных объектов'
        Tier = 'Hint'
        Why  = 'Разрешает создавать глобальные объекты ядра Windows; назначение должно быть ограничено доверенными службами.'
        # Administrators, LOCAL SERVICE, NETWORK SERVICE and SERVICE.
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/create-global-objects
        Member = @('S-1-5-32-544', 'S-1-5-19', 'S-1-5-20', 'S-1-5-6')
        DC     = @('S-1-5-32-544', 'S-1-5-19', 'S-1-5-20', 'S-1-5-6')
    }

    'SeProfileSingleProcessPrivilege' = @{
        Name = 'Профилирование отдельного процесса'
        Tier = 'Hint'
        Why  = 'Позволяет собирать статистику работы процессов, потенциально раскрывая сведения о запущенных службах.'
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/profile-single-process
        Member = @('S-1-5-32-544')
        DC     = @('S-1-5-32-544')
    }

    'SeSystemProfilePrivilege' = @{
        Name = 'Профилирование производительности системы'
        Tier = 'Hint'
        Why  = 'Позволяет профилировать систему в целом и получать дополнительные сведения о работе процессов.'
        # Administrators and NT SERVICE\WdiServiceHost, as the page's own text says - its
        # table lists Administrators alone. The service SID is derived from the service name
        # (SHA-1 of the upper-cased name) and is the same on every machine; checked against
        # sc.exe showsid WdiServiceHost.
        # https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/profile-system-performance
        Member = @('S-1-5-32-544', 'S-1-5-80-3139157870-2983391045-3678747466-658725712-1809340420')
        DC     = @('S-1-5-32-544', 'S-1-5-80-3139157870-2983391045-3678747466-658725712-1809340420')
    }
}

# SeMachineAccountPrivilege is deliberately absent: Get-AddComputerRights covers it
# together with ms-DS-MachineAccountQuota, which is the other half of that story.
# The Se*Deny* rights are absent as well - they take access away.

<#
.SYNOPSIS
    Compares the holders a GPO assigns to a right against the Windows default.

.DESCRIPTION
    Returns what the GPO adds beyond the default and what it removes from it, or nothing
    when the right is not one adPEAS evaluates. The [Privilege Rights] section is absolute,
    so both directions are real statements about the machines in scope.

.PARAMETER Right
    The constant, for instance SeDebugPrivilege.

.PARAMETER HolderSID
    The SIDs the GPO assigns the right to.

.PARAMETER Scope
    Which default sets apply: Member, DC, or both when the GPO reaches both kinds of
    machine. A holder that is default in any scope the policy reaches is not a deviation.

.OUTPUTS
    Hashtable with Added, Removed, HasBaseline, Tier, Name and Why - or $null for a right
    outside the table.
#>
function Compare-UserRightAssignment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Right,

        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string[]]$HolderSID,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Member', 'DC')]
        [string[]]$Scope = @('Member')
    )

    $entry = $Script:UserRightsBaseline[$Right]
    if (-not $entry) { return $null }

    # The union of the baselines for every scope the GPO reaches. A holder that is default
    # on a domain controller is not a deviation in a policy that also reaches one.
    $baseline = @()
    $hasBaseline = $false
    foreach ($s in @($Scope)) {
        if ($null -ne $entry[$s]) {
            $hasBaseline = $true
            $baseline += @($entry[$s])
        }
    }

    # Holders a default may or may not contain, depending on the Windows version the policy
    # was created by. Never reported as added, never as removed.
    $optional = @()
    if ($entry.Optional) {
        foreach ($s in @($Scope)) {
            if ($null -ne $entry.Optional[$s]) { $optional += @($entry.Optional[$s]) }
        }
    }

    $holders = @($HolderSID | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if (-not $hasBaseline) {
        # No documented default for this right. Everything is reported as added and the
        # caller is told the comparison did not happen, so it can fall back rather than
        # present a guess as a deviation.
        return @{
            Added       = $holders
            Removed     = @()
            HasBaseline = $false
            Tier        = $entry.Tier
            Name        = $entry.Name
            Why         = $entry.Why
        }
    }

    # Compare-Object is avoided on purpose: it unrolls a single-element side and returns
    # nothing for two empty ones, both of which have bitten this codebase before.
    $added = @($holders | Where-Object { ($baseline -notcontains $_) -and ($optional -notcontains $_) })
    $removed = @($baseline | Where-Object { $holders -notcontains $_ })

    return @{
        Added       = $added
        Removed     = $removed
        HasBaseline = $true
        Tier        = $entry.Tier
        Name        = $entry.Name
        Why         = $entry.Why
    }
}
