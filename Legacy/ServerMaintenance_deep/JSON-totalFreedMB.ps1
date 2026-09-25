$lastReport = Get-ChildItem "C:\Users\Admin\Desktop\ServerMaintenance_deep\Reports\*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($lastReport) {
    $data = Get-Content $lastReport.FullName | ConvertFrom-Json
    $totalFreed = ($data.Modules | Measure-Object -Property BytesFreed -Sum).Sum
    $totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
    Write-Host "Total freed: $totalFreedMB MB"
}