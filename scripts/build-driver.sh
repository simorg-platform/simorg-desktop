#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# The drivers this computer can make, in one command.
#
#   ./scripts/build-driver.sh                          every driver this computer can make
#   ./scripts/build-driver.sh --code BINARY_LINUX_ARM  one of them (--code repeats)
#   ./scripts/build-driver.sh --codes                  list them, build nothing
#   ./scripts/build-driver.sh --config dev             pointed at localhost
#
# Which drivers that is depends on the computer, because a driver is an
# operating system's binary:
#
#   an Apple silicon Mac   both Mac drivers, from one universal build against
#                          the pinned Qt (fetched the first time), each driver
#                          thinned to its own architecture with `ditto --arch`
#                          and signed again; Linux ARM in Docker, natively; and
#                          Linux x64 in a Colima VM that runs x86-64 through
#                          Rosetta (scripts/build-targets.sh)
#   a Windows computer     both Windows drivers, the ARM64 one cross-compiled
#                          from Intel by scripts/build-windows.ps1 — run this
#                          from **Git Bash**, not WSL, which has no MSVC
#   a Linux computer       the Linux driver of its own architecture
#
# Each driver is made by the two steps underneath:
#
#   scripts/build-targets.sh <target>        compile, bundle, carry Qt inside, verify
#   scripts/package-driver.sh --code <CODE>  the system's installer
#
# What comes out is the file simorg.toml names for each driver under
# release/<CODE>/ — a .dmg, an .AppImage or an .msi — the file a release uploads.
# Simorg's release tooling runs this script when a driver is not built yet or
# was built at another tag, asking for exactly the ones it needs and learning
# which this computer can make from --codes. package-driver.sh needs that
# tooling's installer maker, which is not part of this repository. A target that fails does
# not stop the others; the run ends with what was made and what was not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=''; DIM=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi
die()  { printf '%sbuild-driver: %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$1" >&2; }

REQUESTED=()
CONFIG="prod"
LIST_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --code)   REQUESTED+=("${2:?--code needs a driver category, like BINARY_MAC_APPLE_SILICON}"); shift 2 ;;
        --codes)  LIST_ONLY=1; shift ;;
        --config) CONFIG="${2:?--config is dev or prod}"; shift 2 ;;
        -h|--help) sed -n '4,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument $1" ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# What this computer can make. A driver is an operating system's binary, so the
# host decides: a Mac makes the Mac drivers, Docker makes the Linux ones — on an
# Apple silicon Mac the x64 one in the Rosetta VM, so Colima is needed for it —
# and a Windows computer makes both Windows drivers, cross-compiling the ARM64
# one from Intel.
#
# On Windows this has to be **Git Bash**, which Git for Windows installs: it is
# a Windows shell, so `powershell.exe` runs the build and MSVC and Qt are the
# ones installed on that computer. WSL is a Linux machine that happens to live
# there — no MSVC, no Windows Qt — and is told so rather than left to fail
# halfway through a build.
# The Linux ones are whatever Simorg's scripts/native-docker.sh says this
# computer builds natively, when it is there (SIMORG_NATIVE_DOCKER).
NATIVE_DOCKER_LIB="${SIMORG_NATIVE_DOCKER:-${ROOT}/../../../../scripts/native-docker.sh}"
# shellcheck source=../../../../../scripts/native-docker.sh
[ -f "$NATIVE_DOCKER_LIB" ] && source "$NATIVE_DOCKER_LIB"

buildable_codes() {
    case "$(uname -s)/$(uname -m)" in
        MINGW*|MSYS*|CYGWIN*)
            have powershell.exe && echo BINARY_WINDOWS_X64 BINARY_WINDOWS_ARM
            ;;
        Darwin/arm64)
            echo BINARY_MAC_APPLE_SILICON BINARY_MAC_X64
            ;;
        Darwin/x86_64)
            echo BINARY_MAC_X64 BINARY_MAC_APPLE_SILICON
            ;;
    esac
    if declare -F native_docker_codes >/dev/null; then
        native_docker_codes
    fi
}

# Git Bash spells this directory /c/Simorg/…; PowerShell needs C:\Simorg\… or
# it looks for a drive called `c`.
windows_path_of() {
    (cd "$1" && pwd -W 2>/dev/null) || cygpath -w "$1" 2>/dev/null || printf '%s' "$1"
}

read -r -a BUILDABLE <<<"$(buildable_codes | tr '\n' ' ')"

if [ "$LIST_ONLY" -eq 1 ]; then
    printf '%s\n' ${BUILDABLE[@]+"${BUILDABLE[@]}"}
    exit 0
fi

