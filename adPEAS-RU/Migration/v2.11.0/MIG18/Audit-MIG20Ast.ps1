[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Candidate,[Parameter(Mandatory=$true)][string]$Report)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $Candidate).Path
$rows=New-Object 'System.Collections.Generic.List[object]'
$helps=New-Object 'System.Collections.Generic.List[object]'
$files=0
$commands=0
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File -Filter '*.ps1' | Sort-Object FullName)) {
 $files++
 $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
 $tokens=$null; $errors=$null
 $tree=[System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if ($errors.Count -ne 0) {throw "MIG20 parse error: $relative"}
 foreach ($node in $tree.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst]},$true)) {
  $name=$node.GetCommandName()
  if ($name -notmatch '^(Write-(Host|Output|Log|Warning|Error|Verbose|Information|Debug)|Show-(Line|Header|SubHeader|Output|Object))$') {continue}
  $commands++
  foreach ($arg in $node.CommandElements) {
   if ($arg -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -and $arg -isnot [System.Management.Automation.Language.ExpandableStringExpressionAst]) {continue}
   if ($arg -eq $node.CommandElements[0]) {continue}
   $value=[string]$arg.Value
   if ($value -notmatch '[A-Za-z]{2,}') {continue}
   $kind=if ($value -match '[А-Яа-яЁё]') {'mixed-review'} elseif ($value -match '[A-Za-z]{2,}\s+[A-Za-z]{2,}') {'english-prose-review'} else {'technical-or-dynamic-review'}
   $rows.Add([pscustomobject]@{Path=$relative;Line=$arg.Extent.StartLineNumber;Command=$name;Classification=$kind;Text=$value})
  }
 }
 foreach ($token in $tokens) {
  if ($token.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment -or $token.Text -notmatch '(?im)^\s*(?:#\s*)?\.(SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|NOTES|OUTPUTS|INPUTS)\b') {continue}
  $sections=[regex]::Matches($token.Text,'(?ims)^\s*(?:#\s*)?\.(SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|NOTES|OUTPUTS|INPUTS)\b(.*?)(?=^\s*(?:#\s*)?\.[A-Z]+\b|#>|\z)')
  foreach ($section in $sections) {
   $body=$section.Groups[2].Value.Trim()
   if ($body -notmatch '[A-Za-z]{2,}') {continue}
   $kind=if ($body -match '[А-Яа-яЁё]') {'mixed-review'} else {'english-or-technical-review'}
   $helps.Add([pscustomobject]@{Path=$relative;Line=($token.Extent.StartLineNumber+([regex]::Matches($token.Text.Substring(0,$section.Index),'\n').Count));Section=$section.Groups[1].Value;Classification=$kind;Text=$body})
  }
 }
}
if ($files -eq 0 -or $commands -eq 0) {throw 'MIG20 empty source inventory'}
$data=[ordered]@{Schema='adPEAS-RU.MIG20.Ast.1';Status='PASS';Files=$files;VisibleCommandAstCount=$commands;LiteralCandidates=$rows.ToArray();HelpCandidates=$helps.ToArray();FullLocalizationCertified=$false;ProductionReady=$false}
[IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Report),($data|ConvertTo-Json -Depth 8),[Text.Encoding]::UTF8)
Write-Host "PASS MIG20 AST: $files files, $commands visible commands, $($rows.Count) literal candidates, $($helps.Count) help sections"
