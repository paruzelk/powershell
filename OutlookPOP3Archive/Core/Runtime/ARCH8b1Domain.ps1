#requires -Version 5.1
# ARCH8b1: domain-independent deployment planning and trusted release payload.
function Get-OPAARCH8b1Sha256 {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{[BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-OPAARCH8b1ScopeId {
    param([string]$DomainSid,[string]$TargetOU,[string]$GroupName,[string[]]$ComputerNames,[string]$GpoName='RDS - Outlook POP3 Archive (Pilot)')
    if($DomainSid -cnotmatch '^S-1-5-21-\d+-\d+-\d+$' -or $TargetOU -notmatch '^OU=' -or $GroupName -cnotmatch '^[A-Za-z0-9_.-]{1,20}$' -or [string]::IsNullOrWhiteSpace($GpoName) -or @($ComputerNames).Count -lt 1){throw 'ARCH8b1 explicit domain, OU, group and hosts required.'}
    $names=@($ComputerNames | ForEach-Object {$_.ToLowerInvariant()} | Sort-Object -Unique)
    if($names.Count -ne $ComputerNames.Count -or @($names | Where-Object {$_ -notmatch '^[a-z0-9][a-z0-9.-]*\.[a-z0-9.-]+$'}).Count -gt 0){throw 'ARCH8b1 unique domain computer FQDNs required.'}
    Get-OPAARCH8b1Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(($DomainSid+'|'+$TargetOU.ToLowerInvariant()+'|'+$GroupName.ToLowerInvariant()+'|'+$GpoName.ToLowerInvariant()+'|'+($names -join '|'))))
}
function New-OPAARCH8b1PolicyCommand {
    param([string]$ProgramFiles,[string]$WindowsDirectory)
    foreach($path in @($ProgramFiles,$WindowsDirectory)){
        if($path -notmatch '^[A-Za-z]:\\' -or $path -match '["%\r\n]' -or $path -match '(^|\\)\.\.?($|\\)'){throw 'ARCH8b1 local absolute protected directories required.'}
    }
    $exe=Join-Path $WindowsDirectory 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $entry=Join-Path $ProgramFiles 'OutlookPOP3Archive-Logon\Start-OPAArchiveAtLogon.ps1'
    $command='"'+$exe+'" -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File "'+$entry+'"'
    if($command.Length -gt 259){throw 'ARCH8b1 logon command exceeds conservative length limit.'}
    return $command
}
function Test-OPAARCH8b1RuntimeRelativePath {
    param([string]$Path)
    if($Path -cin @('OutlookPOP3Archive.ps1','Invoke-OPARdsAutoDev.ps1','Invoke-OPALiveArchiveBatches.ps1','BUILD-INFO.json')){return $true}
    return ($Path -cmatch '^Core/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\.ps1$' -and $Path -notmatch '(^|/)\.\.?(/|$)')
}
function New-OPAARCH8b1Payload {
    param([string]$ProjectRoot)
    $root=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $build=Get-Content -LiteralPath (Join-Path $root 'BUILD-INFO.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($build.WindowsPowerShell51CiPassed -ne $true -or [string]$build.SourceCommit -cnotmatch '^[a-f0-9]{40}$'){throw 'ARCH8b1 requires an unpacked CI release; verify external ZIP SHA256 first.'}
    $core=Join-Path $root 'Core'
    foreach($item in @(Get-Item -LiteralPath $root,$core)+@(Get-ChildItem -LiteralPath $core -Recurse -Force)){
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH8b1 redirected source package entry.'}
    }
    $paths=@('OutlookPOP3Archive.ps1','Invoke-OPARdsAutoDev.ps1','Invoke-OPALiveArchiveBatches.ps1','BUILD-INFO.json')
    $paths+=@(Get-ChildItem -LiteralPath $core -Recurse -File -Force | ForEach-Object {$_.FullName.Substring($root.Length+1).Replace('\','/')})
    if(@($paths | Sort-Object -Unique).Count -ne $paths.Count){throw 'ARCH8b1 duplicate source package path.'}
    Add-Type -AssemblyName System.IO.Compression
    $memory=[IO.MemoryStream]::new()
    $archive=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Create,$true)
    $manifest=New-Object 'System.Collections.Generic.List[object]'
    try{
        foreach($path in $paths){
            if(-not (Test-OPAARCH8b1RuntimeRelativePath -Path $path)){throw ('ARCH8b1 unexpected package path: '+$path)}
            $source=Get-Item -LiteralPath (Join-Path $root $path) -ErrorAction Stop
            if($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH8b1 unsafe package source.'}
            $bytes=[IO.File]::ReadAllBytes($source.FullName)
            $entry=$archive.CreateEntry($path,[IO.Compression.CompressionLevel]::Optimal)
            $stream=$entry.Open()
            try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
            $manifest.Add([pscustomobject]@{Path=$path;Sha256=(Get-OPAARCH8b1Sha256 -Bytes $bytes)})
        }
    }finally{$archive.Dispose()}
    try{$zip=$memory.ToArray()}finally{$memory.Dispose()}
    [pscustomobject]@{SourceCommit=[string]$build.SourceCommit;ZipBase64=[Convert]::ToBase64String($zip);ZipSha256=(Get-OPAARCH8b1Sha256 -Bytes $zip);Files=@($manifest.ToArray());LauncherSha256=(Get-FileHash -LiteralPath (Join-Path $root 'Core\Runtime\Start-OPAArchiveAtLogon.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()}
}
