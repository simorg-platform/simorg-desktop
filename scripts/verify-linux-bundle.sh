#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Proves a bundle is self-contained, on a machine that has nothing installed.
#
#   ./scripts/verify-linux-bundle.sh /path/to/simorg-0.1.0-linux-arm64
#
# Run by docker/Dockerfile.linux-build in a clean image before the artifacts are
# allowed out, which is the only honest place to run it: on a developer's own
# machine every library is already there and every check passes whether the
# bundle carries them or not.
#
# What it asserts, in order of how badly each one bites:
#
#   1. Nothing is missing.        No file in the bundle has an unresolved NEEDED.
#   2. Nothing leaks.            No file resolves a Qt library outside the bundle.
#   3. It updates with no window. `simorg-desktop update desktop --json`, what the
#                                machine service runs while the app is closed:
#                                Core and Network, no display, one answer.
#   4. The app starts.           `simorg-desktop --version` under the offscreen
#                                platform plugin — Gui, Widgets, the platform
#                                plugin and the whole loader path — and again
#                                on X11 in a virtual display, which is what
#                                needs xcb-util; and with the system's own copy
#                                of each library in lib/fallback/ when it has
#                                one, the carried copy only when it has none.
#   5. The interface loads.      The app started for real, with every QML module
#                                resolved. This is the check that catches a
#                                missing qml/ directory, which the four above
#                                cannot: a QML module that is not there is a
#                                run-time warning, not a link error.
#   6. Agent surfaces render.    `simorg-desktop --check-web-engine` under a
#                                virtual display: Chromium draws a page and runs
#                                its script, and loads SIMORG_VERIFY_WEB_URL.

set -euo pipefail

BUNDLE="${1:?usage: verify-linux-bundle.sh <bundle directory>}"
[ -d "$BUNDLE" ] || { echo "error: no such bundle: ${BUNDLE}" >&2; exit 1; }
BUNDLE="$(cd "$BUNDLE" && pwd)"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; RED=""; RESET=""
fi
pass() { printf '  %s✓%s %s\n' "${GREEN}" "${RESET}" "$*"; }
fail() { printf '  %s✗%s %s\n' "${RED}" "${RESET}" "$*" >&2; FAILURES=$((FAILURES + 1)); }
note() { printf '    %s%s%s\n' "${DIM}" "$*" "${RESET}"; }

FAILURES=0
printf '\n%sVerifying%s %s\n' "${BOLD}" "${RESET}" "${DIM}$(basename "$BUNDLE")${RESET}"
note "on $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME}" || uname -s) · $(uname -m)"

is_elf() {
    [ -f "$1" ] || return 1
    [ "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]
}


# --- The line between us and the machine ----------------------------------
HOST_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/linux-host-libraries.txt"
HOST_PATTERNS=()
if [ -f "$HOST_LIST" ]; then
    # A glob, and after it perhaps `fallback`, which this reads from the bundle
    # itself instead: whatever lib/fallback/ carries.
    while IFS= read -r line; do
        line="${line%%#*}"
        read -r pattern _ <<< "$line" || true
        if [ -n "${pattern:-}" ]; then HOST_PATTERNS+=("$pattern"); fi
    done < "$HOST_LIST"
fi
carried_fallback() { [ -f "${BUNDLE}/lib/fallback/$1/$1" ]; }

is_host_library() {
    local name="$1" pattern
    for pattern in "${HOST_PATTERNS[@]}"; do
        # shellcheck disable=SC2254
        case "$name" in $pattern) return 0 ;; esac
    done
    return 1
}

