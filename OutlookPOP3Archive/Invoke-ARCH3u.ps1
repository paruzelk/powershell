#requires -Version 5.1
# ARCH3u ONLY: real TEST POP3 PST read-only Plan/Inventory for ten Inbox items.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Inventory')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3u requires native Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3uRealBatchTenPreflight.ps1')
Invoke-OPA265ARCH3uRealBatchTenPreflight -Mode $Mode -RunId $RunId -SourcePst $SourcePst
