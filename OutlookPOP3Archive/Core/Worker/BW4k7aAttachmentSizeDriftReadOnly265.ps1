#requires -Version 5.1
# BW4k7a: synth-only fixed original Attachment1K non-size witness comparison.
# This function DIAGNOSES a source MailItem.Size mismatch; it never accepts it.
. (Join-Path $PSScriptRoot 'BW4k7Attachment1KEvidence265.ps1')

function Compare-OPA265BW4k7aSourceWitnessReadOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Original,
        [Parameter(Mandatory=$true)][psobject]$Current,
        [Parameter(Mandatory=$true)][psobject]$Case,
        [Parameter(Mandatory=$true)][string]$SuiteId
    )
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       [string]$Case.TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       [string]$Case.Name -cne 'Attachment1K'){
        throw 'BW4k7a only original fixed Attachment1K test fixture allowed.'
    }
    [void](Assert-OPA265BW4jWitness -Witness $Original -Case $Case -SuiteId $SuiteId)
    [void](Assert-OPA265BW4jWitness -Witness $Current -Case $Case -SuiteId $SuiteId)

    $fields=@('Schema','SuiteId','CaseName','TestId','ProfileName','EntryId',
        'FolderEntryId','StoreId','InternetMessageId','SearchKeySha256',
        'SubjectUtf8Sha256','SenderUtf8Sha256','BodyUtf8Sha256',
        'HtmlBodyUtf8Sha256','SubjectLength','BodyLength','HtmlBodyLength',
        'ReceivedUtcTicks','OutlookMoveExecuted','ProductionReady')
    $mismatches=New-Object 'System.Collections.Generic.List[string]'
    foreach($field in $fields){
        if([string]$Original.$field -cne [string]$Current.$field){
            $mismatches.Add($field)
        }
    }
    $before=@($Original.Attachments);$after=@($Current.Attachments)
    if($before.Count -ne 1 -or $after.Count -ne 1){
        $mismatches.Add('AttachmentCount')
    }else{
        foreach($field in @('Index','FileName','ByteCount','Sha256')){
            if([string]$before[0].$field -cne [string]$after[0].$field){
                $mismatches.Add(('Attachment.'+$field))
            }
        }
    }
    $aSize=[long]$Original.Size
    $bSize=[long]$Current.Size
    $change=$bSize-$aSize
    $onlySizeChanged=($mismatches.Count -eq 0 -and $change -ne 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7a.Attachment1KReadOnlySourceSizeDriftComparison.1'
        SuiteId=$SuiteId
        TestId=[string]$Case.TestId
        CaseName='Attachment1K'
        Status=if($mismatches.Count -gt 0){'STOP_OtherWitnessFieldDrift'}elseif($onlySizeChanged){'OnlySourceMailItemSizeDriftUnapproved'}else{'NoCurrentSourceWitnessDrift'}
        OriginalSize=$aSize
        CurrentSize=$bSize
        DeltaSize=$change
        OtherFieldMismatchCount=[int]$mismatches.Count
        OtherFieldMismatchNames=@($mismatches.ToArray())
        AttachmentCount=[int]$after.Count
        OriginalAttachmentByteCount=[long]$before[0].ByteCount
        CurrentAttachmentByteCount=[long]$after[0].ByteCount
        OriginalAttachmentSha256=[string]$before[0].Sha256
        CurrentAttachmentSha256=[string]$after[0].Sha256
        AttachmentByteExactMatch=[bool]($before.Count -eq 1 -and $after.Count -eq 1 -and
            [long]$before[0].ByteCount -eq [long]$after[0].ByteCount -and
            [string]$before[0].Sha256 -ceq [string]$after[0].Sha256 -and
            [string]$before[0].FileName -ceq [string]$after[0].FileName)
        OnlySizeDrift=[bool]$onlySizeChanged
        SizeDriftAccepted=$false
        ClaimWritten=$false
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
}
