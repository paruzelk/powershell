function Get-adPEASSession {
<#
.SYNOPSIS
    Shows information about the current adPEAS session or tests connection health.

.DESCRIPTION
    Displays detailed information about the current LDAP connection and session.
    Shows Domain, Server, Protocol, Authentication and Session duration.

    With -TestConnection switch, performs a health check on the active session:
    - Checks session variables
    - Validates LDAP connection object
    - Executes test query to verify connectivity
    - Measures query latency

.PARAMETER TestConnection
    Performs a connection health check instead of showing session info.
    Tests if the session is still active and responsive.
    Shows detailed diagnostic information including domain, server, latency.

.PARAMETER Quiet
    Suppresses all output during TestConnection.
    Only returns $true/$false without displaying test results.
    Useful when called programmatically (e.g., from Invoke-adPEAS).

.EXAMPLE
    Get-adPEASSession
    Shows current session information.

.EXAMPLE
    Get-adPEASSession -TestConnection
    Performs connection health check with diagnostic details.

.EXAMPLE
    Get-adPEASSession -TestConnection -Quiet
    Performs silent health check, returns only $true/$false.

.EXAMPLE
    if (Get-adPEASSession -TestConnection -Quiet) {
        Write-Host "Connection is healthy"
    }

.OUTPUTS
    Without -TestConnection: Displays session information to console
    With -TestConnection: $true if connection is healthy, $false if problems exist

.NOTES
    Author: Alexander Sturz (@_61106960_)
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$TestConnection,

        [Parameter(Mandatory=$false)]
        [switch]$Quiet
    )

    process {
        # Check if session exists (common check for both modes)
        # LdapConnection is used for ALL LDAP operations (queries and modifications)
        $hasLdapConnection = ($null -ne $Script:LdapConnection)

        if (-not $Script:LDAPContext -or -not $hasLdapConnection) {
            if ($TestConnection) {
                if (-not $Quiet) {
                    Show-SubHeader "Проверка состояния подключения..."
                    Show-KeyValue "Переменные сеанса:" "ОШИБКА: активный сеанс отсутствует" -Class Finding
                    return
                }
                return $false
            } else {
                Show-NoSessionError -Context "Get-adPEASSession"
                return $null
            }
        }

        # Test Connection Health
        if ($TestConnection) {
            try {
                # Only show output if not in Quiet mode
                if (-not $Quiet) {
                    Show-Line "Состояние:" -Class Hint
                    Show-SubHeader "Проверка состояния подключения..."
                }

                $testResults = @{
                    SessionExists = $true
                    ConnectionValid = $false
                    QuerySuccessful = $false
                    Latency = $null
                    HealthStatus = "Unknown"
                    Errors = @()
                }

                # Test 1: Session variables (already checked above)
                if (-not $Quiet) {
                    Show-KeyValue "Переменные сеанса:" "ПРОЙДЕНО" -Class Standard
                }

                # Test 2: Check if connection object is valid
                # LdapConnection is the only connection object used for all operations
                if ($hasLdapConnection) {
                    $protocol = if ($Script:LDAPContext.UseLDAPS) { "LDAPS" } else { "LDAP" }
                    if (-not $Quiet) {
                        Show-KeyValue "Объект подключения LDAP:" "ПРОЙДЕНО (LdapConnection для $protocol)" -Class Standard
                    }
                }
                else {
                    if (-not $Quiet) {
                        Show-KeyValue "Объект подключения LDAP:" "ОШИБКА: объект подключения не найден" -Class Finding
                        return
                    }
                    return $false
                }

                # Test 3: Execute test query
                $queryStartTime = Get-Date

                try {
                    $testQuery = Invoke-LDAPSearch -Filter "(objectClass=domain)" -SearchBase $Script:LDAPContext.DomainDN -Properties "name" -Scope Base

                    if (-not $testQuery) {
                        if (-not $Quiet) {
                            Show-KeyValue "Выполнение LDAP-запроса:" "ОШИБКА: тестовый запрос не вернул результатов" -Class Finding
                            return
                        }
                        return $false
                    }

                    $queryEndTime = Get-Date
                    $latency = ($queryEndTime - $queryStartTime).TotalMilliseconds

                    if (-not $Quiet) {
                        Show-KeyValue "Выполнение LDAP-запроса:" "ПРОЙДЕНО (задержка: $([math]::Round($latency, 2)) мс)" -Class Standard
                    }
                    $testResults.QuerySuccessful = $true
                    $testResults.Latency = [math]::Round($latency, 2)

                }
                catch {
                    if (-not $Quiet) {
                        Show-KeyValue "Выполнение LDAP-запроса:" "ОШИБКА: $($_.Exception.Message)" -Class Finding
                        return
                    }
                    return $false
                }

                # All tests passed
                $testResults.HealthStatus = "Healthy"

                if (-not $Quiet) {
                    Show-KeyValue "Результат:" "ПРОЙДЕНО (все проверки успешны — соединение исправно)" -Class Note
                    Show-EmptyLine
                    return
                }

                return $true
            }
            catch {
                if (-not $Quiet) {
                    Show-KeyValue "Непредвиденная ошибка:" "ОШИБКА: $($_.Exception.Message)" -Class Finding
                    Show-EmptyLine
                    return
                }
                return $false
            }
        }

        # Show Session Information (default)
        else {
            # Use SubHeader for session info (big ===== headers reserved for Invoke-adPEAS modules)
            Show-SubHeader "Сведения об активном сеансе..."

            # Connection Details
            Show-Line "Подключение:" -Class Hint
            Show-KeyValue "Домен:" $Script:LDAPContext.Domain

            # Display Domain SID
            if ($Script:LDAPContext.DomainSID) {
                Show-KeyValue "SID домена:" $Script:LDAPContext.DomainSID
            }

            Show-KeyValue "Сервер:" $Script:LDAPContext.Server
            if ($Script:LDAPContext['ServerIP']) {
                Show-KeyValue "IP сервера:" $Script:LDAPContext['ServerIP']
            }
            Show-KeyValue "Протокол:" "$($Script:LDAPContext.Protocol) (порт $($Script:LDAPContext.Port))"
            Show-KeyValue "DN домена:" $Script:LDAPContext.DomainDN

            # Authentication Details
            Show-EmptyLine
            Show-Line "Аутентификация:" -Class Hint

            if ($Script:LDAPContext.KerberosUsed -and $Script:LDAPContext.TGTInfo -and $Script:LDAPContext.TGTInfo.UserName) {
                # For Kerberos auth (Hash/Key/PKINIT), show TGT user
                $TGTUser = "$($Script:LDAPContext.TGTInfo.UserName)@$($Script:LDAPContext.TGTInfo.Domain)"
                Show-KeyValue "Подключение от имени:" $TGTUser

                # Show User SID if available
                if ($Script:LDAPContext.AuthenticatedUserSID) {
                    Show-KeyValue "SID пользователя:" $Script:LDAPContext.AuthenticatedUserSID
                }

                # Show NT-Hash if recovered via UnPAC-the-hash (PKINIT only)
                if ($Script:LDAPContext.TGTInfo.NTHash) {
                    Show-KeyValue "NT-Hash:" $Script:LDAPContext.TGTInfo.NTHash
                }
            }
            elseif ($Script:LDAPContext.AuthenticatedUser) {
                Show-KeyValue "Подключение от имени:" $Script:LDAPContext.AuthenticatedUser

                # Show User SID if available
                if ($Script:LDAPContext.AuthenticatedUserSID) {
                    Show-KeyValue "SID пользователя:" $Script:LDAPContext.AuthenticatedUserSID
                }

                if ($Script:LDAPContext.IdentityMismatch) {
                    Show-KeyValue "Локальная учётная запись:" $Script:LDAPContext.LocalIdentity
                    Show-Line "  Несовпадение личности: ОБНАРУЖЕНО" -Class Hint
                }

                # Show DN and UPN if available
                if ($Script:LDAPContext.AuthenticatedUserDN) {
                    Show-KeyValue "Различающееся имя (DN):" $Script:LDAPContext.AuthenticatedUserDN
                }
                if ($Script:LDAPContext.AuthenticatedUserUPN) {
                    Show-KeyValue "Основное имя пользователя (UPN):" $Script:LDAPContext.AuthenticatedUserUPN
                }
            }
            # Fallback if LDAP verification not available
            elseif ($Script:LDAPContext.Credential) {
                Show-KeyValue "Подключение от имени:" $Script:LDAPContext.Credential.UserName
            }
            else {
                Show-KeyValue "Подключение от имени:" "$env:USERDOMAIN\$env:USERNAME"
            }

            # Authentication Method (Kerberos vs SimpleBind vs Schannel vs NTLM)
            $AuthMethodDisplay = switch ($Script:LDAPContext.AuthMethod) {
                'Kerberos' {
                    # Check if TGT info is available (explicit Kerberos) or detected via SSPI
                    if ($Script:LDAPContext.TGTInfo) {
                        'Kerberos (TGT/TGS)'
                    } else {
                        'Kerberos (SSPI)'
                    }
                }
                'Schannel' { 'Schannel (TLS Client Certificate)' }
                'SimpleBind' { if ($Script:LDAPContext.UseLDAPS) { 'SimpleBind (LDAPS)' } else { 'SimpleBind (LDAP)' } }
                'WindowsSSPI' { 'Windows SSPI (Negotiate)' }
                'WindowsAuth' { 'Windows Authentication (Negotiate)' }
                'NTLM' { if ($Script:LDAPContext.UseLDAPS) { 'NTLM (LDAPS)' } else { 'NTLM (LDAP)' } }
                'NTLM Impersonation' { 'NTLM Impersonation (runas /netonly)' }
                default { 'Unknown' }
            }
            Show-KeyValue "Метод аутентификации:" $AuthMethodDisplay

            # Show TGT details if Kerberos was used
            if ($Script:LDAPContext.KerberosUsed -and $Script:LDAPContext.TGTInfo) {
                $TGT = $Script:LDAPContext.TGTInfo

                # Encryption type mapping (from original session)
                $ETypeDisplay = switch ($TGT.EncryptionType) {
                    17 { 'AES128-CTS-HMAC-SHA1' }
                    18 { 'AES256-CTS-HMAC-SHA1' }
                    23 { 'RC4-HMAC (NTLM)' }
                    default { "etype $($TGT.EncryptionType)" }
                }
                Show-KeyValue "Шифрование TGT:" $ETypeDisplay

                # Show TGT method (how the TGT was obtained)
                if ($TGT.Method) {
                    Show-KeyValue "Способ получения TGT:" $TGT.Method
                }

                # Show TGT realm
                if ($TGT.Domain) {
                    Show-KeyValue "Область Kerberos (TGT):" $TGT.Domain
                }

                # Show clock skew between local system and KDC
                if ($TGT.ClockSkew -and $TGT.ClockSkew -is [TimeSpan]) {
                    $skewSeconds = [Math]::Round($TGT.ClockSkew.TotalSeconds)
                    $skewAbs = [Math]::Abs($skewSeconds)
                    $skewSign = if ($skewSeconds -ge 0) { "+" } else { "-" }
                    if ($skewAbs -ge 3600) {
                        $skewDisplay = "${skewSign}$([Math]::Floor($skewAbs / 3600))h $([Math]::Floor(($skewAbs % 3600) / 60))m"
                    } elseif ($skewAbs -ge 60) {
                        $skewDisplay = "${skewSign}$([Math]::Floor($skewAbs / 60))m $($skewAbs % 60)s"
                    } else {
                        $skewDisplay = "${skewSign}${skewAbs}s"
                    }
                    if ($skewAbs -gt 300) {
                        # >5 minutes - exceeds Kerberos tolerance
                        Show-KeyValue "Расхождение времени:" "$skewDisplay (ПРЕДУПРЕЖДЕНИЕ: превышен допустимый для Kerberos предел в 5 минут!)" -Class Finding
                    } elseif ($skewAbs -gt 270) {
                        # 4.5-5 minutes - close to Kerberos tolerance
                        Show-KeyValue "Расхождение времени:" "$skewDisplay (ПРЕДУПРЕЖДЕНИЕ: приближение к пределу Kerberos в 5 минут)" -Class Finding
                    } elseif ($skewAbs -gt 60) {
                        Show-KeyValue "Расхождение времени:" $skewDisplay -Class Hint
                    } else {
                        Show-KeyValue "Расхождение времени:" $skewDisplay
                    }
                }

                # LIVE TGT Status Check via LSA API
                # Use -Force to bypass the 60-second cache and get real-time ticket status
                $LiveTicketStatus = Test-KerberosTGTExists -Detailed -Force

                if ($LiveTicketStatus.Valid) {
                    # Tickets are valid - show live EndTime from LSA
                    $endTimeLocal = $LiveTicketStatus.EndTime.ToLocalTime()
                    $now = Get-Date
                    $timeRemaining = $LiveTicketStatus.EndTime - $now

                    if ($timeRemaining.TotalSeconds -gt 0) {
                        $remainingDisplay = "{0:hh\:mm\:ss}" -f $timeRemaining
                        Show-KeyValue "TGT действителен до:" "$(Format-adPEASDate $endTimeLocal 'yyyy-MM-dd HH:mm:ss') (осталось $remainingDisplay)"
                    }
                    else {
                        Show-KeyValue "TGT действителен до:" "$(Format-adPEASDate $endTimeLocal 'yyyy-MM-dd HH:mm:ss')" -Class Finding
                        Write-Warning "[!] TGT ИСТЁК — требуется повторная аутентификация!"
                    }

                }
                elseif ($LiveTicketStatus.TicketCount -eq 0) {
                    # Tickets were purged (klist purge)
                    Show-KeyValue "Состояние TGT:" "В КЭШЕ НЕТ БИЛЕТОВ — повторите аутентификацию через Connect-adPEAS" -Class Finding
                }
                elseif (-not $LiveTicketStatus.TGTPresent) {
                    # Tickets exist but no TGT (only service tickets)
                    Show-KeyValue "Состояние TGT:" "TGT НЕ НАЙДЕН (служебных билетов: $($LiveTicketStatus.TicketCount)) — повторите аутентификацию через Connect-adPEAS" -Class Finding
                }
                elseif ($LiveTicketStatus.Expired) {
                    # TGT exists but is expired
                    $expiredTime = if ($LiveTicketStatus.EndTime) {
                        (Format-adPEASDate $LiveTicketStatus.EndTime.ToLocalTime() 'yyyy-MM-dd HH:mm:ss')
                    } else { "unknown" }
                    Show-KeyValue "Состояние TGT:" "ИСТЁК в $expiredTime — повторите аутентификацию через Connect-adPEAS" -Class Finding
                }
                elseif ($LiveTicketStatus.ClientMatch -eq $false) {
                    # TGT exists but for different user
                    $tgtClient = $LiveTicketStatus.ClientName
                    $expectedClient = $Script:LDAPContext.TGTInfo.UserName
                    Show-KeyValue "Состояние TGT:" "НЕСОВПАДЕНИЕ ПОЛЬЗОВАТЕЛЯ (TGT=$tgtClient, ожидался=$expectedClient) — повторите аутентификацию через Connect-adPEAS" -Class Finding
                }
                else {
                    # Unknown issue with tickets
                    Show-KeyValue "Состояние TGT:" "НЕДЕЙСТВИТЕЛЕН — повторите аутентификацию через Connect-adPEAS" -Class Finding
                }
            }

            # Session Metadata
            Show-EmptyLine
            Show-Line "Сеанс:" -Class Hint
            if ($Script:LDAPContext.SessionStartTime) {
                $sessionDuration = (Get-Date) - $Script:LDAPContext.SessionStartTime
                # Through Format-adPEASDate like every other date: handed over as a DateTime,
                # the start read "10/18/2026 14:55:10" - the invariant culture's month first.
                # And the hours in full: 'hh' is the hour of the day, so a session of 26
                # hours read "02:00:00".
                Show-KeyValue "Начало сеанса:" (Format-adPEASDate $Script:LDAPContext.SessionStartTime 'yyyy-MM-dd HH:mm:ss')
                Show-KeyValue "Продолжительность сеанса:" ('{0:00}:{1:mm\:ss}' -f [Math]::Floor($sessionDuration.TotalHours), $sessionDuration)
            }

            # Connection State - check live TGT status for Kerberos sessions
            if ($Script:LDAPContext.KerberosUsed) {
                # Re-use LiveTicketStatus if already queried, otherwise query again with -Force
                if (-not $LiveTicketStatus) {
                    $LiveTicketStatus = Test-KerberosTGTExists -Detailed -Force
                }

                if ($LiveTicketStatus.Valid) {
                    Show-KeyValue "Состояние подключения:" "Подключено (Kerberos TGT действителен)"
                }
                elseif ($LiveTicketStatus.TicketCount -eq 0) {
                    Show-KeyValue "Состояние подключения:" "НЕПОЛНОЕ ПОДКЛЮЧЕНИЕ (нет билетов Kerberos)" -Class Finding
                }
                elseif (-not $LiveTicketStatus.TGTPresent) {
                    Show-KeyValue "Состояние подключения:" "НЕПОЛНОЕ ПОДКЛЮЧЕНИЕ (нет TGT, есть только служебные билеты)" -Class Finding
                }
                elseif ($LiveTicketStatus.Expired) {
                    Show-KeyValue "Состояние подключения:" "НЕПОЛНОЕ ПОДКЛЮЧЕНИЕ (срок TGT истёк)" -Class Finding
                }
                elseif ($LiveTicketStatus.ClientMatch -eq $false) {
                    Show-KeyValue "Состояние подключения:" "НЕПОЛНОЕ ПОДКЛЮЧЕНИЕ (пользователь TGT не совпадает)" -Class Finding
                }
                else {
                    Show-KeyValue "Состояние подключения:" "НЕПОЛНОЕ ПОДКЛЮЧЕНИЕ (TGT недействителен)" -Class Finding
                }
            }
            elseif ($Script:LDAPContext.AuthMethod -eq 'Schannel') {
                Show-KeyValue "Состояние подключения:" "Подключено (Schannel/TLS)"
            }
            else {
                Show-KeyValue "Состояние подключения:" "Подключено"
            }

            # Hints
            Show-EmptyLine
            Show-Line "Справка:" -Class Hint
            Show-KeyValue "Get-adPEASSession -TestConnection" "Проверить состояние подключения"
            Show-KeyValue "Disconnect-adPEAS" "Завершить сеанс"
            Show-EmptyLine
        }
    }
}
