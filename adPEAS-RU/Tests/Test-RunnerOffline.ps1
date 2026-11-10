#Requires -Version 5.1
<#
.SYNOPSIS
  Проверка контракта подключения через обёртку без реального домена.
.DESCRIPTION
  Устраняет регрессию, когда Connect-adPEAS подключается успешно,
  но в обычном режиме выводит сведения вместо объекта соединения.
#>
[CmdletBinding()]
param()
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runner=Join-Path $root 'Run-AD-Audit-RU.ps1'
$source=[IO.File]::ReadAllText($runner,[Text.Encoding]::UTF8)
if(-not $source.Contains('$session=Connect-adPEAS @conn -Quiet')){
 throw 'FAIL: обёртка не вызывает Connect-adPEAS с -Quiet'
}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('adpeas-ru-offline-'+[guid]::NewGuid().ToString('N'))
$utf8=New-Object Text.UTF8Encoding($true)
try {
 New-Item -ItemType Directory -Path $tmp -Force | Out-Null
 Copy-Item -LiteralPath $runner -Destination (Join-Path $tmp 'Run-AD-Audit-RU.ps1') -Force
 $mock=@'
function Connect-adPEAS {
 [CmdletBinding()]
 param(
  [string]$Domain,
  [switch]$UseWindowsAuth,
  [switch]$UseLDAPS,
  [switch]$IgnoreSSLErrors,
  [switch]$Quiet,
  [string]$Server,
  [System.Management.Automation.PSCredential]$Credential
 )
 if(-not $Quiet){throw "FAIL: missing -Quiet"}
 if($UseLDAPS){throw "FAIL: unexpected LDAPS in offline test"}
 if($IgnoreSSLErrors){throw "FAIL: disabled certificate checks unnecessarily"}
 if($Domain -ne 'test.invalid'){throw "FAIL: wrong domain"}
 [pscustomobject]@{Connected=$true}
}
function Invoke-adPEAS {
 [CmdletBinding()]
 param(
  [string]$Outputfile,
  [string]$Format,
  [switch]$OPSEC,
  [string[]]$Module,
  [string[]]$ExcludeModule,
  [switch]$IncludePrivileged
 )
 if(-not $OPSEC){throw "FAIL: missing OPSEC"}
 if($Format -ne 'All'){throw "FAIL: wrong format"}
 if(-not ($Module -contains 'Domain')){throw "FAIL: wrong module"}
 [IO.File]::WriteAllText(($Outputfile+'.txt'),'OFFLINE_OK')
}
function Disconnect-adPEAS {
 $marker=Join-Path $env:TEMP 'ADPEAS_TEST_DISCONNECT_MARKER.txt'
 [IO.File]::WriteAllText($marker,'disconnected')
}
# PS1 imported by Import-Module runs as a script, not a .psm1 module.
'@
 [IO.File]::WriteAllText((Join-Path $tmp 'adPEAS.ps1'),$mock,$utf8)
 $out=Join-Path $tmp 'Reports'
 & (Join-Path $tmp 'Run-AD-Audit-RU.ps1') -Domain 'test.invalid' -UseLDAPS:$false -OPSEC -Module Domain -OutputDirectory $out
 $reports=@(Get-ChildItem -LiteralPath $out -Filter '*.txt' -File)
 if($reports.Count -ne 1){throw "FAIL: expected one offline report, found $($reports.Count)"}
 if([IO.File]::ReadAllText($reports[0].FullName) -ne 'OFFLINE_OK'){throw 'FAIL: unexpected output'}
 Write-Host 'PASS: offline wrapper connects with -Quiet, invokes audit and writes report'
} finally {
 if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
}
