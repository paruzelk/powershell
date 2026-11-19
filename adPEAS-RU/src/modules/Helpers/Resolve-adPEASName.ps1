<#
.SYNOPSIS
    Central DNS resolution for adPEAS with support for hostname-to-IP and DC discovery.

.DESCRIPTION
    Unified DNS resolution function for adPEAS that handles two primary use cases:

    Mode 1: Hostname to IP Resolution (-Name parameter)
        Returns: IP address string or $null
        Use case: Resolving explicit hostnames for TCP connections
        Example: User specifies -Server "dc01.contoso.com" -> resolve to IP

    Mode 2: Domain Controller Discovery (-Domain parameter)
        Returns: PSCustomObject with Hostname and IP
        Use case: Auto-discovering DC when no explicit server specified
        Example: User only specifies -Domain "contoso.com" -> find DC via SRV records

    Features:
    - Uses custom DNS server if specified via -DnsServer or $Script:LDAPContext['DnsServer']
    - Falls back to system DNS resolution
    - Caches resolved IP addresses in $Script:LDAPContext['DnsCache']
    - SRV record lookup for DC discovery (_ldap._tcp.dc._msdcs.<domain>)
    - STALE SRV RECORD HANDLING: Queries ALL SRV records and tests reachability (Port 88 Kerberos + Port 389/636 LDAP) before returning a DC
    - Automatic failover to next DC if first DC is unreachable
    - Reverse DNS for hostname discovery when SRV unavailable

    DC Discovery Order:
    1. Query ALL SRV records for _ldap._tcp.dc._msdcs.<domain>
    2. Sort by Priority (lower = better) and Weight (higher = better)
    3. For each DC: Resolve hostname -> Test Port 88 + 389/636 -> Return if reachable
    4. Fallback: Reverse DNS lookup via system DNS (with reachability test)
    5. Last resort: Direct A record lookup for domain name (with reachability test)

    Resolution Order (for custom DNS):
    1. Resolve-DnsName cmdlet (Windows 8+ / Server 2012+)
    2. Raw UDP DNS query (fallback for older systems or if cmdlet unavailable)
    3. System DNS via [System.Net.Dns] (final fallback)

.PARAMETER Name
    The hostname to resolve to an IP address.
    Returns: IP address string or $null.
    Use this when the user explicitly specified a server/DC.
    Cannot be used together with -Domain.

.PARAMETER Domain
    The domain FQDN to discover a Domain Controller for.
    Returns: PSCustomObject with Hostname and IP properties.
    Use this when no explicit server was specified (auto-discovery).
    Cannot be used together with -Name.

.PARAMETER DnsServer
    Optional. Explicit DNS server IP address to use for this query.
    Must be an IP address (e.g., "10.10.10.1"), not a hostname.
    If not specified, uses $Script:LDAPContext['DnsServer'] if available.

.PARAMETER NoCache
    Skip the cache lookup and force a fresh DNS query.

.PARAMETER UseLDAPS
    When testing DC reachability, test Port 636 instead of Port 389.
    This should match the intended LDAP connection type.

.EXAMPLE
    # Mode 1: Resolve explicit hostname to IP
    Resolve-adPEASName -Name "dc01.contoso.com"
    Returns: "10.0.0.1" (IP address string) or $null

.EXAMPLE
    # Mode 1 with custom DNS
    Resolve-adPEASName -Name "dc01.contoso.com" -DnsServer "10.10.10.1"
    Returns: "10.0.0.1" (IP address string) or $null

.EXAMPLE
    # Mode 2: Discover DC for domain (SRV + reverse DNS)
    Resolve-adPEASName -Domain "contoso.com"
    Returns: @{ Hostname = "dc01.contoso.com"; IP = "10.0.0.1" }

.EXAMPLE
    # Mode 2 with LDAPS reachability test
    Resolve-adPEASName -Domain "contoso.com" -UseLDAPS
    Returns: @{ Hostname = "dc01.contoso.com"; IP = "10.0.0.1" }

.OUTPUTS
    For -Name: [string] IP address or $null if resolution failed.

    For -Domain: [PSCustomObject] with properties:
    - Hostname: The DC hostname (for SPN construction)
    - IP: The resolved IP address (for TCP connections)
    Returns $null if resolution completely failed.

.NOTES
    Author: Alexander Sturz (@_61106960_)
#>

#region Helper Functions

