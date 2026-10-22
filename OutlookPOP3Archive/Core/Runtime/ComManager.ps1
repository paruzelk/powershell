$script:OPAStoreCache = @{}

function Release-OPAComObject {
    <#
    .SYNOPSIS
        Safe ReleaseComObject for transient Outlook RCWs. Arrays are released
        element-wise. Errors are swallowed by design (finalizer safety net).
    #>
    param([AllowNull()][object]$Object)

    if ($null -eq $Object) { return }
    if ($Object -is [System.Array]) {
        foreach ($o in $Object) { Release-OPAComObject -Object $o }
        return
    }
    try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object) } catch {}
}

function Get-OpaStoreByPathCached {
    <#
    .SYNOPSIS
        Finds a Store by file path, caching per session. Enumerating
        $Namespace.Stores creates a new RCW set on every call; destination
        selection runs this for every message, so the cache matters.
        Cached RCWs are revalidated; a dead wrapper (Outlook restarted)
        evicts itself.
    #>
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][string]$Path
    )

    try { $target = [IO.Path]::GetFullPath($Path) } catch { return $null }

    if ($script:OPAStoreCache.ContainsKey($target)) {
        $cached = $script:OPAStoreCache[$target]
        try { [void][string]$cached.FilePath; return $cached }
        catch { $script:OPAStoreCache.Remove($target) }
    }

    $found = $null
    foreach ($store in @($Namespace.Stores)) {
        try {
            $fp = [string]$store.FilePath
            if ([string]::IsNullOrWhiteSpace($fp)) { Release-OPAComObject -Object $store; continue }
            $full = [IO.Path]::GetFullPath($fp)
            if ($full -ieq $target) { $found = $store; continue }
            if ($script:OPAStoreCache.ContainsKey($full)) { Release-OPAComObject -Object $store }
            else { $script:OPAStoreCache[$full] = $store }
        }
        catch { Release-OPAComObject -Object $store }
    }

    if ($null -ne $found) {
        if (-not $script:OPAStoreCache.ContainsKey($target)) { $script:OPAStoreCache[$target] = $found }
        return $script:OPAStoreCache[$target]
    }
    return $null
}

function Clear-OpaStoreCache {
    $script:OPAStoreCache = @{}
    # EntryIDs can change after a store is reopened in the same session.
    # Invalidate the well-known folder cache along with the store cache.
    if (Get-Command Clear-OPAWellKnownFolderCache -ErrorAction SilentlyContinue) {
        Clear-OPAWellKnownFolderCache
    }
}

function New-OPAComSession {
    [CmdletBinding()]
    param([string]$ProfileName)

    $outlook = $null
    $namespace = $null
    $attached = $false

    try {
        try {
            $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject("Outlook.Application")
            $attached = $true
        }
        catch {
            $outlook = New-Object -ComObject Outlook.Application
            $attached = $false
        }

        if ($null -eq $outlook) { throw "Unable to create or attach to Outlook.Application." }

        $namespace = $outlook.GetNamespace("MAPI")
        if ($null -eq $namespace) { throw "Outlook MAPI namespace is unavailable." }

        $currentProfile = ''
        try { $currentProfile = [string]$namespace.CurrentProfileName } catch {}

        if ($attached) {
            # Outlook supports only one MAPI session per running Outlook
            # process. Never attempt to switch a live user's profile.
            if (-not [string]::IsNullOrWhiteSpace($ProfileName) -and
                -not [string]::IsNullOrWhiteSpace($currentProfile) -and
                $ProfileName -ine $currentProfile) {
                throw "Outlook is already running under profile '$currentProfile'. Requested profile '$ProfileName' cannot be switched in the existing Outlook session."
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
            $namespace.Logon($ProfileName, $null, $false, $true)
            $currentProfile = [string]$namespace.CurrentProfileName
            if ([string]::IsNullOrWhiteSpace($currentProfile) -or $currentProfile -ine $ProfileName) {
                throw "Requested Outlook profile '$ProfileName' was not activated. Current MAPI profile is '$currentProfile'."
            }
        }

        [pscustomobject]@{
            Outlook     = $outlook
            Namespace   = $namespace
            Attached    = $attached
            ProfileName = $currentProfile
        }
    }
    catch {
        if ($namespace) { Release-OPAComObject -Object $namespace }
        if ($outlook)   { Release-OPAComObject -Object $outlook }
        throw
    }
}

function Close-OPAComSession {
    [CmdletBinding()]
    param([object]$Session)

    # Flush and close any long-lived step journal FileStreams before the
    # session teardown. Function is defined in ArchiveTransaction.ps1 and is
    # resolved at call time (PowerShell late binding), so load order is fine.
    if (Get-Command Close-OPADuplicateJournalStreams -ErrorAction SilentlyContinue) {
        Close-OPADuplicateJournalStreams
    }
    if (Get-Command Close-OPAStepJournalStreams -ErrorAction SilentlyContinue) {
        Close-OPAStepJournalStreams
    }

    if ($script:OPAStoreCache.Count -gt 0) {
        foreach ($k in @($script:OPAStoreCache.Keys)) { Release-OPAComObject -Object $script:OPAStoreCache[$k] }
        $script:OPAStoreCache = @{}
    }

    if ($null -eq $Session) { return }

    if ($Session.Namespace) { Release-OPAComObject -Object $Session.Namespace }
    if ($Session.Outlook)   { Release-OPAComObject -Object $Session.Outlook }
}
