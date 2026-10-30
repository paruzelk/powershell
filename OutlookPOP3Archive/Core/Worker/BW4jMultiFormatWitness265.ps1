#requires -Version 5.1
. (Join-Path $PSScriptRoot 'BW4jSuitePlan265.ps1')
# All MailItem reading is read-only; attachments use bounded temporary files.
function Get-OPA265BW4jAttachments {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [ValidateRange(1024,4194304)][int]$MaxAttachmentBytes=1048576)
    $att=$Mail.Attachments
    $count=[int]$att.Count
    if($count -lt 0 -or $count -gt 2){throw 'BW4j supports 0..2 attachments in disposable fixtures only.'}
    $out=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le $count;$i++){
        $item=$att.Item($i)
        if([int]$item.Type -ne 1 -or [long]$item.Size -lt 1 -or
           [long]$item.Size -gt $MaxAttachmentBytes){
            throw 'BW4j only permits bounded by-value synthetic attachments.'
        }
        $name=[string]$item.FileName
        if($name.Length -lt 1 -or $name.Length -gt 128 -or
            $name -cmatch '[\\/:*?"<>|\x00-\x1F]'){
            throw 'BW4j attachment filename unsafe.'
        }
        $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (([IO.File]::GetAttributes($tempRoot) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'BW4j temporary root reparse point not permitted.'
        }
        $tempFile=Join-Path $tempRoot ('OPA265-BW4j-'+([guid]::NewGuid().ToString('N'))+'.bin')
        $s=$null
        try{
            if([IO.File]::Exists($tempFile)){throw 'BW4j unique temporary file already exists.'}
            # Writes ONLY an ephemeral synthetic attachment copy, never Outlook/PST.
            $item.SaveAsFile($tempFile)
            $file=Get-Item -LiteralPath $tempFile -Force
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $file.Length -lt 1 -or $file.Length -gt $MaxAttachmentBytes){
                throw 'BW4j saved attachment invalid or outside bounded bytes.'
            }
            $s=[IO.File]::Open($tempFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            $sha=[Security.Cryptography.SHA256]::Create()
            try {
                $digest=[BitConverter]::ToString($sha.ComputeHash($s)).Replace('-','').ToLowerInvariant()
            } finally {$sha.Dispose()}
            $out.Add([pscustomobject][ordered]@{
                Index=[int]$i
                FileName=$name
                ByteCount=[long]$file.Length
                Sha256=$digest
            })
        } finally {
            if($null -ne $s){$s.Dispose()}
            if([IO.File]::Exists($tempFile)){[IO.File]::Delete($tempFile)}
        }
    }
    return ,@($out.ToArray())
}
function Get-OPA265BW4jMailWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$ProfileName,
          [Parameter(Mandatory=$true)][string]$ExpectedEntryId,
          [Parameter(Mandatory=$true)][string]$ExpectedFolderEntryId,
          [Parameter(Mandatory=$true)][string]$ExpectedStoreId)
    if([int]$Mail.Class -ne 43 -or
        [string]$Mail.EntryID -cne $ExpectedEntryId -or
        [string]$Mail.Parent.EntryID -cne $ExpectedFolderEntryId -or
        [string]$Mail.Parent.StoreID -cne $ExpectedStoreId) {
        throw 'BW4j requires exact MailItem EntryID, parent folder and store.'
    }
    $subject=[string]$Mail.Subject
    $sender=[string]$Mail.SenderEmailAddress
    $body=[string]$Mail.Body
    $html=[string]$Mail.HTMLBody
    $attCount=[int]$Mail.Attachments.Count
    [void](Assert-OPA265BW4jFixture -Case $Case -Subject $subject -Body $body -HtmlBody $html -AttachmentCount $attCount)
    if($subject.Length -gt 32768 -or $sender.Length -gt 4096 -or
        $body.Length -gt 1048576 -or $html.Length -gt 2097152) {
        throw 'BW4j oversized text fields in a bounded synthetic witness.'
    }
    $when=[datetime]$Mail.ReceivedTime
    $size=[long]$Mail.Size
    if($when.Year -lt 1990 -or $size -lt 1 -or $size -gt 12582912){
        throw 'BW4j invalid mail timestamp or MailItem.Size.'
    }
    $msgId=[string]$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if($msgId.Length -gt 512 -or
        $msgId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$'){
        throw 'BW4j requires exact bounded InternetMessageId.'
    }
    $key=$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x300B0102')
    try{$keyBytes=[byte[]]$key}catch{throw 'BW4j binary SearchKey missing.'}
    if($null -eq $keyBytes -or $keyBytes.Length -lt 1 -or $keyBytes.Length -gt 4096){
        throw 'BW4j empty/bounded SearchKey required.'
    }
    $attachments=@(Get-OPA265BW4jAttachments -Mail $Mail)
    if($attachments.Count -ne $attCount){throw 'BW4j attachment digest count mismatch.'}
    if($Case.ExpectedAttachmentCount -eq 1 -and
        $attachments[0].ByteCount -lt [long]$Case.MinimumAttachmentBytes){
        throw 'BW4j attachment is smaller than the planned fixture.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j.MultiFormatMailWitness.1'
        SuiteId=$SuiteId
        CaseName=[string]$Case.Name
        TestId=[string]$Case.TestId
        ProfileName=$ProfileName
        EntryId=$ExpectedEntryId
        FolderEntryId=$ExpectedFolderEntryId
        StoreId=$ExpectedStoreId
        InternetMessageId=$msgId
        SearchKeySha256=(Get-OPA265BW4jSha256 -Bytes $keyBytes)
        SubjectUtf8Sha256=(Get-OPA265BW4jTextHash -Value $subject)
        SenderUtf8Sha256=(Get-OPA265BW4jTextHash -Value $sender)
        BodyUtf8Sha256=(Get-OPA265BW4jTextHash -Value $body)
        HtmlBodyUtf8Sha256=(Get-OPA265BW4jTextHash -Value $html)
        SubjectLength=[int]$subject.Length
        BodyLength=[int]$body.Length
        HtmlBodyLength=[int]$html.Length
        Size=[long]$size
        ReceivedUtcTicks=[long]$when.ToUniversalTime().Ticks
        Attachments=@($attachments)
        OutlookMoveExecuted=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4jWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Witness,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][string]$SuiteId)
    $names=@('Schema','SuiteId','CaseName','TestId','ProfileName','EntryId',
        'FolderEntryId','StoreId','InternetMessageId','SearchKeySha256',
        'SubjectUtf8Sha256','SenderUtf8Sha256','BodyUtf8Sha256','HtmlBodyUtf8Sha256',
        'SubjectLength','BodyLength','HtmlBodyLength','Size','ReceivedUtcTicks',
        'Attachments','OutlookMoveExecuted','ProductionReady')
    if($Witness -isnot [pscustomobject] -or
        @($Witness.PSObject.Properties.Name).Count -ne $names.Count) {
        throw 'BW4j invalid exact witness schema.'
    }
    foreach($n in $names){if($Witness.PSObject.Properties.Name -cnotcontains $n){
        throw ('BW4j witness missing '+$n)
    }}
    if($Witness.Schema -cne '2.6.5-BW4j.MultiFormatMailWitness.1' -or
        $Witness.SuiteId -cne $SuiteId -or
        $Witness.TestId -cne [string]$Case.TestId -or
        $Witness.CaseName -cne [string]$Case.Name -or
        [string]::IsNullOrWhiteSpace([string]$Witness.ProfileName) -or
        [string]::IsNullOrWhiteSpace([string]$Witness.EntryId) -or
        [string]::IsNullOrWhiteSpace([string]$Witness.FolderEntryId) -or
        [string]::IsNullOrWhiteSpace([string]$Witness.StoreId) -or
        $Witness.InternetMessageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$' -or
        [long]$Witness.Size -lt 1 -or [long]$Witness.ReceivedUtcTicks -lt 1 -or
        $Witness.OutlookMoveExecuted -isnot [bool] -or $Witness.OutlookMoveExecuted -or
        $Witness.ProductionReady -isnot [bool] -or $Witness.ProductionReady) {
        throw 'BW4j witness identity, timestamp, size or safety flag invalid.'
    }
    foreach($n in @('SearchKeySha256','SubjectUtf8Sha256','SenderUtf8Sha256',
        'BodyUtf8Sha256','HtmlBodyUtf8Sha256')){
        if([string]$Witness.$n -cnotmatch '^[a-f0-9]{64}$'){throw ('BW4j invalid '+$n)}
    }
    $list=@($Witness.Attachments)
    if($list.Count -ne [int]$Case.ExpectedAttachmentCount){throw 'BW4j witness attachment cardinality mismatch.'}
    for($i=0;$i -lt $list.Count;$i++){
        $a=$list[$i]
        if($a -isnot [pscustomobject] -or
           @($a.PSObject.Properties.Name).Count -ne 4 -or
           [int]$a.Index -ne ($i+1) -or [string]::IsNullOrWhiteSpace([string]$a.FileName) -or
           [long]$a.ByteCount -lt [long]$Case.MinimumAttachmentBytes -or
           [long]$a.ByteCount -gt 4194304 -or $a.Sha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'BW4j invalid attachment index, size or hash.'
        }
    }
    return $true
}
function Compare-OPA265BW4jWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Source,
          [Parameter(Mandatory=$true)][object]$Destination,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][string]$SuiteId)
    [void](Assert-OPA265BW4jWitness -Witness $Source -Case $Case -SuiteId $SuiteId)
    [void](Assert-OPA265BW4jWitness -Witness $Destination -Case $Case -SuiteId $SuiteId)
    $sameIdentity=($Source.TestId -ceq $Destination.TestId -and
        $Source.InternetMessageId -ceq $Destination.InternetMessageId -and
        $Source.SearchKeySha256 -ceq $Destination.SearchKeySha256 -and
        $Source.ProfileName -ceq $Destination.ProfileName -and
        $Source.StoreId -cne $Destination.StoreId)
    $subject=($Source.SubjectUtf8Sha256 -ceq $Destination.SubjectUtf8Sha256 -and
        $Source.SubjectLength -eq $Destination.SubjectLength)
    $sender=($Source.SenderUtf8Sha256 -ceq $Destination.SenderUtf8Sha256)
    $body=($Source.BodyUtf8Sha256 -ceq $Destination.BodyUtf8Sha256 -and
        $Source.BodyLength -eq $Destination.BodyLength)
    $html=($Source.HtmlBodyUtf8Sha256 -ceq $Destination.HtmlBodyUtf8Sha256 -and
        $Source.HtmlBodyLength -eq $Destination.HtmlBodyLength)
    $received=([long]$Source.ReceivedUtcTicks -eq [long]$Destination.ReceivedUtcTicks)
    $attMatch=$true
    $left=@($Source.Attachments);$right=@($Destination.Attachments)
    if($left.Count -ne $right.Count){$attMatch=$false}
    else{for($i=0;$i -lt $left.Count;$i++){
        if($left[$i].FileName -cne $right[$i].FileName -or
            [long]$left[$i].ByteCount -ne [long]$right[$i].ByteCount -or
            $left[$i].Sha256 -cne $right[$i].Sha256){$attMatch=$false}
    }}
    $allContent=($subject -and $sender -and $body -and $html -and $received -and $attMatch)
    $status=if(-not $sameIdentity){'BlockedIdentityOrStoreMismatch'}
        elseif(-not $allContent){'ContentOrAttachmentDriftNeedsManualReview'}
        elseif([long]$Source.Size -ne [long]$Destination.Size){'OnlyMAPIMessageSizeChangedNeedsManualReview'}
        else{'AllCheckedFieldsMatchReadOnly'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j.MultiFormatWitnessComparison.1'
        Status=$status
        SuiteId=$SuiteId
        TestId=$Case.TestId
        CaseName=$Case.Name
        IdentityMatches=[bool]$sameIdentity
        SubjectMatches=[bool]$subject
        SenderMatches=[bool]$sender
        BodyMatches=[bool]$body
        HtmlBodyMatches=[bool]$html
        ReceivedUtcTicksMatches=[bool]$received
        AttachmentsMatch=[bool]$attMatch
        SourceSize=[long]$Source.Size
        DestinationSize=[long]$Destination.Size
        DeltaSize=([long]$Destination.Size-[long]$Source.Size)
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        MoveExecutedByComparison=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
    }
}
