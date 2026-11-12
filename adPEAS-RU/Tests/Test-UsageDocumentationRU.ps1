#Requires -Version 5.1
<#
.SYNOPSIS
    DOC1: точность полного перечня параметров README по AST PowerShell.
.DESCRIPTION
    Не подключается к AD, не исполняет исходные команды и не требует сети.
    Сопоставляет собственные параметры десяти пользовательских точек входа
    с документацией; проверяет базовые страницы 00–03 и примерную полноту.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$readmePath=Join-Path $ProjectRoot 'README_RU.md'
$readme=[IO.File]::ReadAllText($readmePath,[Text.Encoding]::UTF8)
$heading='## Быстрый старт и полный синтаксис параметров'
if(-not $readme.StartsWith('# adPEAS-RU 2.9.0'+[Environment]::NewLine+[Environment]::NewLine+$heading)){
 throw 'DOC1: полный справочник параметров должен быть в начале README'
}
$end=$readme.IndexOf('## Локализация содержимого отчётов',[StringComparison]::Ordinal)
if($end -lt 0){throw 'DOC1: утеряна историческая часть README'}
$front=$readme.Substring(0,$end)
$entrypoints=@(
 [pscustomobject]@{ File='Run-AD-Audit-RU.ps1';Function='';Params=@(
   'Domain','Server','OutputDirectory','Format','Module','ExcludeModule','OPSEC','IncludePrivileged','UseLDAPS','AllowUntrustedCertificate','Credential')},
 [pscustomobject]@{ File='src/adPEAS.ps1';Function='Invoke-adPEAS';Params=@(
   'Domain','Server','UseLDAPS','UseWindowsAuth','Credential','Username','Password','Certificate','CertificatePassword','Outputfile',
   'Module','ExcludeModule','OPSEC','NoColor','VerboseLogging','InactiveDays','IncludePrivileged','TimeoutSeconds','Format',
   'OutputAppend','License','Statistics')},
 [pscustomobject]@{ File='src/modules/Core/Connect-adPEAS.ps1';Function='Connect-adPEAS';Params=@(
   'Domain','Server','UseLDAPS','IgnoreSSLErrors','DnsServer','PatchHostsFile','Quiet','UseWindowsAuth','Credential',
   'Username','Password','Certificate','CertificatePassword','ForcePassTheCert','NTHash','AES256Key','AES128Key',
   'Kirbi','Ccache','ForceNTLM','ForceSimpleBind','ForceKerberos','License','BuildCompletionCache','TimeoutSeconds')},
 [pscustomobject]@{ File='src/modules/Collector/Invoke-adPEASCollector.ps1';Function='Invoke-adPEASCollector';Params=@(
   'Domain','Server','Credential','OutputPath','CollectionMethod','NoZip','PrettyPrint')},
 [pscustomobject]@{ File='src/modules/Reporting/Convert-adPEASReport.ps1';Function='Convert-adPEASReport';Params=@(
   'InputJson','OutputPath','Format','License','NoColor')},
 [pscustomobject]@{ File='src/modules/Reporting/Compare-adPEASReport.ps1';Function='Compare-adPEASReport';Params=@(
   'Baseline','Current','OutputPath','NoColor')},
 [pscustomobject]@{ File='src/modules/Helpers/Get-adPEASSession.ps1';Function='Get-adPEASSession';Params=@(
   'TestConnection','Quiet')},
 [pscustomobject]@{ File='src/modules/Core/Disconnect-adPEAS.ps1';Function='Disconnect-adPEAS';Params=@(
   'Force')},
 [pscustomobject]@{ File='Import-adPEAS-RU.ps1';Function='';Params=@('SkipBuild')},
 [pscustomobject]@{ File='Build-Release.ps1';Function='';Params=@(
   'License','Stable','CodeSigningCert','CertPassword','TimestampServer','ConfigPath')}
)
$total=0
foreach($spec in $entrypoints){
 $source=Join-Path $ProjectRoot $spec.File
 if(-not [IO.File]::Exists($source)){throw "DOC1: исходный файл не найден: $($spec.File)"}
 $tokens=$null;$parseErrors=$null
 $ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
 if(@($parseErrors).Count -gt 0){throw "DOC1: ошибки парсинга PowerShell: $($spec.File)"}
 if($spec.Function){
  $matches=@($ast.FindAll({
   param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq $spec.Function
  },$true))
  if($matches.Count -ne 1){throw "DOC1: функция $($spec.Function) отсутствует или повторена"}
  $params=@($matches[0].Body.ParamBlock.Parameters)
 }else{
  if($null -eq $ast.ParamBlock){throw "DOC1: не найден param() в $($spec.File)"}
  $params=@($ast.ParamBlock.Parameters)
 }
 $actual=@($params | ForEach-Object {[string]$_.Name.VariablePath.UserPath} | Sort-Object)
 $expected=@($spec.Params | Sort-Object)
 if(($actual -join ',') -cne ($expected -join ',')){
  throw "DOC1: контракт параметров изменился: $($spec.File) :: фактически $($actual -join ',') :: документация $($expected -join ',')"
 }
 foreach($name in $expected){
  if(-not $front.Contains('-'+$name)){
   throw "DOC1: README не содержит параметр -$name из $($spec.File)"
  }
 }
 $total+=$actual.Count
}
if($entrypoints.Count -ne 10 -or $total -lt 80){
 throw "DOC1: ожидались 10 основных интерфейсов и не менее 80 параметров; найдено $($entrypoints.Count) / $total"
}
foreach($key in @('-OPSEC:$false','-UseLDAPS:$false','-IgnoreSSLErrors:$false',
                'Bloodhound','Shares','-OutputAppend','-InactiveDays','-Statistics',
                '-AllowUntrustedCertificate','-BuildCompletionCache')){
 if(-not $front.Contains($key)){throw "DOC1: отсутствует обязательное предупреждение/ключ $key"}
}
foreach($item in @(
 @{File='00-Home.md';Minimum=3000;Markers=@('Ключевые особенности','Юридические условия','Текущая закреплённая')},
 @{File='01-Installation.md';Minimum=4000;Markers=@('Сетевые','Лицензирование','Варианты файлов')},
 @{File='02-Quick-Start.md';Minimum=6000;Markers=@('OPSEC','OutputAppend','BloodHound')},
 @{File='03-Authentication-Methods.md';Minimum=7000;Markers=@('Kerberos','Schannel','Ccache')},
 @{File='05-BloodHound-Collector.md';Minimum=5000;Markers=@('Invoke-adPEASCollector','DCOnly','GetChangesAll')},
 @{File='12-FAQ.md';Minimum=6000;Markers=@('OPSEC','ESC15','-OutputAppend')}
)){
 $path=Join-Path $ProjectRoot ('docs/ru-RU/'+$item.File)
 if(-not [IO.File]::Exists($path)){throw "DOC1: не создана русская страница $($item.File)"}
 $content=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
 if($content.Length -lt $item.Minimum){throw "DOC1: страница $($item.File) слишком короткая"}
 if(([regex]::Matches($content,'(?m)^~~~')).Count % 2 -ne 0){throw "DOC1: не закрыт Markdown код-блок $($item.File)"}
 foreach($term in $item.Markers){
  if(-not $content.Contains($term)){throw "DOC1: на странице $($item.File) отсутствует тема $term"}
 }
}
Write-Host "PASS DOC1: 10 интерфейсов, $total параметров сверены с PowerShell AST; README в начале и 6 страниц документации проверены" -ForegroundColor Green
