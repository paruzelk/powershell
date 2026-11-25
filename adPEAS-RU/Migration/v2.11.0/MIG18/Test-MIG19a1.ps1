param([Parameter(Mandatory=$true)][string]$Candidate,[Parameter(Mandatory=$true)][string]$Report,[string]$Probe,[string]$ResultPath)
$ErrorActionPreference='Stop'
$Candidate=(Resolve-Path -LiteralPath $Candidate).Path
if ($Probe) {
    if ($Probe -ne 'adPEAS.exe') { Import-Module (Join-Path $Candidate $Probe) -Force -ErrorAction Stop }
    $ErrorActionPreference='Stop'
    $names=@('Invoke-adPEAS','Connect-adPEAS','Disconnect-adPEAS','Get-adPEASHelp')
    $commands=[ordered]@{}
    foreach ($n in $names) {
        $cmd=Get-Command $n -CommandType Function -ErrorAction Stop
        $commands[$n]=@($cmd.Parameters.Keys | Sort-Object)
    }
    $helpText=Get-adPEASHelp -Section QuickStart 6>&1 | Out-String
    if ($helpText -notmatch 'Быстрый старт' -or $helpText -notmatch 'Дополнительная справка' -or $helpText -match '\bQuick Start\b') { throw 'QuickStart runtime localization failed' }
    [IO.File]::WriteAllText($ResultPath,([ordered]@{Variant=$Probe;Commands=$commands;RussianQuickStart=$true;Status='PASS'} | ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8)
    exit 0
}
$root=Split-Path -Parent ([IO.Path]::GetFullPath($Report))
$null=New-Item -ItemType Directory -Path $root -Force
$results=@()
$reference=$null
foreach ($v in @('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe')) {
    $result=Join-Path $root ("MIG19a1-"+$v+".json")
    if (Test-Path -LiteralPath $result) { throw "Stale probe result: $result" }
    $out=Join-Path $root ("MIG19a1-"+$v+".stdout.txt")
    $err=Join-Path $root ("MIG19a1-"+$v+".stderr.txt")
    if ($v -eq 'adPEAS.exe') {
        $exe=Join-Path $Candidate $v
        $cmd="& '$($PSCommandPath.Replace("'","''"))' -Candidate '$($Candidate.Replace("'","''"))' -Report '$($Report.Replace("'","''"))' -Probe '$v' -ResultPath '$($result.Replace("'","''"))'"
        $argsLine='-Command "'+$cmd+'"'
    } else {
        $exe=Join-Path $PSHOME 'powershell.exe'
        $argsLine='-NoLogo -NoProfile -NonInteractive -File "'+$PSCommandPath+'" -Candidate "'+$Candidate+'" -Report "'+$Report+'" -Probe '+$v+' -ResultPath "'+$result+'"'
    }
    $p=Start-Process -FilePath $exe -ArgumentList $argsLine -WorkingDirectory $Candidate -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    if (-not $p.WaitForExit(120000)) { $p.Kill(); throw "Probe timed out: $v" }
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $result)) {
        Get-Content -LiteralPath $err | Write-Host
        throw "Probe failed: $v exit=$($p.ExitCode), result required"
    }
    $r=Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($r.Status -cne 'PASS' -or $r.Variant -cne $v -or -not $r.RussianQuickStart) { throw "Bad probe evidence: $v" }
    $signature=$r.Commands | ConvertTo-Json -Depth 6 -Compress
    if ($null -eq $reference) {$reference=$signature} elseif ($reference -cne $signature) {throw "Public parameter mismatch: $v"}
    $results+= $r
    Write-Host "PASS $v: commands, parameters and Russian QuickStart"
}
@{Schema='adPEAS-RU.MIG19a1.Runtime.1';Results=$results;RealADTestPerformed=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Report -Encoding UTF8
