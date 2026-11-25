#requires -Version 5.1
# ARCH6f3c2: never restore, open, run or exclude a detected payload.
function Get-OPAARCH6VirusHResult {
    param([Exception]$Exception)
    while($null -ne $Exception){
        $hex='{0:X8}' -f [int]$Exception.HResult
        if($hex -cin @('800700E1','800700E2')){return $hex}
        $Exception=$Exception.InnerException
    }
    return $null
}
function Get-OPAARCH6DefenderMatches {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$AttachmentName,
          [Parameter(Mandatory=$true)][datetime]$From,
          [Parameter(Mandatory=$true)][datetime]$To,
          [string]$DetectionId,
          [string]$TemporaryPath)
    if($To -lt $From -or ($To-$From).TotalSeconds -gt 120){return}
    try{$detections=@(Get-MpThreatDetection -ErrorAction Stop)}catch{return}
    $cache=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\Windows\INetCache\Content.Outlook'
    foreach($d in $detections){
        if(-not $d.ActionSuccess -or [string]$d.ProcessName -notmatch '(?i)\\OUTLOOK\.EXE$' -or
           [string]$d.DetectionID -notmatch '^\{?[0-9a-fA-F-]{36}\}?$' -or [long]$d.ThreatID -le 0){continue}
        if($DetectionId -and ([guid]$d.DetectionID -ne [guid]$DetectionId)){continue}
        $time=[datetime]$d.InitialDetectionTime
        if($time -lt $From -or $time -gt $To){continue}
        $matched=@($d.Resources | Where-Object {
            $resource=[string]$_
            if(-not $resource.StartsWith('file:_',[StringComparison]::OrdinalIgnoreCase)){return $false}
            $path=$resource.Substring(6)
            ($TemporaryPath -and $path -ieq $TemporaryPath) -or
            ($path.StartsWith(($cache+'\'),[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($path) -ieq $AttachmentName)
        })
        if($matched.Count -ne 1){continue}
        $threatName=''
        try{
            $threats=@(Get-MpThreat -ErrorAction Stop | Where-Object {[long]$_.ThreatID -eq [long]$d.ThreatID})
            if($threats.Count -eq 1){$threatName=[string]$threats[0].ThreatName}
        }catch{Write-Verbose 'Defender threat name unavailable.'}
        [pscustomobject][ordered]@{DetectionId=([guid]$d.DetectionID).ToString('D');ThreatId=[long]$d.ThreatID;ThreatName=$threatName;DetectionTime=$time.ToString('o');Resource=[string]$matched[0];ProcessName=[string]$d.ProcessName;ActionSuccess=$true}
    }
}
function New-OPAARCH6AntivirusEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$EntryId,
          [Parameter(Mandatory=$true)][string]$AttachmentName,
          [ValidateRange(1,256)][int]$Index,
          [datetime]$From,[datetime]$To,
          [string]$TemporaryPath,[Exception]$Exception)
    if($EntryId -notmatch '^[0-9a-fA-F]{16,2048}$' -or -not $AttachmentName -or $AttachmentName.Length -gt 1024 -or $Index -lt 1){return}
    $hex=Get-OPAARCH6VirusHResult -Exception $Exception
    $observed=if($null -ne $Exception){'{0:X8}' -f [int]$Exception.HResult}else{''}
    $matches=@(Get-OPAARCH6DefenderMatches -AttachmentName $AttachmentName -From $From -To $To -TemporaryPath $TemporaryPath)
    if(-not $hex -and $matches.Count -ne 1){return}
    $d=if($matches.Count -eq 1){$matches[0]}else{$null}
    $reason=if($hex -ceq '800700E2'){'AttachmentQuarantined'}else{'AttachmentBlockedByAntivirus'}
    [pscustomobject][ordered]@{EntryId=$EntryId;AttachmentName=$AttachmentName;AttachmentIndex=$Index;HResult=$hex;ObservedHResult=$observed;Reason=$reason;Defender=$d;MoveAttempted=$false}
}
function ConvertFrom-OPAARCH6AntivirusMessage {
    param([string]$Message,[string]$ExpectedEntryId)
    if($Message -cnotmatch '^ARCH6f3c2 (AttachmentBlockedByAntivirus|AttachmentQuarantined): ([A-Za-z0-9+/=]+)$'){return}
    $reason=$Matches[1];$encoded=$Matches[2]
    try{
        $e=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($encoded))) -ErrorAction Stop
        if($e.EntryId -notmatch '^[0-9a-fA-F]{16,2048}$' -or ($ExpectedEntryId -and $e.EntryId -ine $ExpectedEntryId) -or
           [string]$e.Reason -cne $reason -or $e.MoveAttempted -ne $false -or -not $e.AttachmentName -or
           ([string]$e.AttachmentName).Length -gt 1024 -or [int]$e.AttachmentIndex -lt 1 -or [int]$e.AttachmentIndex -gt 256){return}
        if($e.HResult -cnotin @('800700E1','800700E2')){
            if($null -eq $e.Defender -or $e.Defender.ActionSuccess -ne $true -or [long]$e.Defender.ThreatId -le 0 -or
               [string]$e.Defender.DetectionId -notmatch '^[0-9a-fA-F-]{36}$'){return}
        }
        if(($reason -ceq 'AttachmentQuarantined') -ne ($e.HResult -ceq '800700E2')){return}
        return $e
    }catch{return}
}
function ConvertTo-OPAARCH6AntivirusMessage {
    param([Parameter(Mandatory=$true)][object]$Evidence)
    $data=ConvertTo-Json -InputObject $Evidence -Depth 6 -Compress
    return ('ARCH6f3c2 '+$Evidence.Reason+': '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($data)))
}


