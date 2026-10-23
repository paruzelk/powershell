#requires -Version 5.1
<#
.SYNOPSIS
    Review or create a byte-verified backup of an existing POP3 PST.
.DESCRIPTION
    Preview by default. Requires -CreateBackup and a fixed approval token
    to make a COPY of the PST while Outlook is fully closed. Never changes
    source PST, moves mail, starts Outlook or overwrites existing backups.
.EXAMPLE
    .\New-OPA264ExistingPstBackup.ps1 -SourcePst 'C:\Test\source.pst' -BackupPst 'D:\PstBackup\source-pre-live-tests.pst' -Review
.EXAMPLE
    .\New-OPA264ExistingPstBackup.ps1 -SourcePst 'C:\Test\source.pst' -BackupPst 'D:\PstBackup\source-pre-live-tests.pst' -CreateBackup -ApprovalToken BACKUP-OPA264-EXISTING-PST
#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$BackupPst,
    [switch]$Review,
    [switch]$CreateBackup,
    [string]$ApprovalToken=''
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Worker/ExistingPstBackupGuard.ps1')

if (-not ($Review -xor $CreateBackup)) {
    throw 'Specify exactly one mode: -Review (no writes) OR -CreateBackup.'
}
if ($CreateBackup -and $ApprovalToken -cne 'BACKUP-OPA264-EXISTING-PST') {
    throw 'Creating a backup requires the exact -ApprovalToken BACKUP-OPA264-EXISTING-PST.'
}
if (-not $CreateBackup -and $ApprovalToken) {
    throw 'ApprovalToken is not accepted in read-only review mode.'
}
$plan=Get-OPA264ExistingPstBackupPlan -SourcePst $SourcePst -BackupPst $BackupPst
if ($Review) {
    Write-Output $plan
    return
}
if (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Close ALL Outlook processes before copying an open PST.'
}
if (-not $PSCmdlet.ShouldProcess($plan.BackupPst,
        ('Create a byte-verified COPY of '+$plan.SourcePst))) { return }
# Revalidate after human approval. Never reuse a source-to-destination
# pair that someone has modified during an interactive prompt.
$plan=Get-OPA264ExistingPstBackupPlan -SourcePst $SourcePst -BackupPst $BackupPst
if (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Outlook started before backup copy; refusing.'
}
$sourceStream=$null
$targetStream=$null
try {
    $sourceStream=[IO.FileStream]::new($plan.SourcePst,
        [IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    if ($sourceStream.Length -ne $plan.SourceSizeBytes) {
        throw 'Source PST length changed after backup preflight.'
    }
    $targetStream=[IO.FileStream]::new($plan.IncompletePath,
        [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer=New-Object byte[] (1MB)
    while ($true) {
        $count=$sourceStream.Read($buffer,0,$buffer.Length)
        if ($count -le 0) { break }
        $targetStream.Write($buffer,0,$count)
    }
    $targetStream.Flush($true)
}
finally {
    if ($null -ne $targetStream) { $targetStream.Dispose() }
    if ($null -ne $sourceStream) { $sourceStream.Dispose() }
}
if (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Outlook appeared during copy. Partial file preserved; no valid backup published.'
}
$sourceSize=(Get-Item -LiteralPath $plan.SourcePst -Force).Length
$partialSize=(Get-Item -LiteralPath $plan.IncompletePath -Force).Length
if ($sourceSize -ne $plan.SourceSizeBytes -or $partialSize -ne $plan.SourceSizeBytes) {
    throw 'Source/backup lengths differ. Partial copy preserved; not promoted.'
}
$sourceHash=(Get-FileHash -LiteralPath $plan.SourcePst -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
$partialHash=(Get-FileHash -LiteralPath $plan.IncompletePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
if ($sourceHash -cne $partialHash) {
    throw 'SHA256 mismatch. Partial file preserved; not promoted to backup.'
}
if ([IO.File]::Exists($plan.BackupPst)) {
    throw 'Backup destination appeared during validation; never overwrite.'
}
if (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Outlook started during verification. No backup was promoted.'
}
# Same-directory rename of verified .partial PST to the explicitly
# approved backup name; does not change or reattach the source file.
[IO.File]::Move($plan.IncompletePath,$plan.BackupPst)
Write-Output ([pscustomobject]@{
    Status='BackupCopySHA256Verified'
    SourcePst=$plan.SourcePst
    BackupPst=$plan.BackupPst
    SizeBytes=[long]$plan.SourceSizeBytes
    SHA256=$sourceHash
    OriginalPstModified=$false
    MailMoveExecuted=$false
    ExistingPstMutationAllowed=$false
    Note='A byte-identical backup copy is not a proven functional Outlook restore. Test restore independently before any live PST mutation.'
})
