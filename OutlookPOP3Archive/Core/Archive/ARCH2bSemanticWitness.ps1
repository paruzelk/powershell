#requires -Version 5.1
# ARCH2b: general semantic witness based on the proven BW4j by-value
# attachment SaveAsFile->SHA256 approach. DEV Archive/Resume/Auto remain closed.
# ARCH2c2 private NTFS ACL and exclusive lease are mandatory for each witness.
. (Join-Path $PSScriptRoot 'ARCH2c2TempSafety.ps1')
. (Join-Path $PSScriptRoot 'ARCH6Antivirus.ps1')
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
# ARCH5 conservative complex-attachment export: never open, execute or activate
# an embedded object. Accept only a complete compound-storage export with two
# identical byte-for-byte reads. This is experimental, not OLE certification.
function Get-OPAARCH5ComplexExportProof {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Attachment,
          [Parameter(Mandatory=$true)][string]$Workspace,
          [Parameter(Mandatory=$true)][int]$Type,
          [Parameter(Mandatory=$true)][int64]$MaxBytes,
          [Parameter(Mandatory=$true)][int]$Index)
    $ext=if($Type -eq 5){'.msg'}else{'.bin'}
    $paths=@()
    try{
        $proofs=@()
        for($attempt=0;$attempt -lt 2;$attempt++){
            $path=Join-Path $Workspace ('OPA-ARCH5-'+[guid]::NewGuid().ToString('N')+$ext)
            if([IO.File]::Exists($path)){throw 'ARCH5 temporary export collision.'}
            $paths+= $path
            $Attachment.SaveAsFile($path)
            if(-not [IO.File]::Exists($path)){throw 'ARCH5 complex export missing.'}
            $file=Get-Item -LiteralPath $path -Force
            if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
               $file.Length -lt 512 -or $file.Length -gt $MaxBytes){
                throw 'ARCH5 complex export unsafe or outside bounds.'
            }
            $stream=[IO.File]::OpenRead($path)
            try{
                $header=New-Object byte[] 8
                if($stream.Read($header,0,8) -ne 8 -or
                   [BitConverter]::ToString($header) -cne 'D0-CF-11-E0-A1-B1-1A-E1'){
                    throw 'ARCH5 complex export is not compound storage.'
                }
            }finally{$stream.Dispose()}
            $proofs+= [pscustomobject]@{Length=[int64]$file.Length;Sha=(Get-OPA265ARCH2bFileSha256 -Path $path)}
        }
        if($proofs[0].Length -ne $proofs[1].Length -or $proofs[0].Sha -cne $proofs[1].Sha){
            throw 'ARCH5 complex export bytes are not stable between two reads.'
        }
        return $proofs[0]
    }catch{
        throw ('ARCH5 AttachmentExportUnverified: index='+$Index+' type='+$Type+'; '+$_.Exception.Message)
    }finally{
        foreach($path in $paths){
            if([IO.File]::Exists($path)){[IO.File]::Delete($path)}
        }
    }
}

# Version 3 uses a flat semantic digest for each embedded message. No MSG
# container hash, provider Size, executable activation or Inspector is used.
function Get-OPAARCH5aEmbeddedDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness)
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $Witness) -or
       [string]$Witness.Schema -cne '2.6.5-ARCH5a.MailSemanticWitness.3'){
        throw 'ARCH5a embedded witness is incomplete.'
    }
    $canonical=[ordered]@{}
    foreach($name in @('Schema','ItemClass','InternetMessageIdSha256','SubjectSha256','SenderSha256',
        'ToSha256','CcSha256','BccSha256','RecipientCount','OrderedRecipientDigestSha256',
        'BodySha256','BodyUtf16Length','HtmlBodySha256','HtmlBodyUtf16Length',
        'ReceivedUtcTicks','SentUtcTicks','UnRead','Importance','Sensitivity','CategoriesSha256','AttachmentCount')){
        $canonical[$name]=[string]$Witness.$name
    }
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($a in @($Witness.Attachments)){
        $row=[ordered]@{}
        foreach($name in @('Index','Type','NameUtf8Sha256','PayloadByteCount','PayloadSha256')){
            $row[$name]=[string]$a.$name
        }
        if([int]$a.Type -eq 5){$row['PayloadKind']=[string]$a.PayloadKind}
        [void]$rows.Add($row)
    }
    $canonical['Attachments']=$rows.ToArray()
    return (Get-OPA265ARCH2bTextSha256 -Text (ConvertTo-Json -InputObject $canonical -Depth 8 -Compress))
}