# --- 1. Nothing is missing ------------------------------------------------
#
# Split two ways rather than one. A soname the bundle was never meant to carry
# is only absent because this image is barer than a desktop — worth printing,
# not worth failing over. A soname that should have been bundled and is not is
# the bug this whole exercise exists to prevent.
MISSING=""
ABSENT_HOST=""
STOOD_IN=""
CHECKED=0
while IFS= read -r -d '' f; do
    is_elf "$f" || continue
    CHECKED=$((CHECKED + 1))
    while read -r soname; do
        if is_host_library "$soname" && carried_fallback "$soname"; then
            STOOD_IN="${STOOD_IN}${soname}"$'\n'
        elif is_host_library "$soname"; then
            ABSENT_HOST="${ABSENT_HOST}${soname}"$'\n'
        else
            MISSING="${MISSING}${f#"$BUNDLE"/}: ${soname}"$'\n'
        fi
    done < <(ldd "$f" 2>/dev/null | awk '/not found/ { print $1 }' \
             | while read -r s; do [ -f "${BUNDLE}/lib/${s}" ] || printf '%s\n' "$s"; done)
done < <(find "$BUNDLE" -type f -print0)

if [ -n "$MISSING" ]; then
    fail "libraries that should have been bundled are missing"
    printf '%s' "$MISSING" | sort -u | sed 's/^/    /' >&2
else
    pass "every bundled library resolves  ${DIM}(${CHECKED} ELF files)${RESET}"
fi

if [ -n "$ABSENT_HOST" ]; then
    note "not on this image, and never bundled by design:"
    printf '%s' "$ABSENT_HOST" | sort -u | tr '\n' ' ' | fold -s -w 70 | sed 's/^/      /'
    printf '\n'
fi
if [ -n "$STOOD_IN" ]; then
    note "not on this image, so the launchers load the bundle's own from lib/fallback/:"
    printf '%s' "$STOOD_IN" | sort -u | tr '\n' ' ' | fold -s -w 70 | sed 's/^/      /'
    printf '\n'
fi

