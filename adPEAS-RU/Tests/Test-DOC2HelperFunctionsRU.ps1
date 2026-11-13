#Requires -Version 5.1
<#
.SYNOPSIS
    DOC2b: офлайн-проверка полного перевода справочника Helper Functions.
.DESCRIPTION
    Только чтение Markdown-файлов. Не вызывает LDAP и не исполняет примеры.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$enPath=Join-Path $ProjectRoot 'docs/08-Helper-Functions.md'
$ruPath=Join-Path $ProjectRoot 'docs/ru-RU/08-Helper-Functions.md'
$en=[IO.File]::ReadAllText($enPath,[Text.Encoding]::UTF8)
$ru=[IO.File]::ReadAllText($ruPath,[Text.Encoding]::UTF8)
if($ru.Length -lt 27000){throw 'DOC2b: неполный русский справочник'}
$anchors=@('session-management','kerberos-authentication','password-hash-derivation',
 'sid-and-acl-utilities','credential-decryption','testing-functions',
 'adcs-certificate-enrollment','laps-utilities','gpo-utilities','network-utilities')
foreach($a in $anchors){
 if(([regex]::Matches($ru,[regex]::Escape('<a id="'+$a+'"></a>'))).Count -ne 1){
  throw "DOC2b: отсутствует или повторён якорь $a"
 }
}
$cleanRU=[regex]::Replace($ru,'(?m)^<a id="[a-z0-9-]+"></a>\r?\n\r?\n','')
$enLines=@(($en -replace "`r`n","`n") -split "`n")
$ruLines=@(($cleanRU -replace "`r`n","`n") -split "`n")
if($enLines.Count -ne 905 -or $ruLines.Count -ne $enLines.Count){
 throw "DOC2b: число строк EN=$($enLines.Count) RU=$($ruLines.Count)"
}
$functions=@('Connect-adPEAS','Disconnect-adPEAS','Get-adPEASSession',
 'Build-CompletionCache','Clear-CompletionCache','Get-CompletionCacheStats',
 'Invoke-KerberosAuth','Request-ServiceTicket','Import-KerberosTicket',
 'Get-Hash','ConvertFrom-SID','ConvertTo-LDAPSIDHex','Test-IsPrivileged',
 'Get-ObjectOwner','ConvertFrom-GPPPassword','ConvertFrom-VBE',
 'Invoke-Kerberoast','Invoke-ASREPRoast','Request-ADCSCertificate',
 'Get-LAPSGPOConfig','Get-OUPermissions','Get-GPOLinkage','Invoke-PortScan')
foreach($fn in $functions){
 foreach($lines in @($enLines,$ruLines)){
  if(@($lines | Where-Object {$_ -ceq ('### '+$fn)}).Count -ne 1){
   throw "DOC2b: пропущен раздел $fn"
  }
 }
}
function Remove-Comment([string]$Line){
 if($Line -match '^\s*#'){return ''}
 return ($Line -creplace '[ `t]+#[^\r\n]*$','')
}
$inCode=$false;$codeBlocks=0;$comments=0;$translated=0
$techPattern=[char]96 + '([^' + [char]96 + ']+)' + [char]96
for($i=0;$i -lt $enLines.Count;$i++){
 $x=$enLines[$i];$y=$ruLines[$i]
 if($x.StartsWith(([string][char]96)*3)){
  if($x -cne $y){throw "DOC2b: тип код-блока изменён на строке $i"}
  if(-not $inCode){$codeBlocks++}
  $inCode=-not $inCode
  continue
 }
 if($inCode){
  if((Remove-Comment $x) -cne (Remove-Comment $y)){
   throw "DOC2b: код примера изменён на строке $i"
  }
  if($x -match '^\s*#'){$comments++}
  continue
 }
 $a=@([regex]::Matches($x,$techPattern) | ForEach-Object {$_.Groups[1].Value})
 $b=@([regex]::Matches($y,$techPattern) | ForEach-Object {$_.Groups[1].Value})
 if(($a -join [char]31) -cne ($b -join [char]31)){
  throw "DOC2b: изменён технический токен на строке $i"
 }
 if($x -cne $y){$translated++}
}
if($inCode -or $codeBlocks -lt 30 -or $comments -ne 78 -or $translated -lt 270){
 throw "DOC2b: неполное покрытие: блоков $codeBlocks, комментариев $comments, строк $translated"
}
$linkRegex='\]\(([^)]+)\)'
$enLinks=@([regex]::Matches($en,$linkRegex) | ForEach-Object {$_.Groups[1].Value})
$ruLinks=@([regex]::Matches($ru,$linkRegex) | ForEach-Object {$_.Groups[1].Value})
if(($enLinks -join [char]31) -cne ($ruLinks -join [char]31)){
 throw 'DOC2b: изменены ссылки оригинала'
}
foreach($term in @('Global Catalog','UnPAC-the-Hash','sIDHistory','CredentialRoaming',
 'GrantsControlAccess','READ_PROPERTY','CONTROL_ACCESS','-DomainComputers',
 '-ActiveDays','-ExportOpenPorts','Get-NetworkMap','BatchSize','TimeoutMs','COM/RPC')){
 if(-not $ru.Contains($term)){throw "DOC2b: отсутствует ограничение $term"}
}
Write-Host "PASS DOC2b: 23 функции, $codeBlocks блоков, $comments комментариев; $translated описаний переведено, примеры и ссылки сохранены" -ForegroundColor Green
