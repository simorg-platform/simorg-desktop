#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Turns a finished bundle into the driver a release uploads: the operating
# system's own installer.
#
#   ./scripts/package-driver.sh --code BINARY_MAC_APPLE_SILICON \
#                              --stage build/dist/macos
#
# An application's driver is the file a person on that system downloads and
# opens, and the platform refuses anything else for one:
#
#   macOS    .dmg        Simorg.app and a shortcut to Applications, and a picture
#                        behind them that says to drag one onto the other
#   Linux    .AppImage   one executable file that runs on any distribution
#   Windows  .msi        installed for the person, under their own Programs folder
#
# The same file is what the machine service installs for an agent and what
# Simorg Desktop updates itself from, so nothing here is only for show.
#
# It never builds anything. `scripts/build-targets.sh` and the bundlers do that;
# this is the step between a bundle and an upload, and it is deliberately dumb
# so that what is published is exactly what was tested. The file lands in
# release/<CODE>/ as <slug>-<system>-<arch>.<ext>, the path simorg.toml names
# for that driver, with the build's BUILD-INFO.txt beside it, which is how a
# release tells a prod build from a dev one without opening it. The tag is not
# in the name so the manifest need not change at every release: the release
# puts it in the name a person sees when they download it,
# <slug>-<tag>-<system>-<arch>.<ext>.
#
# The installer itself is made by the installer maker every Simorg application
# shares, so the three formats are made one way everywhere. It is part of
# Simorg's release tooling, not of this repository. What is Simorg Desktop's own
# is here: the AppImage's desktop entry, icon and AppRun, and the WiX source in
# packaging/windows/. simorg.toml says which targets are declared.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CODE=""
STAGE=""
ENTRY="simorg-desktop.exe"

die() { printf 'package-driver: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --code)  CODE="${2:?--code needs a driver category, like BINARY_MAC_APPLE_SILICON}"; shift 2 ;;
        --stage) STAGE="${2:?--stage needs the directory a bundler produced}"; shift 2 ;;
        --entry) ENTRY="${2:?--entry needs the program a Windows install starts}"; shift 2 ;;
        -h|--help) sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument $1" ;;
    esac
done

[ -n "$CODE" ]  || die "--code is required"
[ -n "$STAGE" ] || die "--stage is required"
[ -d "$STAGE" ] || die "no such directory: $STAGE"
STAGE="$(cd "$STAGE" && pwd)"

# --- What it is called --------------------------------------------------------

# The first `key = "value"` under a table of simorg.toml.
manifest_value() {
    awk -v table="[$1]" -v key="$2" '
        $0 == table { inside = 1; next }
        /^\[/       { inside = 0 }
        inside && $1 == key { v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v; exit }
    ' "${ROOT}/simorg.toml"
}
SLUG="$(manifest_value artifact slug)"
VERSION="$(manifest_value release tag)"
[ -n "$SLUG" ] && [ -n "$VERSION" ] || die "simorg.toml names no [artifact] slug or [release] tag"

case "$CODE" in
    BINARY_MAC_APPLE_SILICON) FILE="${SLUG}-macos-arm64.dmg" ;;
    BINARY_MAC_X64)           FILE="${SLUG}-macos-x64.dmg" ;;
    BINARY_LINUX_ARM)         FILE="${SLUG}-linux-aarch64.AppImage" ;;
    BINARY_LINUX_X64)         FILE="${SLUG}-linux-x86_64.AppImage" ;;
    BINARY_WINDOWS_X64)       FILE="${SLUG}-windows-x64.msi" ;;
    BINARY_WINDOWS_ARM)       FILE="${SLUG}-windows-arm64.msi" ;;
    *) die "$CODE is not a binary driver category for an application" ;;
esac

# The build's note on itself names its version, and a file named for one tag
# holding another would be offered to itself as an update.
BUILD_INFO="${STAGE}/BUILD-INFO.txt"
if [ -f "$BUILD_INFO" ]; then
    built="$(sed -n 's/^ *version  *\([^ ]*\).*/\1/p' "$BUILD_INFO" | head -1)"
    if [ -n "$built" ] && [ "$built" != "$VERSION" ]; then
        die "the bundle says version ${built} and simorg.toml says ${VERSION}: build it again"
    fi
