#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourcePst,
      [Parameter(Mandatory=$true)][string]$ProfileName)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop' -or [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA'){throw 'Windows PowerShell 5.1 STA required.'}
$source=[IO.Path]::GetFullPath($SourcePst)
$app=$null;$ns=$null;$root=$null;$items=$null
try{
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -ine $ProfileName){throw 'Profile mismatch.'}
    $accounts=@($ns.Accounts | Where-Object {[int]$_.AccountType -eq 2 -and [string]$_.DeliveryStore.FilePath -ieq $source})
    if($accounts.Count -ne 1){throw 'Exactly one POP3 delivery account required.'}
    $store=$accounts[0].DeliveryStore
    $root=$store.GetRootFolder()
    $items=$root.Items
    $count=[int]$items.Count
    $classes=@{}
    for($i=1;$i -le $count;$i++){
        $item=$null
        try{
            $item=$items.Item($i)
            $class=[int]$item.Class
            if(-not $classes.ContainsKey($class)){$classes[$class]=0}
            $classes[$class]++
        }finally{
            if($null -ne $item -and [Runtime.InteropServices.Marshal]::IsComObject($item)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($item)}
        }
    }
    if([int]$items.Count -ne $count){throw 'Root count changed during read-only observation.'}
    [pscustomobject]@{Schema='2.6.5-ARCH6.RootInventory.1';SourcePst=$source;RootPath=[string]$root.FolderPath;TotalItems=$count;MailItems=[int]$classes[43];Classes=@($classes.GetEnumerator() | Sort-Object Name | ForEach-Object {[pscustomobject]@{Class=$_.Key;Count=$_.Value}});RootArchiveEnabled=$false;ReadOnly=$true}
}finally{
    foreach($o in @($items,$root,$ns,$app)){if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)}}
}
