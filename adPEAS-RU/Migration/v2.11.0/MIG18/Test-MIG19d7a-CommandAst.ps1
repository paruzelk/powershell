param(
 [Parameter(Mandatory=$true)][string]$Candidate,
 [Parameter(Mandatory=$true)][string[]]$Reports,
 [Parameter(Mandatory=$true)][string]$OutputReport
)
$ErrorActionPreference='Stop'
$files=@{}
$records=New-Object 'System.Collections.Generic.List[object]'
$seen=@{}
function Test-ExampleCommand([string]$Text,[string]$Name) {
 $t=$null;$e=$null
 $a=[System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$t,[ref]$e)
 if ($e.Count -ne 0) {return $false}
 $m=@($a.FindAll({param($x) $x -is [System.Management.Automation.Language.CommandAst]},$true) | Where-Object {
   $_.Extent.Text.Trim() -ceq $Text -and $_.GetCommandName() -ceq $Name
 })
 return ($m.Count -eq 1)
}
foreach ($report in $Reports) {
 $data=Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
 foreach ($row in $data.changes) {
  $file=Join-Path $Candidate $row.path
  $lineNumber=[int]$row.line
  $id=$row.path+':'+$lineNumber
  if ($seen.ContainsKey($id)) {throw "Duplicate changed source line: $id"}
  $seen[$id]=$true
  if (-not $files.ContainsKey($file)) {
   $tokens=$null;$errors=$null
   $tree=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file).Path,[ref]$tokens,[ref]$errors)
   if ($errors.Count -gt 0) {throw "Parse failed: $file"}
   $files[$file]=@{
    Commands=@($tree.FindAll({param($a) $a -is [System.Management.Automation.Language.CommandAst]},$true))
    Comments=@($tokens | Where-Object {$_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment})
    Lines=[IO.File]::ReadAllLines((Resolve-Path $file).Path,[Text.Encoding]::UTF8)
   }
  }
  $ctx=$files[$file]
  $status='UNVERIFIED';$detail=''
  if ($lineNumber -lt 1 -or $lineNumber -gt $ctx.Lines.Length -or $ctx.Lines[$lineNumber-1].Trim() -cne $row.after) {
   $detail='Final source line differs from recorded translation'
  } else {
   $matches=@($ctx.Commands | Where-Object {
    $_.Extent.StartLineNumber -eq $lineNumber -and $_.Extent.Text.Trim() -ceq $row.after -and $_.GetCommandName() -ceq $row.command
   })
   if ($matches.Count -eq 1) {$status='EXECUTABLE_COMMAND_AST'}
   elseif ($matches.Count -eq 0) {
    $comments=@($ctx.Comments | Where-Object {
     $_.Extent.StartLineNumber -lt $lineNumber -and $_.Extent.EndLineNumber -gt $lineNumber -and $_.Text.StartsWith('<#') -and $_.Text.EndsWith('#>')
    })
    if ($comments.Count -eq 1) {
     $comment=$comments[0]
     $section=''
     for ($i=$comment.Extent.StartLineNumber; $i -lt $lineNumber; $i++) {
      if ($ctx.Lines[$i-1] -match '^\s*\.(\w+)(?:\s|$)') {$section=$Matches[1].ToUpperInvariant()}
     }
     if ($section -ceq 'EXAMPLE' -and
         (Test-ExampleCommand -Text $row.before -Name $row.command) -and
         (Test-ExampleCommand -Text $row.after -Name $row.command)) {
      $status='COMMENT_HELP_EXAMPLE_AST'
     } else {$detail="Not a verified .EXAMPLE command (section=$section)"}
    } else {$detail='No exact executable AST or enclosing block-comment token'}
   } else {$detail='Multiple executable AST matches'}
  }
  $records.Add([pscustomobject]@{Path=$row.path;Line=$lineNumber;Command=$row.command;Status=$status;Detail=$detail})
 }
}
$executable=@($records | Where-Object {$_.Status -eq 'EXECUTABLE_COMMAND_AST'})
$examples=@($records | Where-Object {$_.Status -eq 'COMMENT_HELP_EXAMPLE_AST'})
$unverified=@($records | Where-Object {$_.Status -eq 'UNVERIFIED'})
$passed=($records.Count -eq 767 -and $unverified.Count -eq 0 -and ($executable.Count+$examples.Count) -eq 767)
$data=[ordered]@{
 Schema='adPEAS-RU.MIG19d7a.AST.1'
 Status=$(if ($passed) {'PASS'} else {'FAIL'})
 Total=$records.Count
 ExecutableCommandAstWitnesses=$executable.Count
 CommentHelpExampleAstWitnesses=$examples.Count
 UnverifiedCount=$unverified.Count
 Files=$files.Count
 Examples=$examples
 Unverified=$unverified
 Records=$records.ToArray()
 RealADTestPerformed=$false
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputReport),($data|ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8)
Write-Host "AST: executable=$($executable.Count) examples=$($examples.Count) unverified=$($unverified.Count) total=$($records.Count)"
foreach ($r in $unverified) {Write-Host "UNVERIFIED $($r.Path):$($r.Line) $($r.Detail)"}
if (-not $passed) {throw 'MIG19d7a AST classification failed; inspect published evidence'}
Write-Host 'PASS: all 767 changed lines classified and verified, including documented examples'
