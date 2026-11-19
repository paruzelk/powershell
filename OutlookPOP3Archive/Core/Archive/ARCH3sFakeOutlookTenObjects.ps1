#requires -Version 5.1
# ARCH3s fake Outlook objects, complete ORIGINAL ARCH2b MailItem semantics.
# No real COM, PST creation or Move. Attachments saved only to original
# ARCH2c2 private TEMP workspace when the ORIGINAL verifier reads them.
. (Join-Path $PSScriptRoot 'ARCH3rTenItemSyntheticIntegration.ps1')
. (Join-Path $PSScriptRoot 'ArchiveSelector.ps1')
. (Join-Path $PSScriptRoot 'ArchiveVerifier.ps1')

function New-OPA265ARCH3sFakeCollection {
    param([object[]]$Records=@())
    $o=[pscustomobject]@{Count=[int]$Records.Count;Records=[object[]]$Records}
    $o | Add-Member -MemberType ScriptMethod -Name Item -Value {
        param($i)
        if($i -lt 1 -or $i -gt $this.Count){throw 'ARCH3s fake Items.Item out of range.'}
        return $this.Records[([int]$i-1)]
    }
    return $o
}

function New-OPA265ARCH3sFakeMail {
    param([Parameter(Mandatory=$true)][ValidateRange(1,10)][int]$Number,
          [Parameter(Mandatory=$true)][string]$EntryId,
          [Parameter(Mandatory=$true)][object]$Parent)
    $recipient=[pscustomobject]@{Type=1;Name='Synthetic Recipient';Address='to@example.invalid'}
    $rec=New-OPA265ARCH3sFakeCollection -Records @($recipient)
    $attachments=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le ($Number % 3);$i++){
        [byte[]]$data=[Text.Encoding]::UTF8.GetBytes(('SYNTHETIC ONLY: payload '+$Number+'/'+$i))
        $att=[pscustomobject]@{
            Type=1;FileName=('synthetic-{0}-{1}.bin' -f $Number,$i)
            Size=[int64]$data.Length;Payload=$data
        }
        $att | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param([string]$Path)
            [IO.File]::WriteAllBytes($Path,[byte[]]$this.Payload)
        }
        [void]$attachments.Add($att)
    }
    $acc=[pscustomobject]@{Value=('<arch3r-synth-'+$Number+'@invalid>')}
    $acc | Add-Member -MemberType ScriptMethod -Name GetProperty -Value {
        param([string]$Tag)
        if($Tag -in @('http://schemas.microsoft.com/mapi/proptag/0x1035001E',
                     'http://schemas.microsoft.com/mapi/proptag/0x1035001F')){
            return [string]$this.Value
        }
        throw 'ARCH3s fake MAPI property unsupported.'
    }
    $date=[datetime]::new(2020,2,1,12,0,0,[DateTimeKind]::Utc).AddDays($Number)
    return [pscustomobject]@{
        Class=43;EntryID=$EntryId;Parent=$Parent
        Subject=('ARCH3r synthetic '+$Number)
        SenderEmailAddress='synthetic@example.invalid'
        To='to@example.invalid';CC='';BCC=''
        Body=('ARCH3r full virtual Body for synthetic mail '+$Number)
        HTMLBody=('<html><body><p>ARCH3r synthetic '+$Number+'</p></body></html>')
        ReceivedTime=$date;SentOn=$date.AddHours(-2)
        UnRead=[bool]($Number % 2 -eq 0);Importance=1;Sensitivity=0
        Categories='synthetic';Recipients=$rec
        Attachments=(New-OPA265ARCH3sFakeCollection -Records $attachments.ToArray())
        PropertyAccessor=$acc;Size=[int64](2048+$Number+38)
    }
}

