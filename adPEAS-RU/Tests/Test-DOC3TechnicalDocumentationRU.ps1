#Requires -Version 5.1
<#
.SYNOPSIS
  DOC3: автономная сверка русской архитектуры, модели риска и диагностики.
.DESCRIPTION
  Только читает Markdown. Не подключается к Active Directory, не выполняет примеры
  и не изменяет конфигурацию компьютеров. Совместимо с Windows PowerShell 5.1.
#>
[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'

$documents = @(
 @{ Name='09-Architecture.md'; Lines=478; Headings=33; Blocks=11; Comments=15; MinChanged=125 },
 @{ Name='10-Risk-Scoring-System.md'; Lines=597; Headings=48; Blocks=9; Comments=4; MinChanged=310 },
 @{ Name='11-Troubleshooting.md'; Lines=615; Headings=36; Blocks=37; Comments=49; MinChanged=210 }
)
$backtickMark = [string][char]96
$fence = $backtickMark * 3
$tokenRegex = $backtickMark + '([^' + $backtickMark + ']+)' + $backtickMark
$headingRegex = '^(#{1,4}) (.+)$'
$originalLinks = '\]\(([^)]+)\)'
$anchorRegex = '<a id="[a-z0-9-]+"></a>'
$linefeed = [string][char]10
$crlf = [string][char]13 + $linefeed
$allChanged = 0
$allSamples = 0

foreach ($doc in $documents) {
 $sourcePath = Join-Path $ProjectRoot ('docs/' + $doc.Name)
 $russianPath = Join-Path $ProjectRoot ('docs/ru-RU/' + $doc.Name)
 if (-not (Test-Path -LiteralPath $sourcePath) -or -not (Test-Path -LiteralPath $russianPath)) {
  throw "DOC3: отсутствует файл $($doc.Name)"
 }
 $en = [IO.File]::ReadAllText($sourcePath,[Text.Encoding]::UTF8).Replace($crlf,$linefeed)
 $ru = [IO.File]::ReadAllText($russianPath,[Text.Encoding]::UTF8).Replace($crlf,$linefeed)
 $original = @($en.Split([char]10))
 $translated = @($ru.Split([char]10))
 if ($original.Count -ne $doc.Lines -or $translated.Count -ne $original.Count) {
  throw "DOC3: число строк $($doc.Name): EN=$($original.Count) RU=$($translated.Count)"
 }
 $inside = $false
 $language = ''
 $blocks = 0
 $comments = 0
 $heads = 0
 $changes = 0
 $machine = 0

 for($i=0; $i -lt $original.Count; $i++) {
  $a = $original[$i]
  $b = $translated[$i]
  if ($a.TrimStart().StartsWith($fence)) {
   if ($a -cne $b) { throw "DOC3: нарушено ограждение кода в $($doc.Name), строка $($i+1)" }
   if (-not $inside) {
    $blocks++
    $language = $a.Trim().Substring(3).Trim().ToLowerInvariant()
   }
   $inside = -not $inside
   continue
  }
  if ($inside) {
   if ($a -match '^\s*#') {
    $comments++
    if ($a -cne $b -and $b -notmatch '[А-Яа-яЁё]') {
     throw "DOC3: не русифицирован комментарий $($doc.Name):$($i+1)"
    }
    continue
   }
   if ($language -in @('powershell','javascript','bash') -or $doc.Name -eq '10-Risk-Scoring-System.md') {
    if ($a -cne $b) {
     throw "DOC3: изменена машинная строка примера $($doc.Name):$($i+1)"
    }
    $machine++
   }
   continue
  }
  $aHead = [regex]::Match($a,$headingRegex)
  $bHead = [regex]::Match($b,$headingRegex)
  if ($aHead.Success) {
   $heads++
   if (-not $bHead.Success -or $aHead.Groups[1].Value -cne $bHead.Groups[1].Value) {
    throw "DOC3: изменён уровень заголовка $($doc.Name):$($i+1)"
   }
   $originalHeading = $aHead.Groups[2].Value
   $russianHeading = $bHead.Groups[2].Value
   if ($a -cne $b) {
    if ($russianHeading -notmatch '^<a id="[a-z0-9-]+"></a>') {
     throw "DOC3: исходная ссылка на заголовок не сохранена $($doc.Name):$($i+1)"
    }
   }
  }
  $clean = [regex]::Replace($b,$anchorRegex,'')
  $englishTokens = @([regex]::Matches($a,$tokenRegex) | ForEach-Object { $_.Groups[1].Value })
  $russianTokens = @([regex]::Matches($clean,$tokenRegex) | ForEach-Object { $_.Groups[1].Value })
  if (($englishTokens -join [char]31) -cne ($russianTokens -join [char]31)) {
   throw "DOC3: изменён параметр или идентификатор $($doc.Name):$($i+1)"
  }
  if ($a.StartsWith('|') -ne $clean.StartsWith('|')) {
   throw "DOC3: нарушена таблица $($doc.Name):$($i+1)"
  }
  if ($a -cne $clean) { $changes++ }
 }
 if ($inside -or $blocks -ne $doc.Blocks -or $heads -ne $doc.Headings -or
     $comments -ne $doc.Comments -or $changes -lt $doc.MinChanged) {
  throw "DOC3: неполный документ $($doc.Name): blocks=$blocks headings=$heads comments=$comments translated=$changes"
 }
 $eLinks = @([regex]::Matches($en,$originalLinks) | ForEach-Object {$_.Groups[1].Value})
 $rLinks = @([regex]::Matches($ru,$originalLinks) | ForEach-Object {$_.Groups[1].Value})
 if (($eLinks -join [char]31) -cne ($rLinks -join [char]31)) {
  throw "DOC3: изменены ссылки документа $($doc.Name)"
 }
 $allChanged += $changes
 $allSamples += $machine
 Write-Host ("PASS DOC3: {0} — {1} строк описаний, {2} блоков, {3} заголовков" -f $doc.Name,$changes,$blocks,$heads)
}
# В модельной таблице сохраняются все машинные ключи, числа и источники проверок.
$scoringFile = Join-Path $ProjectRoot 'docs/10-Risk-Scoring-System.md'
$scoringRuFile = Join-Path $ProjectRoot 'docs/ru-RU/10-Risk-Scoring-System.md'
$e = [IO.File]::ReadAllText($scoringFile,[Text.Encoding]::UTF8)
$r = [IO.File]::ReadAllText($scoringRuFile,[Text.Encoding]::UTF8)
$scoreRow = '(?m)^\|\s*'+$backtickMark+'([^'+$backtickMark+']+)'+$backtickMark+'\s*\|\s*(\d+)\s*\|\s*([A-Za-z0-9-]+)\s*\|'
$originalScores = @([regex]::Matches($e,$scoreRow) | ForEach-Object { $_.Groups[1].Value + ':' + $_.Groups[2].Value + ':' + $_.Groups[3].Value })
$translatedScores = @([regex]::Matches($r,$scoreRow) | ForEach-Object { $_.Groups[1].Value + ':' + $_.Groups[2].Value + ':' + $_.Groups[3].Value })
if ($originalScores.Count -lt 75 -or ($originalScores -join [char]31) -cne ($translatedScores -join [char]31)) {
 throw "DOC3: ключи, баллы или привязки проверки изменены: EN=$($originalScores.Count) RU=$($translatedScores.Count)"
}
foreach ($term in @('×1.6','×1.4','×1.3','×1.25','×1.2','×1.1',
 '×1.0','×0.9','×0.8','×0.2','×0.15','×0.1','0.003',
 'DCSync','Protected Users','SECURITY','CORRELATION','-VerboseLogging',
 'KRB5KDC_ERR_PREAUTH_FAILED','-ForceSimpleBind','LdapConnection',
 'RenderModel','NOT_DELEGATED','pwdLastSet','msDS-SupportedEncryptionTypes')) {
 $target=if ($term -eq '-VerboseLogging' -or $term -eq '-ForceSimpleBind' -or $term -eq 'KRB5KDC_ERR_PREAUTH_FAILED') {
  [IO.File]::ReadAllText((Join-Path $ProjectRoot 'docs/ru-RU/11-Troubleshooting.md'),[Text.Encoding]::UTF8)
 } else {
  $r + [IO.File]::ReadAllText((Join-Path $ProjectRoot 'docs/ru-RU/09-Architecture.md'),[Text.Encoding]::UTF8)
 }
 if ($target.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0) {
  throw "DOC3: отсутствует критическое значение $term"
 }
}
Write-Host "PASS DOC3: $allChanged переведённых строк, $allSamples неизменённых машинных строк и $($originalScores.Count) баллов находок; тест не обращался к AD" -ForegroundColor Green
