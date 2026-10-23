$reportsPath = Join-Path $PSScriptRoot 'Reports'
$lastReport = Get-ChildItem -LiteralPath $reportsPath -Filter '*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($lastReport) {
    $data = Get-Content -LiteralPath $lastReport.FullName -Raw | ConvertFrom-Json
    $totalFreed = ($data.Modules | Measure-Object -Property BytesFreed -Sum).Sum
    $totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
    Write-Host "Total freed: $totalFreedMB MB"
} else {
    Write-Error "No JSON reports found in $reportsPath"
    exit 1
}