# Only the exact randomly named export created by this invocation may be
# deleted here. Never scan or recursively delete unknown workspace entries.
function Remove-OPAARCH5bPrivateMsgExport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$Workspace,
          [ValidateRange(1,40)][int]$Attempts=20,
          [ValidateRange(0,1000)][int]$DelayMilliseconds=100)
    $full=[IO.Path]::GetFullPath($Path)
    $root=[IO.Path]::GetFullPath($Workspace)
    if([IO.Path]::GetDirectoryName($full) -ine $root -or
       [IO.Path]::GetFileName($full) -cnotmatch '^OPA-ARCH5a-[0-9a-f]{32}\.msg$'){
        throw 'ARCH5b private MSG cleanup path mismatch.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $root)
    for($i=1;$i -le $Attempts;$i++){
        if(-not [IO.File]::Exists($full)){return}
        if(([IO.File]::GetAttributes($full) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'ARCH5b private MSG cleanup refused reparse point.'
        }
        try{
            [IO.File]::Delete($full)
            if(-not [IO.File]::Exists($full)){return}
        }catch [IO.IOException]{
            if($i -eq $Attempts){throw}
        }
        if($i -lt $Attempts -and $DelayMilliseconds -gt 0){Start-Sleep -Milliseconds $DelayMilliseconds}
    }
    throw 'ARCH5b private MSG remains after bounded cleanup.'
}

function Get-OPAARCH5aEmbeddedProof {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Attachment,
          [Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][string]$Workspace,
          [Parameter(Mandatory=$true)][string]$TemporaryDirectory,
          [Parameter(Mandatory=$true)][int64]$MaxBytes,
          [Parameter(Mandatory=$true)][int]$MaxAttachmentCount,
          [Parameter(Mandatory=$true)][int]$Index,
          [Parameter(Mandatory=$true)][int]$Depth,
          [Parameter(Mandatory=$true)][hashtable]$Budget)
    try{
        if($Depth -ge 4){throw 'Embedded message depth limit (4) exceeded.'}
        $session=$Mail.Application.Session
        if($null -eq $session){throw 'Outlook namespace unavailable for embedded MSG.'}
        $digests=@()
        for($attempt=0;$attempt -lt 2;$attempt++){
            if([int]$Budget.Remaining -le 0){throw 'Embedded message read budget (128) exceeded.'}
            $Budget.Remaining=[int]$Budget.Remaining-1
            $path=Join-Path $Workspace ('OPA-ARCH5a-'+[guid]::NewGuid().ToString('N')+'.msg')
            $child=$null;$readError=$null;$closeError=$null
            if([IO.File]::Exists($path)){throw 'Embedded export path collision.'}
            try{
                $Attachment.SaveAsFile($path)
                if(-not [IO.File]::Exists($path)){throw 'Embedded MSG export missing.'}
                $file=Get-Item -LiteralPath $path -Force
                if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                   $file.Length -lt 512 -or $file.Length -gt $MaxBytes){
                    throw 'Embedded MSG export unsafe or outside bounds.'
                }
                $stream=[IO.File]::OpenRead($path)
                try{
                    $head=New-Object byte[] 8
                    if($stream.Read($head,0,8) -ne 8 -or [BitConverter]::ToString($head) -cne 'D0-CF-11-E0-A1-B1-1A-E1'){
                        throw 'Embedded MSG is not compound storage.'
                    }
                }finally{$stream.Dispose()}
                # Open the private COPY using Outlook's documented MSG reader.
                # Do not Display, Save, Send, Move or activate attachments.
                $child=$session.OpenSharedItem($path)
                if($null -eq $child -or [int]$child.Class -ne 43){
                    throw 'Embedded item is not a readable MailItem.'
                }
                $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $child -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments -MaxAttachmentBytes $MaxBytes -MaxAttachmentCount $MaxAttachmentCount -TemporaryDirectory $TemporaryDirectory -EmbeddedDepth ($Depth+1) -EmbeddedBudget $Budget
                $digests+= Get-OPAARCH5aEmbeddedDigest -Witness $w
            }catch{
                $readError=$_
            }finally{
                try{
                    if($null -ne $child -and [int]$child.Class -eq 43){[void]$child.Close(1)}
                }catch{$closeError=$_}
                finally{
                    try{
                        # OpenSharedItem on our unique private path returns a
                        # transient child, not the live source or shared session.
                        if($null -ne $child -and [Runtime.InteropServices.Marshal]::IsComObject($child)){
                            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($child)
                        }
                    }catch{if($null -eq $closeError){$closeError=$_}}
                    finally{$child=$null}
                }
                try{
                    Remove-OPAARCH5bPrivateMsgExport -Path $path -Workspace $Workspace
                }catch{
                    $detail=if($null -ne $readError){'Read: '+$readError.Exception.Message+'; '}else{''}
                    if($null -ne $closeError){$detail+='Close: '+$closeError.Exception.Message+'; '}
                    throw ('ARCH5b AttachmentCleanupFailed: '+$detail+'Cleanup: '+$_.Exception.Message)
                }
            }
            if($null -ne $readError){throw $readError}
            if($null -ne $closeError){throw $closeError}
        }
        if($digests.Count -ne 2 -or $digests[0] -cne $digests[1]){
            throw 'Embedded MSG semantic content differs between independent reads.'
        }
        return [pscustomobject]@{Sha=[string]$digests[0]}
    }catch{
        if($_.Exception.Message -like 'ARCH5b AttachmentCleanupFailed:*'){throw}
        throw ('ARCH5 AttachmentExportUnverified: index='+$Index+' type=5; ARCH5a '+$_.Exception.Message)
    }
}

