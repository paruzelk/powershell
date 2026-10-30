#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4fFreshFixtureScope265.ps1')
    $script:id='98bef817-0fb5-478a-b869-33f02fda59d3'
    $script:subject="OPA265 BW4e1 FRESH TEST $script:id"
    $script:header='OPA265 BW4e1 disposable synthetic test.'
    $script:idLine="TestId: $script:id"
    $script:body=$script:header+"`n`n"+$script:idLine+"`n`n"+
        "This message contains no customer data.`n"+
        "Created exclusively for read-only Outlook/MAPI verification.`n"+
        "No historical operation or journal may be reused.`n"
    $script:bothSpaced=$script:body.Replace($script:header,$script:header+' ').
        Replace($script:idLine,$script:idLine+' ')
}
Describe 'BW4f3 exact ONE Outlook-added U+0020 trailing space on fixture markers' {
    It 'accepts all nonempty lines ending with one ASCII space, Outlook CRLF' {
        $v=$script:bothSpaced.Replace("`n","`r`n")
        $r=Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0
        $r.IsExactOperatorFixture | Should -BeTrue
        $r.TestId | Should -BeExactly $script:id
    }
    It 'accepts exactly one trailing space with plain LF' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:bothSpaced -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts exactly one trailing space with Outlook CRCRLF' {
        $v=$script:bothSpaced.Replace("`n","`r`r`n")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts exactly one trailing space with CR-only' {
        $v=$script:bothSpaced.Replace("`n","`r")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts trailing one space on header only' {
        $v=$script:body.Replace($script:header,$script:header+' ')
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'accepts trailing one space on TestId only' {
        $v=$script:body.Replace($script:idLine,$script:idLine+' ')
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'retains recognition of original precise markers with zero trailing spaces' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:body -AttachmentCount 0).IsExactOperatorFixture | Should -BeTrue
    }
    It 'rejects two trailing spaces in fixture header' {
        $v=$script:body.Replace($script:header,$script:header+'  ')
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects two trailing spaces after TestId GUID' {
        $v=$script:body.Replace($script:idLine,$script:idLine+'  ')
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects trailing tab in fixture header' {
        $v=$script:body.Replace($script:header,$script:header+"`t")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects trailing tab after TestId GUID' {
        $v=$script:body.Replace($script:idLine,$script:idLine+"`t")
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects nonbreaking space on fixture header' {
        $v=$script:body.Replace($script:header,($script:header+[char]0xA0))
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects nonbreaking space after TestId GUID' {
        $v=$script:body.Replace($script:idLine,($script:idLine+[char]0xA0))
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects a different Body GUID even with the accepted single space' {
        $v=$script:bothSpaced.Replace($script:id,'49bf59da-6d84-4e36-8b6d-0d9857b8eed1')
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects two TestId lines, both padded one space' {
        $v=$script:bothSpaced+$script:idLine+" `n"
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $v -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects a real customer subject despite matching Body marker shape' {
        (Get-OPA265BW4fFixtureTag -Subject 'Invoice and files' -Body $script:bothSpaced -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects any attachments even for correctly spaced fixture' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:bothSpaced -AttachmentCount 1).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects missing Outlook Attachments collection rather than treating it as zero' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:bothSpaced).IsExactOperatorFixture | Should -BeFalse
    }
    It 'never mutates the original Body or silently changes raw content SHA input' {
        $original=$script:bothSpaced.Replace("`n","`r`n")
        $before=[Text.Encoding]::Unicode.GetBytes($original)
        $sha=[Security.Cryptography.SHA256]::Create()
        try {
            $hashBefore=[BitConverter]::ToString($sha.ComputeHash($before))
            $null=Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $original -AttachmentCount 0
            $hashAfter=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::Unicode.GetBytes($original)))
            $hashAfter | Should -BeExactly $hashBefore
        } finally {
            $sha.Dispose()
        }
    }
};
