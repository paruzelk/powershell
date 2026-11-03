#requires -Version 5.1
BeforeAll {
  . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7nProviderSizeFlagDiagnostics265.ps1')
  function New-BW4k7nFake {
    $pins=Get-OPA265BW4k7nPins
    $v=@{
      '0x0E070003'=[int]17
      '0x0E170003'=[int]0
      '0x0E1B000B'=$true
      '0x0E080003'=[int]9957
      '0x0E080014'=[long]9957
      '0x10160003'=[int]3
      '0x0E1F000B'=$true
      '0x3FDE0003'=[int]65001
      '0x3FFD0003'=[int]65001
      '0x30080040'=[datetime]'2026-11-03T09:45:00Z'
      '0x30070040'=[datetime]'2026-11-03T09:30:00Z'
    }
    $pa=[pscustomobject]@{Map=$v}
    $pa | Add-Member -MemberType ScriptMethod -Name GetProperty -Value {
      param($uri)
      $key=([string]$uri).Replace('http://schemas.microsoft.com/mapi/proptag/','')
      if(-not $this.Map.ContainsKey($key)){
        throw (New-Object Runtime.InteropServices.COMException('not found',-2147221233))
      }
      return $this.Map[$key]
    }
    $mail=[pscustomobject]@{
      Class=43;EntryID=$pins.DestinationEntryId
      Parent=[pscustomobject]@{EntryID=$pins.DestinationFolderEntryId;StoreID='test-archive-store'}
      PropertyAccessor=$pa;Size=[long]9957
    }
    return [pscustomobject]@{Mail=$mail;PA=$pa;Pins=$pins}
  }
  function Get-BW4k7nFakeProbe {
    param($Fixture)
    if($null -eq $Fixture){$Fixture=New-BW4k7nFake}
    $p=@{
      Mail=$Fixture.Mail;StoreId='test-archive-store'
      FolderEntryId=$Fixture.Pins.DestinationFolderEntryId
      EntryId=$Fixture.Pins.DestinationEntryId
    }
    Get-OPA265BW4k7nArchivedProbe @p
  }
  function New-BW4k7nAudit {
    $p=Get-OPA265BW4k7nPins
    return [pscustomobject]@{
      Schema='2.6.5-BW4k7m.IndependentRealPostMoveAudit.1'
      Status='ContentMatchRawPrMessageFlagsDriftUnclassifiedManualReview'
      VerifiedOriginalEvidenceSha256=$p.OriginalEvidenceSha256
      VerifiedOriginalIrreversibleClaimSha256=$p.IrreversibleClaimSha256
      SourceMessageIdMatches=0;DestinationMessageIdMatches=1
      DestinationEntryId=$p.DestinationEntryId
      FullSemanticContentMatch=$true;SemanticFieldMismatchCount=0
      SourceRawPrMessageFlags=65555;DestinationRawPrMessageFlags=17
      ChangedMaskHex='0x00010002';Unknown0x00010000Changed=$true
      PrMessageStatusEqual=$true
      SourceDiagnosticMessageSize=[long]10489
      DestinationDiagnosticMessageSize=[long]9957
      HistoricalRawStateMismatchWaived=$false
      OutlookMoveExecutedByThisAudit=$false
      ProductionReady=$false
    }
  }
  function Get-BW4k7nResult {
    param($Fixture,$Audit)
    if($null -eq $Audit){$Audit=New-BW4k7nAudit}
    if($null -eq $Fixture){$Fixture=New-BW4k7nFake}
    Get-OPA265BW4k7nClassification -ArchivedProbe (Get-BW4k7nFakeProbe $Fixture) -IndependentArchiveAudit $Audit
  }
}
Describe 'BW4k7n PST provider scalar MAPI + post-restart immutable evidence safety' {
  It 'pin original Evidence SHA' {
    (Get-OPA265BW4k7nPins).OriginalEvidenceSha256 | Should -BeExactly "36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29"
  }
  It 'pin original one-shot Claim SHA' {
    (Get-OPA265BW4k7nPins).IrreversibleClaimSha256 | Should -BeExactly "6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58"
  }
  It 'pin fresh FixtureId' {
    (Get-OPA265BW4k7nPins).FixtureId | Should -BeExactly "d1a68868-acf5-4c70-860d-5521e1ce2836"
  }
  It 'pin existing destination EntryId' {
    (Get-OPA265BW4k7nPins).DestinationEntryId | Should -BeExactly "00000000E88584FF275FEE45B531E472CF338A8A24002000"
  }
  It 'preserve historic BW4k7g Claim' {
    (Get-OPA265BW4k7nPins).OldBW4k7gClaimSha256 | Should -BeExactly "325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c"
  }
  It 'pinned 10489 before and 9957 after' {
     $p=Get-OPA265BW4k7nPins; $p.OriginalMailSize | Should -Be 10489; $p.ArchivedMailSize | Should -Be 9957
  }
  It 'bounded property count is 11' {
    @(Get-OPA265BW4k7nProbePlan).Count | Should -Be 11
  }
  It 'distinct MessageFlags vs MessageStatus tags' {
     $p=@(Get-OPA265BW4k7nProbePlan); $p[0].Tag | Should -BeExactly "0x0E070003"; $p[1].Tag | Should -BeExactly "0x0E170003"
  }
  It 'correct Int32/Int64 message size tags' {
     $p=@(Get-OPA265BW4k7nProbePlan); $p[3].Tag | Should -BeExactly "0x0E080003"; $p[4].Tag | Should -BeExactly "0x0E080014"
  }
  It 'store support mask excluded' {
    (@(Get-OPA265BW4k7nProbePlan) | ForEach-Object {$_.Tag}) -join "," | Should -Not -Match "0x340D0003"
  }
  It 'large compressed RTF property excluded' {
    (@(Get-OPA265BW4k7nProbePlan) | ForEach-Object {$_.Tag}) -join "," | Should -Not -Match "0x10090102"
  }
  It 'successful scoped scalar archived probe' {
     $w=Get-BW4k7nFakeProbe (New-BW4k7nFake); $w.PropertyCount | Should -Be 11; $w.ArchiveMailItemSize | Should -Be 9957; $w.Properties[0].Value | Should -Be 17
  }
  It 'original required status is zero' {
    (Get-BW4k7nFakeProbe (New-BW4k7nFake)).Properties[1].Value | Should -Be 0
  }
  It 'missing optional message size preserved as null' {
     $f=New-BW4k7nFake; [void]$f.PA.Map.Remove("0x0E080003"); $w=Get-BW4k7nFakeProbe $f; $w.Properties[3].Available | Should -BeFalse; $null -eq $w.Properties[3].Value | Should -BeTrue
  }
  It 'missing optional 64-bit size preserved as absent' {
     $f=New-BW4k7nFake; [void]$f.PA.Map.Remove("0x0E080014"); (Get-BW4k7nFakeProbe $f).Properties[4].Available | Should -BeFalse
  }
  It 'missing native format is acceptable' {
     $f=New-BW4k7nFake; [void]$f.PA.Map.Remove("0x10160003"); (Get-BW4k7nFakeProbe $f).Properties[5].Available | Should -BeFalse
  }
  It 'required flags absence is blocked' {
     $f=New-BW4k7nFake; [void]$f.PA.Map.Remove("0x0E070003"); {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'required status absence is blocked' {
     $f=New-BW4k7nFake; [void]$f.PA.Map.Remove("0x0E170003"); {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'required attach absence is blocked' {
     $f=New-BW4k7nFake; [void]$f.PA.Map.Remove("0x0E1B000B"); {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'wrong flags type blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E070003"]="17"; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'negative provider size blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E080003"]=[int]-1; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'wrong extended size type blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E080014"]="9957"; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'wrong has-attachment bool blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E1B000B"]=[int]1; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'wrong timestamp type blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x30080040"]="2026-11-03"; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'UTC timestamp numeric bounded' {
     $w=Get-BW4k7nFakeProbe (New-BW4k7nFake); $w.Properties[9].Kind | Should -BeExactly "DateTime"; $w.Properties[9].Value | Should -BeGreaterThan 0
  }
  It 'incorrect original archived EntryID blocked' {
     $f=New-BW4k7nFake; $f.Mail.EntryID=("a"*48); {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'incorrect destination folder ID blocked' {
     $f=New-BW4k7nFake; $f.Mail.Parent.EntryID=("a"*48); {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'incorrect store ID blocked' {
     $f=New-BW4k7nFake; $f.Mail.Parent.StoreID="else"; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'non-MailItem class blocked' {
     $f=New-BW4k7nFake; $f.Mail.Class=48; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'changed destination MailItem.Size blocked' {
     $f=New-BW4k7nFake; $f.Mail.Size=9958; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'changed destination flags blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E070003"]=[int]65555; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'changed destination status blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E170003"]=[int]1; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'changed destination attachments blocked' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E1B000B"]=$false; {Get-BW4k7nFakeProbe $f} | Should -Throw
  }
  It 'two separate identical read paths stable' {
     $f=New-BW4k7nFake; $a=Get-BW4k7nFakeProbe $f; $b=Get-BW4k7nFakeProbe $f; (Assert-OPA265BW4k7nStableArchivedProbe -First $a -Second $b) | Should -BeTrue
  }
  It 'optional size difference detected across reads' {
     $f=New-BW4k7nFake; $a=Get-BW4k7nFakeProbe $f; $f.PA.Map["0x0E080003"]=[int]9958; $b=Get-BW4k7nFakeProbe $f; {Assert-OPA265BW4k7nStableArchivedProbe -First $a -Second $b} | Should -Throw
  }
  It 'optional availability drift detected' {
     $f=New-BW4k7nFake; $a=Get-BW4k7nFakeProbe $f; [void]$f.PA.Map.Remove("0x0E080014"); $b=Get-BW4k7nFakeProbe $f; {Assert-OPA265BW4k7nStableArchivedProbe -First $a -Second $b} | Should -Throw
  }
  It 'timestamp drift between reads detected' {
     $f=New-BW4k7nFake; $a=Get-BW4k7nFakeProbe $f; $f.PA.Map["0x30080040"]=[datetime]"2026-11-03T11:00:00Z"; $b=Get-BW4k7nFakeProbe $f; {Assert-OPA265BW4k7nStableArchivedProbe -First $a -Second $b} | Should -Throw
  }
  It 'forged writer permit invalidates stable observations' {
     $f=New-BW4k7nFake; $a=Get-BW4k7nFakeProbe $f; $b=Get-BW4k7nFakeProbe $f; $b.WriterPermit=$true; {Assert-OPA265BW4k7nStableArchivedProbe -First $a -Second $b} | Should -Throw
  }
  It 'two original and fresh flag deltas are identical' {
     $r=Get-BW4k7nResult; $r.ExactFlagDeltaReproducedAcrossTwoFixtures | Should -BeTrue; $r.HistoricalBW4k7gChangedMaskHex | Should -BeExactly "0x00010002"; $r.NewBW4k7mChangedMaskHex | Should -BeExactly "0x00010002"
  }
  It 'documented 0x2 and unknown 0x10000 reported separately' {
     $r=Get-BW4k7nResult; $r.KnownMfUnmodified0x00000002Changed | Should -BeTrue; $r.Unknown0x00010000Changed | Should -BeTrue; $r.RawFlag0x00010000MeaningEstablished | Should -BeFalse
  }
  It 'never conflates store support mask HTML flag' {
    (Get-BW4k7nResult).CrossPropertyStoreHtmlOkEquivalenceAssumed | Should -BeFalse
  }
  It 'separate PR_MESSAGE_STATUS zero both times' {
     $r=Get-BW4k7nResult; $r.PrMessageStatusBeforeMove | Should -Be 0; $r.PrMessageStatusAfterMove | Should -Be 0; $r.PrMessageStatusUnchanged | Should -BeTrue
  }
  It 'size delta exactly negative 532 bytes' {
     $r=Get-BW4k7nResult; $r.MailItemSizeDeltaBytes | Should -Be -532; $r.SizeDifferenceReproducedAfterOutlookRestart | Should -BeTrue
  }
  It 'does not invent original PR_MESSAGE_SIZE before Move' {
     $r=Get-BW4k7nResult; $r.OriginalPrMessageSizeCapturedBeforeMove | Should -BeFalse; $r.OriginalPrMessageSizeExtendedCapturedBeforeMove | Should -BeFalse
  }
  It 'does not claim causation for size delta' {
    (Get-BW4k7nResult).PropertySpecificSizeDeltaCauseProven | Should -BeFalse
  }
  It 'current PR_MESSAGE_SIZE equal to destination MailItem.Size' {
     $r=Get-BW4k7nResult; $r.PrMessageSizePresent | Should -BeTrue; $r.PrMessageSizeBytes | Should -Be 9957; $r.PrMessageSizeMatchesDestinationMailItemSize | Should -BeTrue
  }
  It 'current PR_MESSAGE_SIZE discrepancy still needs investigation' {
     $f=New-BW4k7nFake; $f.PA.Map["0x0E080003"]=[int]9999; $r=Get-BW4k7nResult $f; $r.PrMessageSizeMatchesDestinationMailItemSize | Should -BeFalse; $r.ProductionReady | Should -BeFalse
  }
  It '64-bit optional property is independently evaluated' {
     $r=Get-BW4k7nResult; $r.PrMessageSizeExtendedPresent | Should -BeTrue; $r.PrMessageSizeExtendedBytes | Should -Be 9957; $r.PrMessageSizeExtendedMatchesDestinationMailItemSize | Should -BeTrue
  }
  It 'missing optional size leaves comparison null' {
     $f=New-BW4k7nFake; [void]$f.PA.Map.Remove("0x0E080003"); $r=Get-BW4k7nResult $f; $r.PrMessageSizePresent | Should -BeFalse; $null -eq $r.PrMessageSizeMatchesDestinationMailItemSize | Should -BeTrue
  }
  It 'no production permit or waiver even when content identical' {
     $r=Get-BW4k7nResult; $r.ProductionReady | Should -BeFalse; $r.WriterPermit | Should -BeFalse; $r.ProviderFlagWaiver | Should -BeFalse; $r.AutomaticRetryAllowed | Should -BeFalse
  }
  It 'rejected wrong original Claim SHA' {
     $a=New-BW4k7nAudit; $a.VerifiedOriginalIrreversibleClaimSha256=("0"*64); {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected wrong original Evidence SHA' {
     $a=New-BW4k7nAudit; $a.VerifiedOriginalEvidenceSha256=("0"*64); {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected wrong archived EntryID audit' {
     $a=New-BW4k7nAudit; $a.DestinationEntryId=("0"*48); {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected source-one/destination-zero alternate case' {
     $a=New-BW4k7nAudit; $a.SourceMessageIdMatches=1; $a.DestinationMessageIdMatches=0; {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected altered semantic content' {
     $a=New-BW4k7nAudit; $a.FullSemanticContentMatch=$false; $a.SemanticFieldMismatchCount=1; {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected changed flag XOR audit' {
     $a=New-BW4k7nAudit; $a.ChangedMaskHex="0x00000002"; {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected changed PR_MESSAGE_STATUS audit' {
     $a=New-BW4k7nAudit; $a.PrMessageStatusEqual=$false; {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected changed diagnostic destination size' {
     $a=New-BW4k7nAudit; $a.DestinationDiagnosticMessageSize=9956; {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'rejected forged production readiness' {
     $a=New-BW4k7nAudit; $a.ProductionReady=$true; {Get-BW4k7nResult $null $a} | Should -Throw
  }
  It 'controller invokes original independent audit before probe' {
     $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "../../Core/Diagnostics/Invoke-OPA265BW4k7nReadOnlyProviderInvestigation.ps1"); $s | Should -Match "Invoke-OPA265BW4k7mIndependentPostMoveAudit"; $s | Should -Match "Get-OPA265BW4k7nArchivedProbe"
  }
  It 'controller cannot write, Move or Save' {
     $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "../../Core/Diagnostics/Invoke-OPA265BW4k7nReadOnlyProviderInvestigation.ps1"); $s | Should -Not -Match "(?i)\.(Move|Save|Delete|Send|SetProperty)\s*\("; $s | Should -Not -Match "Write-OPA265BW4k7mClaimOnce"
  }
  It 'controller offers WhatIf with no Outlook access' {
     $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "../../Core/Diagnostics/Invoke-OPA265BW4k7nReadOnlyProviderInvestigation.ps1"); $s | Should -Match "WhatIfNoOutlookReadNoPstOrEvidenceWrite"; $s | Should -Match "IndependentProcessRestartComparisonAvailable"
  }
}
