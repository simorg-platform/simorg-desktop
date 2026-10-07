#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Simorg Desktop's hand-over to its next version on macOS and Linux.
#
# An app cannot replace its own files while it runs, so the app writes this
# script into the folder it staged the new version in, starts it on its own, and
# closes. This waits for it to be gone, moves the old copy aside and the new one
# into its place — the app bundle on macOS, the AppImage on Linux — and opens the
# new version. The new
# version writes "started" in the hand-over note as it opens; if it has not within
# STARTED_WITHIN seconds, this puts the old version back, opens that instead, and
# says why in the note. Whichever version opens reads the note.
#
#   desktop-handover.sh STAGING            the hand-over, as the person
#   desktop-handover.sh --swap STAGING     the move alone, under the password prompt
#   desktop-handover.sh --restore STAGING  putting the old version back, likewise
#
# STAGING holds handover.env (the variables below, each quoted by the app),
# entries (one top-level name per line), new/ (the new version, taken out of its
# disk image or AppImage) and, when
# the install's folder needs an administrator, swap-elevated.sh and
# restore-elevated.sh, which run this under the operating system's prompt.
#
#   APP_PID         the app that is closing
#   PARENT          the folder the entries live in
#   APP_ENTRY       what the app runs from: its bundle on macOS, its AppImage on Linux
#   NOTE            the hand-over note
#   FROM, TO        the versions
#   SYSTEM          macos or linux
#   STARTED_WITHIN  seconds the new version has to say it started
#   ELEVATE         1 when PARENT needs an administrator to change
#   REOPEN          1 to open the new version and put the old one back if it does
#                   not start; 0 for the update with no window, which opens nothing
#                   and is told "finished" once the move is done
#   OWNER           uid:gid of the person, who gets the old copy back to delete

set -u

MODE=run
case "${1:-}" in
    --swap) MODE=swap; shift ;;
    --restore) MODE=restore; shift ;;
