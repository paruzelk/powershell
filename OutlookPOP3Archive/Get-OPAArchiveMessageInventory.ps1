#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourcePst,
      [Parameter(Mandatory=$true)][string]$ProfileName)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop' -or [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA'){throw 'Windows PowerShell 5.1 STA required.'}
function Release-InventoryCom {
    param($Object)
    if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object)}
}
function Add-InventoryCount {
    param([hashtable]$Table,[string]$Key)
    if(-not $Table.ContainsKey($Key)){$Table[$Key]=0L}
    $Table[$Key]++
}
function Read-InventoryFolder {
    param($Folder,[hashtable]$Stats)
    $items=$null;$children=$null
    try{
        $path=[string]$Folder.FolderPath
        $items=$Folder.Items
        $count=[int]$items.Count
        $Stats.Folders++
        for($i=1;$i -le $count;$i++){
            $item=$null;$attachments=$null;$recipients=$null
            try{
                $item=$items.Item($i)
                if($null -eq $item){throw 'Item unavailable.'}
                $class=[int]$item.Class
                $messageClass=[string]$item.MessageClass
                Add-InventoryCount -Table $Stats.Classes -Key ([string]$class)
                Add-InventoryCount -Table $Stats.MessageClasses -Key $messageClass
                $Stats.Items++
                $reasons=New-Object 'System.Collections.Generic.List[string]'
                $year='Unknown'
                if($class -eq 43){
                    try{$year=([datetime]$item.ReceivedTime).Year.ToString()}catch{}
                    $attachments=$item.Attachments
                    $ac=[int]$attachments.Count
                    if($ac -gt 128){$reasons.Add('AttachmentCountUnsupported')}
                    $recipients=$item.Recipients
                    if([int]$recipients.Count -gt 2048){$reasons.Add('RecipientCountUnsupported')}
                    if($messageClass -match 'SMIME|RPMSG|Secure'){ $reasons.Add('ProtectedMessageClass') }
                    for($j=1;$j -le $ac;$j++){
                        $attachment=$null
                        try{
                            $attachment=$attachments.Item($j)
                            $type=[int]$attachment.Type
                            Add-InventoryCount -Table $Stats.AttachmentTypes -Key ([string]$type)
                            if($type -ne 1){$reasons.Add(('AttachmentType='+$type))}
                            if([long]$attachment.Size -gt 1GB -or [long]$attachment.Size -lt 0){$reasons.Add('AttachmentSizeUnsupported')}
                            if(([string]$attachment.FileName).Length -gt 1024){$reasons.Add('AttachmentNameUnsupported')}
                        }finally{Release-InventoryCom $attachment}
                    }
                }else{$reasons.Add('NonMailItem')}
                if($reasons.Count -gt 0){
                    foreach($reason in @($reasons | Select-Object -Unique)){Add-InventoryCount -Table $Stats.Risks -Key $reason;Add-InventoryCount -Table $Stats.RiskByYear -Key ($year+' '+$reason)}
                    $Stats.Details.Add([pscustomobject]@{Folder=$path;EntryId=[string]$item.EntryID;Class=$class;MessageClass=$messageClass;Year=$year;Reasons=(@($reasons | Select-Object -Unique) -join '; ')})
                }
            }catch{
                $Stats.Errors.Add([pscustomobject]@{Folder=$path;Index=$i;Message=$_.Exception.Message})
            }finally{Release-InventoryCom $recipients;Release-InventoryCom $attachments;Release-InventoryCom $item}
        }
        if([int]$items.Count -ne $count){$Stats.Errors.Add([pscustomobject]@{Folder=$path;Index=0;Message='Item count changed during scan.'})}
        $children=$Folder.Folders
        $childCount=[int]$children.Count
        for($k=1;$k -le $childCount;$k++){
            $child=$null
            try{$child=$children.Item($k);Read-InventoryFolder -Folder $child -Stats $Stats}finally{Release-InventoryCom $child}
        }
        if([int]$children.Count -ne $childCount){$Stats.Errors.Add([pscustomobject]@{Folder=$path;Index=0;Message='Folder count changed during scan.'})}
    }finally{Release-InventoryCom $children;Release-InventoryCom $items}
}
$source=[IO.Path]::GetFullPath($SourcePst)
$app=$null;$ns=$null;$root=$null;$store=$null
try{
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -ine $ProfileName){throw 'Profile mismatch.'}
    $accounts=@($ns.Accounts | Where-Object {[int]$_.AccountType -eq 2 -and [string]$_.DeliveryStore.FilePath -ieq $source})
    if($accounts.Count -ne 1){throw 'Exactly one POP3 delivery account required.'}
    $store=$accounts[0].DeliveryStore
    $root=$store.GetRootFolder()
    $stats=@{Folders=0;Items=0L;Classes=@{};MessageClasses=@{};AttachmentTypes=@{};Risks=@{};RiskByYear=@{};Details=(New-Object 'System.Collections.Generic.List[object]');Errors=(New-Object 'System.Collections.Generic.List[object]')}
    Read-InventoryFolder -Folder $root -Stats $stats
    [pscustomobject]@{Schema='2.6.5-ARCH6f3a.MessageInventory.1';SourcePst=$source;Folders=$stats.Folders;Items=$stats.Items;Classes=$stats.Classes;MessageClasses=$stats.MessageClasses;AttachmentTypes=$stats.AttachmentTypes;Risks=$stats.Risks;RiskByYear=$stats.RiskByYear;Details=$stats.Details.ToArray();Errors=$stats.Errors.ToArray();Complete=($stats.Errors.Count -eq 0);MetadataOnly=$true;ReadOnly=$true}
}finally{Release-InventoryCom $root;Release-InventoryCom $store;Release-InventoryCom $ns;Release-InventoryCom $app}