function Invoke-RawDnsQuery {
    <#
    .SYNOPSIS
        Performs a raw UDP DNS query (RFC 1035). Internal helper function.
    .DESCRIPTION
        Fallback DNS resolver for systems where Resolve-DnsName is not available.
        Sends a UDP DNS query directly to the specified DNS server and parses the response.
        Supports A-record (IPv4) and SRV-record lookups.
    .PARAMETER Name
        The hostname to resolve.
        For SRV queries, use the full SRV name (e.g., "_ldap._tcp.dc._msdcs.contoso.com").
    .PARAMETER DnsServer
        The DNS server IP address.
    .PARAMETER Type
        The DNS record type to query. Valid values: 'A' (default) or 'SRV'.
    .PARAMETER Timeout
        Query timeout in milliseconds. Default: 5000 (5 seconds).
    .PARAMETER ReturnAllSRV
        For SRV queries only: If set, returns ALL SRV records as an array sorted by Priority/Weight.
        Otherwise returns only the first (best) record. Default: $false.
    .OUTPUTS
        For A records: [string] IPv4 address if successful, $null otherwise.
        For SRV records: [PSCustomObject] or [PSCustomObject[]] with Priority, Weight, Port, Target properties, or $null.
    .NOTES
        Internal use only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$DnsServer,

        [Parameter(Mandatory = $false)]
        [ValidateSet('A', 'SRV')]
        [string]$Type = 'A',

        [Parameter(Mandatory = $false)]
        [int]$Timeout = 5000,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnAllSRV
    )

    $udpClient = $null

    try {
        # Build DNS query packet (RFC 1035)
        # Header: 12 bytes
        # Question: variable length

        # Generate random transaction ID (2 bytes)
        $transactionId = [byte[]]@(
            [byte](Get-Random -Minimum 0 -Maximum 256),
            [byte](Get-Random -Minimum 0 -Maximum 256)
        )

        # DNS Header (12 bytes)
        # Flags: 0x0100 = Standard query, recursion desired
        $header = [byte[]]@(
            $transactionId[0], $transactionId[1],  # Transaction ID
            0x01, 0x00,                             # Flags: Standard query, RD=1
            0x00, 0x01,                             # Questions: 1
            0x00, 0x00,                             # Answer RRs: 0
            0x00, 0x00,                             # Authority RRs: 0
            0x00, 0x00                              # Additional RRs: 0
        )

        # Build QNAME (domain name in DNS format)
        # Each label prefixed with length byte, terminated with 0x00
        $qname = [System.Collections.Generic.List[byte]]::new()
        $labels = $Name.Split('.')
        foreach ($label in $labels) {
            # Skip empty labels (e.g., from "test..example.com")
            if ([string]::IsNullOrEmpty($label)) {
                continue
            }
            $labelBytes = [System.Text.Encoding]::ASCII.GetBytes($label)
            # RFC 1035: Each label is limited to 63 octets
            if ($labelBytes.Length -gt 63) {
                Write-Log "[Invoke-RawDnsQuery] Метка DNS превышает предел 63 байта: $label"
                return $null
            }
            $qname.Add([byte]$labelBytes.Length)
            $qname.AddRange($labelBytes)
        }
        $qname.Add(0x00)  # Null terminator

        # QTYPE: A=1, SRV=33 (RFC 1035, RFC 2782)
        $qtype = switch ($Type) {
            'A'   { 1 }
            'SRV' { 33 }
        }

        # QTYPE and QCLASS (IN = 0x0001)
        $question = [byte[]]@(
            [byte](($qtype -shr 8) -band 0xFF),
            [byte]($qtype -band 0xFF),
            0x00, 0x01  # QCLASS IN
        )

        # Combine packet
        $packet = [byte[]]($header + $qname.ToArray() + $question)

        # Send UDP query
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.ReceiveTimeout = $Timeout
        $udpClient.Client.SendTimeout = $Timeout

        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($DnsServer), 53)
        $udpClient.Connect($endpoint)
        $null = $udpClient.Send($packet, $packet.Length)

        # Receive response
        $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $response = $udpClient.Receive([ref]$remoteEP)

        # Parse response
        if ($response.Length -lt 12) {
            Write-Log "[Invoke-RawDnsQuery] Слишком короткий ответ DNS: $($response.Length) байт"
            return $null
        }

        # Check transaction ID matches
        if ($response[0] -ne $transactionId[0] -or $response[1] -ne $transactionId[1]) {
            Write-Log "[Invoke-RawDnsQuery] Несовпадение идентификатора транзакции"
            return $null
        }

        # Check for errors (RCODE in lower 4 bits of byte 3)
        $rcode = $response[3] -band 0x0F
        if ($rcode -ne 0) {
            Write-Log "[Invoke-RawDnsQuery] Ошибка DNS, код RCODE: $rcode"
            return $null
        }

        # Get answer count (bytes 6-7, big-endian)
        $answerCount = ($response[6] -shl 8) -bor $response[7]
        if ($answerCount -eq 0) {
            Write-Log "[Invoke-RawDnsQuery] Ответ DNS не содержит записей"
            return $null
        }

        # Skip header (12 bytes) and question section
        $offset = 12

        # Skip QNAME (handles both regular labels and compression pointers)
        while ($offset -lt $response.Length -and $response[$offset] -ne 0) {
            if (($response[$offset] -band 0xC0) -eq 0xC0) {
                # Compression pointer - skip 2 bytes and done (no null terminator after pointer)
                $offset += 2
                break
            }
            $offset += $response[$offset] + 1
        }
        # Skip null terminator only if we didn't hit a compression pointer
        if ($offset -lt $response.Length -and $response[$offset] -eq 0) { $offset++ }

        # Skip QTYPE and QCLASS (4 bytes)
        $offset += 4

        # Helper function to read a DNS name (handles compression pointers)
        # RFC 1035: Maximum recursion depth to prevent infinite loops from malformed responses
        $MaxPointerDepth = 10

        $ReadDnsName = {
            param([byte[]]$Data, [int]$StartOffset)

            $name = [System.Collections.Generic.List[string]]::new()
            $currentOffset = $StartOffset
            $bytesRead = 0
            $jumped = $false
            $pointerDepth = 0
            $visitedOffsets = [System.Collections.Generic.HashSet[int]]::new()

            while ($currentOffset -lt $Data.Length) {
                $labelLen = $Data[$currentOffset]

                if ($labelLen -eq 0) {
                    # End of name
                    if (-not $jumped) { $bytesRead++ }
                    break
                }

                if (($labelLen -band 0xC0) -eq 0xC0) {
                    # Compression pointer (2 bytes)
                    if ($currentOffset + 1 -ge $Data.Length) { break }

                    # Prevent infinite loop from cyclic pointers
                    $pointerDepth++
                    if ($pointerDepth -gt $MaxPointerDepth) {
                        Write-Log "[Invoke-RawDnsQuery] Превышена глубина указателей; возможен некорректный ответ DNS"
                        break
                    }

                    $pointer = (($labelLen -band 0x3F) -shl 8) -bor $Data[$currentOffset + 1]

                    # Detect self-referencing or already-visited pointer (infinite loop prevention)
                    if ($pointer -eq $currentOffset -or $visitedOffsets.Contains($pointer)) {
                        Write-Log "[Invoke-RawDnsQuery] Зацикленный указатель по смещению $pointer; некорректный ответ DNS"
                        break
                    }
                    $null = $visitedOffsets.Add($currentOffset)

                    if (-not $jumped) { $bytesRead += 2 }
                    $jumped = $true
                    $currentOffset = $pointer
                    continue
                }

                # Regular label
                if (-not $jumped) { $bytesRead += $labelLen + 1 }
                $currentOffset++
                if ($currentOffset + $labelLen -gt $Data.Length) { break }
                $label = [System.Text.Encoding]::ASCII.GetString($Data, $currentOffset, $labelLen)
                $name.Add($label)
                $currentOffset += $labelLen
            }

            return @{
                Name = $name -join '.'
                BytesRead = $bytesRead
            }
        }

        # Collect SRV records for sorting by priority
        $srvRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Parse answer records
        for ($i = 0; $i -lt $answerCount -and $offset -lt $response.Length; $i++) {
            # Skip NAME (may be compressed)
            if (($response[$offset] -band 0xC0) -eq 0xC0) {
                $offset += 2  # Compression pointer
            }
            else {
                while ($offset -lt $response.Length -and $response[$offset] -ne 0) {
                    $offset += $response[$offset] + 1
                }
                $offset++  # Skip null terminator
            }

            # Check if we have enough bytes for the fixed fields
            if ($offset + 10 -gt $response.Length) { break }

            # TYPE (2 bytes)
            $recordType = ($response[$offset] -shl 8) -bor $response[$offset + 1]
            $offset += 2

            # CLASS (2 bytes) - skip
            $offset += 2

            # TTL (4 bytes) - skip
            $offset += 4

            # RDLENGTH (2 bytes)
            $rdlength = ($response[$offset] -shl 8) -bor $response[$offset + 1]
            $offset += 2

            # Check for A record (type 1) with 4 bytes of data
            if ($Type -eq 'A' -and $recordType -eq 1 -and $rdlength -eq 4 -and $offset + 4 -le $response.Length) {
                $ip = "$($response[$offset]).$($response[$offset + 1]).$($response[$offset + 2]).$($response[$offset + 3])"
                return $ip
            }

            # Check for SRV record (type 33)
            if ($Type -eq 'SRV' -and $recordType -eq 33 -and $rdlength -ge 7 -and $offset + $rdlength -le $response.Length) {
                # SRV RDATA: Priority (2), Weight (2), Port (2), Target (variable)
                $priority = ($response[$offset] -shl 8) -bor $response[$offset + 1]
                $weight = ($response[$offset + 2] -shl 8) -bor $response[$offset + 3]
                $port = ($response[$offset + 4] -shl 8) -bor $response[$offset + 5]

                # Read target hostname (starts at offset + 6)
                $targetResult = & $ReadDnsName $response ($offset + 6)
                $target = $targetResult.Name

                if ($target) {
                    $srvRecords.Add([PSCustomObject]@{
                        Priority = $priority
                        Weight   = $weight
                        Port     = $port
                        Target   = $target.TrimEnd('.')
                    })
                }
            }

            # Skip RDATA
            $offset += $rdlength
        }

        # Return results based on query type
        if ($Type -eq 'SRV' -and $srvRecords.Count -gt 0) {
            # Sort by Priority (lower = preferred), then by Weight (higher = preferred)
            $sortedRecords = @($srvRecords | Sort-Object Priority, @{Expression={-$_.Weight}})
            Write-Log "[Invoke-RawDnsQuery] Найдено SRV-записей: $($srvRecords.Count)"

            if ($ReturnAllSRV) {
                # Return ALL records sorted by priority/weight
                return $sortedRecords
            }
            else {
                # Return only the best record (legacy behavior)
                $bestRecord = $sortedRecords[0]
                Write-Log "[Invoke-RawDnsQuery] Возвращается предпочтительная SRV-запись: $($bestRecord.Target):$($bestRecord.Port) (приоритет: $($bestRecord.Priority))"
                return $bestRecord
            }
        }

        Write-Log "[Invoke-RawDnsQuery] В ответе отсутствует запись типа $Type"
        return $null
    }
    catch {
        Write-Log "[Invoke-RawDnsQuery] Ошибка: $_"
        return $null
    }
    finally {
        if ($udpClient) {
            $udpClient.Close()
        }
    }
}

