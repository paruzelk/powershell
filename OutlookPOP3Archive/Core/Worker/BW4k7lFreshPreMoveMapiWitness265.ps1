#requires -Version 5.1
# BW4k7l: fresh, unique disposable mail PRE-MOVE witness only.
# Never invokes MailItem.Move/Save/Delete/Send or changes any Outlook PST.
function Assert-OPA265BW4k7lFixtureId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$FixtureId)
    if($FixtureId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
       $FixtureId -ceq '87e72fd0-9e77-4098-a403-cbe99870b9e7'){
        throw 'BW4k7l requires a NEW lowercase hyphenated GUID, never an old fixture.'
    }
    return $true
}
function Get-OPA265BW4k7lSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-OPA265BW4k7lStringSha {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
    Get-OPA265BW4k7lSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($Value))
}
function Get-OPA265BW4k7lStatusReadOnly {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$PropertyAccessor)
    try {
        $value=$PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E170003')
        if($value -isnot [int]){throw 'BW4k7l PR_MESSAGE_STATUS was not Int32.'}
        return [pscustomobject]@{Available=$true;Value=[int]$value}
    }catch {
        if([string]$_.Exception.Message -ceq 'BW4k7l PR_MESSAGE_STATUS was not Int32.'){throw}
        $e=$_.Exception;$notFound=$false
        while($null -ne $e){
            if([int]$e.HResult -eq -2147221233){$notFound=$true}
            $e=$e.InnerException
        }
        if(-not $notFound){throw 'BW4k7l PR_MESSAGE_STATUS failed for a reason other than MAPI_E_NOT_FOUND.'}
        return [pscustomobject]@{Available=$false;Value=$null}
    }
}
function Get-OPA265BW4k7lAttachmentHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Attachment)
    if([int]$Attachment.Type -ne 1){throw 'BW4k7l only simple by-value attachment is allowed.'}
    $name=[string]$Attachment.FileName
    if([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 255 -or
       $name -cnotmatch '^[A-Za-z0-9._-]+$'){
        throw 'BW4k7l unexpected unsafe synthetic attachment name.'
    }
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('OPA265-BW4k7l-'+[guid]::NewGuid().ToString('N')+'.bin')
    try {
        if([IO.File]::Exists($temp)){throw 'BW4k7l transient collision.'}
        # SaveAsFile creates an isolated temporary attachment byte copy only.
        # It does NOT save or mutate the Outlook item.
        $Attachment.SaveAsFile($temp)
        if(-not [IO.File]::Exists($temp)){throw 'BW4k7l attachment byte copy missing.'}
        $info=Get-Item -LiteralPath $temp -Force
        if($info.Length -ne 1024){throw 'BW4k7l expected exactly 1024 attachment bytes.'}
        return [pscustomobject][ordered]@{
            NameSha256=(Get-OPA265BW4k7lStringSha -Value $name)
            ByteLength=[long]$info.Length
            BytesSha256=(Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }finally {
        if([IO.File]::Exists($temp)){Remove-Item -LiteralPath $temp -Force -ErrorAction Stop}
    }
}
function Get-OPA265BW4k7lFreshMailWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][string]$FixtureId,
        [Parameter(Mandatory=$true)][string]$ExpectedEntryId,
        [Parameter(Mandatory=$true)][string]$ExpectedFolderId,
        [Parameter(Mandatory=$true)][string]$ExpectedStoreId
    )
    [void](Assert-OPA265BW4k7lFixtureId -FixtureId $FixtureId)
    if([int]$Mail.Class -ne 43 -or
       [string]$Mail.EntryID -cne $ExpectedEntryId -or
       [string]$Mail.Parent.EntryID -cne $ExpectedFolderId -or
       [string]$Mail.Parent.StoreID -cne $ExpectedStoreId){
        throw 'BW4k7l exact source MailItem/store/folder identity changed.'
    }
    $subject=[string]$Mail.Subject
    $body=[string]$Mail.Body
    if($subject -cne ('OPA265-BW4k7l-'+$FixtureId) -or
       -not $body.Contains('OPA265-BW4k7l disposable fixture '+$FixtureId) -or
       $body.Length -gt 65536 -or
       $body.Length -lt 40){
        throw 'BW4k7l mail is not the exact new disposable test fixture.'
    }
    $rc=$Mail.Recipients;$n=[int]$rc.Count
    if($n -lt 1 -or $n -gt 32){throw 'BW4k7l recipients must be complete, bounded and nonempty.'}
    $parts=New-Object 'System.Collections.Generic.List[string]'
    for($i=1;$i -le $n;$i++){
        $r=$rc.Item($i)
        if([int]$r.Type -lt 1 -or [int]$r.Type -gt 3 -or
           [string]::IsNullOrWhiteSpace([string]$r.Address)){
            throw 'BW4k7l recipient type/address missing.'
        }
        foreach($part in @([string]$i,[string]$r.Type,[string]$r.Name,[string]$r.Address)){
            if($part.Length -gt 4096){throw 'BW4k7l recipient field unbounded.'}
            $parts.Add(($part.Length.ToString([Globalization.CultureInfo]::InvariantCulture)+':'+$part))
        }
    }
    $pa=$Mail.PropertyAccessor
    $messageId=[string]$pa.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if($messageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$' -or
       $messageId.Length -gt 512){
        throw 'BW4k7l requires exact safe original InternetMessageId for future correlation.'
    }
    [byte[]]$searchKey=[byte[]]$pa.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x300B0102')
    if($searchKey.Length -lt 1 -or $searchKey.Length -gt 4096){
        throw 'BW4k7l missing or unsafe PR_SEARCH_KEY.'
    }
    $flags=$pa.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E070003')
    if($flags -isnot [int] -or [int]$flags -lt 0){throw 'BW4k7l PR_MESSAGE_FLAGS is invalid.'}
    $status=Get-OPA265BW4k7lStatusReadOnly -PropertyAccessor $pa
    $hasAttach=$pa.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E1B000B')
    if($hasAttach -isnot [bool] -or -not [bool]$hasAttach -or
       [int]$Mail.Attachments.Count -ne 1 -or
       (([int]$flags -band 16) -eq 0) -or
       ((([int]$flags -band 1) -ne 0) -eq [bool]$Mail.UnRead)){
        throw 'BW4k7l HASATTACH/read semantic mismatch or attachment count changed.'
    }
    $attach=Get-OPA265BW4k7lAttachmentHash -Attachment $Mail.Attachments.Item(1)
    $html=[string]$Mail.HTMLBody
    if($html.Length -gt 524288){throw 'BW4k7l HTMLBody exceeds bounded synthetic limit.'}
    $sender=[string]$Mail.SenderEmailAddress
    $received=[datetime]$Mail.ReceivedTime
    $sent=[datetime]$Mail.SentOn
    $size=[long]$Mail.Size
    if([string]::IsNullOrWhiteSpace($sender) -or $sender.Length -gt 4096 -or
       $received.Year -lt 2020 -or $sent.Year -lt 2020 -or
       $size -lt 1 -or $size -gt 1073741824){
        throw 'BW4k7l sender, timestamps or diagnostic size invalid.'
    }
    $w=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7l.FreshPreMoveMapiWitness.1'
        FixtureId=$FixtureId
        SourceEntryId=$ExpectedEntryId
        SourceFolderEntryId=$ExpectedFolderId
        SourceStoreIdSha256=(Get-OPA265BW4k7lStringSha -Value $ExpectedStoreId)
        InternetMessageId=$messageId
        InternetMessageIdSha256=(Get-OPA265BW4k7lStringSha -Value $messageId)
        SearchKeySha256=(Get-OPA265BW4k7lSha256 -Bytes $searchKey)
        SubjectSha256=(Get-OPA265BW4k7lStringSha -Value $subject)
        BodySha256=(Get-OPA265BW4k7lStringSha -Value $body)
        HtmlBodySha256=(Get-OPA265BW4k7lStringSha -Value $html)
        SenderSha256=(Get-OPA265BW4k7lStringSha -Value $sender)
        ReceivedUtcTicks=[long]$received.ToUniversalTime().Ticks
        SentUtcTicks=[long]$sent.ToUniversalTime().Ticks
        MessageSizeDiagnostic=[long]$size
        RecipientCount=$n
        RecipientDigestSha256=(Get-OPA265BW4k7lStringSha -Value ($parts -join [char]10))
        RawPrMessageFlags=[int]$flags
        RawPrMessageFlagsHex=('0x{0:X8}' -f [int]$flags)
        PrMessageStatusAvailable=[bool]$status.Available
        PrMessageStatus=$(if([bool]$status.Available){[int]$status.Value}else{$null})
        PrHasAttach=[bool]$hasAttach
        UnRead=[bool]$Mail.UnRead
        AttachmentCount=[int]$Mail.Attachments.Count
        AttachmentNameSha256=[string]$attach.NameSha256
        AttachmentByteLength=[long]$attach.ByteLength
        AttachmentBytesSha256=[string]$attach.BytesSha256
        RawFlag0x00010000BeforeMove=(([int]$flags -band 65536) -ne 0)
        BeforeMove=$true;OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
    return $w
}
function Assert-OPA265BW4k7lStableFreshWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$First,
          [Parameter(Mandatory=$true)][psobject]$Second)
    if([string]$First.Schema -cne '2.6.5-BW4k7l.FreshPreMoveMapiWitness.1' -or
       [string]$Second.Schema -cne [string]$First.Schema -or
       -not [bool]$First.BeforeMove -or -not [bool]$Second.BeforeMove -or
       [bool]$First.OutlookMoveExecuted -or [bool]$Second.OutlookMoveExecuted -or
       [bool]$First.WriterPermit -or [bool]$Second.WriterPermit -or
       [bool]$First.ProductionReady -or [bool]$Second.ProductionReady -or
       [bool]$First.AutomaticRetryAllowed -or [bool]$Second.AutomaticRetryAllowed){
        throw 'BW4k7l missing immutable pre-Move schema or forbidden permission.'
    }
    $fields=@($First.PSObject.Properties.Name)
    if($fields.Count -ne @($Second.PSObject.Properties.Name).Count){throw 'BW4k7l witness fields missing.'}
    foreach($name in $fields){
        if($Second.PSObject.Properties.Name -cnotcontains $name -or
           [string]$First.$name -cne [string]$Second.$name){
            throw ('BW4k7l two live reads differed: '+$name)
        }
    }
    return $true
}
function Get-OPA265BW4k7lEvidencePath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$FixtureId)
    [void](Assert-OPA265BW4k7lFixtureId -FixtureId $FixtureId)
    Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4k7l-PreMove') ('fixture-'+$FixtureId+'.json')
}
function Write-OPA265BW4k7lEvidenceOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Record)
    if([string]$Record.Schema -cne '2.6.5-BW4k7l.ImmutablePreMoveEvidence.1' -or
       [bool]$Record.OutlookMoveExecuted -or
       [bool]$Record.WriterPermit -or
       [bool]$Record.ProductionReady -or
       [bool]$Record.AutomaticRetryAllowed){
        throw 'BW4k7l invalid immutable evidence record.'
    }
    $path=Get-OPA265BW4k7lEvidencePath -FixtureId ([string]$Record.FixtureId)
    $folder=[IO.Path]::GetDirectoryName($path)
    if(-not [IO.Directory]::Exists($folder)){[void][IO.Directory]::CreateDirectory($folder)}
    if(([IO.File]::GetAttributes($folder) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7l unsafe redirected evidence folder.'
    }
    if([IO.File]::Exists($path)){throw 'BW4k7l immutable evidence already exists. NEVER OVERWRITE.'}
    $json=ConvertTo-Json -InputObject $Record -Depth 8 -Compress
    if($json.Length -gt 32768){throw 'BW4k7l oversized evidence record.'}
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($json+[char]10)
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }finally{$stream.Dispose()}
    return [pscustomobject][ordered]@{
        EvidencePath=$path
        EvidenceSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        Bytes=$bytes.Length
        CreatedOnce=$true
    }
}
