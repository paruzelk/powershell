#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4fFreshFixtureScope265.ps1')
    $script:fixtureId='98bef817-0fb5-478a-b869-33f02fda59d3'
    $script:subject="OPA265 BW4e1 FRESH TEST $script:fixtureId"
    $script:body="OPA265 BW4e1 disposable synthetic test.`n`nTestId: $script:fixtureId`n`nThis message contains no customer data.`nCreated exclusively for read-only Outlook/MAPI verification.`nNo historical operation or journal may be reused."
}
Describe 'BW4f2 strict read-only fixture identification across Outlook POP3 Body line endings' {
    It 'accepts original LF synthetic body with exactly one canonical GUID' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:body -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts ordinary Outlook CRLF' {
        $v=$script:body.Replace("`n","`r`n")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts Outlook duplicated-CR + LF on receipt (CRCRLF)' {
        $v=$script:body.Replace("`n","`r`r`n")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts classic Outlook plain-text CR-only' {
        $v=$script:body.Replace("`n","`r")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts Outlook mixed CRCRLF, CRLF, CR, LF without changing characters' {
        $v=$script:body
        $line=0
        $v=[regex]::Replace($v,"\n", {param($m)
            $line++
            if($line % 4 -eq 0){return "`r`r`n"}
            if($line % 3 -eq 0){return "`r`n"}
            if($line % 2 -eq 0){return "`r"}
            return "`n"
        })
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'does not mutate the supplied source Body or use lossy text conversion' {
        $v=$script:body.Replace("`n","`r`r`n")
        $original=$v
        $null=Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0
        $v | Should -BeExactly $original
        $v.Contains("`r`r`n") | Should -BeTrue
    }
    It 'rejects a customer message with different subject' {
        (Get-OPA265BW4fFixtureTag -Subject 'Invoice' -Body $script:body.Replace("`n","`r`r`n") -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects changed fixture header even with tolerated separators' {
        $v=$script:body.Replace('disposable synthetic test.','real correspondence.').Replace("`n","`r`r`n")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects a body TestId different from subject GUID' {
        $v=$script:body.Replace($script:fixtureId,'49bf59da-6d84-4e36-8b6d-0d9857b8eed1').Replace("`n","`r")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects duplicate TestId lines after normalization' {
        $v=$script:body.Replace("`n","`r`r`n")+"`rTestId: $script:fixtureId"
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects malformed TestId with extra trailing text' {
        $v=$script:body.Replace("TestId: $script:fixtureId","TestId: $script:fixtureId UNKNOWN").Replace("`n","`r")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects leading whitespace before exact fixture header' {
        $v=' '+$script:body.Replace("`n","`r")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects any attachments even when Outlook supplies CRCRLF' {
        $v=$script:body.Replace("`n","`r`r`n")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 1).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects unknown attachments count rather than assuming zero' {
        $v=$script:body.Replace("`n","`r`r`n")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects zero GUID in both subject and body' {
        $zero=[guid]::Empty.ToString('D')
        $sub=$script:subject.Replace($script:fixtureId,$zero)
        $body=$script:body.Replace($script:fixtureId,$zero).Replace("`n","`r`r`n")
        (Get-OPA265BW4fFixtureTag -Subject $sub -Body $body -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
}
