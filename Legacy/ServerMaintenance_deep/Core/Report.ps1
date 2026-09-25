#requires -Version 5.1

function New-SMFReport {
    param([object]$Context)

    try {
        if ($null -eq $Context.ProfileSettings -or -not $Context.ProfileSettings.GenerateReport) { return }

        $ReportPath = $Context.ReportPath
        if (-not (Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

        $TimeStamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $JsonFile  = Join-Path $ReportPath "SMF_$TimeStamp.json"
        $HtmlFile  = Join-Path $ReportPath "SMF_$TimeStamp.html"
        $CsvFile   = Join-Path $ReportPath "SMF_$TimeStamp.csv"

        $EndTime = if ($null -ne $Context.EndTime) { $Context.EndTime } else { Get-Date }
        $Report = [PSCustomObject]@{
            Framework  = "Server Maintenance Framework"
            Version    = $Context.Version
            Computer   = $Context.ComputerName
            Profile    = $Context.Profile
            RunId      = $Context.RunId
            StartTime  = $Context.StartTime
            EndTime    = $EndTime
            Duration   = $EndTime - $Context.StartTime
            Modules    = @($Context.Results)
        }
        $Report | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonFile -Encoding UTF8

        $moduleResults = $Context.Results | Where-Object {
            $_.PSObject.Properties["Module"] -and $_.Module -and $_.Module -ne ""
        }

        $userDetailsList = $Context.Results | Where-Object {
            $_.PSObject.Properties["UserDetails"] -and $_.UserDetails.Count -gt 0
        }

        $html = @()
        $html += '<!DOCTYPE html>'
        $html += '<html>'
        $html += '<head>'
        $html += '    <meta charset="UTF-8">'
        $html += '    <title>Server Maintenance Report</title>'
        $html += '    <style>'
        $html += '        body { font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif; margin: 30px; background: #f8f9fa; }'
        $html += '        .container { max-width: 1200px; margin: auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }'
        $html += '        h1, h2 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }'
        $html += '        table { width: 100%; border-collapse: collapse; margin-top: 20px; }'
        $html += '        th { background: #34495e; color: white; padding: 10px; text-align: left; }'
        $html += '        td { padding: 8px 10px; border-bottom: 1px solid #ddd; }'
        $html += '        tr:hover { background: #f1f1f1; }'
        $html += '        .summary { background: #ecf0f1; padding: 15px; border-radius: 6px; margin: 20px 0; }'
        $html += '        .summary span { font-weight: bold; color: #2980b9; }'
        $html += '        .details { margin-top: 30px; background: #fefefe; padding: 15px; border-left: 4px solid #3498db; }'
        $html += '        .details h3 { margin-top: 20px; color: #2c3e50; }'
        $html += '        .details p { background: #f9f9f9; padding: 8px; border-radius: 4px; }'
        $html += '        .details table { width: 100%; border-collapse: collapse; margin-top: 10px; }'
        $html += '        .details th { background: #2c3e50; color: white; padding: 6px; text-align: left; }'
        $html += '        .details td { padding: 6px; border-bottom: 1px solid #ddd; }'
        $html += '        .details details { margin-top: 10px; padding: 10px; background: #f9f9f9; border-radius: 4px; }'
        $html += '        .details summary { font-weight: bold; cursor: pointer; }'
        $html += '        .details summary:hover { color: #2980b9; }'
        $html += '    </style>'
        $html += '</head>'
        $html += '<body>'
        $html += '<div class="container">'
        $html += '    <h1>Server Maintenance Framework Report</h1>'

        $totalFilesFound = ($moduleResults | Measure-Object -Property FilesFound -Sum).Sum
        $totalFilesDeleted = ($moduleResults | Measure-Object -Property FilesDeleted -Sum).Sum
        $totalBytesFreed = ($moduleResults | Measure-Object -Property BytesFreed -Sum).Sum
        $totalBytesFreedMB = [math]::Round($totalBytesFreed / 1MB, 2)

        $html += '    <div class="summary">'
        $html += "        <p><strong>Computer:</strong> $($Context.ComputerName)</p>"
        $html += "        <p><strong>Profile:</strong> $($Context.Profile)</p>"
        $html += "        <p><strong>Start:</strong> $($Context.StartTime)</p>"
        $html += "        <p><strong>End:</strong> $($Context.EndTime)</p>"
        $html += "        <p><strong>Duration:</strong> $($Context.Duration)</p>"
        $html += "        <hr>"
        $html += "        <p><span>Files found:</span> $totalFilesFound</p>"
        $html += "        <p><span>Files deleted:</span> $totalFilesDeleted</p>"
        $html += "        <p><span>Total freed:</span> $totalBytesFreedMB MB</p>"
        $html += '    </div>'

        $html += '    <h2>Module Results</h2>'
        $html += '    <table>'
        $html += '        <thead>'
        $html += '            <tr>'
        $html += '                <th>Module</th>'
        $html += '                <th>Status</th>'
        $html += '                <th>Found</th>'
        $html += '                <th>Deleted</th>'
        $html += '                <th>Before (MB)</th>'
        $html += '                <th>Freed (MB)</th>'
        $html += '            </tr>'
        $html += '        </thead>'
        $html += '        <tbody>'

        if ($moduleResults.Count -gt 0) {
            foreach ($Item in $moduleResults) {
                $statusColor = switch ($Item.Status) {
                    "Completed" { "color: green;" }
                    "Failed"    { "color: red; font-weight: bold;" }
                    default     { "color: orange;" }
                }
                $html += "            <tr>"
                $html += "                <td><b>$($Item.Module)</b></td>"
                $html += "                <td style='$statusColor'>$($Item.Status)</td>"
                $html += "                <td>$($Item.FilesFound)</td>"
                $html += "                <td>$($Item.FilesDeleted)</td>"
                $html += "                <td>$([math]::Round($Item.BytesBefore / 1MB, 2)) MB</td>"
                $html += "                <td>$([math]::Round($Item.BytesFreed / 1MB, 2)) MB</td>"
                $html += "            </tr>"
            }
        } else {
            $html += "            <tr><td colspan='6'>No module data</td></tr>"
        }

        $html += '        </tbody>'
        $html += '    </table>'

        # Additional stats for modules with WouldDelete/Skipped
        foreach ($Item in $moduleResults) {
            if ($Item.PSObject.Properties["WouldDeleteCount"] -and $Item.PSObject.Properties["SkippedCount"]) {
                $html += '    <div class="details">'
                $html += "        <h3>$($Item.Module) - Additional Stats</h3>"
                $html += "        <p><b>Would Delete:</b> $($Item.WouldDeleteCount)</p>"
                $html += "        <p><b>Skipped:</b> $($Item.SkippedCount)</p>"
                $html += '    </div>'
            }
        }

        $html += '    <div class="details">'
        $html += '        <h2>Warnings &amp; Errors per Module</h2>'
        $ModuleDetails = ""
        foreach ($Item in $moduleResults) {
            $warnings = $Item.Warnings -join "<br>"
            $errors = $Item.Errors -join "<br>"
            if ($warnings -or $errors) {
                $ModuleDetails += "<h3>$($Item.Module)</h3>"
                if ($warnings) { $ModuleDetails += "<p><b>Warnings:</b><br>$warnings</p>" }
                if ($errors) { $ModuleDetails += "<p><b>Errors:</b><br>$errors</p>" }
            }
        }
        if (-not $ModuleDetails) { $ModuleDetails = "<p>No warnings or errors.</p>" }
        $html += "        $ModuleDetails"
        $html += '    </div>'

        # User details (collapsible)
        foreach ($Item in $userDetailsList) {
            $html += '    <div class="details">'
            $html += '        <details>'
            $summary = "$($Item.Module) - user details ($($Item.UserDetails.Count) profiles)"
            $html += "            <summary><b>$summary</b></summary>"
            $html += '            <table>'
            $html += '                <thead>'
            $html += '                    <tr>'
            $html += '                        <th>User</th>'
            $html += '                        <th>Account</th>'
            $html += '                        <th>Profile Path</th>'
            $html += '                        <th>Size (MB)</th>'
            $html += '                        <th>Last Use</th>'
            $html += '                        <th>AD Enabled</th>'
            $html += '                        <th>AD Last Logon</th>'
            $html += '                        <th>Action</th>'
            $html += '                        <th>Reason</th>'
            $html += '                    </tr>'
            $html += '                </thead>'
            $html += '                <tbody>'
            foreach ($u in $Item.UserDetails) {
                $html += '                    <tr>'
                $html += "                        <td>$($u.User)</td>"
                $html += "                        <td>$($u.Account)</td>"
                $html += "                        <td>$($u.ProfilePath)</td>"
                $html += "                        <td>$($u.SizeMB)</td>"
                $html += "                        <td>$($u.LastUseTime)</td>"
                $html += "                        <td>$($u.ADEnabled)</td>"
                $html += "                        <td>$($u.ADLastLogon)</td>"
                $html += "                        <td><strong>$($u.Action)</strong></td>"
                $html += "                        <td>$($u.Reason)</td>"
                $html += '                    </tr>'
            }
            $html += '                </tbody>'
            $html += '            </table>'
            $html += '        </details>'
            $html += '    </div>'
        }

        $html += '</div>'
        $html += '</body>'
        $html += '</html>'

        $htmlContent = $html -join "`r`n"
        [System.IO.File]::WriteAllText($HtmlFile, $htmlContent, [System.Text.UTF8Encoding]::new($true))

        if ($moduleResults.Count -gt 0) {
            $moduleResults | Select-Object Module, Status, FilesFound, FilesDeleted,
                @{N='BytesFreedMB';E={[math]::Round($_.BytesFreed/1MB,2)}} |
                Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
        }

        Write-Host ""
        Write-Host "Reports generated:"
        Write-Host "  $JsonFile"
        Write-Host "  $HtmlFile"
        if (Test-Path $CsvFile) { Write-Host "  $CsvFile" }
    }
    catch {
        Write-Host ""
        Write-Host "Report generation failed:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        if (Get-Command Write-SMFLog -ErrorAction SilentlyContinue) {
            Write-SMFLog "Report generation failed: $($_.Exception.Message)" "ERROR"
        }
    }
}