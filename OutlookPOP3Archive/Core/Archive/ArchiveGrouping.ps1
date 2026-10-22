function Get-OPAArchiveGroupParts {
    param(
        [Parameter(Mandatory=$true)][datetime]$Date,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$Grouping = 'YearQuarter'
    )
    switch ($Grouping) {
        'None'        { @() }
        'Year'        { @('{0:D4}' -f $Date.Year) }
        'YearQuarter' { @('{0:D4}' -f $Date.Year; 'Q{0}' -f [int][Math]::Ceiling($Date.Month / 3.0)) }
        'YearMonth'   { @(('{0:D4}' -f $Date.Year), ('{0:D2}' -f $Date.Month)) }
    }
}

function Get-OPAArchiveTargetPath {
    param(
        [Parameter(Mandatory=$true)][datetime]$ReceivedTime,
        [string]$SourceFolderName,
        [string]$SourceFolderPath,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$Grouping = 'YearQuarter'
    )
    $parts = @(Get-OPAArchiveGroupParts -Date $ReceivedTime -Grouping $Grouping)
    $sourceParts = @()
    if ($SourceFolderPath) {
        $sourceParts = @($SourceFolderPath -split '\\' | Where-Object { $_ })
        if ($sourceParts.Count -gt 0) {
            # FolderPath normally starts with the source Store name. Archive
            # PST already supplies its own root, so preserve only the folder
            # hierarchy below that store root.
            try {
                if ($sourceParts.Count -gt 1) { $sourceParts = @($sourceParts | Select-Object -Skip 1) }
            } catch {}
        }
    }
    if ($sourceParts.Count -eq 0 -and $SourceFolderName) { $sourceParts = @($SourceFolderName) }
    $parts += $sourceParts
    [string]::Join('\', $parts)
}

function Get-OPAArchiveNestedFolder {
    param(
        [Parameter(Mandatory=$true)][object]$ArchiveStore,
        [Parameter(Mandatory=$true)][datetime]$ReceivedTime,
        [Parameter(Mandatory=$true)][string]$SourceFolderName,
        [string]$SourceFolderPath,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$Grouping = 'YearQuarter'
    )
    $current = $ArchiveStore.GetRootFolder()
    $targetPath = Get-OPAArchiveTargetPath -ReceivedTime $ReceivedTime -SourceFolderName $SourceFolderName -SourceFolderPath $SourceFolderPath -Grouping $Grouping
    foreach ($part in @($targetPath -split '\\' | Where-Object { $_ })) {
        $next = $null
        $folders = $null
        try {
            $folders = $current.Folders
            foreach ($f in @($folders)) {
                try {
                    if ($null -eq $next -and [string]$f.Name -ieq [string]$part) { $next = $f }
                    else { Release-OPAComObject -Object $f }
                }
                catch { Release-OPAComObject -Object $f }
            }
        }
        finally { Release-OPAComObject -Object $folders }

        if ($null -eq $next) { $next = $current.Folders.Add([string]$part) }
        if ($current -ne $next) {
            $previous = $current
            $current = $next
            Release-OPAComObject -Object $previous
        }
    }
    $current
}
