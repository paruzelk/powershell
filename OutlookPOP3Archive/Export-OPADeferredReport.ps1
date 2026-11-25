#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourcePst,
      [Parameter(Mandatory=$true)][string]$ProfileName,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath($SourcePst)
$dir=Join-Path ([IO.Path]::GetDirectoryName($source)) 'OutlookPOP3Archive-Transactions'
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH6Antivirus.ps1')
$ledgers=@(Get-ChildItem -LiteralPath $dir -Filter 'ARCH6-deferred-*.jsonl' -File)+@(Get-ChildItem -LiteralPath $dir -Filter 'ARCH6-threat-*.jsonl' -File)
$rows=@(foreach($f in $ledgers){
    if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Redirected deferred ledger.'}
    $d=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if($d.Schema -cnotin @('2.6.5-ARCH6f3a.Deferred.1','2.6.5-ARCH6f3c2.HistoricalThreat.1')){throw 'Unexpected deferred schema.'}
    if($d.SourcePst -ine $source -or $d.Profile -ine $ProfileName){continue}
    foreach($r in @($d.Rows)){
        $e=ConvertFrom-OPAARCH6AntivirusMessage -Message $r.Message -ExpectedEntryId $r.EntryId
        $local=ConvertFrom-OPAARCH6LocalExportMessage -Message $r.Message -ExpectedEntryId $r.EntryId
        $detail=''
        if($null -ne $local){$e=$local;$detail=$local.ErrorDetail}
        [pscustomobject]@{TransactionId=$d.TransactionId;Folder=$r.SourceFolderPath;Date=$r.ArchiveDate;Subject=$r.Subject;Sender=$r.Sender;Size=$r.Size;Reason=$r.Reason;EntryId=$r.EntryId;AttachmentName=$e.AttachmentName;AttachmentIndex=$e.AttachmentIndex;HResult=$e.HResult;ObservedHResult=$e.ObservedHResult;ThreatName=$e.Defender.ThreatName;ThreatId=$e.Defender.ThreatId;DetectionId=$e.Defender.DetectionId;DetectionTime=$e.Defender.DetectionTime;ErrorDetail=$detail;Message=$r.Message}
    }
})
$out=[IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($out)
$stamp=(Get-Date).ToString('yyyyMMdd-HHmmss-fff')
$csv=Join-Path $out ('DeferredItems-'+$stamp+'.csv')
$html=Join-Path $out ('DeferredItems-'+$stamp+'.html')
# CSV formula injection protection for user-controlled mail text.
$safeRows=@(foreach($r in $rows){
    $copy=[ordered]@{}
    foreach($prop in $r.PSObject.Properties){
        $value=[string]$prop.Value
        if($value -match '^[\s]*[=+\-@]'){$value="'"+$value}
        $copy[$prop.Name]=$value
    }
    [pscustomobject]$copy
})
$safeRows | Export-Csv -LiteralPath $csv -Encoding UTF8 -NoTypeInformation -NoClobber
$rows | ConvertTo-Html -Title 'OutlookPOP3Archive deferred items (historical, not live verification)' | Out-File -LiteralPath $html -Encoding UTF8 -NoClobber
[pscustomobject]@{DeferredRecords=$rows.Count;Csv=$csv;Html=$html;LiveVerification=$false}
