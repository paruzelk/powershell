#requires -Version 5.1
BeforeAll {
 . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7gPostMoveSemanticReadOnly265.ps1')
 function New-BW4k7gSyntheticWitness {
  param([long]$Size=8122)
  [pscustomobject][ordered]@{
   Schema='2.6.5-BW4j.MultiFormatMailWitness.1'
   SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
   CaseName='Attachment1K'
   TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
   ProfileName='Outlook'
   EntryId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
   FolderEntryId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
   StoreId='FAKE-POP3-STORE'
   InternetMessageId='<opa@example.test>'
   SearchKeySha256=('a'*64)
   SubjectUtf8Sha256=('b'*64)
   SenderUtf8Sha256=('c'*64)
   BodyUtf8Sha256=('d'*64)
   HtmlBodyUtf8Sha256=('e'*64)
   SubjectLength=35;BodyLength=55;HtmlBodyLength=78
   Size=$Size
   ReceivedUtcTicks=[long]637000000000000000
   Attachments=@([pscustomobject][ordered]@{
    Index=1;FileName='test.bin';ByteCount=[long]1024
    Sha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
   })
   OutlookMoveExecuted=$false;ProductionReady=$false
  }
 }
 function New-BW4k7gSyntheticCase {
  [pscustomobject]@{
   TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
   Name='Attachment1K';ExpectedAttachmentCount=1;MinimumAttachmentBytes=1024
  }
 }
 function New-BW4k7gClaim {
  New-OPA265BW4k7gAttemptClaim -SourcePst 'C:\syntheticSource.pst' -DestinationPst 'C:\syntheticDest.pst' -SourceStoreId 'SRC' -DestinationStoreId 'DST' -InternetMessageId '<opa@example.test>'
 }
 function New-BW4k7gDestSemantics {
  [pscustomobject][ordered]@{
   Schema='2.6.5-BW4k7g.DestinationRecipientsStateReadOnly.1'
   DestinationEntryId='TARGET'
   RecipientCount=1;ToCount=1;CcCount=0;BccCount=0
   RecipientDigestSha256='11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024'
   UserStateDigestSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
   UnRead=$false;MapiFlags=65555;ReadHasAttachBits=17
   AttachmentCount=1;OutlookMoveExecuted=$false;ProductionReady=$false
  }
 }
}
Describe 'BW4k7g SEM-001 exact original content with only signed +512 source-size drift' {
 BeforeEach {
  $script:original=New-BW4k7gSyntheticWitness -Size 8122
  $script:current=New-BW4k7gSyntheticWitness -Size 8634
  $script:case=New-BW4k7gSyntheticCase
  $script:opts=@{
   Original=$script:original;Current=$script:current;Case=$script:case
   SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
  }
 }
 It 'allows exact 8122 to 8634 +512 without global Size waiver' {
  (Assert-OPA265BW4k7gPinnedSourceContent @opts) | Should -BeTrue
 }
 It 'blocks changed source Size other than exactly 8634' {
  $script:current.Size=8635
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*Size*'
 }
 It 'blocks changed original Size' {
  $script:original.Size=8121
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*Size*'
 }
 It 'blocks changed original Body SHA256' {
  $script:current.BodyUtf8Sha256=('0'*64)
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*semantic field*'
 }
 It 'blocks changed HTML SHA256' {
  $script:current.HtmlBodyUtf8Sha256=('0'*64)
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*semantic field*'
 }
 It 'blocks changed received date' {
  $script:current.ReceivedUtcTicks=[long]637000000000000001
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*semantic field*'
 }
 It 'blocks changed SearchKey' {
  $script:current.SearchKeySha256=('f'*64)
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*semantic field*'
 }
 It 'blocks changed source EntryID' {
  $script:current.EntryId='different'
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw
 }
 It 'blocks changed attachment SHA256' {
  $script:current.Attachments[0].Sha256=('0'*64)
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*attachment*'
 }
 It 'blocks changed attachment filename' {
  $script:current.Attachments[0].FileName='other.bin'
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*attachment*'
 }
 It 'blocks changed attachment length' {
  $script:current.Attachments[0].ByteCount=1025
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw '*attachment*'
 }
 It 'blocks missing by-value attachment' {
  $script:current.Attachments=@()
  {Assert-OPA265BW4k7gPinnedSourceContent @opts} | Should -Throw
 }
}
Describe 'BW4k7g irreversible original one-shot Claim in universally fenced BW4k1 path' {
 BeforeEach {
  $script:claim=New-BW4k7gClaim
  $script:root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  [void][IO.Directory]::CreateDirectory($script:root)
 }
 It 'builds exactly pinned durable Claim before any Move' {
  (Assert-OPA265BW4k7gClaim -Claim $script:claim) | Should -BeTrue
 }
 It 'stores exact prior immutable +512 decision and recipient/state SHA' {
  $script:claim.ManualSourceSizeDecisionSha256 | Should -BeExactly '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6'
  $script:claim.ImmutableRecipientStateSnapshotSha256 | Should -BeExactly 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
 }
 It 'rejects new execution permit in Claim schema' {
  $script:claim | Add-Member -NotePropertyName CanRetry -NotePropertyValue $true
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*schema*'
 }
 It 'rejects different destination Folder EntryID' {
  $script:claim.DestinationFolderEntryId='DIFFERENT'
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*claim altered*'
 }
 It 'rejects a modified semantic snapshot SHA' {
  $script:claim.ImmutableRecipientStateSnapshotSha256=('0'*64)
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*claim altered*'
 }
 It 'rejects invalid source store SHA' {
  $script:claim.SourceStoreIdSha256='fake'
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*store digest*'
 }
 It 'rejects identical source and destination store' {
  $script:claim.DestinationStoreIdSha256=$script:claim.SourceStoreIdSha256
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*store or message*'
 }
 It 'rejects enabled automatic retry' {
  $script:claim.AutomaticRetryAllowed=$true
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*forbidden claim*'
 }
 It 'rejects historical journal writer capability' {
  $script:claim.HistoricalJournalWriteAllowed=$true
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*forbidden claim*'
 }
 It 'rejects missing explicit attempt time' {
  $script:claim.AttemptUtc='not-time'
  {Assert-OPA265BW4k7gClaim -Claim $script:claim} | Should -Throw '*attempt time*'
 }
 It 'writes UTF8 BOM Claim in exact BW4k1 path once' {
  $w=Write-OPA265BW4k7gClaimOnce -Claim $script:claim -LocalAppData $script:root
  $w.ClaimSha256 | Should -Match '^[a-f0-9]{64}$'
  $w.ClaimPath | Should -Match 'BW4k1-Claims'
  $bytes=[IO.File]::ReadAllBytes($w.ClaimPath)
  (@($bytes[0],$bytes[1],$bytes[2]) -join ',') | Should -BeExactly '239,187,191'
 }
 It 'rejects duplicate irreversible Claim and never overwrites it' {
  $w=Write-OPA265BW4k7gClaimOnce -Claim $script:claim -LocalAppData $script:root
  {Write-OPA265BW4k7gClaimOnce -Claim $script:claim -LocalAppData $script:root} | Should -Throw
  (Get-FileHash -LiteralPath $w.ClaimPath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $w.ClaimSha256
 }
 It 'independently reads original immutable Claim after writing' {
  $w=Write-OPA265BW4k7gClaimOnce -Claim $script:claim -LocalAppData $script:root
  $v=Read-OPA265BW4k7gClaimVerified -ExpectedClaimSha256 $w.ClaimSha256 -LocalAppData $script:root
  $v.Schema | Should -BeExactly '2.6.5-BW4k7g.OneIrreversibleAttachment1KMoveClaim.1'
 }
 It 'rejects changed Claim SHA after writing' {
  $null=Write-OPA265BW4k7gClaimOnce -Claim $script:claim -LocalAppData $script:root
  {Read-OPA265BW4k7gClaimVerified -ExpectedClaimSha256 ('0'*64) -LocalAppData $script:root} | Should -Throw '*NEVER RETRY*'
 }
}
Describe 'BW4k7g post-Move destination semantic independent witness guards' {
 BeforeEach {$script:a=New-BW4k7gDestSemantics}
 It 'accepts two stable destination semantic snapshots' {
  (Assert-OPA265BW4k7gStableDestSemantics -First $script:a -Second (New-BW4k7gDestSemantics)) | Should -BeTrue
 }
 It 'blocks changed recipient digest between audits' {
  $b=New-BW4k7gDestSemantics;$b.RecipientDigestSha256=('f'*64)
  {Assert-OPA265BW4k7gStableDestSemantics -First $script:a -Second $b} | Should -Throw '*second read drift*'
 }
 It 'blocks changed user-state SHA between audits' {
  $b=New-BW4k7gDestSemantics;$b.UserStateDigestSha256=('f'*64)
  {Assert-OPA265BW4k7gStableDestSemantics -First $script:a -Second $b} | Should -Throw '*second read drift*'
 }
 It 'blocks destination semantic witness forged Move' {
  $script:a.OutlookMoveExecuted=$true
  {Assert-OPA265BW4k7gStableDestSemantics -First $script:a -Second (New-BW4k7gDestSemantics)} | Should -Throw '*invalid double*'
 }
 It 'blocks unexpected extra destination witness property' {
  $script:a | Add-Member -NotePropertyName WriterPermit -NotePropertyValue $true
  {Assert-OPA265BW4k7gStableDestSemantics -First $script:a -Second (New-BW4k7gDestSemantics)} | Should -Throw '*invalid double*'
 }
}
Describe 'BW4k7g controller source writer boundaries and read-only audit contract' {
 BeforeAll {
  $script:execScript=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7gOneShotAttachmentMove.ps1') -Raw -Encoding UTF8
  $script:auditScript=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7gPostMoveReadOnly.ps1') -Raw -Encoding UTF8
 }
 It 'has exactly one MailItem.Move in executable source' {
  @([regex]::Matches($script:execScript,'\$mail\.Move\s*\(')).Count | Should -Be 1
 }
 It 'writes Claim before the exact one MailItem.Move' {
  $claimAt=$script:execScript.IndexOf('Write-OPA265BW4k7gClaimOnce')
  $moveAt=$script:execScript.IndexOf('$mail.Move(')
  $claimAt | Should -BeGreaterThan 0
  $moveAt | Should -BeGreaterThan $claimAt
 }
 It 'routes through prior read-only BW4k7f full preflight' {
  $script:execScript | Should -Match 'Invoke-OPA265BW4k7fEmptyTargetReview'
 }
 It 'requires the pinned destination folder EntryID and exact approval' {
  $script:execScript | Should -Match '00000000D3E190022DF61241BBDE594AD46A661B82800000'
  $script:execScript | Should -Match 'MOVE EXACT ONE BW4K7G ATTACHMENT1K DISPOSABLE MAIL'
 }
 It 'WhatIf and Review branch before Claim write and Move' {
  $script:execScript | Should -Match '\$Mode -ceq ''Review'' -or \$dry'
  $script:execScript | Should -Match 'WhatIfNoClaimNoMove'
 }
 It 'postmove script never invokes MailItem.Move or Claim writer' {
  $script:auditScript | Should -Not -Match '\$mail\.Move\s*\('
  $script:auditScript | Should -Not -Match 'Write-OPA265BW4k7gClaimOnce'
  $script:auditScript | Should -Match 'Get-OPA265BW4k7gDestinationSemantic'
 }
 It 'postmove script enforces source-zero/destination-one' {
  $script:auditScript | Should -Match 'sourceMatches.Count -ne 0'
  $script:auditScript | Should -Match 'targetMatches.Count -ne 1'
  $script:auditScript | Should -Match 'AttachmentBytesAndSha256Match'
 }
 It 'postmove script never declares PST durability or production proof' {
  $script:auditScript | Should -Match 'PhysicalPstDurabilityProven=\$false'
  $script:auditScript | Should -Match 'ProductionReady=\$false'
 }
}
