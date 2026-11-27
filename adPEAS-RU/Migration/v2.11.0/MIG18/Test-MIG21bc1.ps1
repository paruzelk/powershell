param([Parameter(Mandatory=$true)][string]$Candidate)
$ErrorActionPreference = 'Stop'
$path = Join-Path $Candidate 'src/modules/Reporting/Export-HTMLReport.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path).Path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw $errors[0].Message }
foreach ($name in @('ConvertTo-RuMIG21SysvolDiagnostic','Get-RuMIG21CoverageNotice','ConvertTo-RuReportLine')) {
    $nodes = @($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
    if ($nodes.Count -ne 1) { throw "Missing or duplicate $name" }
    . ([scriptblock]::Create($nodes[0].Extent.Text))
}
$line = 'Skipped - SYSVOL not accessible'
$ru = 'Проверка пропущена: SYSVOL недоступен.'
if ((ConvertTo-RuReportLine -Text $line) -cne $ru) { throw 'Exact translation failed' }
if ((ConvertTo-RuReportLine -Text '3 SYSVOL folder(s) could not be read - the result below is incomplete') -cne 'Не удалось прочитать папки SYSVOL (количество: 3); результат ниже неполный.') { throw 'Count translation failed' }
$ordinary = 'CN=SYSVOL,OU=Test,DC=example,DC=local'
if ((ConvertTo-RuReportLine -Text $ordinary) -cne $ordinary) { throw 'Unexpected AD data translation' }
$findings = @(
    [pscustomobject]@{Type='Line';Class='Hint';Text=$line}
    [pscustomobject]@{Type='Line';Class='Note';Text=$ru}
    [pscustomobject]@{Type='Line';Class='Finding';Text='2 SYSVOL file(s) could not be read or parsed - the result below is incomplete'}
    [pscustomobject]@{Type='Object';Class='Finding';Text=$line}
)
$before = $findings | ConvertTo-Json -Depth 8 -Compress
$html = Get-RuMIG21CoverageNotice -Findings $findings
if ($html -notmatch 'ограничениях SYSVOL: 3\.' -or $html -notmatch 'Complete=True') { throw 'Coverage notice failed' }
if (($findings | ConvertTo-Json -Depth 8 -Compress) -cne $before) { throw 'Input mutated' }
if ((Get-RuMIG21CoverageNotice -Findings @()) -notmatch 'не подтверждает полноту') { throw 'Empty coverage overstated' }
$template = Get-Content (Join-Path $Candidate 'src/modules/Reporting/templates/report-template.html') -Raw -Encoding UTF8
if ([regex]::Matches($template,'\{\{MIG21_COVERAGE_NOTICE\}\}').Count -ne 1) { throw 'Template marker missing/duplicate' }
Write-Host 'PASS MIG21bc1 presentation, negative case, counts, no input mutation'
