# Аутентификация и подключение

Рекомендуемый для внутреннего аудита вариант — текущая доменная учётная запись Windows с минимально достаточными правами:

```powershell
Import-Module .\adPEAS.ps1
Connect-adPEAS -Domain "example.local" -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEAS -OPSEC
Disconnect-adPEAS
```

Альтернативные данные: `Connect-adPEAS -Domain "example.local" -Credential (Get-Credential)`.

В оригинале поддерживаются Kerberos, Windows SSPI, SimpleBind, NTLM, PKINIT и сертификаты. Функции с NT-хешем, AES-ключом, Pass-the-Ticket и модификацией билетов предназначены для специализированных тестов и не должны использоваться для обычной инвентаризации.

**Важно:** штатная однострочная форма `Invoke-adPEAS -Domain ...` в upstream передаёт `IgnoreSSLErrors=$true`. Русская обёртка использует отдельное подключение, сохраняющее проверку сертификата.