#requires -Version 5.1
# BW4c: two Outlook read paths, one existing MAPI session. Never grants Worker authorization.
# Compare Outlook opaque hexadecimal identities byte-for-byte, ignoring hex letter case.
# Non-hexadecimal mock IDs still require exact ordinal equality.
function Test-OPA265BW4cOpaqueIdMatch {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Observed,
          [AllowEmptyString()][string]$Expected)
    if ([string]::IsNullOrWhiteSpace($Observed) -or
        [string]::IsNullOrWhiteSpace($Expected)) { return $false }
    if ([string]::Equals($Observed,$Expected,[StringComparison]::Ordinal)) { return $true }
    if ($Observed.Length -eq $Expected.Length -and
        ($Observed.Length % 2) -eq 0 -and
        $Observed -cmatch '^[0-9a-fA-F]+$' -and
        $Expected -cmatch '^[0-9a-fA-F]+$') {
        return [string]::Equals($Observed,$Expected,[StringComparison]::OrdinalIgnoreCase)
    }
    return $false
}
function Get-OPA265BW4cHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-OPA265BW4cItemWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$StoreId,
        [Parameter(Mandatory=$true)][string]$FolderEntryId,
        [Parameter(Mandatory=$true)][string]$CandidateEntryId,
        [Parameter(Mandatory=$true)][ValidateSet('PrimaryReadOnly','IndependentReadOnly')][string]$Method
    )
    if ([int]$Mail.Class -ne 43 -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Mail.EntryID) -Expected $CandidateEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Mail.Parent.EntryID) -Expected $FolderEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Mail.Parent.StoreID) -Expected $StoreId)) {
        throw 'BW4c: candidate is not the exact MailItem in the pinned folder and store.'
    }
    $id=[string]$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if ([string]::IsNullOrWhiteSpace($id) -or $id.Length -gt 4096) {
        throw 'BW4c: a complete InternetMessageId is required.'
    }
    $key=$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x300B0102')
    if ($null -eq $key) { throw 'BW4c: missing MAPI PR_SEARCH_KEY.' }
    try { [byte[]]$keyBytes=[byte[]]$key } catch { throw 'BW4c: MAPI PR_SEARCH_KEY is not binary.' }
    if ($keyBytes.Length -lt 1 -or $keyBytes.Length -gt 4096) { throw 'BW4c: invalid search key length.' }
    $size=[long]$Mail.Size
    if ($size -lt 1) { throw 'BW4c: invalid MAPI message size.' }
    $when=[datetime]$Mail.ReceivedTime
    if ($when.Year -lt 1990) { throw 'BW4c: invalid received timestamp.' }
    $subject=[string]$Mail.Subject
    $sender=[string]$Mail.SenderEmailAddress
    $body=[string]$Mail.Body
    if ($subject.Length -gt 32768 -or $sender.Length -gt 4096 -or $body.Length -gt 4194304) {
        throw 'BW4c: item content exceeds bounded read-only fingerprint limits.'
    }
    # Deterministic field-length-prefix encoding; fingerprint is NOT full MAPI byte equality.
    $buffer=New-Object Text.StringBuilder
    foreach($v in @($subject,$sender,$body,[string]$size,[string]$when.ToUniversalTime().Ticks)) {
        [void]$buffer.Append(([string]$v).Length.ToString([Globalization.CultureInfo]::InvariantCulture))
        [void]$buffer.Append(':')
        [void]$buffer.Append([string]$v)
    }
    $contentHash=Get-OPA265BW4cHash -Bytes ([Text.Encoding]::UTF8.GetBytes($buffer.ToString()))
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4b.PerItemWitness.1'
        CaptureId=[guid]::NewGuid().ToString('D')
        CaptureMethod=$Method
        SourcePst=$SourcePst
        SourceStoreId=$StoreId
        SourceEntryId=$CandidateEntryId
        InternetMessageId=$id
        SearchKeySha256=(Get-OPA265BW4cHash -Bytes $keyBytes)
        ContentSha256=$contentHash
        ObservedItemCount=1
    }
}
function Get-OPA265BW4cPop3Store {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][string]$SourcePst)
    if (-not [IO.Path]::IsPathRooted($SourcePst) -or
        $SourcePst.StartsWith('\\',[StringComparison]::Ordinal) -or
        [IO.Path]::GetExtension($SourcePst) -ine '.pst' -or
        -not [IO.File]::Exists($SourcePst) -or
        (([IO.File]::GetAttributes($SourcePst) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'BW4c requires an existing non-symlink local PST.'
    }
    $canonical=[IO.Path]::GetFullPath($SourcePst)
    $count=[int]$Namespace.Stores.Count
    if ($count -lt 1 -or $count -gt 128) { throw 'BW4c: unsafe Outlook store inventory.' }
    $selected=$null
    $hits=0
    for($i=1;$i -le $count;$i++) {
        $s=$Namespace.Stores.Item($i)
        $path=''
        try { $path=[string]$s.FilePath } catch { continue }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ([string]::Equals([IO.Path]::GetFullPath($path),$canonical,[StringComparison]::OrdinalIgnoreCase)) {
            $selected=$s
            $hits++
        }
    }
    if ($hits -ne 1) { throw 'BW4c: source PST is not uniquely mounted in the active Outlook session.' }
    $storeId=[string]$selected.StoreID
    if ([string]::IsNullOrWhiteSpace($storeId)) { throw 'BW4c: missing store ID.' }
    $pop3=0
    $accountCount=[int]$Namespace.Accounts.Count
    if ($accountCount -lt 1 -or $accountCount -gt 128) { throw 'BW4c: unsafe Outlook account inventory.' }
    for($i=1;$i -le $accountCount;$i++) {
        $account=$Namespace.Accounts.Item($i)
        if ([int]$account.AccountType -ne 2) { continue } # olPop3 only, never IMAP.
        $delivery=$account.DeliveryStore
        if ($null -eq $delivery) { throw 'BW4c: POP3 DeliveryStore unavailable.' }
        if (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$delivery.StoreID) -Expected $storeId) { $pop3++ }
    }
    if ($pop3 -ne 1) { throw 'BW4c: exactly one POP3 DeliveryStore must own the selected PST.' }
    return [pscustomobject]@{ Store=$selected; StoreId=$storeId; SourcePst=$canonical }
}
function Get-OPA265BW4cDualReadback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$FolderEntryId,
        [Parameter(Mandatory=$true)][string]$CandidateEntryId,
        [ValidateRange(1,5000)][int]$MaxFolderItems=1000,
        [switch]$UseTargetedMessageIdReadOnly
    )
    if ([string]::IsNullOrWhiteSpace($FolderEntryId) -or
        [string]::IsNullOrWhiteSpace($CandidateEntryId) -or
        $FolderEntryId.Length -gt 8192 -or $CandidateEntryId.Length -gt 8192) {
        throw 'BW4c: explicit folder and message EntryIDs are mandatory.'
    }
    $scope=Get-OPA265BW4cPop3Store -Namespace $Namespace -SourcePst $SourcePst
    $folder=$null
    try { $folder=$Namespace.GetFolderFromID($FolderEntryId,$scope.StoreId) }
    catch { throw ('BW4c: GetFolderFromID failed for explicit folder/store: '+[string]$_.Exception.Message) }
    if ($null -eq $folder) { throw 'BW4c: GetFolderFromID returned null for the explicit store.' }
    $observedFolderEntryId=[string]$folder.EntryID
    $observedFolderStoreId=[string]$folder.StoreID
    if (-not (Test-OPA265BW4cOpaqueIdMatch -Observed $observedFolderEntryId -Expected $FolderEntryId)) {
        throw ('BW4c: GetFolderFromID folder EntryID mismatch; expected chars='+$FolderEntryId.Length+
            ', observed chars='+$observedFolderEntryId.Length+'. No fallback or Move.')
    }
    if (-not (Test-OPA265BW4cOpaqueIdMatch -Observed $observedFolderStoreId -Expected $scope.StoreId)) {
        throw ('BW4c: GetFolderFromID StoreID mismatch; expected chars='+$scope.StoreId.Length+
            ', observed chars='+$observedFolderStoreId.Length+'. No fallback or Move.')
    }
    # Route 1: direct MAPI namespace lookup.
    $direct=$Namespace.GetItemFromID($CandidateEntryId,$scope.StoreId)
    if ($null -eq $direct) { throw 'BW4c: GetItemFromID returned no candidate.' }
    $a=Get-OPA265BW4cItemWitness -Mail $direct -SourcePst $scope.SourcePst -StoreId $scope.StoreId -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -Method PrimaryReadOnly
    # Route 2: either bounded full enumeration (original BW4c) or EXPLICIT
    # BW4e2 targeted server/MAPI restriction. Never scan a large folder client-side.
    $items=$folder.Items
    $n=[int]$items.Count
    $matched=$null
    $hits=0
    $scanned=0
    if ($UseTargetedMessageIdReadOnly) {
        if ($n -lt 1 -or $n -gt 100000) {
            throw 'BW4e2: folder count outside targeted-read-only guard (1..100000).'
        }
        $messageId=[string]$a.InternetMessageId
        # Strictly bounded simple InternetMessageId; reject SQL quoting/injection,
        # whitespace, controls and ambiguous characters rather than escaping.
        if ($messageId.Length -gt 512 -or
            $messageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$') {
            throw 'BW4e2: direct MAPI InternetMessageId is not safe for exact DASL filtering.'
        }
        $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = ' + "'" + $messageId + "'"
        $restricted=$null
        try { $restricted=$items.Restrict($filter) }
        catch { throw ('BW4e2: exact MAPI InternetMessageId restriction failed closed: '+[string]$_.Exception.Message) }
        if ($null -eq $restricted) { throw 'BW4e2: MAPI Restrict returned null; no fallback.' }
        $hits=[int]$restricted.Count
        if ($hits -ne 1) { throw 'BW4e2: exact InternetMessageId restriction must return ONE item (zero/duplicates denied).' }
        $matched=$restricted.Item(1)
        if ($null -eq $matched) { throw 'BW4e2: filtered item is null.' }
        if (-not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$matched.EntryID) -Expected $CandidateEntryId)) {
            throw 'BW4e2: restriction returned a different EntryID; no fallback.'
        }
        # BW4f: a changing Inbox invalidates the dual-path snapshot.
        # A Restrict collection is not a snapshot guarantee. Fail closed when
        # an item was delivered, removed or reindexed during MAPI readback.
        $recheckedHits=[int]$restricted.Count
        $recheckedFolderCount=[int]$items.Count
        if ($recheckedHits -ne 1 -or $recheckedFolderCount -ne $n) {
            throw 'BW4f: MAPI restricted result or folder cardinality changed during readback; no consistent evidence.'
        }
        $directRecheck=$null
        try { $directRecheck=$Namespace.GetItemFromID($CandidateEntryId,$scope.StoreId) }
        catch { throw ('BW4f: direct candidate recheck failed closed: '+[string]$_.Exception.Message) }
        if ($null -eq $directRecheck) { throw 'BW4f: direct candidate recheck returned null.' }
        $recheck=Get-OPA265BW4cItemWitness -Mail $directRecheck -SourcePst $scope.SourcePst -StoreId $scope.StoreId -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -Method DirectStabilityRecheck
        if ([string]$recheck.InternetMessageId -cne [string]$a.InternetMessageId -or
            [string]$recheck.SearchKeySha256 -cne [string]$a.SearchKeySha256 -or
            [string]$recheck.ContentSha256 -cne [string]$a.ContentSha256) {
            throw 'BW4f: direct candidate MAPI fingerprint changed during readback; no stable evidence.'
        }
        # No full enumeration of the original 26485-item folder took place.
        $scanned=0
    } else {
        if ($n -lt 1 -or $n -gt $MaxFolderItems) {
            throw 'BW4c: folder cardinality outside explicit scan cap; no partial proof.'
        }
        for($i=1;$i -le $n;$i++) {
            $item=$items.Item($i)
            if (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$item.EntryID) -Expected $CandidateEntryId) {
                $hits++
                $matched=$item
            }
        }
        if ($hits -ne 1 -or $null -eq $matched) {
            throw 'BW4c: folder scan must find exactly one candidate.'
        }
        $scanned=$n
    }
    $b=Get-OPA265BW4cItemWitness -Mail $matched -SourcePst $scope.SourcePst -StoreId $scope.StoreId -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -Method IndependentReadOnly
    if ($UseTargetedMessageIdReadOnly -and (
        [string]$b.InternetMessageId -cne [string]$a.InternetMessageId -or
        [string]$b.SearchKeySha256 -cne [string]$a.SearchKeySha256 -or
        [string]$b.ContentSha256 -cne [string]$a.ContentSha256)) {
        throw 'BW4e2: direct and restricted readbacks disagree; no synthetic Move permit.'
    }
    return [pscustomobject]@{
        Primary=$a
        Independent=$b
        TwoSeparateOutlookReadPaths=$true
        SameOutlookSession=$true
        IndependentExternalMAPIProof=$false
        FolderItemsScanned=$scanned
        FolderItemsObserved=$n
        TargetedMessageIdReadOnlyUsed=[bool]$UseTargetedMessageIdReadOnly
        CandidateMatches=1
        MailMoveExecuted=$false
    }
}