function New-OPA265ARCH3sFakeOutlook {
    [CmdletBinding()]
    param([ValidateSet('None','SourceStillPresent','DestinationMissing','ExtraDestination',
        'HtmlDrift','BodyDrift','RecipientDrift','AttachmentDrift','MissingOriginalWitness',
        'DuplicateSourceSelector','DuplicateArchiveSelector','WrongTargetFolder',
        'StaleArchiveIdUnique','StaleArchiveIdAmbiguous')][string]$VerifierFault='None',
        [ValidateRange(1,10)][int]$FaultAt=4,
        [Parameter(Mandatory=$true)][string]$Workspace)
    $plan=@(New-OPA265ARCH3rTenSyntheticPlan)
    $pst=Join-Path $Workspace 'ARCH3s-FAKE-NOT-A-REAL-PST.pst'
    $source=[pscustomobject]@{Name='Входящие';FolderPath='\\SYNTHETIC-POP3\Входящие';Folders=@()}
    $target=[pscustomobject]@{Name='Входящие';FolderPath='\\SYNTHETIC-ARCHIVE\2020\Входящие';Folders=@()}
    $year=[pscustomobject]@{Name='2020';FolderPath='\\SYNTHETIC-ARCHIVE\2020';Folders=@($target)}
    $root=[pscustomobject]@{Name='SYNTHETIC-ARCHIVE';FolderPath='\\SYNTHETIC-ARCHIVE';Folders=@($year)}
    $out=New-Object 'System.Collections.Generic.List[object]'
    $src=New-Object 'System.Collections.Generic.List[object]'
    $moves=New-Object 'System.Collections.Generic.List[object]'
    $map=@{}
    for($i=1;$i -le 10;$i++){
        $row=$plan[$i-1]
        $mail=New-OPA265ARCH3sFakeMail -Number $i -EntryId ([string]$row.ArchiveEntryId) -Parent $target
        if($i -eq $FaultAt){
            switch($VerifierFault){
                'HtmlDrift' {$mail.HTMLBody += ' SYNTHETIC HTML DRIFT'}
                'BodyDrift' {$mail.Body += ' SYNTHETIC BODY DRIFT'}
                'RecipientDrift' {$mail.Recipients.Records[0].Address='changed@example.invalid'}
                'AttachmentDrift' {
                    if($mail.Attachments.Count -eq 0){throw 'ARCH3s AttachmentDrift requires an attachment at FaultAt.'}
                    $mail.Attachments.Records[0].Payload[0]=[byte]70
                }
                'SourceStillPresent' {
                    [void]$src.Add([pscustomobject]@{Class=43;EntryID=[string]$row.SourceEntryId})
                }
            }
        }
        if(-not($VerifierFault -eq 'DestinationMissing' -and $i -eq $FaultAt)){
            [void]$out.Add($mail)
            $map[[string]$mail.EntryID]=$mail
        }
        $archiveId=[string]$row.ArchiveEntryId
        if($VerifierFault -in @('StaleArchiveIdUnique','StaleArchiveIdAmbiguous') -and $i -eq $FaultAt){
            $archiveId=('F'*32)
        }
        if($VerifierFault -eq 'DuplicateArchiveSelector' -and $i -eq $FaultAt){
            $archiveId=[string]$plan[0].ArchiveEntryId
        }
        $sourceId=[string]$row.SourceEntryId
        if($VerifierFault -eq 'DuplicateSourceSelector' -and $i -eq $FaultAt){
            $sourceId=[string]$plan[0].SourceEntryId
        }
        $path=[string]$row.TargetFolderPath
        if($VerifierFault -eq 'WrongTargetFolder' -and $i -eq $FaultAt){
            $path='\\SYNTHETIC-ARCHIVE\2020\Wrong'
        }
        $w=$row.SourceWitness
        if($VerifierFault -eq 'MissingOriginalWitness' -and $i -eq $FaultAt){$w=$null}
        [void]$moves.Add([pscustomobject]@{
            SourceEntryId=$sourceId;ArchiveEntryId=$archiveId
            SourceFolderPath=[string]$row.SourceFolderPath
            TargetFolderPath=$path;ArchivePst=$pst
            Subject=[string]$row.Subject;Sender='synthetic@example.invalid'
            InternetMessageId=('<arch3r-synth-'+$i+'@invalid>')
            Size=$null;SourceSemanticWitness=$w
        })
        if($VerifierFault -eq 'StaleArchiveIdAmbiguous' -and $i -eq $FaultAt){
            [void]$out.Add((New-OPA265ARCH3sFakeMail -Number $i -EntryId ('E'*32) -Parent $target))
        }
    }
    if($VerifierFault -eq 'ExtraDestination'){
        [void]$out.Add((New-OPA265ARCH3sFakeMail -Number 4 -EntryId ('D'*32) -Parent $target))
    }
    $source | Add-Member -MemberType NoteProperty -Name Items -Value (New-OPA265ARCH3sFakeCollection -Records $src.ToArray())
    $target | Add-Member -MemberType NoteProperty -Name Items -Value (New-OPA265ARCH3sFakeCollection -Records $out.ToArray())
    $store=[pscustomobject]@{StoreID='ARCH3s-FAKE-STORE';FilePath=$pst;Root=$root}
    $store | Add-Member -MemberType ScriptMethod -Name GetRootFolder -Value {return $this.Root}
    $ns=[pscustomobject]@{StoreID='ARCH3s-FAKE-STORE';Map=$map}
    $ns | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
        param([string]$EntryId,[string]$StoreID)
        if($StoreID -cne [string]$this.StoreID){throw 'ARCH3s fake archive store differs.'}
        if($this.Map.ContainsKey($EntryId)){return $this.Map[$EntryId]}
        return $null
    }
    return [pscustomobject]@{
        Namespace=$ns;SourceFolder=$source;TargetFolder=$target
        ArchiveStore=$store;ArchivePst=$pst;ExpectedMoves=$moves.ToArray()
        SyntheticOnly=$true
    }
}
