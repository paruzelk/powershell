#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vDisposablePstManifest265.ps1')
    $script:suiteId='7cc9b0f2-6c17-4f6b-9b2b-1db6d07a14b1'
    $script:layout=Get-OPA265BW4k7vLayout -SuiteId $script:suiteId -LocalAppData $env:LOCALAPPDATA
    $script:fixture=Get-OPA265BW4k7vFixtureExpectations -SuiteId $script:suiteId
    $records=New-Object 'System.Collections.Generic.List[object]'
    foreach($x in $script:fixture.FixtureItems){
        $records.Add([pscustomobject]@{
            CaseId=$x.CaseId;Name=$x.Name
            Subject=(Get-OPA265BW4k7vExpectedSubject -Item $x)
            Role=$x.Role;SourceFolderPath=$x.SourceFolderPath
            SyntheticArchiveYear=[int]$x.Year
            Class=43;MessageClass='IPM.Note'
            EntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
            FolderEntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
            StoreId='SYNTHETIC-STORE-ONLY'
            WitnessSha256=('a'*64)
        })
    }
    $script:record=[pscustomobject]@{
        Schema='2.6.5-BW4k7v.ImmutableFreshDisposablePreMove.1'
        SuiteId=$script:suiteId
        SourcePst=$script:layout.SourcePst
        FixtureRootFolderName=$script:layout.FixtureRootFolderName
        OutlookProfile='Outlook'
        SourcePstStoreId='SYNTHETIC-STORE-ONLY'
        RootFolderEntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
        SyntheticSuiteManifestSha256=$script:fixture.SuiteManifestSha256
        CreatingOutlookProcessId=1234
        CreatingOutlookProcessStartUtcTicks=639000000000000000L
        FixtureCount=8
        Items=@($records.ToArray())
        OnlySyntheticItemsCreated=$true
        OutlookMoveExecuted=$false;OutlookSendExecuted=$false
        ProductionPstOrMailboxModified=$false
        DurableMoveIntentOrClaimCreated=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
Describe 'BW4k7v fresh isolated Outlook PST plan, original 8 synthetic preMove manifest, and fail-closed approval' {
    It 'requires canonical lowercase fresh GUID' {
        {Assert-OPA265BW4k7vSuiteId -SuiteId 'NOT-GUID'} | Should -Throw
    }
    It 'forbids historic fixture id' {
        {Assert-OPA265BW4k7vSuiteId -SuiteId 'd1a68868-acf5-4c70-860d-5521e1ce2836'} | Should -Throw
    }
    It 'rejects all-zero suite id' {
        {Assert-OPA265BW4k7vSuiteId -SuiteId '00000000-0000-0000-0000-000000000000'} | Should -Throw
    }
    It 'rejects uppercase GUID' {
        {Assert-OPA265BW4k7vSuiteId -SuiteId $script:suiteId.ToUpperInvariant()} | Should -Throw
    }
    It 'accepts fresh canonical GUID' {
        (Assert-OPA265BW4k7vSuiteId -SuiteId $script:suiteId) | Should -BeTrue
    }
    It 'generates separate local path' {
        $script:layout.SourcePst | Should -Match 'OutlookPOP3Archive-BW4k7v-Isolated'
    }
    It 'new PST path contains exact suite ID' {
        $script:layout.SourcePst | Should -Match $script:suiteId
    }
    It 'new PST extension is pst' {
        [IO.Path]::GetExtension($script:layout.SourcePst) | Should -BeExactly '.pst'
    }
    It 'new PST filename starts fixed prefix' {
        [IO.Path]::GetFileName($script:layout.SourcePst) | Should -BeExactly ('OPA265-BW4k7v-'+$script:suiteId+'.pst')
    }
    It 'new manifest filename fixed' {
        [IO.Path]::GetFileName($script:layout.ManifestPath) | Should -BeExactly 'premovereadonly-manifest.json'
    }
    It 'new root folder name contains suite ID' {
        $script:layout.FixtureRootFolderName | Should -BeExactly ('OPA265-BW4k7v-'+$script:suiteId)
    }
    It 'layout never accepts production PST path' {
        $script:layout.ProductionPstPathAccepted | Should -BeFalse
    }
    It 'layout writer disabled' {
        $script:layout.WriterPermit | Should -BeFalse
    }
    It 'layout no production' {
        $script:layout.ProductionReady | Should -BeFalse
    }
    It 'does not accept UNC folder for local fixture' {
        {Get-OPA265BW4k7vLayout -SuiteId $script:suiteId -LocalAppData '\\share\test'} | Should -Throw
    }
    It 'does not accept relative folder for local fixture' {
        {Get-OPA265BW4k7vLayout -SuiteId $script:suiteId -LocalAppData 'Downloads'} | Should -Throw
    }
    It 'first class fixture count exactly eight' {
        $script:fixture.ExpectedCount | Should -Be 8
    }
    It 'fixture list eight ordinary Mail' {
        @($script:fixture.FixtureItems | Where-Object {$_.Kind -ne 'Mail'}).Count | Should -Be 0
    }
    It 'fixture has two Sent folder objects' {
        @($script:fixture.FixtureItems | Where-Object {$_.Role -eq 'SentItems'}).Count | Should -Be 2
    }
    It 'fixture has two user folder objects' {
        @($script:fixture.FixtureItems | Where-Object {$_.Role -eq 'UserMail'}).Count | Should -Be 2
    }
    It 'fixture has four Inbox objects' {
        @($script:fixture.FixtureItems | Where-Object {$_.Role -eq 'Inbox'}).Count | Should -Be 4
    }
    It 'fixture does not include three nonmail objects' {
        @($script:fixture.FixtureItems | Where-Object {$_.Class -ne 43}).Count | Should -Be 0
    }
    It 'fixture does not include 2026 mail' {
        @($script:fixture.FixtureItems | Where-Object {$_.Year -eq 2026}).Count | Should -Be 0
    }
    It 'explicit synthetic years not actual MAPI dates' {
        $script:fixture.RealMapiMessageDatesProven | Should -BeFalse
    }
    It 'generated Sent folder not genuine sent mail' {
        $script:fixture.GenuineSentItemsMessagesProven | Should -BeFalse
    }
    It 'no Move or Send in fixtures' {
        $script:fixture.NoOutlookMoveOrSend | Should -BeTrue
    }
    It 'manifest schema exact' {
        $script:record.Schema | Should -BeExactly '2.6.5-BW4k7v.ImmutableFreshDisposablePreMove.1'
    }
    It 'valid fabricated immutable manifest passes pure shape' {
        (Assert-OPA265BW4k7vManifestShape -Manifest $script:record -Layout $script:layout) | Should -BeTrue
    }
    It 'rejects wrong original source PST' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.SourcePst='C:\production.pst'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects wrong Outlook profile' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.OutlookProfile='Other'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects wrong initial suite manifest sha' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.SyntheticSuiteManifestSha256='0'*64; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects missing mail object' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items=@($m.Items[0..6]); {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects duplicate mail CaseId' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[1].CaseId=$m.Items[0].CaseId; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects altered synthetic year metadata' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].SyntheticArchiveYear=1999; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects changed subject' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].Subject='not synthetic'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects changed original relative folder' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].SourceFolderPath='\Else'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects changed role from Sent Items' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[4].Role='Inbox'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects alternate MAPI class' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].Class=46; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects altered MessageClass' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].MessageClass='IPM.Schedule.Meeting.Request'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects missing item entry ID' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].EntryId=''; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects missing original folder entry ID' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].FolderEntryId=''; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects wrongly bound store ID' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].StoreId='other'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects invalid witness SHA' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.Items[0].WitnessSha256='not-sha256'; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects forged creation process ticks' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.CreatingOutlookProcessStartUtcTicks=0; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects false synthetic-only flag' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.OnlySyntheticItemsCreated=$false; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects fabricated Move executed flag' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.OutlookMoveExecuted=$true; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects fabricated Send executed flag' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.OutlookSendExecuted=$true; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects production PST modification flag' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.ProductionPstOrMailboxModified=$true; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects fixture granting writer permission' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.WriterPermit=$true; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'rejects fixture claiming production readiness' {
        $m=Copy-OPA265BW4k7uObject -Value $script:record; $m.ProductionReady=$true; {Assert-OPA265BW4k7vManifestShape -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'guarded evidence file uses CreateNew not overwrite' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vDisposablePstManifest265.ps1'); $s | Should -Match 'FileMode]::CreateNew'
    }
    It 'guarded evidence file calls Flush(true)' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vDisposablePstManifest265.ps1'); $s | Should -Match 'Flush\(\$true\)'
    }
    It 'guarded evidence requires same original SHA to Verify' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vDisposablePstManifest265.ps1'); $s | Should -Match 'pre-Move manifest file changed'
    }
    It 'Outlook creation uses folder Items.Add only' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vOutlookFixtureCapture265.ps1'); $s | Should -Match 'Folder.Items.Add'
    }
    It 'Outlook creation never Application.CreateItem' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vOutlookFixtureCapture265.ps1'); $s | Should -Not -Match 'Application.CreateItem\s*\('
    }
    It 'Outlook code never calls Move Send Delete' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vOutlookFixtureCapture265.ps1'); $s | Should -Not -Match '[.](Move|Send|Delete)[ ]*[(]'
    }
    It 'controller never calls Move Send Delete' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Not -Match '[.](Move|Send|Delete)[ ]*[(]'
    }
    It 'controller requires exact creation approval' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Match 'CREATE NEW BW4K7V PST'
    }
    It 'controller requires independent restarted Outlook' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Match 'CreatingOutlookProcessStartUtcTicks'
    }
    It 'controller creates a Unicode PST only in separate directory' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Match 'AddStoreEx'
    }
    It 'controller never grants production' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Match 'ProductionReady=\$false'
    }
    It 'controller reads each original fixture twice' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Match '\$mailOne='; $s | Should -Match '\$mailTwo='
    }
    It 'controller only creates eight mail test fixtures' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Match 'CreatedFixtureCount=8'
    }
    It 'controller tags year synthetically not MAPI date' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7vFreshDisposablePstPreflight.ps1'); $s | Should -Match 'ArchiveYearIsSyntheticTagNotActualMapiDate'
    }
}
