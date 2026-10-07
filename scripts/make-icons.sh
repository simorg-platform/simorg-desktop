#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Draws Simorg Desktop's application icons from the Simorg mark, for every
# platform, and writes them where the build and the installers take them from.
#
#   ./scripts/make-icons.sh                 write every icon that is not current
#   ./scripts/make-icons.sh --check         write nothing; fail when one is stale
#   ./scripts/make-icons.sh --preview DIR   also put every size of each into DIR
#   ./scripts/make-icons.sh --local         use this computer's rsvg-convert,
#                                           python3 and Inter instead of a container
#
# The drawing is scripts/icons/make_icons.py, which says what it writes and why
# each platform's icon is shaped the way it is. This only gives it the same
# rsvg-convert and the same Inter (for the words on the .dmg's picture)
# everywhere: a throwaway Alpine container, so a Mac, a Windows computer and a
# Linux machine all write byte-for-byte the same files. The icons are
# committed; nothing in a build runs this.
#
# Run it after changing resources/branding/simorg-logo.svg or make_icons.py,
# and commit what it writes. docs/packaging.md, "Application icons", has the rest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="alpine:3.20"

LOCAL=0
ARGS=()
PREVIEW=""
while [ $# -gt 0 ]; do
    case "$1" in
        --local)   LOCAL=1; shift ;;
        --check)   ARGS+=(--check); shift ;;
        --preview) PREVIEW="${2:?--preview needs a directory}"; shift 2 ;;
        -h|--help) sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'make-icons: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done

# A path Docker on Windows takes (C:/…), and the same path anywhere else.
host_path() {
    (cd "$1" && pwd -W 2>/dev/null) || (cd "$1" && pwd)
}

if [ "$LOCAL" -eq 1 ]; then
    if [ -n "$PREVIEW" ]; then mkdir -p "$PREVIEW"; ARGS+=(--preview "$PREVIEW"); fi
    exec python3 "${SCRIPT_DIR}/icons/make_icons.py" "${ARGS[@]+"${ARGS[@]}"}"
fi

command -v docker >/dev/null 2>&1 ||
    { printf 'make-icons: no docker here; install rsvg-convert and python3 and pass --local\n' >&2; exit 1; }

MOUNTS=(-v "$(host_path "$ROOT"):/src")
if [ -n "$PREVIEW" ]; then
    mkdir -p "$PREVIEW"
    MOUNTS+=(-v "$(host_path "$PREVIEW"):/preview")
    ARGS+=(--preview /preview)
fi

# MSYS_NO_PATHCONV keeps Git Bash on Windows from rewriting /src into C:\….
# Run as root, because apk is; what it writes is handed back to whoever owns
# the tree before the container goes.
MSYS_NO_PATHCONV=1 docker run --rm "${MOUNTS[@]}" "$IMAGE" sh -euc '
    # A mirror that answers badly once is not a reason to fail.
    for attempt in 1 2 3; do
        apk add --no-cache rsvg-convert python3 font-inter >/dev/null 2>&1 && break
        [ "$attempt" = 3 ] && { apk add --no-cache rsvg-convert python3 font-inter; exit 1; }
        sleep 2
    done
    python3 /src/scripts/icons/make_icons.py "$@"
    owner="$(stat -c %u:%g /src)"
    for path in /src/packaging/macos/Simorg.icns /src/packaging/windows/simorg.ico \
                /src/packaging/windows/installer-dialog.bmp /src/packaging/windows/installer-banner.bmp \
                /src/packaging/macos/dmg-background.png /src/packaging/macos/dmg-background@2x.png \
                /src/resources/branding/app-icon; do
        [ -e "$path" ] && chown -R "$owner" "$path"
    done
    [ -d /preview ] && chown -R "$(stat -c %u:%g /preview)" /preview
    exit 0
' make-icons "${ARGS[@]+"${ARGS[@]}"}"