[ ${#REQUESTED[@]} -gt 0 ] || REQUESTED=(${BUILDABLE[@]+"${BUILDABLE[@]}"})
[ ${#REQUESTED[@]} -gt 0 ] || die "$(uname -s) on $(uname -m) can make none of this application's drivers; see the header"

for code in "${REQUESTED[@]}"; do
    case "$code" in
        BINARY_MAC_APPLE_SILICON|BINARY_MAC_X64|BINARY_LINUX_ARM|BINARY_LINUX_X64|BINARY_WINDOWS_X64|BINARY_WINDOWS_ARM) ;;
        *) die "$code is not a target this application publishes" ;;
    esac
    if ! printf ' %s ' ${BUILDABLE[@]+"${BUILDABLE[@]}"} | grep -q " ${code} "; then
        case "$code/$(uname -s)" in
            BINARY_WINDOWS_*/Linux)
                # Including WSL, which is where somebody on Windows reaches first.
                die "$code is built on Windows itself, in Git Bash — this is Linux, which has no MSVC and no Windows Qt.
     Open Git Bash on that computer and run the same command there." ;;
            BINARY_WINDOWS_*/MINGW*|BINARY_WINDOWS_*/MSYS*)
                die "$code needs powershell.exe on the PATH, and this shell has none." ;;
            *)
                die "$code cannot be made on this computer; it makes: ${BUILDABLE[*]:-none}" ;;
        esac
    fi
    # A target the manifest does not name is still buildable — that is how the
    # first archive for a new target gets made — but the release will not carry
    # it until a [[driver]] says so, and finding that out after the upload is slow.
    grep -q "^code = \"${code}\"$" "${ROOT}/simorg.toml" \
        || warn "simorg.toml names no [[driver]] with code = \"${code}\"; add one in the same change that starts publishing it"
done

wants() { printf ' %s ' "${REQUESTED[@]}" | grep -q " $1 "; }

MADE=()
FAILED=()
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- macOS: one universal build, one archive per architecture ---------------
mac_arch() {
    case "$1" in
        BINARY_MAC_APPLE_SILICON) echo arm64 ;;
        BINARY_MAC_X64)           echo x86_64 ;;
    esac
}

build_mac() {
    local codes=() code
    for code in BINARY_MAC_APPLE_SILICON BINARY_MAC_X64; do wants "$code" && codes+=("$code"); done
    [ ${#codes[@]} -gt 0 ] || return 0

    printf '\n%s%s%s  %smacos, %s%s\n' "$BOLD" "${codes[*]}" "$RESET" "$DIM" "$CONFIG" "$RESET"
    local install=()
    # The pinned universal Qt, fetched the first time a release needs it.
    if [ "$CONFIG" = "prod" ]; then install=(--install-qt); fi
    if ! "${ROOT}/scripts/build-targets.sh" macos --config "$CONFIG" ${install[@]+"${install[@]}"}; then
        FAILED+=("${codes[@]}")
        return 0
    fi

    local stage="${ROOT}/build/dist/macos" built arch source_stage
    if [ ! -d "${stage}/Simorg.app" ]; then
        warn "the build left no Simorg.app in build/dist/macos"
        FAILED+=("${codes[@]}")
        return 0
    fi
    built="$(lipo -archs "${stage}/Simorg.app/Contents/MacOS/Simorg")"

    for code in "${codes[@]}"; do
        arch="$(mac_arch "$code")"
        case " $built " in
            *" $arch "*) ;;
            *) warn "the build holds ${built}, not ${arch}: ${code} needs the universal Qt (scripts/build-targets.sh --install-qt macos)"
               FAILED+=("$code"); continue ;;
        esac
        source_stage="$stage"
        if [ "$(echo "$built" | wc -w | tr -d ' ')" -gt 1 ]; then
            # One architecture per download. ditto thins every Mach-O file it
            # copies and leaves everything else as it is; thinning changes the
            # code, so the bundle is signed again, ad hoc until a Developer ID
            # identity is given.
            source_stage="${WORK}/${code}"
            ditto --arch "$arch" "$stage" "$source_stage"
            if ! { codesign --force --deep --sign - "${source_stage}/Simorg.app" >/dev/null 2>&1 \
                   && codesign --verify --deep "${source_stage}/Simorg.app" >/dev/null 2>&1; }; then
                warn "the ${arch} bundle does not verify after it was signed again"
                FAILED+=("$code"); continue
            fi
            if [ "$(lipo -archs "${source_stage}/Simorg.app/Contents/MacOS/Simorg")" != "$arch" ]; then
                warn "ditto left more than ${arch} in the ${code} bundle"
                FAILED+=("$code"); continue
            fi
            if [ -f "${source_stage}/BUILD-INFO.txt" ]; then
                sed -i '' -E "s/^(  architecture +).*/\\1${arch}/" "${source_stage}/BUILD-INFO.txt"
            fi
        fi
        if "${ROOT}/scripts/package-driver.sh" --code "$code" --stage "$source_stage"; then
            MADE+=("$code")
        else
            FAILED+=("$code")
        fi
    done
}

