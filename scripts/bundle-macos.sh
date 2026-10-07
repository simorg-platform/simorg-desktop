#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Finishes a macOS build into something that runs on a Mac with no Qt.
#
#   ./scripts/bundle-macos.sh --stage build/targets/macos-prod/stage --out build/dist/macos
#
# Qt's own deployment covers most of the app: SIMORG_DEPLOY_QT runs macdeployqt
# after the link step and Simorg.app comes out with its frameworks inside. What
# it leaves is finished here: references it left absolute, the bundle's seal,
# and the checks that nothing in it points at a path that exists on this Mac and
# on no other. The terminal command is Simorg CLI's now, an application of its
# own, so the bundle carries the app alone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STAGE=""
OUT=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
muted() { printf '  %s%s%s\n' "${DIM}" "$*" "${RESET}"; }
warn()  { printf '%swarning:%s %s\n' "${YELLOW}" "${RESET}" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "${RED}" "${RESET}" "$*" >&2; exit 1; }
ok()    { printf '  %s✓%s %s\n' "${GREEN}" "${RESET}" "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --stage)     STAGE="${2:?--stage needs a directory}"; shift 2 ;;
        --out)       OUT="${2:?--out needs a directory}"; shift 2 ;;
        *)           die "unknown option '$1'" ;;
    esac
done

[ -n "$STAGE" ] || die "--stage is required"
[ -n "$OUT" ] || die "--out is required"

# The tree `cmake --install` produced: Simorg.app at the root because its
# install rule says BUNDLE DESTINATION .
APP="${STAGE}/Simorg.app"

[ -d "$APP" ] || die "no app bundle at ${APP} — was the tree installed rather than copied?"
mkdir -p "$OUT"

# --- What the archive looks like -----------------------------------------
# One named folder inside the archive, the same shape the Linux tarball has, so
# unzipping produces something identifiable rather than three loose items in
# whatever directory the person was standing in.
VERSION="${SIMORG_VERSION:-0.0.0}"
APP_EXECUTABLE="${APP}/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "${APP}/Contents/Info.plist" 2>/dev/null)"
ARCH_TAG="$(lipo -archs "$APP_EXECUTABLE" 2>/dev/null | tr ' ' '-' || uname -m)"
NAME="simorg-${VERSION}-macos-${ARCH_TAG}"

STAGING="${OUT}/.archive"
ARCHIVE_ROOT="${STAGING}/${NAME}"
rm -rf "$STAGING"
mkdir -p "$ARCHIVE_ROOT"

cp -R "$APP" "${ARCHIVE_ROOT}/Simorg.app"

# --- Finishing what macdeployqt leaves behind ----------------------------
#
# macdeployqt copies a framework in and rewrites the references *it* knows
# about. It does not descend into a framework that contains an executable of its
# own, and Qt ships exactly one that does: QtWebEngineCore carries
# QtWebEngineProcess.app, the separate process Chromium renders in. Homebrew
# builds that helper with absolute install names, so a deployed bundle contains
#
#   .../QtWebEngineProcess: /opt/homebrew/opt/qtbase/lib/QtCore.framework/...
#
# and on any other Mac the app opens, the agent Workbench stays blank, and
# nothing anywhere says why — the main process is fine, it is the child that
# cannot start.
#
# So every Mach-O file in the bundle is walked, and any dependency at an
# absolute path outside the operating system's own directories is pointed back
# at the copy inside Contents/Frameworks, bringing it in first if it is not
# already there.
APP_ROOT="${ARCHIVE_ROOT}/Simorg.app"

# @loader_path rather than @executable_path: it resolves against the file doing
# the loading, so one rule is right for the app binary, for a framework loaded
# by it, and for a helper executable seven directories down.
rel_to_frameworks() {
    local dir="$1" rel up="" segment
    rel="${dir#"$APP_ROOT"/}"
    local IFS='/'
    for segment in $rel; do [ -n "$segment" ] && up="../${up}"; done
    printf '%sContents/Frameworks' "$up"
}

is_macho() {
    [ -f "$1" ] || return 1
    file -b "$1" 2>/dev/null | grep -q 'Mach-O'
}

