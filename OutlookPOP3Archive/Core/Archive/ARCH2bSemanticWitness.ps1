#requires -Version 5.1
# ARCH2b: general semantic witness based on the proven BW4j by-value
# attachment SaveAsFile->SHA256 approach. DEV Archive/Resume/Auto remain closed.
function Get-OPA265ARCH2bTextSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant()
    } finally {$sha.Dispose()}
}
function Get-OPA265ARCH2bFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $stream=$null;$sha=$null
    try {
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha=[Security.Cryptography.SHA256]::Create()
        return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant()
    }
    finally {
        if($null -ne $sha){$sha.Dispose()}
        if($null -ne $stream){$stream.Dispose()}
    }
}
function Get-OPA265ARCH2bAttachmentWitnesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [ValidateRange(1024,1073741824)][int64]$MaxAttachmentBytes=268435456,
        [ValidateRange(1,256)][int]$MaxAttachmentCount=128,
        [string]$TemporaryDirectory=[IO.Path]::GetTempPath()
    )
    $root=[IO.Path]::GetFullPath($TemporaryDirectory)
    if(-not [IO.Directory]::Exists($root) -or
       (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2b attachment temp root missing or reparse point; no Move authorized.'
    }
    $collection=$Mail.Attachments
    $count=[int]$collection.Count
    if($count -lt 0 -or $count -gt $MaxAttachmentCount){
        throw 'ARCH2b attachment count exceeds bounded witness limit; no Move authorized.'
    }
    $result=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le $count;$i++){
        $attachment=$null;$tempPath=$null
        try{
            $attachment=$collection.Item($i)
            if($null -eq $attachment){throw 'ARCH2b attachment collection returned null.'}
            $type=[int]$attachment.Type
            $reportedSize=[int64]$attachment.Size
            if($type -ne 1 -or $reportedSize -lt 0 -or $reportedSize -gt $MaxAttachmentBytes){
                throw ('ARCH2b unsupported attachment type/size at index '+$i+
                    '; embedded/OLE attachments not yet certified.')
            }
            $filename=[string]$attachment.FileName
            if($filename.Length -gt 1024){throw 'ARCH2b attachment name exceeds bound.'}
            # No original attachment filename in temp path or journal.
            $tempPath=Join-Path $root ('OPA-ARCH2b-'+[guid]::NewGuid().ToString('N')+'.bin')
            if([IO.File]::Exists($tempPath)){throw 'ARCH2b temp collision; stop.'}
            # SaveAsFile writes only an ephemeral attachment COPY, not a PST.
            # A process crash can leave sensitive temp data (documented risk).
            $attachment.SaveAsFile($tempPath)
            if(-not [IO.File]::Exists($tempPath)){throw 'ARCH2b SaveAsFile did not create a file.'}
            $file=Get-Item -LiteralPath $tempPath -Force
            if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                [int64]$file.Length -gt $MaxAttachmentBytes){
                throw 'ARCH2b attachment output unsafe/oversized.'
            }
            $result.Add([pscustomobject][ordered]@{
                Index=[int]$i
                Type=$type
                NameUtf8Sha256=(Get-OPA265ARCH2bTextSha256 -Text $filename)
                PayloadByteCount=[int64]$file.Length
                PayloadSha256=(Get-OPA265ARCH2bFileSha256 -Path $tempPath)
            }) | Out-Null
        }
        finally {
            if($tempPath -and [IO.File]::Exists($tempPath)){
                try {[IO.File]::Delete($tempPath)}
                catch {throw 'ARCH2b temp attachment copy cleanup failed; stop.'}
            }
            if($null -ne $attachment -and
               (Get-Command -Name Release-OPAComObject -ErrorAction SilentlyContinue)){
                Release-OPAComObject -Object $attachment
            }
        }
    }
    return $result.ToArray()
}
function Get-OPA265ARCH2bMailSemanticWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [int64]$MaxAttachmentBytes=268435456,
        [int]$MaxAttachmentCount=128,
        [string]$TemporaryDirectory=[IO.Path]::GetTempPath()
    )
    if([int]$Mail.Class -ne 43){throw 'ARCH2b only Outlook MailItem class 43 supported.'}
    # The already-saved item is the source baseline, never a pre-Save template.
    $subject=[string]$Mail.Subject
    $sender=[string]$Mail.SenderEmailAddress
    $to=[string]$Mail.To;$cc=[string]$Mail.CC;$bcc=[string]$Mail.BCC
    $body=[string]$Mail.Body;$html=[string]$Mail.HTMLBody
    $messageId=[string](Get-OPAInternetMessageId -Item $Mail)
    $received=[datetime]$Mail.ReceivedTime
    $sent=[datetime]$Mail.SentOn
    $unread=[bool]$Mail.UnRead
    $importance=[int]$Mail.Importance
    $sensitivity=[int]$Mail.Sensitivity
    $categories=[string]$Mail.Categories
    $recipients=$Mail.Recipients
    $recCount=[int]$recipients.Count
    if($recCount -lt 0 -or $recCount -gt 2048){throw 'ARCH2b recipient count exceeds witness bound.'}
    $recParts=New-Object 'System.Collections.Generic.List[string]'
    for($i=1;$i -le $recCount;$i++){
        $r=$null
        try{
            $r=$recipients.Item($i)
            if($null -eq $r){throw 'ARCH2b missing recipient record.'}
            $recParts.Add(('{0}|{1}|{2}' -f [int]$r.Type,
                (Get-OPA265ARCH2bTextSha256 -Text ([string]$r.Name)),
                (Get-OPA265ARCH2bTextSha256 -Text ([string]$r.Address)))) | Out-Null
        }
        finally {
            if($null -ne $r -and
               (Get-Command -Name Release-OPAComObject -ErrorAction SilentlyContinue)){
                Release-OPAComObject -Object $r
            }
        }
    }
    $attachmentArgs=@{
        Mail=$Mail
        MaxAttachmentBytes=$MaxAttachmentBytes
        MaxAttachmentCount=$MaxAttachmentCount
        TemporaryDirectory=$TemporaryDirectory
    }
    $att=@(Get-OPA265ARCH2bAttachmentWitnesses @attachmentArgs)
    $witness=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
        ItemClass=43
        InternetMessageIdSha256=(Get-OPA265ARCH2bTextSha256 -Text $messageId)
        SubjectSha256=(Get-OPA265ARCH2bTextSha256 -Text $subject)
        SenderSha256=(Get-OPA265ARCH2bTextSha256 -Text $sender)
        ToSha256=(Get-OPA265ARCH2bTextSha256 -Text $to)
        CcSha256=(Get-OPA265ARCH2bTextSha256 -Text $cc)
        BccSha256=(Get-OPA265ARCH2bTextSha256 -Text $bcc)
        RecipientCount=$recCount
        OrderedRecipientDigestSha256=(Get-OPA265ARCH2bTextSha256 -Text ($recParts.ToArray() -join [char]10))
        BodySha256=(Get-OPA265ARCH2bTextSha256 -Text $body)
        BodyUtf16Length=[int]$body.Length
        HtmlBodySha256=(Get-OPA265ARCH2bTextSha256 -Text $html)
        HtmlBodyUtf16Length=[int]$html.Length
        ReceivedUtcTicks=[int64]$received.ToUniversalTime().Ticks
        SentUtcTicks=[int64]$sent.ToUniversalTime().Ticks
        UnRead=$unread
        Importance=$importance
        Sensitivity=$sensitivity
        CategoriesSha256=(Get-OPA265ARCH2bTextSha256 -Text $categories)
        AttachmentCount=$att.Count
        Attachments=@($att)
        MailItemSizeDiagnosticBytes=[int64]$Mail.Size
    }
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $witness)){
        throw 'ARCH2b incomplete source semantic witness; no Move authorized.'
    }
    return $witness
}
function Test-OPA265ARCH2bWitnessSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness)
    if($null -eq $Witness -or
       [string]$Witness.Schema -cne '2.6.5-ARCH2b.MailSemanticWitness.1' -or
       [int]$Witness.ItemClass -ne 43){return $false}
    foreach($name in @('InternetMessageIdSha256','SubjectSha256','SenderSha256',
        'ToSha256','CcSha256','BccSha256','OrderedRecipientDigestSha256',
        'BodySha256','HtmlBodySha256','CategoriesSha256')){
        if([string]$Witness.$name -cnotmatch '^[a-f0-9]{64}$'){return $false}
    }
    foreach($name in @('BodyUtf16Length','HtmlBodyUtf16Length','RecipientCount',
        'AttachmentCount','ReceivedUtcTicks','SentUtcTicks','MailItemSizeDiagnosticBytes')){
        if($null -eq $Witness.$name){return $false}
        try{if([int64]$Witness.$name -lt 0){return $false}}catch{return $false}
    }
    if($Witness.UnRead -isnot [bool]){return $false}
    $att=@($Witness.Attachments)
    if($att.Count -ne [int]$Witness.AttachmentCount){return $false}
    for($i=0;$i -lt $att.Count;$i++){
        $a=$att[$i]
        if($null -eq $a -or [int]$a.Index -ne ($i+1) -or
           [int]$a.Type -ne 1 -or
           [string]$a.NameUtf8Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$a.PayloadSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           $null -eq $a.PayloadByteCount){return $false}
        try{if([int64]$a.PayloadByteCount -lt 0){return $false}}catch{return $false}
    }
    return $true
}
function Compare-OPA265ARCH2bMailSemanticWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Source,
          [Parameter(Mandatory=$true)][object]$Destination)
    $issues=New-Object 'System.Collections.Generic.List[string]'
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $Source) -or
       -not (Test-OPA265ARCH2bWitnessSchema -Witness $Destination)){
        $issues.Add('SourceOrDestinationWitnessIncomplete') | Out-Null
    } else {
        foreach($name in @('InternetMessageIdSha256','SubjectSha256','SenderSha256',
            'ToSha256','CcSha256','BccSha256','RecipientCount','OrderedRecipientDigestSha256',
            'BodySha256','BodyUtf16Length','HtmlBodySha256','HtmlBodyUtf16Length',
            'ReceivedUtcTicks','SentUtcTicks','UnRead','Importance','Sensitivity',
            'CategoriesSha256','AttachmentCount')){
            if([string]$Source.$name -cne [string]$Destination.$name){
                $issues.Add(('Different'+$name)) | Out-Null
            }
        }
        if([int]$Source.AttachmentCount -eq [int]$Destination.AttachmentCount){
            $left=@($Source.Attachments);$right=@($Destination.Attachments)
            for($i=0;$i -lt $left.Count;$i++){
                foreach($name in @('Index','Type','NameUtf8Sha256','PayloadByteCount','PayloadSha256')){
                    if([string]$left[$i].$name -cne [string]$right[$i].$name){
                        $issues.Add(('Attachment'+($i+1)+'Different'+$name)) | Out-Null
                    }
                }
            }
        }
    }
    $ok=$issues.Count -eq 0
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2b.SemanticComparison.1'
        Status=if($ok){'CapturedUserContentMatchedDiagnosticProviderSizeOnly'}else{'CriticalMailContentOrAttachmentDifferenceBlocked'}
        CriticalContentMatches=$ok
        IssueCodes=@($issues.ToArray())
        SourceSizeDiagnosticBytes=[int64]$Source.MailItemSizeDiagnosticBytes
        DestinationSizeDiagnosticBytes=[int64]$Destination.MailItemSizeDiagnosticBytes
        ProviderSizeDifferenceIsNotAutomaticCorruption=$true
        OriginalMoveMayBeRetried=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