# --- 2. Nothing leaks -----------------------------------------------------
#
# A bundle built on a machine that has Qt can quietly resolve half of itself
# against the system copy and look perfectly healthy. Here, in an image with no
# Qt at all, any Qt library resolved outside the bundle is a hole.
LEAKED=""
while IFS= read -r -d '' f; do
    is_elf "$f" || continue
    while read -r soname resolved; do
        case "$soname" in
            libQt6*|libqt*) ;;
            *) continue ;;
        esac
        case "$resolved" in
            "$BUNDLE"/*) ;;
            *) LEAKED="${LEAKED}${f#"$BUNDLE"/}: ${soname} -> ${resolved}"$'\n' ;;
        esac
    done < <(ldd "$f" 2>/dev/null | awk '/=>/ { print $1, $3 }')
done < <(find "$BUNDLE" -type f -print0)

if [ -n "$LEAKED" ]; then
    fail "Qt resolved from outside the bundle"
    printf '%s' "$LEAKED" | sed 's/^/    /' >&2
else
    pass "no Qt library comes from outside the bundle"
fi

# --- 3. It updates with no window -----------------------------------------
# HeadlessUpdate.h: with no machine service here, it says so as one JSON
# document and exits 5, having opened nothing, display or none.
if [ -x "${BUNDLE}/simorg-desktop" ]; then
    if output="$(env -u DISPLAY -u WAYLAND_DISPLAY "${BUNDLE}/simorg-desktop" update desktop --json 2>&1)"; then
        status=0
    else
        status=$?
    fi
    if [ "$status" -eq 5 ] && printf '%s' "$output" | grep -q '"SERVICE_UNREACHABLE"'; then
        pass "simorg-desktop update desktop  ${DIM}no service, said so and ended${RESET}"
    else
        fail "simorg-desktop update desktop exited ${status}"
        printf '%s\n' "$output" | sed 's/^/    /' >&2
    fi
fi

# --- 4. The app starts ----------------------------------------------------
if [ -x "${BUNDLE}/simorg-desktop" ]; then
    # The version from standard output alone: Qt's own warnings, such as a C
    # locale's, go to standard error and are shown only when it fails.
    errors="$(mktemp)"
    if output="$(QT_QPA_PLATFORM=offscreen "${BUNDLE}/simorg-desktop" --version 2>"$errors")"; then
        pass "simorg-desktop --version  ${DIM}$(printf '%s' "$output" | head -1)${RESET}"
    else
        fail "simorg-desktop --version exited $?"
        { printf '%s\n' "$output"; cat "$errors"; } | sed 's/^/    /' >&2
    fi
    rm -f "$errors"

    # On X11 as well. The offscreen plugin needs nothing of the display stack;
    # xcb needs libxcb-cursor and the rest of xcb-util, without which Qt 6.5 and
    # later will not open a window, and which neither Ubuntu 22.04 nor WSL
    # installs. They are carried, and this is what proves it.
    if command -v xvfb-run >/dev/null 2>&1; then
        if output="$(HOME="$(mktemp -d)" QT_QPA_PLATFORM=xcb xvfb-run -a -s '-screen 0 1280x800x24' \
                       "${BUNDLE}/simorg-desktop" --version 2>&1)"; then
            pass "and on X11  ${DIM}the xcb platform plugin and the xcb-util libraries under it${RESET}"
        else
            fail "simorg-desktop --version on X11 exited $?"
            printf '%s\n' "$output" | sed -n '1,20s/^/    /p' >&2
        fi
    else
        note "no xvfb-run here, so the X11 platform plugin was not opened"
    fi

    # Which copy of each library in lib/fallback/ the app was given: this
    # system's whenever the loader knows one — it is the copy the system's own
    # plugins were built against — and the carried one only when it knows none.
    # What the loader knows is asked of it directly, with ldd on the program,
    # which the launcher's LD_LIBRARY_PATH does not reach; what the app really
    # loaded, from the loader's trace of it started through the launcher.
    if [ -d "${BUNDLE}/lib/fallback" ]; then
        trace="$(mktemp -d)"
        QT_QPA_PLATFORM=offscreen LD_DEBUG=libs LD_DEBUG_OUTPUT="${trace}/ld" \
            "${BUNDLE}/simorg-desktop" --version >/dev/null 2>&1 || true
        for dir in "${BUNDLE}"/lib/fallback/*/; do
            [ -d "$dir" ] || continue
            name="$(basename "$dir")"
            system="$( { ldd "${BUNDLE}/bin/simorg-desktop" 2>/dev/null || true; } \
                       | awk -v n="$name" '$1 == n && $3 ~ /^\// { print $3 }')"
            loaded="$(awk -v n="/${name}" '
                !found && index($0, "calling init: ") && substr($0, length($0) - length(n) + 1) == n {
                    sub(/^.*calling init: /, ""); print; found = 1
                }' "${trace}"/ld.* 2>/dev/null || true)"
            if [ -z "$loaded" ]; then
                note "${name}: the app never loaded it, so which copy it takes was not seen"
            elif [ -n "$system" ]; then
                if [ "$(readlink -f "$loaded")" = "$(readlink -f "$system")" ]; then
                    pass "${name} is this system's own  ${DIM}${system}${RESET}"
                else
                    fail "${name} came from ${loaded}, and this system has its own: ${system}"
                fi
            elif [ "$(readlink -f "$loaded")" = "$(readlink -f "${dir}${name}")" ]; then
                pass "${name} is the bundle's  ${DIM}this system has none of its own${RESET}"
            else
                fail "${name} came from ${loaded}, on a system with none of its own, rather than from lib/fallback/"
            fi
        done
        rm -rf "$trace"
    fi

    # --- 5. The interface loads -------------------------------------------
    #
    # Started for real and then killed. It will fail to reach the platform and
    # fail to find Docker, both of which are fine and neither of which is what
    # is being looked for here: a QML module that did not make it into the
    # bundle says so on stderr and carries on with an empty window, so only
    # reading that stderr finds it.
    log="$(mktemp)"
    # Through `sh -c` so that the kill at the end of the timeout is that shell's
    # exit status rather than a signal this one reports as "Killed" beside a
    # check that passed.
    HOME="$(mktemp -d)" QT_QPA_PLATFORM=offscreen \
        sh -c "timeout --signal=KILL 25 '${BUNDLE}/simorg-desktop' --background" >"$log" 2>&1 || true

    trouble='is not installed|Cannot load library|failed to load component|Type [A-Za-z0-9_.]+ unavailable|error while loading shared libraries|This application failed to start'
    if grep -qE "$trouble" "$log"; then
        fail "the interface did not load"
        # The whole log, not the matching lines: a QML failure names the type
        # that was unavailable on one line and the reason it was unavailable
        # three lines further down, and the second one is the useful one.
        # One sed rather than `sed | head -40`: a log past a pipe's 64 KB would
        # leave sed writing into a closed pipe, and pipefail would end the
        # verification here instead of carrying on to the other checks.
        sed -n '1,40s/^/    /p' "$log" >&2
    else
        pass "the interface loads with every QML module resolved"
    fi
    rm -f "$log"

    # --- 6. Agent surfaces render -----------------------------------------
    #
    # The Workbench and the Brain are web pages, and a bundle can pass all of
    # the above with Chromium unable to draw one: QtWebEngineProcess not found,
    # resources/ missing, a library only the renderer needs, a sandbox that
    # kills every renderer on start. So the app itself is asked to render a page
    # (`--check-web-engine`), under a virtual display: its built-in page, whose
    # script has to run, and SIMORG_VERIFY_WEB_URL too when set, which proves
    # TLS and certificates.
    if [ -x "${BUNDLE}/libexec/QtWebEngineProcess" ]; then
        if ! command -v xvfb-run >/dev/null 2>&1; then
            note "no xvfb-run here, so no page was rendered"
        else
            for url in "" ${SIMORG_VERIFY_WEB_URL:-}; do
                log="$(mktemp)"
                if HOME="$(mktemp -d)" xvfb-run -a -s '-screen 0 1280x800x24' \
                     timeout --signal=KILL 90 "${BUNDLE}/simorg-desktop" --check-web-engine $url >"$log" 2>&1; then
                    pass "renders ${url:-its built-in page}  ${DIM}$(grep -m1 'web engine:' "$log" | sed 's/^.*web engine: //' | cut -c1-70)${RESET}"
                    grep -m1 "without Chromium's sandbox" "$log" | sed 's/^.*Agent surfaces/Agent surfaces/' \
                        | while read -r sentence; do note "$sentence"; done
                else
                    fail "the web engine did not render ${url:-its built-in page}"
                    sed 's/^/    /' "$log" | tail -30 >&2
                fi
                rm -f "$log"
            done
        fi
    else
        note "no Qt WebEngine in this bundle, so agent surfaces are not drawn by it"
    fi
fi

# --- What the machine had to provide --------------------------------------
#
# Every library this will resolve outside itself, transitively — so the list is
# a little longer than scripts/linux-host-libraries.txt, because it also names
# what the host's own libraries pull in behind them. That is the right list to
# print: it is the whole of what a target machine has to already have.
printf '\n  %sthe bundle asked this machine for%s\n' "${BOLD}" "${RESET}"
while IFS= read -r -d '' f; do
    is_elf "$f" || continue
    ldd "$f" 2>/dev/null \
        | awk -v b="$BUNDLE" '/=>/ && $3 != "" && index($3, b) != 1 { print $1 }'
done < <(find "$BUNDLE" -type f -print0) \
    | sort -u \
    | while read -r soname; do [ -f "${BUNDLE}/lib/${soname}" ] || printf '    %s\n' "$soname"; done

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
    printf '%s%d check(s) failed — these artifacts are not self-contained%s\n\n' "${RED}" "$FAILURES" "${RESET}" >&2
    exit 1
fi
printf '  %s✓ self-contained%s\n\n' "${GREEN}${BOLD}" "${RESET}"
