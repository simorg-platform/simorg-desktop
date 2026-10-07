# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Simorg Desktop's hand-over to its next version on Windows; desktop-handover.sh
# is the same on macOS and Linux, and the two say the same things in the same
# order.
#
# Simorg Desktop is installed on Windows by its .msi, for the person and under
# their own Programs folder, and it is updated the same way: the new version's
# installer upgrades the old one in place, which keeps Apps and Features, the
# Start menu and the PATH entry the installer added all true. Windows cannot
# replace a program that is running, so the app writes this into the folder it
# staged the installer in, starts it on its own, and closes. This waits for it
# to be gone, runs the installer, and opens the new version. The new version
# writes "started" in the hand-over note as it opens; if it has not within
# started_within seconds, the note says so.
#
# Unlike macOS and Linux, nothing is put back when the new version does not
# start: the installer has already replaced the old one, as an installer does,
# and the note says how to repair it.
#
#   powershell -File desktop-handover.ps1 -Staging DIR
#
# DIR holds handover.json (app_pid, parent, app_exe, installer, note, from, to,
# started_within, reopen) and the installer. With reopen false, which is the
# update with no window (`update desktop --json`), nothing is opened and the note says "finished" once
# the installer is done.

param(
    [Parameter(Mandatory = $true)][string]$Staging
)

$ErrorActionPreference = 'Stop'
$Settings = Get-Content -Raw -LiteralPath (Join-Path $Staging 'handover.json') | ConvertFrom-Json
$Parent = $Settings.parent
$Log = Join-Path $Staging 'handover.log'

function Write-Log([string]$Text) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Add-Content -LiteralPath $Log -Value "$stamp $Text"
}

# The note, written whole and moved into place so a reader never sees half of it.
function Write-Note([string]$State, [string]$Reason) {
    $note = [ordered]@{
        state  = $State
        from   = $Settings.from
        to     = $Settings.to
        reason = $Reason
        at     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $temporary = "$($Settings.note).$PID"
    # Without a byte-order mark, which Windows PowerShell's own UTF8 adds and a JSON reader refuses.
    [IO.File]::WriteAllText($temporary, ($note | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $temporary -Destination $Settings.note -Force
    # What happened, where the version that opens next reads it.
    Copy-Item -LiteralPath $Log -Destination ([IO.Path]::ChangeExtension($Settings.note, '.log')) -Force -ErrorAction SilentlyContinue
}

function Open-Version {
    Start-Process -FilePath (Join-Path $Parent $Settings.app_exe) -WorkingDirectory $Parent
}

function Get-RunningFromInstall {
    $prefix = $Parent.TrimEnd('\') + '\'
    return @(Get-Process | Where-Object {
            $_.Id -ne $PID -and $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
        })
}

function Stop-Handover([int]$Code) {
    Set-Location -LiteralPath $env:TEMP
    [Environment]::CurrentDirectory = $env:TEMP
    Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
    exit $Code
}

$From = $Settings.from
$To = $Settings.to
Write-Log "handing Simorg Desktop $From over to $To in $Parent"

$waited = 0
while (Get-Process -Id $Settings.app_pid -ErrorAction SilentlyContinue) {
    if ($waited -ge 600) {
        Write-Log "the app (pid $($Settings.app_pid)) did not close"
        Write-Note 'failed' "Simorg Desktop $From did not close within a minute, so the update was not installed."
        Stop-Handover 1
    }
    Start-Sleep -Milliseconds 100
    $waited++
}
# Its helpers, such as the web engine's, end with it; a few seconds at most.
$waited = 0
while ($waited -lt 50 -and (Get-RunningFromInstall).Count -gt 0) {
    Start-Sleep -Milliseconds 200
    $waited++
}

# The installer with its own progress bar and no Cancel button, for the person, so no password is asked:
# /qb! is the basic interface without Cancel, and nothing restarts the computer.
Write-Log "installing $To"
$msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
$installerLog = Join-Path $Staging 'installer.log'
try {
    $process = Start-Process -FilePath $msiexec -Wait -PassThru -ArgumentList @(
        '/i', "`"$($Settings.installer)`"", '/qb!', '/norestart', '/l*v', "`"$installerLog`"")
    $code = $process.ExitCode
} catch {
    Write-Log "the installer did not start: $($_.Exception.Message)"
    $code = -1
}
Write-Log "the installer ended with $code"
if ($code -ne 0 -and $code -ne 3010) {
    # Windows Installer's own record of what it did, for the row's "What happened".
    Get-Content -LiteralPath $installerLog -Tail 40 -ErrorAction SilentlyContinue | Add-Content -LiteralPath $Log
    if ($code -eq 1602) {
        Write-Note 'failed' "The installer was closed before it finished, so Simorg Desktop $From is still installed."
    } else {
        Write-Note 'failed' "Simorg Desktop $To could not be installed, so $From is still installed. What happened is below."
    }
    if ($Settings.reopen) { Open-Version }
    Stop-Handover 1
}

if (-not $Settings.reopen) {
    Write-Log "$To is in place"
    Write-Note 'finished' ''
    Stop-Handover 0
}

Write-Log "opening $To"
Open-Version
$waited = 0
while ($waited -lt ($Settings.started_within * 5)) {
    $text = Get-Content -Raw -LiteralPath $Settings.note -ErrorAction SilentlyContinue
    if ($text -and $text.Contains('"state":"started"')) {
        Write-Log "$To started"
        Remove-Item -LiteralPath $Settings.note -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ([IO.Path]::ChangeExtension($Settings.note, '.log')) -Force -ErrorAction SilentlyContinue
        Stop-Handover 0
    }
    Start-Sleep -Milliseconds 200
    $waited++
}

Write-Log "$To did not say it started within $($Settings.started_within) seconds"
Write-Note 'failed' "Simorg Desktop $To was installed but did not open within $($Settings.started_within) seconds. Open it from the Start menu, and if it still does not open, download it again from its page to repair it."
Stop-Handover 1
