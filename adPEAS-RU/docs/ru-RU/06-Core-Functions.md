# Основные функции и работа с LDAP

Архитектура adPEAS 2.x основана на `System.DirectoryServices.Protocols.LdapConnection`, без обязательного модуля `ActiveDirectory`.

Основные команды: `Connect-adPEAS`, `Disconnect-adPEAS`, `Invoke-adPEAS`, `Get-DomainUser`, `Get-DomainGroup`, `Get-DomainComputer`, `Get-DomainGPO`, `Get-ObjectACL`.

Пример последовательности:

```powershell
Import-Module .\adPEAS.ps1
Connect-adPEAS -Domain "example.local" -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false
Get-DomainUser -Identity "administrator"
Disconnect-adPEAS
```

При анализе ACL учитывайте унаследованные ACE, вложенность групп, `Deny`, `GenericAll`, `WriteDacl`, `WriteOwner` и права на конкретные классы объектов.