# ARCH6f3c3: classify only the narrow pre-Move SaveAsFile boundary.
# No antivirus discovery or query. Never retry the original payload.
function Get-OPAARCH6ExportFailureKind {
    param([Exception]$Exception,[switch]$MissingOutput)
    $com=$false
    while($null -ne $Exception){
        $hex='{0:X8}' -f [int]$Exception.HResult
        # Known system faults are not item-local: permission, disk, path,
        # write protection, sharing, resource exhaustion, RPC/COM disconnect.
        if($Exception -is [UnauthorizedAccessException] -or
           $hex -cin @('80070005','80070003','8007000F','80070013','80070015','80070017','8007001D','80070020','80070021','80070027','80070070','80070008','8007000E','800700AA','800705AA','800706BA','800706BE','800706BF','80010108','80010007','80010012','800401FD','80040115','8004011D','8001010A','80010001')){
            return 'SystemFailure'
        }
        if($Exception -is [Runtime.InteropServices.COMException]){$com=$true}
        $Exception=$Exception.InnerException
    }
    if($MissingOutput){return 'AttachmentPayloadUnavailable'}
    if($com){return 'AttachmentExportFailed'}
    return 'UnknownFailure'
}
function Assert-OPAARCH6ExportWorkspaceHealthy {
    param([Parameter(Mandatory=$true)][string]$Workspace,
          [long]$AttachmentBytes)
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $Workspace)
    $root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Workspace))
    $drive=[IO.DriveInfo]::new($root)
    if(-not $drive.IsReady -or $AttachmentBytes -lt 0 -or $drive.AvailableFreeSpace -lt ($AttachmentBytes+64MB)){
        throw 'ARCH6f3c3 insufficient workspace capacity; stop.'
    }
    $probe=Join-Path $Workspace ('OPA-health-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $stream=$null
    try{
        $stream=[IO.FileStream]::new($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.WriteByte(0)
        $stream.Flush($true)
    }finally{
        if($null -ne $stream){$stream.Dispose();[IO.File]::Delete($probe)}
    }
    if([IO.File]::Exists($probe)){throw 'ARCH6f3c3 workspace probe cleanup failed.'}
}
function New-OPAARCH6LocalExportEvidence {
    [CmdletBinding()]
    param([object]$Mail,[object]$Attachment,[string]$EntryId,[string]$AttachmentName,
          [int]$Index,[long]$AttachmentBytes,[string]$Workspace,[Exception]$Exception,
          [switch]$MissingOutput)
    if($EntryId -notmatch '^[0-9a-fA-F]{16,2048}$' -or -not $AttachmentName -or $AttachmentName.Length -gt 1024 -or $Index -lt 1 -or $Index -gt 256){return}
    $kind=Get-OPAARCH6ExportFailureKind -Exception $Exception -MissingOutput:$MissingOutput
    if($kind -cin @('SystemFailure','UnknownFailure')){return}
    # Read only existing metadata to reject a disconnected/changed object.
    if([int]$Mail.Class -ne 43 -or [string]$Mail.EntryID -ine $EntryId -or
       [int]$Attachment.Type -ne 1 -or [string]$Attachment.FileName -cne $AttachmentName -or [long]$Attachment.Size -ne $AttachmentBytes){return}
    Assert-OPAARCH6ExportWorkspaceHealthy -Workspace $Workspace -AttachmentBytes $AttachmentBytes
    $hex=Get-OPAARCH6VirusHResult -Exception $Exception
    $observed=if($null -ne $Exception){'{0:X8}' -f [int]$Exception.HResult}else{''}
    if($hex){
        $reason=if($hex -ceq '800700E2'){'AttachmentQuarantined'}else{'AttachmentBlockedByAntivirus'}
        return [pscustomobject][ordered]@{EntryId=$EntryId;AttachmentName=$AttachmentName;AttachmentIndex=$Index;HResult=$hex;ObservedHResult=$observed;Reason=$reason;Defender=$null;MoveAttempted=$false}
    }
    $detail=if($null -ne $Exception){[string]$Exception.Message}else{''}
    if($detail.Length -gt 2048){$detail=$detail.Substring(0,2048)}
    return [pscustomobject][ordered]@{EntryId=$EntryId;AttachmentName=$AttachmentName;AttachmentIndex=$Index;HResult=$null;ObservedHResult=$observed;Reason=$kind;Defender=$null;MoveAttempted=$false;WorkspaceHealthy=$true;MetadataMatched=$true;ErrorDetail=$detail}
}
function ConvertTo-OPAARCH6LocalExportMessage {
    param([Parameter(Mandatory=$true)][object]$Evidence)
    if($Evidence.Reason -cin @('AttachmentBlockedByAntivirus','AttachmentQuarantined')){return (ConvertTo-OPAARCH6AntivirusMessage -Evidence $Evidence)}
    $json=ConvertTo-Json -InputObject $Evidence -Depth 6 -Compress
    return ('ARCH6f3c3 '+$Evidence.Reason+': '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
}
function ConvertFrom-OPAARCH6LocalExportMessage {
    param([string]$Message,[string]$ExpectedEntryId)
    if($Message -cnotmatch '^ARCH6f3c3 (AttachmentExportFailed|AttachmentPayloadUnavailable): ([A-Za-z0-9+/=]{1,32768})$'){return}
    $reason=$Matches[1];$encoded=$Matches[2]
    try{
        $e=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($encoded))) -ErrorAction Stop
        if($e.EntryId -notmatch '^[0-9a-fA-F]{16,2048}$' -or ($ExpectedEntryId -and $e.EntryId -ine $ExpectedEntryId) -or
           $e.Reason -cne $reason -or $e.MoveAttempted -isnot [bool] -or $e.MoveAttempted -or
           $e.WorkspaceHealthy -isnot [bool] -or -not $e.WorkspaceHealthy -or $e.MetadataMatched -isnot [bool] -or -not $e.MetadataMatched -or
           -not $e.AttachmentName -or ([string]$e.AttachmentName).Length -gt 1024 -or [int]$e.AttachmentIndex -lt 1 -or [int]$e.AttachmentIndex -gt 256 -or
           $e.HResult -or $null -ne $e.Defender -or [string]$e.ObservedHResult -cnotmatch '^[0-9A-F]{8}$' -or ([string]$e.ErrorDetail).Length -gt 2048){return}
        return $e
    }catch{return}
}
