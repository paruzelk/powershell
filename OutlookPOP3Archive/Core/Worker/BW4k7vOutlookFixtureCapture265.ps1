#requires -Version 5.1
# BW4k7v real Outlook helper, only exact new test PST; no Move/Delete/Send.
. (Join-Path $PSScriptRoot 'BW4k7vDisposablePstManifest265.ps1')
function Get-OPA265BW4k7vOutlookProcess {
    [CmdletBinding()]
    param()
    $p=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($p.Count -ne 1){throw 'BW4k7v requires exactly one Outlook process.'}
    return [pscustomobject]@{Pid=[int]$p[0].Id;StartTicks=[long]$p[0].StartTime.ToUniversalTime().Ticks}
}
function Get-OPA265BW4k7vExactMountedStore {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$Layout)
    $found=New-Object 'System.Collections.Generic.List[object]'
    $count=[int]$Namespace.Stores.Count
    if($count -lt 1 -or $count -gt 128){throw 'BW4k7v unsafe store count.'}
    for($i=1;$i -le $count;$i++){
        $store=$Namespace.Stores.Item($i)
        $path=''
        try{$path=[string]$store.FilePath}catch{}
        if($path -and [string]::Equals([IO.Path]::GetFullPath($path),
           [string]$Layout.SourcePst,[StringComparison]::OrdinalIgnoreCase)){
            $found.Add($store)
        }
    }
    if($found.Count -ne 1){throw 'BW4k7v exact new PST must be mounted once.'}
    return $found[0]
}
function Get-OPA265BW4k7vExactFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$FixtureRoot,
          [Parameter(Mandatory=$true)][object]$Case,
          [switch]$CreateIfMissing)
    $path=[string]$Case.SourceFolderPath
    if($path -cnotin @('\Inbox','\Sent Items','\Projects\Alpha\2022','\Projects\Beta')){
        throw 'BW4k7v disallowed synthetic folder path.'
    }
    $current=$FixtureRoot
    $names=@($path.TrimStart([char]'\').Split([char]'\'))
    foreach($name in $names){
        if($name -cnotmatch '^[A-Za-z0-9 ]{1,32}$'){throw 'BW4k7v unsafe folder name.'}
        $next=$null
        for($i=1;$i -le [int]$current.Folders.Count;$i++){
            $child=$current.Folders.Item($i)
            if([string]$child.Name -ceq $name){
                if($null -ne $next){throw 'BW4k7v ambiguous matching folder.'}
                $next=$child
            }
        }
        if($null -eq $next){
            if(-not $CreateIfMissing){throw 'BW4k7v original folder missing.'}
            $next=$current.Folders.Add($name)
        }
        $current=$next
    }
    return $current
}
function New-OPA265BW4k7vSavedMail {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Folder,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][object]$Layout)
    # Folder.Items.Add ensures the new item is born inside the isolated PST.
    # Outlook.Application.CreateItem would instead target the default user mailbox.
    $mail=$Folder.Items.Add('IPM.Note')
    $mail.Subject=Get-OPA265BW4k7vExpectedSubject -Item $Case
    $mail.Body=[string]$Case.Body
    if([string]$Case.HtmlBody){$mail.HTMLBody=[string]$Case.HtmlBody}
    $mail.To=(@($Case.RecipientsTo) -join '; ')
    $mail.CC=(@($Case.RecipientsCc) -join '; ')
    $mail.BCC=(@($Case.RecipientsBcc) -join '; ')
    $mail.UnRead=$false
    $mail.Categories='BW4k7vDisposable'
    $tag=$mail.UserProperties.Add('OPA265BW4k7vArchiveYear',1,$true)
    $tag.Value=[string]$Case.Year
    foreach($att in @($Case.Attachments)){
        $temp=Join-Path ([string]$Layout.AttachmentScratchDirectory) ('attachment-'+[guid]::NewGuid().ToString('N')+'.bin')
        try{
            $bytes=[Convert]::FromBase64String([string]$att.BytesBase64)
            if($bytes.Length -ne [int]$att.ByteCount -or $bytes.Length -gt 262144){
                throw 'BW4k7v synthetic attachment payload invalid.'
            }
            [IO.File]::WriteAllBytes($temp,$bytes)
            [void]$mail.Attachments.Add($temp,1,1,[string]$att.Name)
        }finally{
            if([IO.File]::Exists($temp)){
                Remove-Item -LiteralPath $temp -Force -ErrorAction Stop
            }
        }
    }
    $mail.Save()
    $id=[string]$mail.EntryID
    if($id -cnotmatch '^[a-fA-F0-9]{40,512}$'){
        throw 'BW4k7v newly saved MailItem EntryID unavailable.'
    }
    return $id
}
function Get-OPA265BW4k7vMailWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][object]$Folder,
          [Parameter(Mandatory=$true)][object]$Store,
          [Parameter(Mandatory=$true)][object]$Layout)
    if([int]$Mail.Class -ne 43 -or [string]$Mail.MessageClass -cne 'IPM.Note' -or
       [string]$Mail.EntryID -cnotmatch '^[a-fA-F0-9]{40,512}$' -or
       [string]$Mail.Parent.EntryID -cne [string]$Folder.EntryID -or
       [string]$Folder.StoreID -cne [string]$Store.StoreID -or
       [string]$Mail.Subject -cne (Get-OPA265BW4k7vExpectedSubject -Item $Case)){
        throw 'BW4k7v wrong item Class/MessageClass/EntryID/parent/store or subject.'
    }
    $year=$Mail.UserProperties.Find('OPA265BW4k7vArchiveYear')
    if($null -eq $year -or [string]$year.Value -cne [string]$Case.Year){
        throw 'BW4k7v synthetic year tag missing.'
    }
    $expectedAtt=@($Case.Attachments)
    if([int]$Mail.Attachments.Count -ne $expectedAtt.Count){
        throw 'BW4k7v attachment count mismatch.'
    }
    $witnessAtt=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le [int]$Mail.Attachments.Count;$i++){
        $a=$Mail.Attachments.Item($i);$spec=$expectedAtt[$i-1]
        if([int]$a.Type -ne 1 -or [string]$a.FileName -cne [string]$spec.Name){
            throw 'BW4k7v only exact synthetic by-value attachment allowed.'
        }
        $temp=Join-Path ([string]$Layout.AttachmentScratchDirectory) ('readback-'+[guid]::NewGuid().ToString('N')+'.bin')
        try{
            if([IO.File]::Exists($temp)){throw 'BW4k7v temporary filename collision.'}
            $a.SaveAsFile($temp)
            $file=Get-Item -LiteralPath $temp -ErrorAction Stop
            if($file.Length -ne [long]$spec.ByteCount -or $file.Length -gt 262144){
                throw 'BW4k7v decoded attachment length differs from original synthetic.'
            }
            $digest=(Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
            if($digest -cne [string]$spec.PayloadSha256){
                throw 'BW4k7v attachment raw SHA256 changed.'
            }
            $witnessAtt.Add([pscustomobject][ordered]@{
                FileName=[string]$a.FileName
                Bytes=[long]$file.Length
                Sha256=$digest
            })
        }finally{
            if([IO.File]::Exists($temp)){
                Remove-Item -LiteralPath $temp -Force -ErrorAction Stop
            }
        }
    }
    $recipientParts=New-Object 'System.Collections.Generic.List[string]'
    $rs=$Mail.Recipients
    if([int]$rs.Count -lt 1 -or [int]$rs.Count -gt 16){
        throw 'BW4k7v recipient bounds or count invalid.'
    }
    for($i=1;$i -le [int]$rs.Count;$i++){
        $r=$rs.Item($i)
        $recipientParts.Add(('{0}|{1}|{2}|{3}' -f $i,[int]$r.Type,
            [string]$r.Name,[string]$r.Address))
    }
    $body=[string]$Mail.Body;$html=[string]$Mail.HTMLBody
    if($body.Length -gt 131072 -or $html.Length -gt 524288){
        throw 'BW4k7v body or HTML too large for bounded witness.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v.RealSyntheticPstPreMoveWitness.1'
        CaseId=[string]$Case.CaseId
        Name=[string]$Case.Name
        Role=[string]$Case.Role
        FolderPath=[string]$Case.SourceFolderPath
        SyntheticArchiveYear=[int]$Case.Year
        EntryId=[string]$Mail.EntryID;FolderEntryId=[string]$Folder.EntryID
        StoreId=[string]$Store.StoreID
        Subject=[string]$Mail.Subject
        Class=43;MessageClass='IPM.Note'
        YearTag=[string]$year.Value
        BodySha256=(Get-OPA265BW4k7vSha -Text $body)
        HtmlSha256=(Get-OPA265BW4k7vSha -Text $html)
        ToSha256=(Get-OPA265BW4k7vSha -Text ([string]$Mail.To))
        CcSha256=(Get-OPA265BW4k7vSha -Text ([string]$Mail.CC))
        BccSha256=(Get-OPA265BW4k7vSha -Text ([string]$Mail.BCC))
        RecipientsSha256=(Get-OPA265BW4k7vSha -Text ($recipientParts -join [char]10))
        CategoriesSha256=(Get-OPA265BW4k7vSha -Text ([string]$Mail.Categories))
        UnRead=[bool]$Mail.UnRead
        AttachmentWitnesses=@($witnessAtt.ToArray())
        CalendarYearFromActualMapiReceivedOrSentNotProven=$true
        GenuineSentMessageNotProven=$true
        OutlookMoveOrSendExecuted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
