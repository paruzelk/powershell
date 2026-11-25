param(
 [Parameter(Mandatory=$true)][string]$Candidate,
 [Parameter(Mandatory=$true)][ValidateSet('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe')][string]$Variant,
 [Parameter(Mandatory=$true)][string]$InputJson,
 [Parameter(Mandatory=$true)][string]$OutputBase
)
$ErrorActionPreference='Stop'
$trace=$OutputBase+'.trace.txt'
function Write-Mig19bcTrace([string]$Stage) {
 [IO.File]::AppendAllText($trace,([DateTime]::UtcNow.ToString('o')+' '+$Stage+[Environment]::NewLine),[Text.Encoding]::UTF8)
}
try {
 Write-Mig19bcTrace 'ENTER'
 if ($Variant -ne 'adPEAS.exe') {
  Import-Module -Name (Join-Path $Candidate $Variant) -Force -ErrorAction Stop
 }
 $ErrorActionPreference='Stop'
 Write-Mig19bcTrace 'IMPORTED'
 $null=Get-Command Convert-adPEASReport -CommandType Function -ErrorAction Stop
 $inputHash=(Get-FileHash -LiteralPath $InputJson -Algorithm SHA256).Hash
 Convert-adPEASReport -InputJson $InputJson -OutputPath $OutputBase -Format All -NoColor -ErrorAction Stop -WarningAction Stop
 Write-Mig19bcTrace 'CONVERT_RETURNED'
 if ((Get-FileHash -LiteralPath $InputJson -Algorithm SHA256).Hash -cne $inputHash) {throw 'Input fixture changed'}
 $files=[ordered]@{}
 foreach ($ext in @('html','txt','json')) {
  $file=$OutputBase+'.'+$ext
  $item=Get-Item -LiteralPath $file -ErrorAction Stop
  if ($item.Length -le 3) {throw "Empty output: $ext"}
  $files[$ext]=[ordered]@{Length=$item.Length;SHA256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
 }
 $data=[ordered]@{Variant=$Variant;Status='PASS';InputSha256=$inputHash;Files=$files;RealADTestPerformed=$false}
 [IO.File]::WriteAllText(($OutputBase+'.evidence.json'),($data | ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8)
 Write-Mig19bcTrace 'EVIDENCE_WRITTEN'
 exit 0
} catch {
 [IO.File]::WriteAllText(($OutputBase+'.failure.txt'),($_ | Format-List * -Force | Out-String),[Text.Encoding]::UTF8)
 Write-Mig19bcTrace 'FAIL'
 [Console]::Error.WriteLine($_.Exception.Message)
 exit 1
}
