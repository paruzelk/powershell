#Requires -Version 5.1
<#
.SYNOPSIS
  DOC2d: офлайн-сверка русского справочника Security Checks с закреплённым оригиналом.
.DESCRIPTION
  Тест только читает Markdown и никогда не подключается к AD и не выполняет примеры.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$englishPath = Join-Path $ProjectRoot 'docs/04-Security-Checks.md'
$russianPath = Join-Path $ProjectRoot 'docs/ru-RU/04-Security-Checks.md'
if (-not (Test-Path -LiteralPath $englishPath) -or -not (Test-Path -LiteralPath $russianPath)) {
 throw 'DOC2d: не найден исходный или переводной справочник'
}
$en = [IO.File]::ReadAllText($englishPath,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$ru = [IO.File]::ReadAllText($russianPath,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$enLines = @($en.Split([char]10))
$ruLines = @($ru.Split([char]10))
if ($enLines.Count -ne 1766 -or $ruLines.Count -ne $enLines.Count) {
 throw "DOC2d: нарушено соответствие исходных строк EN=$($enLines.Count) RU=$($ruLines.Count)"
}
$headPattern = '(?m)^### ((?:Get|Invoke)-[A-Za-z0-9]+)$'
$enHeads = @([regex]::Matches($en,$headPattern) | ForEach-Object { $_.Groups[1].Value })
$ruHeads = @([regex]::Matches($ru,$headPattern) | ForEach-Object { $_.Groups[1].Value })
if ($enHeads.Count -ne 54 -or ($enHeads -join [char]31) -cne ($ruHeads -join [char]31)) {
 throw "DOC2d: состав 54 разделов функций не совпадает ($($enHeads.Count)/$($ruHeads.Count))"
}
$anchors = @(
 'security-checks-reference','output-filtering-noise-reduction','filtered-checks',
 'how-filtering-works','viewing-all-results','checks-without-filtering',
 'admin-only-checks-admincount1','disabled-account-handling','overview',
 'domain-module','creds-module','rights-module','delegation-module','adcs-module',
 'accounts-module','gpo-module','computer-module','application-module',
 'shares-module','navigation'
)
foreach ($anchor in $anchors) {
 $tag = '<a id="'+$anchor+'"></a>'
 if (([regex]::Matches($ru,[regex]::Escape($tag))).Count -ne 1) {
  throw "DOC2d: потерян или дублирован исходный якорь $anchor"
 }
}
$backtickChar = [string][char]96
$codeFence = $backtickChar * 3
$tokenPattern = $backtickChar + '([^' + $backtickChar + ']+)' + $backtickChar
$insideCode = $false
$codeBlocks = 0
$psBlocks = 0
$comments = 0
$translated = 0
for ($i=0; $i -lt $enLines.Count; $i++) {
 $english = $enLines[$i]
 $russian = $ruLines[$i]
 if ($english.TrimStart().StartsWith($codeFence)) {
  if ($english -cne $russian) { throw "DOC2d: изменена разметка примера на строке $($i+1)" }
  if (-not $insideCode) {
   $codeBlocks++
   if ($english.Trim() -ceq ($codeFence+'powershell')) { $psBlocks++ }
  }
  $insideCode = -not $insideCode
  continue
 }
 if ($insideCode) {
  if ($english -match '^\s*#(?:\s|$)') {
   $comments++
   if ($russian -cnotmatch '[А-Яа-яЁё]') {
    throw "DOC2d: комментарий остался без русского перевода на строке $($i+1)"
   }
  } elseif ($english -cne $russian) {
   throw "DOC2d: изменена исполняемая или машинная строка на строке $($i+1)"
  }
  continue
 }
 $cleanRU = [regex]::Replace($russian,'<a id="[a-z0-9-]+"></a>','')
 if ($english.StartsWith('|') -ne $cleanRU.StartsWith('|')) {
  throw "DOC2d: нарушена строка таблицы на строке $($i+1)"
 }
 $originalTokens = @([regex]::Matches($english,$tokenPattern) | ForEach-Object { $_.Groups[1].Value })
 $translatedTokens = @([regex]::Matches($cleanRU,$tokenPattern) | ForEach-Object { $_.Groups[1].Value })
 if (($originalTokens -join [char]31) -cne ($translatedTokens -join [char]31)) {
  throw "DOC2d: изменён параметр, LDAP-фильтр или технический токен на строке $($i+1)"
 }
 if ($english -cne $cleanRU) { $translated++ }
}
if ($insideCode -or $codeBlocks -ne 57 -or $psBlocks -ne 55 -or $comments -ne 28) {
 throw "DOC2d: нарушена структура примеров blocks=$codeBlocks ps=$psBlocks comments=$comments"
}
if ($translated -lt 880) {
 throw "DOC2d: недостаточная полнота перевода: $translated строк"
}
$linkPattern = '\]\(([^)]+)\)'
$sourceLinks = @([regex]::Matches($en,$linkPattern) | ForEach-Object { $_.Groups[1].Value })
$targetLinks = @([regex]::Matches($ru,$linkPattern) | ForEach-Object { $_.Groups[1].Value })
if (($sourceLinks -join [char]31) -cne ($targetLinks -join [char]31)) {
 throw 'DOC2d: изменены URL или ссылки на разделы'
}
foreach ($term in @(
 'KDC_ERR_CLIENT_REVOKED','-IncludePrivileged','-IncludeInactive',
 'adminCount=1','Test-IsExpectedInScope','tombstoneLifetime',
 'msDS-SupportedEncryptionTypes','dsHeuristics','msFVE-RecoveryPassword',
 'msPKIDPAPIMasterKeys','msPKIAccountCredentials','ReadProperty',
 'ControlAccess','NTAuthCertificates','ESC16','Reanimate-Tombstones',
 'MachineAccountQuota','msDS-GroupMSAMembership','RODC','SDProp',
 'EffectiveSetting','IsEffectiveSetting','gPCFileSysPath','SourceFile',
 'SYSVOL','notFullySearched','-ListSharesOnly','-ShareName',
 '-OPSEC','-Module Shares','JSON','открытом виде'
)) {
 if ($ru.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0) {
  throw "DOC2d: отсутствует техническое ограничение: $term"
 }
}
Write-Host "PASS DOC2d: $($enHeads.Count) функций, $codeBlocks блоков, $psBlocks PowerShell, $comments комментариев, $translated строк переведено; идентификаторы и ссылки неизменны" -ForegroundColor Green
