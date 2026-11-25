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
    $matches=@(Get-OPAARCH6DefenderMatches -AttachmentName $AttachmentName -From $From -To $To -TemporaryPath $TemporaryPath)
    if(-not $hex -and $matches.Count -ne 1){return}
    $d=if($matches.Count -eq 1){$matches[0]}else{$null}
    $reason=if($hex -ceq '800700E2'){'AttachmentQuarantined'}else{'AttachmentBlockedByAntivirus'}
    [pscustomobject][ordered]@{EntryId=$EntryId;AttachmentName=$AttachmentName;AttachmentIndex=$Index;HResult=$hex;Reason=$reason;Defender=$d;MoveAttempted=$false}
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