repair_bundle_references() {
    local rounds=0 changed=1

    # Looped because bringing a framework in adds a file that has to be asked
    # the same question. Two rounds is the most this has ever needed; the bound
    # is here so a cycle cannot hang a build.
    while [ "$changed" -eq 1 ] && [ "$rounds" -lt 5 ]; do
        changed=0
        rounds=$((rounds + 1))

        local -a files=()
        while IFS= read -r -d '' f; do
            is_macho "$f" && files+=("$f")
        done < <(find "$APP_ROOT" -type f -print0)

        local binary dependency
        for binary in "${files[@]}"; do
            local touched=0
            while read -r dependency; do
                case "$dependency" in
                    /usr/lib/*|/System/Library/*) continue ;;
                    @*) continue ;;
                    /*) ;;
                    *) continue ;;
                esac

                # Where this belongs inside Contents/Frameworks. For a
                # framework that is everything from <Name>.framework onwards,
                # so /opt/homebrew/opt/qtbase/lib/QtCore.framework/Versions/A/QtCore
                # becomes QtCore.framework/Versions/A/QtCore; for a loose dylib
                # it is just the file name.
                local inside head
                case "$dependency" in
                    *.framework/*)
                        head="${dependency%%.framework/*}"
                        inside="${head##*/}.framework/${dependency#*.framework/}" ;;
                    *)  inside="${dependency##*/}" ;;
                esac

                if [ ! -e "${APP_ROOT}/Contents/Frameworks/${inside}" ]; then
                    local source_root
                    case "$inside" in
                        *.framework/*)
                            source_root="${dependency%%.framework/*}.framework"
                            [ -d "$source_root" ] || { warn "cannot find ${source_root}"; continue; }
                            cp -R "$source_root" "${APP_ROOT}/Contents/Frameworks/" ;;
                        *)
                            [ -f "$dependency" ] || { warn "cannot find ${dependency}"; continue; }
                            cp "$dependency" "${APP_ROOT}/Contents/Frameworks/${inside}" ;;
                    esac
                    chmod -R u+w "${APP_ROOT}/Contents/Frameworks/${inside}"
                    muted "brought in ${inside%%/*}"
                fi

                install_name_tool -change "$dependency" \
                    "@loader_path/$(rel_to_frameworks "$(dirname "$binary")")/${inside}" \
                    "$binary" 2>/dev/null || continue
                touched=1
                changed=1
            done < <(otool -L "$binary" 2>/dev/null | awk 'NR > 1 { print $1 }')

            # An edited Mach-O carries a signature that no longer matches it,
            # and macOS refuses to load one of those outright — which reads as
            # "the file is damaged" rather than as anything to do with this.
            [ "$touched" -eq 1 ] && codesign --force --sign - "$binary" 2>/dev/null || true
        done
    done

    [ "$rounds" -gt 1 ] && ok "rewrote the references macdeployqt left absolute"
    return 0
}

repair_bundle_references

# --- And the seal, last ---------------------------------------------------
#
# Everything above *edits* Mach-O files inside a bundle that was already signed:
# install names are rewritten, frameworks are brought in.
# Each edited file is re-signed as it is touched, but the bundle's own signature
# seals its resources as they were at the moment macdeployqt signed it, and
# macOS refuses a bundle whose seal no longer matches — as "Simorg.app is
# damaged and can't be opened", which names nothing a person could act on.
#
# So the bundle is signed once more, ad-hoc, after the last file in it has
# stopped moving. --deep because the nested code has to be sealed before the
# thing that contains it: QtWebEngineProcess.app is a bundle inside a framework
# inside this one.
if codesign --force --deep --sign - "$APP_ROOT" >/dev/null 2>&1 \
   && codesign --verify --deep "$APP_ROOT" >/dev/null 2>&1; then
    ok "signed"
else
    # Not fatal. An unsigned bundle still runs once the quarantine flag is
    # off, which the README already tells people to do, and a build that
    # refused to finish over this would be worse than one that says so.
    warn "the bundle could not be signed; it will need Finder's right-click → Open"
fi

cat > "${ARCHIVE_ROOT}/README.txt" <<'EOF'
Simorg for macOS
================

    Simorg.app      drag it to /Applications

Nothing else has to be installed: Qt and everything under it are inside the
bundle. To work from a terminal instead, Simorg CLI is an application of its
own, with an install line on its page on simorg.tech.

FIRST LAUNCH
-----------
This build is signed ad-hoc rather than with a Developer ID, so macOS will not
open it on the first try. On macOS 15 and later the old right-click -> Open
trick no longer works; the route is:

    open it, let macOS refuse, then
    System Settings -> Privacy & Security -> scroll down -> Open Anyway

Or clear the quarantine flag yourself before the first launch:

    xattr -dr com.apple.quarantine Simorg.app

Neither is needed for a notarised build, and neither says anything about
whether the app is safe -- only that Apple has not been paid to vouch for it.
EOF

# --- Nothing may point outside the bundle --------------------------------
#
# The Linux side proves this by running the archive in a container with nothing
# installed. There is no such thing for macOS, so it is proved by reading: any
# dependency that is neither inside the bundle nor part of the OS is a path that
# happens to exist on this Mac and on no other.
AUDIT="${ARCHIVE_ROOT}/MANIFEST.txt"
{
    printf 'Simorg — macOS build\n\n'
    printf 'Architectures  %s\n' "$(lipo -archs "$APP_EXECUTABLE" 2>/dev/null || uname -m)"
    printf 'Contents       %s\n\n' 'Simorg.app'
    printf 'FRAMEWORKS AND LIBRARIES CARRIED INSIDE THE BUNDLE\n\n'
    find "${ARCHIVE_ROOT}/Simorg.app/Contents/Frameworks" -maxdepth 1 -mindepth 1 2>/dev/null \
        | sed "s|.*/|  |" | sort
    printf '\nPROVIDED BY macOS\n'
    printf '  /usr/lib and /System/Library only — every Mac has these.\n'
} > "$AUDIT"

