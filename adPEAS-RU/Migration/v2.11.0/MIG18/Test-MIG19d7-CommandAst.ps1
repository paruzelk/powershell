param(
 [Parameter(Mandatory=$true)][string]$Candidate,
 [Parameter(Mandatory=$true)][string[]]$Reports,
 [Parameter(Mandatory=$true)][string]$OutputReport
)
$ErrorActionPreference='Stop'
$files=@{}
$count=0
foreach ($report in $Reports) {
 $data=Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
 foreach ($row in $data.changes) {
  $file=Join-Path $Candidate $row.path
  if (-not $files.ContainsKey($file)) {
   $tokens=$null;$errors=$null
   $tree=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file).Path,[ref]$tokens,[ref]$errors)
   if ($errors.Count -gt 0) {throw "Parse failed: $file"}
   $files[$file]=@($tree.FindAll({param($a) $a -is [System.Management.Automation.Language.CommandAst]},$true))
  }
  $matches=@($files[$file] | Where-Object {
   $_.Extent.StartLineNumber -eq $row.line -and $_.Extent.Text.Trim() -ceq $row.after -and $_.GetCommandName() -ceq $row.command
  })
  if ($matches.Count -ne 1) {throw "Missing exact CommandAst witness: $($row.path):$($row.line)"}
  $count++
 }
}
if ($count -ne 767) {throw "Unexpected total AST witness count: $count"}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputReport),([ordered]@{Schema='adPEAS-RU.MIG19d7.AST.1';Status='PASS';CommandAstWitnesses=$count;Files=$files.Count;RealADTestPerformed=$false}|ConvertTo-Json),[Text.Encoding]::UTF8)
Write-Host "PASS: $count exact display CommandAst witnesses"