esac
STAGING="${1:?the staging folder}"
. "$STAGING/handover.env"
LOG="$STAGING/handover.log"
if [ "$MODE" = run ]; then exec >>"$LOG" 2>&1; fi

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# A name this may move: one path segment, never the folder itself or its parent.
valid_entry() {
    case "$1" in
        ''|.|..|*/*) return 1 ;;
    esac
    return 0
}

exists() { [ -e "$1" ] || [ -L "$1" ]; }

# Every entry aside and its new one in. Stops at the first failure and says so;
# restore() undoes whatever got that far.
swap() {
    mkdir -p "$STAGING/previous" || return 1
    : >"$STAGING/owners"
    while IFS= read -r entry; do
        valid_entry "$entry" || continue
        if exists "$PARENT/$entry"; then
            printf '%s %s\n' "$(ls -nd "$PARENT/$entry" | awk '{print $3 ":" $4}')" "$entry" >>"$STAGING/owners"
            mv "$PARENT/$entry" "$STAGING/previous/$entry" || return 1
        fi
        mv "$STAGING/new/$entry" "$PARENT/$entry" || return 1
    done <"$STAGING/entries"
    return 0
}

# The old version back where it was, and anything the new one added taken out.
restore() {
    status=0
    while IFS= read -r entry; do
        valid_entry "$entry" || continue
        if exists "$STAGING/previous/$entry"; then
            if exists "$PARENT/$entry"; then rm -rf "${PARENT:?}/$entry" || status=1; fi
            mv "$STAGING/previous/$entry" "$PARENT/$entry" || status=1
        elif ! exists "$STAGING/new/$entry" && exists "$PARENT/$entry"; then
            rm -rf "${PARENT:?}/$entry" || status=1
        fi
    done <"$STAGING/entries"
    return $status
}

if [ "$MODE" = swap ]; then
    if ! swap; then
        restore
        exit 1
    fi
    # The old copy goes back to the person, who deletes it once the new one has opened.
    chown -R "$OWNER" "$STAGING/previous" 2>/dev/null
    exit 0
fi

if [ "$MODE" = restore ]; then
    restore
    status=$?
    # What was root's is root's again.
    while IFS=' ' read -r owner entry; do
        valid_entry "$entry" || continue
        exists "$PARENT/$entry" && chown -R "$owner" "$PARENT/$entry" 2>/dev/null
    done <"$STAGING/owners"
    exit $status
fi

# ---- The hand-over, as the person -----------------------------------------------

# The note, written whole and moved into place so a reader never sees half of it.
note() {
    tmp="$NOTE.$$"
    printf '{"state":"%s","from":"%s","to":"%s","reason":"%s","at":"%s"}\n' \
        "$1" "$FROM" "$TO" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$tmp" && mv -f "$tmp" "$NOTE"
    # What happened, where the version that opens next reads it.
    cp "$LOG" "${NOTE%.json}.log" 2>/dev/null
}

open_version() {
    if [ "$SYSTEM" = macos ]; then
        /usr/bin/open "$PARENT/$APP_ENTRY"
    elif command -v setsid >/dev/null 2>&1; then
        setsid "$PARENT/$APP_ENTRY" >/dev/null 2>&1 </dev/null &
    else
        nohup "$PARENT/$APP_ENTRY" >/dev/null 2>&1 </dev/null &
    fi
}

# What a running copy's command line holds: a path inside the bundle on macOS,
# and on Linux the AppImage itself, which its runtime process is started as.
if [ "$SYSTEM" = macos ]; then RUNNING="$PARENT/$APP_ENTRY/"; else RUNNING="$PARENT/$APP_ENTRY"; fi

running_from_entry() { pgrep -f "$RUNNING" >/dev/null 2>&1; }

finish() {
    rm -rf "$STAGING"
    exit "$1"
}

log "handing Simorg Desktop $FROM over to $TO in $PARENT"

# A pid of 0 would be this script's own process group, which is always there.
waited=0
while [ "$APP_PID" -gt 0 ] 2>/dev/null && kill -0 "$APP_PID" 2>/dev/null; do
    if [ "$waited" -ge 600 ]; then
        log "the app (pid $APP_PID) did not close"
        note failed "Simorg Desktop $FROM did not close within a minute, so the update was not installed."
        finish 1
    fi
    sleep 0.1
    waited=$((waited + 1))
done
# Its helpers, such as the web engine's, end with it; a few seconds at most.
waited=0
while [ "$REOPEN" = 1 ] && [ "$waited" -lt 50 ] && running_from_entry; do
    sleep 0.2
    waited=$((waited + 1))
done

output=""
if [ "$ELEVATE" = 1 ]; then
    log "moving it into place under the password prompt"
    output="$(/bin/sh "$STAGING/swap-elevated.sh" 2>&1)"
    status=$?
    printf '%s\n' "$output"
else
    swap
    status=$?
    [ "$status" -eq 0 ] || restore
fi
if [ "$status" -ne 0 ]; then
    log "the move did not finish ($status)"
    case "$status:$output" in
        126:*|*"(-128)"*)
            note failed "The password prompt was closed, so Simorg Desktop $FROM is still installed. Simorg asks for it because the folder it is in belongs to every user of this computer." ;;
        *)
            note failed "Simorg Desktop $TO could not be moved into place, so $FROM is still installed. What happened is below." ;;
    esac
    [ "$REOPEN" = 1 ] && open_version
    finish 1
fi

if [ "$REOPEN" != 1 ]; then
    log "$TO is in place"
    note finished ""
    finish 0
fi

log "opening $TO"
open_version
waited=0
while [ "$waited" -lt $((STARTED_WITHIN * 5)) ]; do
    if grep -q '"state":"started"' "$NOTE" 2>/dev/null; then
        log "$TO started"
        rm -f "$NOTE" "${NOTE%.json}.log"
        finish 0
    fi
    sleep 0.2
    waited=$((waited + 1))
done

log "$TO did not say it started within $STARTED_WITHIN seconds; putting $FROM back"
pkill -TERM -f "$RUNNING" 2>/dev/null
waited=0
while [ "$waited" -lt 25 ] && running_from_entry; do
    sleep 0.2
    waited=$((waited + 1))
done
pkill -KILL -f "$RUNNING" 2>/dev/null

if [ "$ELEVATE" = 1 ]; then
    /bin/sh "$STAGING/restore-elevated.sh"
else
    restore
fi
if [ $? -ne 0 ]; then
    note failed "Simorg Desktop $TO did not open, and $FROM could not be put back. Download Simorg Desktop again from its page to repair it."
    finish 1
fi
note rolled_back "Simorg Desktop $TO did not open within $STARTED_WITHIN seconds, so $FROM was put back and opened instead. What happened is below."
open_version
finish 1