else
    printf 'package-driver: warning: %s has no BUILD-INFO.txt, so nothing will say how it was built\n' "$STAGE" >&2
fi

OUT="${ROOT}/release/${CODE}"
# Under build/ rather than the system's temporary folder: Docker Desktop shares
# the home directory with its containers, and not macOS's /var/folders.
mkdir -p "${ROOT}/build"
WORK="$(mktemp -d "${ROOT}/build/package-driver.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# One driver per directory: an earlier tag's file, or the .tgz this used to
# make, is nobody's driver now.
rm -rf "$OUT"
mkdir -p "$OUT"
TARGET="${OUT}/${FILE}"

# --- The installer, made the one way every application makes it ---------------

MAKE_INSTALLER="${ROOT}/../../scripts/make-installer.sh"
[ -x "$MAKE_INSTALLER" ] || die "no ${MAKE_INSTALLER}: it makes every application's installer"

case "$CODE" in
    BINARY_MAC_*)
        [ -d "${STAGE}/Simorg.app" ] || die "the stage has no Simorg.app"
        # The picture behind the disk image's window, saying to drag Simorg onto
        # Applications; scripts/icons/make_icons.py draws it, @2x beside it.
        "$MAKE_INSTALLER" --code "$CODE" --stage "$STAGE" --out "$TARGET" --name Simorg \
            --background "${ROOT}/packaging/macos/dmg-background.png"
        ;;
    BINARY_LINUX_*)
        [ -x "${STAGE}/simorg-desktop" ] || die "the stage has no simorg-desktop launcher"
        # The bundle as it is, with what an AppImage of Simorg carries at its top:
        # the desktop entry and icon the system menu shows, and an AppRun that
        # runs the app with whatever it was given — `update desktop --json` too,
        # which the machine service runs to update it while it is closed.
        # The installer maker keeps it as AppRun.entry and puts its check in front:
        # a computer that cannot load the app says why rather than doing nothing.
        appdir="${WORK}/AppDir"
        mkdir -p "$appdir"
        cp -a "${STAGE}/." "${appdir}/"
        cp "${ROOT}/packaging/linux/tech.simorg.desktop.desktop" "${appdir}/tech.simorg.desktop.desktop"
        # The application icon, not the bare mark: the plate scripts/make-icons.sh
        # draws. The SVG is what the install script puts in the menu's icon theme
        # (it takes <Icon>.svg before <Icon>.png); .DirIcon is the 256-pixel PNG
        # the AppImage specification asks for, which file managers and AppImage
        # integrators show for the file itself.
        cp "${ROOT}/resources/branding/app-icon/simorg-app-icon.svg" "${appdir}/tech.simorg.desktop.svg"
        cp "${ROOT}/resources/branding/app-icon/simorg-256.png" "${appdir}/tech.simorg.desktop.png"
        ln -s tech.simorg.desktop.png "${appdir}/.DirIcon"
        cat > "${appdir}/AppRun" <<'APPRUN'
#!/bin/sh
# Simorg, as an AppImage: the desktop app.
here="$(dirname "$(readlink -f "$0")")"
exec "${here}/simorg-desktop" "$@"
APPRUN
        chmod +x "${appdir}/AppRun"
        "$MAKE_INSTALLER" --code "$CODE" --stage "$appdir" --out "$TARGET" --name Simorg --slug simorg-desktop
        ;;
    BINARY_WINDOWS_*)
        [ -f "${STAGE}/${ENTRY}" ] || die "the stage has no ${ENTRY}"
        # WixToolset.UI.wixext for the installer's pages: Welcome, Ready, and the
        # last page that opens Simorg (packaging/windows/simorg-desktop.wxs).
        "$MAKE_INSTALLER" --code "$CODE" --stage "$STAGE" --out "$TARGET" \
            --wxs "${ROOT}/packaging/windows/simorg-desktop.wxs" --version "$VERSION" --entry "$ENTRY" \
            --ext WixToolset.UI.wixext
        ;;
esac

[ -f "$TARGET" ] || die "nothing was written to ${TARGET}"
[ -f "$BUILD_INFO" ] && cp "$BUILD_INFO" "${OUT}/BUILD-INFO.txt"

printf '\n  %s\n' "$TARGET"
printf '  %s\n\n' "$(du -h "$TARGET" | cut -f1)"