function Resolve-HostnameToIP {
    <#
    .SYNOPSIS
        Resolves a hostname to an IP address. Internal helper function.
    .NOTES
        Internal use only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $false)]
        [string]$DnsServer,

        [Parameter(Mandatory = $false)]
        [switch]$NoCache
    )

    # Check if input is already an IP address
    $ipAddress = $null
    if ([System.Net.IPAddress]::TryParse($Hostname, [ref]$ipAddress)) {
        Write-Log "[Resolve-HostnameToIP] Исходное значение уже является IP-адресом: $Hostname"
        return $Hostname
    }

    # Initialize DNS cache if not exists
    if ($Script:LDAPContext -and -not $Script:LDAPContext['DnsCache']) {
        $Script:LDAPContext['DnsCache'] = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    # Check cache first (unless NoCache specified)
    if (-not $NoCache -and $Script:LDAPContext -and $Script:LDAPContext['DnsCache'] -and $Script:LDAPContext['DnsCache'].ContainsKey($Hostname)) {
        $cachedIP = $Script:LDAPContext['DnsCache'][$Hostname]
        Write-Log "[Resolve-HostnameToIP] Найдено в кэше для $Hostname : $cachedIP"
        return $cachedIP
    }

    # Try custom DNS server if specified
    if ($DnsServer) {
        Write-Log "[Resolve-HostnameToIP] Разрешение $Hostname через указанный DNS-сервер: $DnsServer"

        # Method 1: Resolve-DnsName cmdlet (Windows 8+ / Server 2012+)
        try {
            $DnsResult = Resolve-DnsName -Name $Hostname -Server $DnsServer -Type A -DnsOnly -ErrorAction Stop

            if ($DnsResult -and $DnsResult.IPAddress) {
                $ResolvedIP = ($DnsResult | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1).IPAddress

                if ($ResolvedIP) {
                    Write-Log "[Resolve-HostnameToIP] Имя $Hostname разрешено в $ResolvedIP через Resolve-DnsName"

                    # Cache the result
                    if ($Script:LDAPContext -and $Script:LDAPContext['DnsCache']) {
                        $Script:LDAPContext['DnsCache'][$Hostname] = $ResolvedIP
                    }

                    return $ResolvedIP
                }
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Log "[Resolve-HostnameToIP] Resolve-DnsName недоступен; используется резервный запрос UDP"
        }
        catch {
            Write-Log "[Resolve-HostnameToIP] Ошибка Resolve-DnsName: $_"
        }

        # Method 2: Raw UDP DNS query (fallback)
        try {
            $UdpResult = Invoke-RawDnsQuery -Name $Hostname -DnsServer $DnsServer -Type A

            if ($UdpResult) {
                Write-Log "[Resolve-HostnameToIP] Имя $Hostname разрешено в $UdpResult через DNS-запрос UDP"

                # Cache the result
                if ($Script:LDAPContext -and $Script:LDAPContext['DnsCache']) {
                    $Script:LDAPContext['DnsCache'][$Hostname] = $UdpResult
                }

                return $UdpResult
            }
        }
        catch {
            Write-Log "[Resolve-HostnameToIP] Ошибка запроса UDP DNS: $_"
        }
    }

    # Fallback: System DNS
    Write-Log "[Resolve-HostnameToIP] Разрешение $Hostname через системный DNS"

    try {
        $DnsResult = [System.Net.Dns]::GetHostEntry($Hostname)

        if ($DnsResult -and $DnsResult.AddressList.Count -gt 0) {
            # Prefer IPv4 address, fallback to IPv6
            $ResolvedAddr = $DnsResult.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1

            if (-not $ResolvedAddr) {
                $ResolvedAddr = $DnsResult.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' } | Select-Object -First 1
            }

            if ($ResolvedAddr) {
                $ResolvedIP = $ResolvedAddr.IPAddressToString
                Write-Log "[Resolve-HostnameToIP] Имя $Hostname разрешено в $ResolvedIP через системный DNS"

                # Cache the result
                if ($Script:LDAPContext -and $Script:LDAPContext['DnsCache']) {
                    $Script:LDAPContext['DnsCache'][$Hostname] = $ResolvedIP
                }

                return $ResolvedIP
            }
        }
    }
    catch {
        Write-Log "[Resolve-HostnameToIP] Ошибка разрешения имени системным DNS: $_"
    }

    # Resolution failed
    Write-Log "[Resolve-HostnameToIP] Не удалось разрешить имя $Hostname"
    return $null
}

function Test-DCReachable {
    <#
    .SYNOPSIS
        Tests if a Domain Controller is reachable by checking critical ports. Internal helper function.
    .DESCRIPTION
        Performs TCP connection tests to verify DC availability.
        Tests Port 88 (Kerberos KDC) first as it's the most reliable DC indicator,
        then Port 389 (LDAP) or Port 636 (LDAPS).
    .PARAMETER IP
        The IP address to test.
    .PARAMETER Hostname
        Optional hostname (for logging purposes).
    .PARAMETER TimeoutMs
        Connection timeout in milliseconds. Default: 1000 (1 second).
    .PARAMETER UseLDAPS
        If set, tests Port 636 instead of Port 389.
    .OUTPUTS
        $true if DC is reachable, $false otherwise.
    .NOTES
        Internal use only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IP,

        [Parameter(Mandatory = $false)]
        [string]$Hostname,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMs = 1000,

        [Parameter(Mandatory = $false)]
        [switch]$UseLDAPS
    )

    $DisplayName = if ($Hostname) { "$Hostname ($IP)" } else { $IP }
    $LdapPort = if ($UseLDAPS) { 636 } else { 389 }

    # Helper function to test a single port with proper resource cleanup
    $TestPort = {
        param([string]$TargetIP, [int]$Port, [int]$Timeout)

        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $client.BeginConnect($TargetIP, $Port, $null, $null)
            $waitSuccess = $asyncResult.AsyncWaitHandle.WaitOne($Timeout, $false)

            if ($waitSuccess) {
                # Must call EndConnect to complete the async operation (prevents resource leaks)
                try {
                    $client.EndConnect($asyncResult)
                    return $client.Connected
                }
                catch {
                    # EndConnect throws if connection failed
                    return $false
                }
            }
            else {
                # Timeout - connection did not complete in time
                return $false
            }
        }
        catch {
            return $false
        }
        finally {
            # Guaranteed cleanup
            if ($client) {
                try { $client.Close() } catch { }
                try { $client.Dispose() } catch { }
            }
        }
    }

    # Test Port 88 (Kerberos KDC) - best indicator of a real DC
    $kerberosReachable = & $TestPort $IP 88 $TimeoutMs

    if ($kerberosReachable) {
        Write-Log "[Test-DCReachable] $DisplayName — порт 88 (Kerberos) доступен"

        # Also verify LDAP port is open
        $ldapReachable = & $TestPort $IP $LdapPort $TimeoutMs

        if ($ldapReachable) {
            Write-Log "[Test-DCReachable] $DisplayName — порт $LdapPort (LDAP) доступен; контроллер домена отвечает"
            return $true
        }
        else {
            Write-Log "[Test-DCReachable] $DisplayName — порт $LdapPort (LDAP) недоступен"
            return $false
        }
    }
    else {
        Write-Log "[Test-DCReachable] $DisplayName — порт 88 (Kerberos) недоступен; контроллер домена не отвечает"
        return $false
    }
}

