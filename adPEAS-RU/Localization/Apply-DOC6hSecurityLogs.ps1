#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6h: перевод диагностических строк пяти модулей аудита AD.
.DESCRIPTION
    Все исходные строки сверяются перед записью, перевод привязан к номеру
    строки и модулю. Технические значения и алгоритмы остаются без изменений.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$allow=@(
 'src/modules/Checks/Application/Get-ExchangeInfrastructure.ps1',
 'src/modules/Checks/Creds/Get-CredentialExposure.ps1',
 'src/modules/Checks/GPO/Get-GPOPermissions.ps1',
 'src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1',
 'src/modules/Checks/ADCS/Get-WeakCertificateMapping.ps1'
)
$expected=@(27,27,22,22,17)
$plans=New-Object 'System.Collections.Generic.List[object]'
$total=0
for($i=1;$i -le 5;$i++){
    $manifestPath=Join-Path $PSScriptRoot ('DOC6h-Check{0}.json' -f $i)
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "DOC6h: отсутствует реестр $i"}
    $map=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($map.schema -ne 'adPEAS-RU.DOC6h.SecurityLog.1' -or $map.path -cne $allow[$i-1]){
        throw "DOC6h: неверная схема или файл в реестре $i"
    }
    if(@($map.entries).Count -ne $expected[$i-1]){throw "DOC6h: неверное число переводов $i"}
    $filePath=Join-Path $ProjectRoot (([string]$map.path).Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $filePath -PathType Leaf)){throw "DOC6h: файл отсутствует $($map.path)"}
    $raw=[IO.File]::ReadAllText($filePath,[Text.Encoding]::UTF8)
    $crlf=[string][char]13+[string][char]10
    $sep=if($raw.Contains($crlf)){$crlf}else{[string][char]10}
    $lines=[regex]::Split($raw,'\r?\n')
    $seen=New-Object 'System.Collections.Generic.HashSet[int]'
    foreach($row in @($map.entries)){
        $number=[int]$row.line
        $original=[string]$row.original
        $target=[string]$row.target
        if($number -lt 1 -or $number -gt $lines.Count -or -not $seen.Add($number)){
            throw "DOC6h: повторный или неверный номер $($map.path):$number"
        }
        if($original -ceq $target -or [string]::IsNullOrWhiteSpace($target)){
            throw "DOC6h: пустой или совпадающий перевод $($map.path):$number"
        }
        if($lines[$number-1] -cne $original){throw "DOC6h: исходная строка изменилась $($map.path):$number"}
        $lines[$number-1]=$target
        $total++
    }
    $plans.Add([PSCustomObject]@{Path=$filePath;Content=[string]::Join($sep,$lines)})
}
if($plans.Count -ne 5 -or $total -ne 115){
    throw "DOC6h: ожидалось 5 файлов и 115 сообщений, найдено $($plans.Count) и $total"
}
foreach($plan in $plans){
    [IO.File]::WriteAllText($plan.Path,$plan.Content,(New-Object Text.UTF8Encoding($true)))
}
Write-Host '[RU] PASS DOC6h: 115 диагностических сообщений, 5 PS-файлов UTF-8 BOM'
