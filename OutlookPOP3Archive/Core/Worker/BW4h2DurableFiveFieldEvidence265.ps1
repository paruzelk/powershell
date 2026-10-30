#requires -Version 5.1
# BW4h2: independently pinned five field SHA256 digests and original MAPI Size.
# No MailItem.Move, journal writer or production Worker activation.
function Get-OPA265BW4h2EvidencePath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $id=[guid]::Empty
    if (-not [guid]::TryParse($TestId,[ref]$id) -or $id -eq [guid]::Empty -or
        $TestId -cne $id.ToString('D') -or
        [string]::IsNullOrWhiteSpace($LocalAppData) -or
        -not [IO.Path]::IsPathRooted($LocalAppData)) {
        throw 'BW4h2 requires canonical TestId and local per-user AppData.'
    }
    Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4h2-FieldEvidence') ('fixture-'+$TestId+'.json')
}
function Get-OPA265BW4h2FieldEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][string]$TestId,
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [Parameter(Mandatory=$true)][string]$PstPath,
        [Parameter(Mandatory=$true)][string]$StoreId,
        [Parameter(Mandatory=$true)][string]$FolderEntryId,
        [Parameter(Mandatory=$true)][string]$ItemEntryId
    )
    if ([int]$Mail.Class -ne 43 -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Mail.EntryID) -Expected $ItemEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Mail.Parent.EntryID) -Expected $FolderEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Mail.Parent.StoreID) -Expected $StoreId) -or
        -not [IO.Path]::IsPathRooted($PstPath)) {
        throw 'BW4h2 exact MailItem or parent/store/PST identity mismatch.'
    }
    $subject=[string]$Mail.Subject
    $sender=[string]$Mail.SenderEmailAddress
    $body=[string]$Mail.Body
    $size=[long]$Mail.Size
    $when=[datetime]$Mail.ReceivedTime
    if ($when.Year -lt 1990 -or $size -lt 1 -or
        $subject.Length -gt 32768 -or $sender.Length -gt 4096 -or
        $body.Length -gt 4194304) {
        throw 'BW4h2 invalid received date, size or unbounded content.'
    }
    $attachments=-1
    try { $attachments=[int]$Mail.Attachments.Count }
    catch { throw 'BW4h2 must read AttachmentCount.' }
    $tag=Get-OPA265BW4fFixtureTag -Subject $subject -Body $body -AttachmentCount $attachments
    if (-not [bool]$tag.IsExactOperatorFixture -or
        [string]$tag.TestId -cne $TestId -or $attachments -ne 0) {
        throw 'BW4h2 only accepts the exact zero-attachment disposable test fixture.'
    }
    $messageId=[string]$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if ($messageId.Length -gt 512 -or
        $messageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$') {
        throw 'BW4h2 requires a bounded exact InternetMessageId.'
    }
    $key=$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x300B0102')
    try { $keyBytes=[byte[]]$key }
    catch { throw 'BW4h2 MAPI SearchKey must be bytes.' }
    if ($null -eq $keyBytes -or $keyBytes.Length -lt 1 -or $keyBytes.Length -gt 4096) {
        throw 'BW4h2 MAPI SearchKey invalid or absent.'
    }
    $ticks=$when.ToUniversalTime().Ticks
    $contentHash=Get-OPA265BW4h1ContentHash -Subject $subject -SenderEmailAddress $sender -Body $body -Size $size -ReceivedUtcTicks $ticks
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4h2.ImmutableFiveFieldEvidence.1'
        TestId=$TestId
        ProfileName=$ProfileName
        PstPath=[IO.Path]::GetFullPath($PstPath)
        StoreId=$StoreId
        FolderEntryId=$FolderEntryId
        ItemEntryId=$ItemEntryId
        InternetMessageId=$messageId
        SearchKeySha256=(Get-OPA265BW4cHash -Bytes $keyBytes)
        ContentFingerprintSha256=$contentHash
        SubjectLength=[int]$subject.Length
        SubjectUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $subject)
        SenderEmailAddressLength=[int]$sender.Length
        SenderEmailAddressUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $sender)
        BodyLength=[int]$body.Length
        BodyUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $body)
        BodyCR=[int]([regex]::Matches($body,'\r')).Count
        BodyLF=[int]([regex]::Matches($body,'\n')).Count
        Size=[long]$size
        ReceivedUtcTicks=[long]$ticks
        ReceivedUtcTicksSha256=(Get-OPA265BW4h1FieldDigest -Text ($ticks.ToString([Globalization.CultureInfo]::InvariantCulture)))
        AttachmentCount=[int]$attachments
        CapturedUtc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4h2Evidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [Parameter(Mandatory=$true)][string]$TestId)
    $names=@('Schema','TestId','ProfileName','PstPath','StoreId','FolderEntryId',
        'ItemEntryId','InternetMessageId','SearchKeySha256','ContentFingerprintSha256',
        'SubjectLength','SubjectUtf8Sha256','SenderEmailAddressLength',
        'SenderEmailAddressUtf8Sha256','BodyLength','BodyUtf8Sha256','BodyCR',
        'BodyLF','Size','ReceivedUtcTicks','ReceivedUtcTicksSha256',
        'AttachmentCount','CapturedUtc','AutomaticRetryAllowed','ProductionReady')
    $id=[guid]::Empty
    if ($Evidence -isnot [pscustomobject] -or
        @($Evidence.PSObject.Properties.Name).Count -ne $names.Count -or
        -not [guid]::TryParse([string]$TestId,[ref]$id) -or $id -eq [guid]::Empty -or
        [string]$TestId -cne $id.ToString('D')) {
        throw 'BW4h2 malformed field evidence or invalid operator TestId.'
    }
    foreach($name in $names){
        if ($Evidence.PSObject.Properties.Name -cnotcontains $name) {
            throw ('BW4h2 missing required field '+$name)
        }
    }
    if ([string]$Evidence.Schema -cne '2.6.5-BW4h2.ImmutableFiveFieldEvidence.1' -or
        [string]$Evidence.TestId -cne $TestId -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.ProfileName) -or
        -not [IO.Path]::IsPathRooted([string]$Evidence.PstPath) -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.StoreId) -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.FolderEntryId) -or
        [string]::IsNullOrWhiteSpace([string]$Evidence.ItemEntryId) -or
        [string]$Evidence.InternetMessageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$' -or
        [long]$Evidence.Size -lt 1 -or [long]$Evidence.ReceivedUtcTicks -lt 1 -or
        [int]$Evidence.AttachmentCount -ne 0 -or
        [int]$Evidence.SubjectLength -lt 1 -or [int]$Evidence.BodyLength -lt 1 -or
        $Evidence.AutomaticRetryAllowed -isnot [bool] -or $Evidence.AutomaticRetryAllowed -or
        $Evidence.ProductionReady -isnot [bool] -or $Evidence.ProductionReady) {
        throw 'BW4h2 required evidence fields invalid.'
    }
    foreach($name in @('SearchKeySha256','ContentFingerprintSha256','SubjectUtf8Sha256',
        'SenderEmailAddressUtf8Sha256','BodyUtf8Sha256','ReceivedUtcTicksSha256')) {
        if ([string]$Evidence.$name -cnotmatch '^[0-9a-f]{64}$') {
            throw ('BW4h2 invalid field SHA256 '+$name)
        }
    }
    $dt=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Evidence.CapturedUtc,[ref]$dt)){
        throw 'BW4h2 captured UTC invalid.'
    }
    return $true
}
function Write-OPA265BW4h2OnceEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][string]$EvidencePath)
    [void](Assert-OPA265BW4h2Evidence -Evidence $Evidence -TestId $TestId)
    $expected=Get-OPA265BW4h2EvidencePath -TestId $TestId
    if(-not [string]::Equals([IO.Path]::GetFullPath($EvidencePath),
        [IO.Path]::GetFullPath($expected),
        [StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4h2 evidence path cannot be redirected.'
    }
    $dir=[IO.Path]::GetDirectoryName($expected)
    if(-not [IO.Directory]::Exists($dir)){[void][IO.Directory]::CreateDirectory($dir)}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4h2 evidence directory is a reparse point.'
    }
    $data=(New-Object Text.UTF8Encoding($true)).GetBytes((ConvertTo-Json -InputObject $Evidence -Depth 5))
    $stream=$null
    try{
        $stream=[IO.FileStream]::new($expected,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($data,0,$data.Length)
        $stream.Flush($true)
    } finally {if($null -ne $stream){$stream.Dispose()}}
    return $expected
}
function Compare-OPA265BW4h2FieldEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After)
    [void](Assert-OPA265BW4h2Evidence -Evidence $Before -TestId ([string]$Before.TestId))
    [void](Assert-OPA265BW4h2Evidence -Evidence $After -TestId ([string]$Before.TestId))
    $identity=([string]$Before.TestId -ceq [string]$After.TestId -and
        [string]$Before.InternetMessageId -ceq [string]$After.InternetMessageId -and
        [string]$Before.SearchKeySha256 -ceq [string]$After.SearchKeySha256 -and
        [string]$Before.ProfileName -ceq [string]$After.ProfileName)
    $fields=[ordered]@{
        Subject=([string]$Before.SubjectUtf8Sha256 -ceq [string]$After.SubjectUtf8Sha256 -and
                 [int]$Before.SubjectLength -eq [int]$After.SubjectLength)
        SenderEmailAddress=([string]$Before.SenderEmailAddressUtf8Sha256 -ceq [string]$After.SenderEmailAddressUtf8Sha256 -and
                            [int]$Before.SenderEmailAddressLength -eq [int]$After.SenderEmailAddressLength)
        Body=([string]$Before.BodyUtf8Sha256 -ceq [string]$After.BodyUtf8Sha256 -and
              [int]$Before.BodyLength -eq [int]$After.BodyLength)
        Size=([long]$Before.Size -eq [long]$After.Size)
        ReceivedUtcTicks=([long]$Before.ReceivedUtcTicks -eq [long]$After.ReceivedUtcTicks -and
                          [string]$Before.ReceivedUtcTicksSha256 -ceq [string]$After.ReceivedUtcTicksSha256)
    }
    $otherFour=($fields.Subject -and $fields.SenderEmailAddress -and
        $fields.Body -and $fields.ReceivedUtcTicks)
    $status=if(-not $identity){'BlockedIdentityDrift'}
        elseif(-not $otherFour){'ContentFieldDriftNeedsManualReview'}
        elseif(-not $fields.Size){'OnlyMAPIMessageSizeChangedManualReview'}
        elseif([string]$Before.ContentFingerprintSha256 -cne [string]$After.ContentFingerprintSha256){
            'BlockedCompositeFingerprintInconsistency'
        }else{'AllFiveFieldsMatchReadOnly'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4h2.FieldByFieldComparison.1'
        Status=$status
        IdentityMatches=[bool]$identity
        SubjectMatches=[bool]$fields.Subject
        SenderEmailAddressMatches=[bool]$fields.SenderEmailAddress
        BodyMatches=[bool]$fields.Body
        SizeMatches=[bool]$fields.Size
        ReceivedUtcTicksMatches=[bool]$fields.ReceivedUtcTicks
        FourNonSizeFieldsMatch=[bool]$otherFour
        SourceSize=[long]$Before.Size
        DestinationSize=[long]$After.Size
        DestinationMinusSourceSize=([long]$After.Size-[long]$Before.Size)
        CompositeFingerprintMatches=([string]$Before.ContentFingerprintSha256 -ceq [string]$After.ContentFingerprintSha256)
        IndependentPreMoveFieldEvidenceAvailable=$true
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
    }
}