function Resolve-SrvRecord {
    <#
    .SYNOPSIS
        Resolves DNS SRV records. Internal helper function.
    .PARAMETER Name
        The SRV record name to query.
    .PARAMETER DnsServer
        Optional custom DNS server.
    .PARAMETER ReturnAll
        If set, returns ALL SRV records sorted by Priority/Weight.
        Otherwise returns only the first (best) record.
    .OUTPUTS
        Single PSCustomObject or array of PSCustomObjects with Target, Port, Priority, Weight.
    .NOTES
        Internal use only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$DnsServer,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnAll
    )

    $AllRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Try custom DNS server if specified
    if ($DnsServer) {
        Write-Log "[Resolve-SrvRecord] Разрешение SRV $Name через указанный DNS-сервер: $DnsServer"

        # Method 1: Resolve-DnsName cmdlet
        try {
            $DnsResult = Resolve-DnsName -Name $Name -Server $DnsServer -Type SRV -DnsOnly -ErrorAction Stop

            # Safely check if we got valid SRV records
            # $DnsResult can be $null, a single object, or an array
            if ($null -ne $DnsResult) {
                # Filter for SRV records that have a NameTarget property
                $SrvRecordsFound = @($DnsResult | Where-Object { $null -ne $_.NameTarget })

                if ($SrvRecordsFound.Count -gt 0) {
                    # Sort by Priority (lower = better), then by Weight (higher = better)
                    $SortedRecords = $SrvRecordsFound | Sort-Object Priority, @{Expression={-$_.Weight}}

                    foreach ($rec in $SortedRecords) {
                        $AllRecords.Add([PSCustomObject]@{
                            Target = $rec.NameTarget.TrimEnd('.')
                            Port = $rec.Port
                            Priority = $rec.Priority
                            Weight = $rec.Weight
                        })
                    }

                    if ($AllRecords.Count -gt 0) {
                        Write-Log "[Resolve-SrvRecord] Найдено SRV-записей через Resolve-DnsName: $($AllRecords.Count)"
                        if ($ReturnAll) { return $AllRecords.ToArray() }
                        return $AllRecords[0]
                    }
                }
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Log "[Resolve-SrvRecord] Resolve-DnsName недоступен; используется резервный запрос UDP"
        }
        catch {
            Write-Log "[Resolve-SrvRecord] Ошибка Resolve-DnsName: $_"
        }

        # Method 2: Raw UDP DNS query (fallback)
        if ($AllRecords.Count -eq 0) {
            try {
                $UdpResult = Invoke-RawDnsQuery -Name $Name -DnsServer $DnsServer -Type SRV -ReturnAllSRV:$ReturnAll

                if ($UdpResult) {
                    # Handle both single record and array results
                    if ($UdpResult -is [System.Array]) {
                        Write-Log "[Resolve-SrvRecord] Найдено SRV-записей через UDP DNS: $($UdpResult.Count)"
                        foreach ($rec in $UdpResult) {
                            $AllRecords.Add($rec)
                        }
                        if ($ReturnAll) { return $AllRecords.ToArray() }
                        return $AllRecords[0]
                    }
                    elseif ($UdpResult.Target) {
                        Write-Log "[Resolve-SrvRecord] Найдена SRV-запись: $($UdpResult.Target):$($UdpResult.Port) через UDP DNS"
                        return $UdpResult
                    }
                }
            }
            catch {
                Write-Log "[Resolve-SrvRecord] Ошибка запроса UDP DNS: $_"
            }
        }
    }

    # Fallback: System DNS
    if ($AllRecords.Count -eq 0) {
        Write-Log "[Resolve-SrvRecord] Разрешение SRV $Name через системный DNS"

        # Method 1: Resolve-DnsName without custom server
        try {
            $DnsResult = Resolve-DnsName -Name $Name -Type SRV -DnsOnly -ErrorAction Stop

            # Safely check if we got valid SRV records
            # $DnsResult can be $null, a single object, or an array
            if ($null -ne $DnsResult) {
                # Filter for SRV records that have a NameTarget property
                $SrvRecordsFound = @($DnsResult | Where-Object { $null -ne $_.NameTarget })

                if ($SrvRecordsFound.Count -gt 0) {
                    $SortedRecords = $SrvRecordsFound | Sort-Object Priority, @{Expression={-$_.Weight}}

                    foreach ($rec in $SortedRecords) {
                        $AllRecords.Add([PSCustomObject]@{
                            Target = $rec.NameTarget.TrimEnd('.')
                            Port = $rec.Port
                            Priority = $rec.Priority
                            Weight = $rec.Weight
                        })
                    }

                    if ($AllRecords.Count -gt 0) {
                        Write-Log "[Resolve-SrvRecord] Найдено SRV-записей через системный DNS: $($AllRecords.Count)"
                        if ($ReturnAll) { return $AllRecords.ToArray() }
                        return $AllRecords[0]
                    }
                }
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Log "[Resolve-SrvRecord] Resolve-DnsName недоступен для системного поиска SRV"
        }
        catch {
            Write-Log "[Resolve-SrvRecord] Ошибка системного поиска SRV через DNS: $_"
        }
    }

    # Method 2: UDP fallback via system DNS server
    if ($AllRecords.Count -eq 0) {
        try {
            # Try Get-CimInstance first (PowerShell 3.0+), fall back to Get-WmiObject (deprecated but works on older systems)
            $SystemDnsServer = $null
            try {
                $NetworkConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
                    Where-Object { $_.DNSServerSearchOrder } | Select-Object -First 1
                if ($NetworkConfig) { $SystemDnsServer = $NetworkConfig.DNSServerSearchOrder[0] }
            }
            catch {
                # Fallback to Get-WmiObject for older systems
                $NetworkConfig = Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
                    Where-Object { $_.DNSServerSearchOrder } | Select-Object -First 1
                if ($NetworkConfig) { $SystemDnsServer = $NetworkConfig.DNSServerSearchOrder[0] }
            }

            if ($SystemDnsServer) {
                Write-Log "[Resolve-SrvRecord] Резервный запрос SRV по UDP через системный DNS: $SystemDnsServer"
                $UdpResult = Invoke-RawDnsQuery -Name $Name -DnsServer $SystemDnsServer -Type SRV -ReturnAllSRV:$ReturnAll

                if ($UdpResult) {
                    # Handle both single record and array results
                    if ($UdpResult -is [System.Array]) {
                        Write-Log "[Resolve-SrvRecord] Найдено SRV-записей через системный DNS по UDP: $($UdpResult.Count)"
                        if ($ReturnAll) { return $UdpResult }
                        return $UdpResult[0]
                    }
                    elseif ($UdpResult.Target) {
                        Write-Log "[Resolve-SrvRecord] Найдена SRV-запись: $($UdpResult.Target):$($UdpResult.Port) через системный DNS по UDP"
                        return $UdpResult
                    }
                }
            }
        }
        catch {
            Write-Log "[Resolve-SrvRecord] Ошибка системного запроса SRV по UDP: $_"
        }
    }

    Write-Log "[Resolve-SrvRecord] Не удалось разрешить SRV-запись: $Name"
    return $null
}

#endregion Helper Functions

#region Main Function

function Resolve-adPEASName {
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'Domain')]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if ([string]::IsNullOrEmpty($_)) { return $true }
            $ip = $null
            if ([System.Net.IPAddress]::TryParse($_, [ref]$ip)) { return $true }
            throw "DnsServer должен быть IP-адресом, а не именем узла: $_"
        })]
        [string]$DnsServer,

        [Parameter(Mandatory = $false)]
        [switch]$NoCache,

        [Parameter(Mandatory = $false)]
        [switch]$UseLDAPS
    )

    process {
        # Determine effective DNS server (parameter or from LDAPContext)
        $EffectiveDnsServer = $DnsServer
        if (-not $EffectiveDnsServer -and $Script:LDAPContext -and $Script:LDAPContext['DnsServer']) {
            $EffectiveDnsServer = $Script:LDAPContext['DnsServer']
        }

        # Determine if LDAPS should be used for reachability tests
        $EffectiveUseLDAPS = $UseLDAPS
        if (-not $EffectiveUseLDAPS -and $Script:LDAPContext -and $Script:LDAPContext['UseLDAPS']) {
            $EffectiveUseLDAPS = $true
        }

        # Hostname to IP Resolution (-Name parameter)
        if ($PSCmdlet.ParameterSetName -eq 'Name') {
            return Resolve-HostnameToIP -Hostname $Name -DnsServer $EffectiveDnsServer -NoCache:$NoCache
        }

        # Domain Controller Discovery (-Domain parameter)
        $SrvRecordName = "_ldap._tcp.dc._msdcs.$Domain"
        Write-Log "[Resolve-adPEASName] Запрос SRV-записей: $SrvRecordName"

        $SrvResults = Resolve-SrvRecord -Name $SrvRecordName -DnsServer $EffectiveDnsServer -ReturnAll
        if ($SrvResults) {
            if ($SrvResults -isnot [System.Array]) {
                $SrvResults = @($SrvResults)
            }
            Write-Log "[Resolve-adPEASName] Найдено контроллеров домена по SRV: $($SrvResults.Count)"

            # Iterate through DCs in priority order, test reachability
            foreach ($SrvRecord in $SrvResults) {
                $DcHostname = $SrvRecord.Target
                Write-Log "[Resolve-adPEASName] Проверка контроллера домена $DcHostname (приоритет: $($SrvRecord.Priority), вес: $($SrvRecord.Weight))"

                # Resolve DC hostname to IP
                $DcIP = Resolve-HostnameToIP -Hostname $DcHostname -DnsServer $EffectiveDnsServer -NoCache:$NoCache

                if (-not $DcIP) {
                    Write-Log "[Resolve-adPEASName] Не удалось определить IP узла $DcHostname; переход к следующему контроллеру"
                    continue
                }

                # Test if DC is actually reachable (Port 88 + 389/636)
                if (Test-DCReachable -IP $DcIP -Hostname $DcHostname -UseLDAPS:$EffectiveUseLDAPS) {
                    Write-Log "[Resolve-adPEASName] Контроллер $DcHostname ($DcIP) доступен; используется этот узел"
                    return [PSCustomObject]@{
                        Hostname = $DcHostname
                        IP = $DcIP
                    }
                }
                else {
                    Write-Log "[Resolve-adPEASName] Контроллер $DcHostname ($DcIP) недоступен (устаревшая SRV-запись?); переход к следующему"
                }
            }

            Write-Log "[Resolve-adPEASName] Все контроллеры домена по SRV недоступны: $($SrvResults.Count)"
        }

        # Fallback: Reverse DNS lookup (system DNS only)
        if (-not $EffectiveDnsServer) {
            Write-Log "[Resolve-adPEASName] Обратный DNS-поиск для: $Domain"
            try {
                $DnsResult = [System.Net.Dns]::GetHostEntry($Domain)
                if ($DnsResult -and $DnsResult.AddressList.Count -gt 0) {
                    # Prefer IPv4 address, fallback to IPv6
                    $DcIPAddr = $DnsResult.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
                    if (-not $DcIPAddr) {
                        $DcIPAddr = $DnsResult.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' } | Select-Object -First 1
                    }
                    if (-not $DcIPAddr -and $DnsResult.AddressList.Count -gt 0) {
                        $DcIPAddr = $DnsResult.AddressList[0]
                    }

                    if ($DcIPAddr) {
                        $DcIPString = $DcIPAddr.IPAddressToString
                        Write-Log "[Resolve-adPEASName] Домен разрешён в IP-адрес: $DcIPString"

                        # Try reverse lookup to get actual DC hostname
                        $DcHostname = $Domain  # Default to domain name if reverse lookup fails
                        try {
                            $ReverseResult = [System.Net.Dns]::GetHostEntry($DcIPAddr)
                            if ($ReverseResult -and $ReverseResult.HostName -and $ReverseResult.HostName -ne $Domain) {
                                $DcHostname = $ReverseResult.HostName
                                Write-Log "[Resolve-adPEASName] Обратный DNS-поиск вернул: $DcHostname"
                            }
                        }
                        catch {
                            Write-Log "[Resolve-adPEASName] Ошибка обратного DNS; вместо имени узла используется домен: $_"
                        }

                        if (Test-DCReachable -IP $DcIPString -Hostname $DcHostname -UseLDAPS:$EffectiveUseLDAPS) {
                            Write-Log "[Resolve-adPEASName] Контроллер $DcHostname ($DcIPString) доступен через обратный DNS"
                            return [PSCustomObject]@{
                                Hostname = $DcHostname
                                IP = $DcIPString
                            }
                        }
                        else {
                            Write-Log "[Resolve-adPEASName] Контроллер $DcHostname ($DcIPString) недоступен через обратный DNS"
                        }
                    }
                }
            }
            catch {
                Write-Log "[Resolve-adPEASName] Ошибка системного разрешения DNS: $_"
            }
        }

        # Last resort: Direct A record lookup for domain name
        Write-Log "[Resolve-adPEASName] Резервный вариант: прямое разрешение имени домена"
        $DomainIP = Resolve-HostnameToIP -Hostname $Domain -DnsServer $EffectiveDnsServer -NoCache:$NoCache

        if ($DomainIP) {
            if (Test-DCReachable -IP $DomainIP -Hostname $Domain -UseLDAPS:$EffectiveUseLDAPS) {
                Write-Log "[Resolve-adPEASName] Контроллер $Domain ($DomainIP) доступен через прямое разрешение"
                return [PSCustomObject]@{
                    Hostname = $Domain
                    IP = $DomainIP
                }
            }
            else {
                Write-Log "[Resolve-adPEASName] Контроллер $Domain ($DomainIP) недоступен через прямое разрешение"
            }
        }

        # Complete failure
        Write-Log "[Resolve-adPEASName] Не удалось обнаружить доступный контроллер для домена: $Domain"
        return $null
    }
}

#endregion Main Function