function Get-OPA265ARCH2bAttachmentWitnesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [ValidateRange(1024,1073741824)][int64]$MaxAttachmentBytes=268435456,
        [ValidateRange(1,256)][int]$MaxAttachmentCount=128,
        [switch]$AllowComplexAttachments,
        [switch]$ExtendedAttachmentWitness,
        [switch]$RecursiveEmbeddedWitness,
        [int]$EmbeddedDepth=0,
        [hashtable]$EmbeddedBudget,
        [string]$TemporaryDirectory=[IO.Path]::GetTempPath()
    )
    # Private ACL must be applied atomically at creation. The exclusive lease
    # stays open throughout SaveAsFile / SHA256 / per-file cleanup.
    $workspaceLease=$null;$collection=$null;$captureError=$null
    try {
        $workspaceLease=New-OPA265ARCH2c2PrivateWorkspace -TemporaryDirectory $TemporaryDirectory
        $workspace=[string]$workspaceLease.WorkspacePath
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
            if(-not $ExtendedAttachmentWitness){
                if($type -ne 1 -or $reportedSize -lt 0 -or $reportedSize -gt $MaxAttachmentBytes){
                    throw ('ARCH2b unsupported attachment type/size at index '+$i+
                        '; embedded/OLE attachments not yet certified.')
                }
            }else{
                if($reportedSize -lt 0 -or $reportedSize -gt $MaxAttachmentBytes){
                    throw ('ARCH5 AttachmentSizeUnsupported: index='+$i+' type='+$type+' bytes='+$reportedSize+' limit='+$MaxAttachmentBytes)
                }
                if($type -ne 1 -and (-not $AllowComplexAttachments -or $type -notin @(5,6))){
                    throw ('ARCH5 AttachmentTypeUnsupported: index='+$i+' type='+$type+' bytes='+$reportedSize)
                }
            }
            $filename=[string]$attachment.FileName
            if($filename.Length -gt 1024){throw 'ARCH2b attachment name exceeds bound.'}
            if($RecursiveEmbeddedWitness -and $type -eq 5){
                $proof=Get-OPAARCH5aEmbeddedProof -Attachment $attachment -Mail $Mail -Workspace $workspace -TemporaryDirectory $TemporaryDirectory -MaxBytes $MaxAttachmentBytes -MaxAttachmentCount $MaxAttachmentCount -Index $i -Depth $EmbeddedDepth -Budget $EmbeddedBudget
                [void]$result.Add([pscustomobject][ordered]@{
                    Index=[int]$i;Type=$type
                    NameUtf8Sha256=(Get-OPA265ARCH2bTextSha256 -Text $filename)
                    PayloadByteCount=[int64]0
                    PayloadSha256=[string]$proof.Sha
                    PayloadKind='EmbeddedMailSemanticSha256'
                })
                continue
            }
            if($ExtendedAttachmentWitness -and $type -in @(5,6)){
                $proof=Get-OPAARCH5ComplexExportProof -Attachment $attachment -Workspace $workspace -Type $type -MaxBytes $MaxAttachmentBytes -Index $i
                [void]$result.Add([pscustomobject][ordered]@{
                    Index=[int]$i;Type=$type
                    NameUtf8Sha256=(Get-OPA265ARCH2bTextSha256 -Text $filename)
                    PayloadByteCount=[int64]$proof.Length
                    PayloadSha256=[string]$proof.Sha
                })
                continue
            }
            # No original attachment filename in temp path or journal.
            $tempPath=Join-Path $workspace ('OPA-ARCH2b-'+[guid]::NewGuid().ToString('N')+'.bin')
            if([IO.File]::Exists($tempPath)){throw 'ARCH2b temp collision; stop.'}
            # SaveAsFile writes only an ephemeral attachment COPY, not a PST.
            # A process crash can leave sensitive temp data (documented risk).
            $exportStarted=Get-Date
            try {
                $attachment.SaveAsFile($tempPath)
                if(-not [IO.File]::Exists($tempPath)){throw 'ARCH2b SaveAsFile did not create a file.'}
            }catch{
                if($ExtendedAttachmentWitness -and $type -eq 1){
                    $e=New-OPAARCH6AntivirusEvidence -EntryId ([string]$Mail.EntryID) -AttachmentName $filename -Index $i -From $exportStarted.AddSeconds(-1) -To (Get-Date) -TemporaryPath $tempPath -Exception $_.Exception
                    if($null -ne $e){throw (ConvertTo-OPAARCH6AntivirusMessage -Evidence $e)}
                }
                throw
            }
            $file=Get-Item -LiteralPath $tempPath -Force
            if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                [int64]$file.Length -gt $MaxAttachmentBytes){
                if($ExtendedAttachmentWitness){
                    throw ('ARCH5 AttachmentExportUnverified: index='+$i+' type='+$type+' bytes='+$file.Length+' limit='+$MaxAttachmentBytes)
                }
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
            if($null -ne $attachment -and [Runtime.InteropServices.Marshal]::IsComObject($attachment) -and
               (Get-Command -Name Release-OPAComObject -ErrorAction SilentlyContinue)){
                Release-OPAComObject -Object $attachment
            }
        }
    }
        return $result.ToArray()
    }catch{
        $captureError=$_
        throw
    }
    finally {
        try{
            if($null -ne $collection -and [Runtime.InteropServices.Marshal]::IsComObject($collection)){
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($collection)
            }
        }finally{
            # Unknown residue is never recursively deleted. Keep the initial
            # failure visible instead of replacing it with the cleanup error.
            if($null -ne $workspaceLease){
                try{Close-OPA265ARCH2c2PrivateWorkspace -Workspace $workspaceLease}
                catch{
                    if($null -ne $captureError){
                        throw ('ARCH5b AttachmentCleanupFailed: capture='+$captureError.Exception.Message+'; workspace cleanup='+$_.Exception.Message)
                    }
                    throw ('ARCH5b AttachmentCleanupFailed: '+$_.Exception.Message)
                }
            }
        }
    }
}
function Get-OPA265ARCH2c1AttachmentWorkspaceInventory {
    [CmdletBinding()]
    param([string]$TemporaryDirectory=[IO.Path]::GetTempPath())
    $root=[IO.Path]::GetFullPath($TemporaryDirectory)
    if(-not [IO.Directory]::Exists($root) -or
       (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2c1 inventory temp root missing or reparse point.'
    }
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($path in [IO.Directory]::GetDirectories($root,'OPA-ARCH2c1-*',[IO.SearchOption]::TopDirectoryOnly)){
        $name=[IO.Path]::GetFileName($path)
        if($name -cnotmatch '^OPA-ARCH2c1-[0-9a-f]{32}$'){continue}
        if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'ARCH2c1 workspace inventory includes a reparse point; manual review required.'
        }
        $folder=Get-Item -LiteralPath $path -Force
        $rows.Add([pscustomobject][ordered]@{
            WorkspacePath=[string]$folder.FullName
            LastWriteTimeUtc=[datetime]$folder.LastWriteTimeUtc
            RequiresManualReview=$true
            LeaseState=(Get-OPA265ARCH2c2ObservedLeaseState -WorkspacePath $path)
            AutomaticallyDeleted=$false
        }) | Out-Null
    }
    return $rows.ToArray()
}
function Get-OPA265ARCH2bMailSemanticWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [int64]$MaxAttachmentBytes=268435456,
        [int]$MaxAttachmentCount=128,
        [switch]$ExtendedAttachmentWitness,
        [switch]$AllowComplexAttachments,
        [switch]$RecursiveEmbeddedWitness,
        [int]$EmbeddedDepth=0,
        [hashtable]$EmbeddedBudget,
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
    $recipients=$null
    try{
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
            if($null -ne $r -and [Runtime.InteropServices.Marshal]::IsComObject($r) -and
               (Get-Command -Name Release-OPAComObject -ErrorAction SilentlyContinue)){
                Release-OPAComObject -Object $r
            }
        }
    }
    }finally{
        if($null -ne $recipients -and [Runtime.InteropServices.Marshal]::IsComObject($recipients)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($recipients)
        }
        $recipients=$null
    }
    if($RecursiveEmbeddedWitness -and -not $ExtendedAttachmentWitness){throw 'ARCH5a requires extended witness policy.'}
    if($RecursiveEmbeddedWitness -and $null -eq $EmbeddedBudget){$EmbeddedBudget=@{Remaining=128}}
    if($ExtendedAttachmentWitness){$MaxAttachmentBytes=1073741824}
    $attachmentArgs=@{
        Mail=$Mail
        MaxAttachmentBytes=$MaxAttachmentBytes
        MaxAttachmentCount=$MaxAttachmentCount
        TemporaryDirectory=$TemporaryDirectory
    }
    if($ExtendedAttachmentWitness){
        $attachmentArgs.ExtendedAttachmentWitness=$true
        $attachmentArgs.AllowComplexAttachments=[bool]$AllowComplexAttachments
        if($RecursiveEmbeddedWitness){
            $attachmentArgs.RecursiveEmbeddedWitness=$true
            $attachmentArgs.EmbeddedDepth=$EmbeddedDepth
            $attachmentArgs.EmbeddedBudget=$EmbeddedBudget
        }
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
    if($ExtendedAttachmentWitness){
        $witness.Schema='2.6.5-ARCH5.MailSemanticWitness.2'
    }
    if($RecursiveEmbeddedWitness){$witness.Schema='2.6.5-ARCH5a.MailSemanticWitness.3'}
    if(-not (Test-OPA265ARCH2bWitnessSchema -Witness $witness)){
        throw 'ARCH2b incomplete source semantic witness; no Move authorized.'
    }
    return $witness
}
function Test-OPA265ARCH2bWitnessSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness)
    if($null -eq $Witness -or
       [string]$Witness.Schema -cnotin @('2.6.5-ARCH2b.MailSemanticWitness.1','2.6.5-ARCH5.MailSemanticWitness.2','2.6.5-ARCH5a.MailSemanticWitness.3') -or
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
    $recursive=[string]$Witness.Schema -ceq '2.6.5-ARCH5a.MailSemanticWitness.3'
    $extended=$recursive -or [string]$Witness.Schema -ceq '2.6.5-ARCH5.MailSemanticWitness.2'
    $att=@($Witness.Attachments)
    if($att.Count -ne [int]$Witness.AttachmentCount){return $false}
    for($i=0;$i -lt $att.Count;$i++){
        $a=$att[$i]
        if($null -eq $a -or [int]$a.Index -ne ($i+1) -or
           ((-not $extended -and [int]$a.Type -ne 1) -or
            ($extended -and [int]$a.Type -notin @(1,5,6))) -or
           [string]$a.NameUtf8Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$a.PayloadSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           $null -eq $a.PayloadByteCount){return $false}
        try{
            if([int64]$a.PayloadByteCount -lt 0){return $false}
            if($recursive -and [int]$a.Type -eq 5){
                if([int64]$a.PayloadByteCount -ne 0 -or [string]$a.PayloadKind -cne 'EmbeddedMailSemanticSha256'){return $false}
            }elseif($extended -and ([int64]$a.PayloadByteCount -gt 1073741824 -or
                ([int]$a.Type -in @(5,6) -and [int64]$a.PayloadByteCount -lt 512))){return $false}
        }catch{return $false}
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
        if([string]$Source.Schema -cne [string]$Destination.Schema){[void]$issues.Add('DifferentWitnessSchema')}
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