# --- Linux: one Docker build per architecture ---------------------------------
# The target is named as build-targets.sh names it (x64); the archive and the
# directory inside it as Debian names the architecture (amd64).
build_linux() {
    local code="$1" arch="$2" named="$3"
    wants "$code" || return 0
    printf '\n%s%s%s  %slinux-%s, %s%s\n' "$BOLD" "$code" "$RESET" "$DIM" "$arch" "$CONFIG" "$RESET"
    if ! "${ROOT}/scripts/build-targets.sh" "linux-${arch}" --config "$CONFIG"; then
        FAILED+=("$code")
        return 0
    fi

    # Linux leaves the tarball, because that is what a Linux download is, so it
    # is unpacked here rather than teaching the packer about two shapes.
    local dist="${ROOT}/build/dist/linux-${arch}" tarball unpack stage
    tarball="$(find "$dist" -maxdepth 1 -type f -name "simorg-*-linux-${named}.tar.gz" 2>/dev/null | head -1)"
    if [ -z "$tarball" ]; then
        warn "the build left no linux-${arch} bundle in ${dist#"${ROOT}"/}"
        FAILED+=("$code")
        return 0
    fi
    unpack="${WORK}/${code}"
    mkdir -p "$unpack"
    tar -C "$unpack" -xzf "$tarball"
    stage="$(find "$unpack" -maxdepth 1 -type d -name "simorg-*-linux-${named}" | head -1)"
    if [ -z "$stage" ]; then
        warn "$(basename "$tarball") holds no simorg-*-linux-${named} directory"
        FAILED+=("$code")
        return 0
    fi
    # The build's note on itself travels with the driver, as the Mac one does:
    # it is how anybody tells a prod build from a dev one.
    if [ -f "${dist}/BUILD-INFO.txt" ]; then cp "${dist}/BUILD-INFO.txt" "${stage}/BUILD-INFO.txt"; fi
    if "${ROOT}/scripts/package-driver.sh" --code "$code" --stage "$stage"; then
        MADE+=("$code")
    else
        FAILED+=("$code")
    fi
}

# --- Windows: MSVC on the computer itself, ARM64 cross-compiled from Intel ---
#
# The build is PowerShell's — nothing about a Windows build resembles a Unix one
# past "run cmake" — and this is the one command that runs it, so a release on
# Windows is the same sentence as a release on a Mac.
build_windows() {
    local code="$1" arch="$2"
    wants "$code" || return 0
    printf '\n%s%s%s  %swindows-%s, %s%s\n' "$BOLD" "$code" "$RESET" "$DIM" "$arch" "$CONFIG" "$RESET"

    local project
    project="$(windows_path_of "$ROOT")"
    if ! powershell.exe -NoProfile -ExecutionPolicy Bypass \
        -File "${project}\\scripts\\build-windows.ps1" "$arch" -Config "$CONFIG"; then
        FAILED+=("$code")
        return 0
    fi

    # What build-windows.ps1 leaves: build/targets/windows-<arch>-<config>/simorg-<version>-windows-<arch>.
    local stage
    stage="$(find "${ROOT}/build/targets/windows-${arch}-${CONFIG}" -maxdepth 1 -type d \
        -name "simorg-*-windows-${arch}" 2>/dev/null | head -1)"
    if [ -z "$stage" ]; then
        warn "the Windows build left no simorg-*-windows-${arch} folder to pack"
        FAILED+=("$code")
        return 0
    fi
    # The program the installer's Start-menu shortcut opens, and the one the
    # machine service finds in it by the application's slug.
    if "${ROOT}/scripts/package-driver.sh" --code "$code" --stage "$stage" --entry simorg-desktop.exe; then
        MADE+=("$code")
    else
        FAILED+=("$code")
    fi
}

build_mac
build_linux BINARY_LINUX_ARM arm64 arm64
build_linux BINARY_LINUX_X64 x64 amd64
build_windows BINARY_WINDOWS_X64 x64
build_windows BINARY_WINDOWS_ARM arm64

printf '\n%sbuild-driver%s\n' "$BOLD" "$RESET"
for code in ${MADE[@]+"${MADE[@]}"}; do
    printf '  %s✓%s %-26s %s%s%s\n' "$GREEN" "$RESET" "$code" "$DIM" \
        "$(cd "$ROOT" && find "release/${code}" -maxdepth 1 -type f ! -name BUILD-INFO.txt | head -1)" "$RESET"
done
for code in ${FAILED[@]+"${FAILED[@]}"}; do
    printf '  %s✗%s %s did not build; its output is above\n' "$RED" "$RESET" "$code"
done
[ ${#FAILED[@]} -eq 0 ]