# --- Nothing may dangle either ------------------------------------------
#
# A broken symlink is invisible to every check below: it is not `-type f`, so
# the walk that follows skips it, and `otool` cannot open it to be asked about
# its dependencies. That is not hypothetical — Qt's own QML deployment used to
# fill Contents/PlugIns with links copied verbatim out of Homebrew's keg farm,
# and the bundle that shipped had no QML modules in it at all while passing
# every test here. See cmake/SimorgMacOsDeploy.cmake, which is what stops it
# happening; this is what would say so if it ever started again.
DANGLING="$(find "$ARCHIVE_ROOT" -type l ! -exec test -e {} \; -print 2>/dev/null || true)"
if [ -n "$DANGLING" ]; then
    printf '%serror:%s these point at nothing:\n' "${RED}" "${RESET}" >&2
    printf '%s\n' "$DANGLING" | sed "s|${ARCHIVE_ROOT}/||" | sed 's/^/    /' >&2
    die "the macOS build has broken symlinks in it"
fi
ok "no broken links"

STRAY=""
while IFS= read -r -d '' binary; do
    file "$binary" 2>/dev/null | grep -q 'Mach-O' || continue
    while read -r dependency; do
        case "$dependency" in
            @executable_path/*|@loader_path/*|@rpath/*) ;;
            /usr/lib/*|/System/Library/*) ;;
            "${ARCHIVE_ROOT}"/*) ;;
            *) STRAY="${STRAY}${binary#"$ARCHIVE_ROOT"/}: ${dependency}"$'\n' ;;
        esac
    done < <(otool -L "$binary" 2>/dev/null | awk 'NR > 1 { print $1 }')
done < <(find "$ARCHIVE_ROOT" -type f -perm -u+x -print0)

if [ -n "$STRAY" ]; then
    printf '%serror:%s these point at paths outside the bundle:\n' "${RED}" "${RESET}" >&2
    printf '%s' "$STRAY" | sort -u | sed 's/^/    /' >&2
    die "the macOS build is not self-contained"
fi
ok "nothing points outside the bundle"

# --- The bundle executable is still the application ----------------------
#
# The check that exists because its absence shipped a broken build. A command
# line was once copied to Contents/MacOS/simorg, which on a case-insensitive
# disk *is* Contents/MacOS/Simorg — so the application was replaced by it, and
# double-clicking the icon ran a program that printed a version banner to nobody
# and exited, while every other check here passed.
#
# Asked by reading rather than by running: macdeployqt ships only the `cocoa`
# platform plugin, so there is no headless way to start this bundle. The
# application is Qt Quick, so "does this binary link Qt Quick" is the question,
# and it needs no display to answer.
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "${APP_ROOT}/Contents/Info.plist" 2>/dev/null)"
[ -n "$executable" ] || die "the bundle declares no CFBundleExecutable"

bundle_main="${APP_ROOT}/Contents/MacOS/${executable}"
[ -f "$bundle_main" ] || die "the bundle has no ${executable} in Contents/MacOS"

if ! otool -L "$bundle_main" 2>/dev/null | grep -q 'QtQuick'; then
    printf '    %s does not link Qt Quick, so it is not the application.\n' \
        "Contents/MacOS/${executable}" >&2
    die "the bundle executable is not Simorg"
fi
ok "the bundle executable is the application"

# --- Archive -------------------------------------------------------------
#
# `ditto -c -k` rather than `zip`: it is Apple's own tool for this, and it is
# the one that keeps the symlinks inside a framework and the extended
# attributes a signature lives in. A plain `zip` of a .app produces a bundle
# that fails to launch on the other end.
ARCHIVE="${OUT}/${NAME}.zip"

rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$ARCHIVE_ROOT" "$ARCHIVE"
cp "$AUDIT" "${OUT}/MANIFEST.txt"

# The unpacked copy beside the archive is the repaired one, moved rather than
# made separately: a bundle copied straight out of the build tree would still
# carry the absolute Homebrew paths, run perfectly on this Mac and fail on every
# other — the exact trap this script exists to close, left sitting in the
# output directory.
rm -rf "${OUT}/Simorg.app" "${OUT}/simorg"
[ -d "${ARCHIVE_ROOT}/Simorg.app" ] && mv "${ARCHIVE_ROOT}/Simorg.app" "${OUT}/Simorg.app"
rm -rf "$STAGING"

( cd "$OUT" && shasum -a 256 ./*.zip > SHA256SUMS )

ok "$(basename "$ARCHIVE")  ${DIM}$(du -h "$ARCHIVE" | cut -f1)${RESET}"
