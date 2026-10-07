#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Turns a staged install tree into a self-contained Linux directory: one that
# runs on a machine with no Qt, no development packages and nothing installed
# for it.
#
#   ./scripts/bundle-linux.sh --stage /stage/usr --out /bundle/simorg-0.1.0-linux-arm64
#
# Qt has no supported way to do this. `qt_generate_deploy_qml_app_script` covers
# macOS and Windows; on Linux it is a no-op that prints a warning, which would
# leave a build with the program alone and a hope that the target has Qt 6. It
# does not, and the first thing anybody sees is
#
#   ./simorg-desktop: error while loading shared libraries: libQt6WebSockets.so.6
#
# So this walks the dependency graph itself, copies what a target cannot be
# expected to have, and leaves alone what it must provide — see EXCLUDE below
# for where that line is and why it is drawn there.
#
# The result is a directory, never a tree to unpack over /usr: it carries a
# qt.conf, and a qt.conf in /usr/bin would redirect every other Qt application
# on the machine.
#
# With --glibc-floor it is then made to load on a C library as old as that,
# whatever the build machine had — see "The oldest system it runs on" below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STAGE=""
OUT=""
QML_SOURCE="${SOURCE_DIR}/src/app/qml"
STRIP=0
GLIBC_FLOOR=""
GLIBCXX_FLOOR=""
POLYFILL_GLIBC=""

# ------------------------------------------------------------------ output ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info()  { printf '  %s\n' "$*"; }
muted() { printf '  %s%s%s\n' "${DIM}" "$*" "${RESET}"; }
warn()  { printf '%swarning:%s %s\n' "${YELLOW}" "${RESET}" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "${RED}" "${RESET}" "$*" >&2; exit 1; }
ok()    { printf '  %s✓%s %s\n' "${GREEN}" "${RESET}" "$*"; }

# A command nobody expected to fail ends the run under `set -e` without a word,
# and the build log then says only that the Docker step exited 1. This names the
# line and the command instead.
trap 'printf "%serror:%s line %s failed: %s\n" "${RED}" "${RESET}" "$LINENO" "$BASH_COMMAND" >&2' ERR

usage() {
    cat <<EOF
${BOLD}Simorg Linux bundler${RESET}

  ./scripts/bundle-linux.sh --stage <dir> --out <dir> [options]

${BOLD}REQUIRED${RESET}
  --stage <dir>        The staged install prefix — the 'usr' of a
                       \`DESTDIR=… cmake --install\`.
  --out <dir>          Bundle root to create. Deleted first if it exists.

${BOLD}OPTIONS${RESET}
  --qml-source <dir>   QML to scan for imports. Default: src/app/qml.
  --strip              Strip the bundled binaries and libraries.
  --glibc-floor <x.y>  Make every file load on this glibc or newer, with
                       polyfill-glibc. Needs --glibcxx-floor beside it.
  --glibcxx-floor <v>  The newest GLIBCXX_ version the floor system's C++
                       runtime has, like 3.4.30; anything newer fails the run.
  --polyfill-glibc <f> The polyfill-glibc program. Default: the one on PATH.
  --help               This.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --stage)      STAGE="${2:?--stage needs a directory}"; shift 2 ;;
        --out)        OUT="${2:?--out needs a directory}"; shift 2 ;;
        --qml-source) QML_SOURCE="${2:?--qml-source needs a directory}"; shift 2 ;;
        --strip)      STRIP=1; shift ;;
        --glibc-floor)    GLIBC_FLOOR="${2:?--glibc-floor needs a version, like 2.35}"; shift 2 ;;
        --glibcxx-floor)  GLIBCXX_FLOOR="${2:?--glibcxx-floor needs a version, like 3.4.30}"; shift 2 ;;
        --polyfill-glibc) POLYFILL_GLIBC="${2:?--polyfill-glibc needs the program}"; shift 2 ;;
        --help|-h)    usage; exit 0 ;;
        *)            die "unknown option '$1' — try --help" ;;
    esac
done

[ -n "$STAGE" ] || { usage; die "--stage is required"; }
[ -n "$OUT" ]   || { usage; die "--out is required"; }
[ -d "$STAGE" ] || die "no such staged tree: ${STAGE}"

for tool in patchelf ldd readelf; do
    command -v "$tool" >/dev/null 2>&1 || die "${tool} is required (apt-get install patchelf binutils)"
done
if [ -n "$GLIBC_FLOOR" ]; then
    [ -n "$GLIBCXX_FLOOR" ] || die "--glibc-floor needs --glibcxx-floor: the C++ runtime is the floor system's too"
    POLYFILL_GLIBC="${POLYFILL_GLIBC:-$(command -v polyfill-glibc || true)}"
    [ -x "$POLYFILL_GLIBC" ] || die "--glibc-floor needs polyfill-glibc (github.com/corsix/polyfill-glibc), and there is none on PATH"
    command -v c++ >/dev/null 2>&1 || die "--glibc-floor needs a C++ compiler for the compatibility library"
fi

# --------------------------------------------------------------- exclusions --
#
# What a target machine provides. The list and the reasoning behind every line
# of it live in scripts/linux-host-libraries.txt, shared with the verifier so
# that the two can never come to disagree about where the line is.
HOST_LIST="${SCRIPT_DIR}/linux-host-libraries.txt"
[ -f "$HOST_LIST" ] || die "missing ${HOST_LIST}"

EXCLUDE_PATTERNS=()
FALLBACK_PATTERNS=()
while IFS= read -r line; do
    line="${line%%#*}"
    read -r pattern word _ <<< "$line" || true
    [ -n "${pattern:-}" ] || continue
    EXCLUDE_PATTERNS+=("$pattern")
    case "${word:-}" in
        "")       ;;
        fallback) FALLBACK_PATTERNS+=("$pattern") ;;
        *)        die "${HOST_LIST}: '${word}' after ${pattern} is not a word it knows (only 'fallback')" ;;
    esac
done < "$HOST_LIST"

matches_any() {
    local name="$1" pattern; shift
    for pattern in "$@"; do
        # shellcheck disable=SC2254
        case "$name" in $pattern) return 0 ;; esac
    done
    return 1
}
is_excluded() { matches_any "$1" "${EXCLUDE_PATTERNS[@]}"; }
is_fallback() { [ ${#FALLBACK_PATTERNS[@]} -gt 0 ] && matches_any "$1" "${FALLBACK_PATTERNS[@]}"; }

# ----------------------------------------------------------------- Qt paths --
qt_query() {
    local key="$1"
    if command -v qtpaths6 >/dev/null 2>&1; then
        qtpaths6 --query "$key" 2>/dev/null && return 0
    fi
    if command -v qmake6 >/dev/null 2>&1; then
        qmake6 -query "$key" 2>/dev/null && return 0
    fi
    if command -v qtpaths >/dev/null 2>&1; then
        qtpaths --query "$key" 2>/dev/null && return 0
    fi
    return 1
}

QT_LIBS="$(qt_query QT_INSTALL_LIBS || true)"
QT_PLUGINS="$(qt_query QT_INSTALL_PLUGINS || true)"
QT_QML="$(qt_query QT_INSTALL_QML || true)"
QT_LIBEXECS="$(qt_query QT_HOST_LIBEXECS || true)"
QT_BINS="$(qt_query QT_HOST_BINS || true)"

[ -n "$QT_PLUGINS" ] || die "cannot find Qt — qtpaths6 and qmake6 are both missing"
[ -d "$QT_PLUGINS" ] || die "Qt reports a plugin directory that does not exist: ${QT_PLUGINS}"

# ------------------------------------------------------------------- layout --
rm -rf "$OUT"
mkdir -p "${OUT}/bin" "${OUT}/lib" "${OUT}/plugins"
mkdir -p "${OUT}/qml"

printf '\n%s▸ Bundling%s %s\n' "${BOLD}" "${RESET}" "${DIM}$(basename "$OUT")${RESET}"
muted "qt libs     ${QT_LIBS}"
muted "qt plugins  ${QT_PLUGINS}"
muted "qt qml      ${QT_QML}"

# --- The program itself --------------------------------------------------
[ -d "${STAGE}/bin" ] || die "no bin/ in the staged tree: ${STAGE}"
cp -a "${STAGE}/bin/." "${OUT}/bin/"
if [ -d "${STAGE}/share" ]; then
    mkdir -p "${OUT}/share"
    cp -a "${STAGE}/share/." "${OUT}/share/"
fi

# --- Qt plugins ----------------------------------------------------------
#
# Chosen by category rather than copied wholesale. Every one of these is loaded
# by soname at run time, so none of them is reachable from `ldd` — a bundle that
# walked dependencies alone would start and then have no way to draw a window,
# open a TLS connection or decode a PNG.
copy_plugin_category() {
    local category="$1"
    local src="${QT_PLUGINS}/${category}"
    [ -d "$src" ] || return 0
    mkdir -p "${OUT}/plugins/${category}"
    find "$src" -maxdepth 1 -name '*.so' -exec cp -aL {} "${OUT}/plugins/${category}/" \;
}

# tls carries the OpenSSL backend, and without it every HTTPS request and the
# Hub's own wss:// socket fail with "TLS initialization failed" — on a machine
# that has OpenSSL installed, which is what makes it such a puzzling one.
PLUGIN_CATEGORIES=(tls networkinformation)

PLUGIN_CATEGORIES+=(
    platforms                       # xcb, wayland, eglfs, offscreen, minimal, linuxfb
    platforminputcontexts           # compose key, ibus
    platformthemes                  # xdgdesktopportal, where Qt built one
    xcbglintegrations               # glx and egl under X
    wayland-decoration-client
    wayland-graphics-integration-client
    wayland-shell-integration
    egldeviceintegrations           # eglfs on a board with no window system
    imageformats                    # svg, jpeg, gif, ico, webp
    iconengines                     # the svg icon engine, which the tray uses
    generic                         # evdev keyboard, mouse and touch
)

for category in "${PLUGIN_CATEGORIES[@]}"; do
    copy_plugin_category "$category"
done

# A debug build's Qt ships these beside the real ones; they are for a debugger
# to attach to and only make the archive larger.
find "${OUT}/plugins" -name '*.debug' -delete 2>/dev/null || true

# The GTK 3 theme is the one plugin left out. It links the whole of GTK — GDK,
# Pango, gdk-pixbuf, cairo — which cannot be carried, because GTK loads the
# desktop's own themes, input modules and pixbuf loaders into the process, and
# which cannot be asked for either, because a machine without GTK would then
# not start at all. Qt picks the desktop portal's theme or its own instead;
# what is given up is a GTK-drawn file dialog on a desktop without a portal.
rm -f "${OUT}/plugins/platformthemes/libqgtk3.so"

ok "plugins  $(find "${OUT}/plugins" -name '*.so' | wc -l | tr -d ' ') files"

# --- QML modules ---------------------------------------------------------
#
# Found with Qt's own qmlimportscanner so the list stays right as the interface
# grows, then widened to the whole top-level module directory of each hit. That
# widening is deliberate: QtQuick.Controls resolves its *style* at run time, so
# QtQuick/Controls/Basic is never an import anybody wrote and is exactly what
# the application will not start without.
[ -n "$QT_QML" ] && [ -d "$QT_QML" ] || die "Qt reports no QML directory; is qt6-declarative installed?"

SCANNER=""
for candidate in "${QT_LIBEXECS}/qmlimportscanner" "${QT_BINS}/qmlimportscanner" \
                 "$(command -v qmlimportscanner 2>/dev/null || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { SCANNER="$candidate"; break; }
done

declare -a QML_TOP_LEVEL=()
if [ -n "$SCANNER" ] && [ -d "$QML_SOURCE" ]; then
    while IFS= read -r relative; do
        [ -n "$relative" ] || continue
        QML_TOP_LEVEL+=("${relative%%/*}")
    done < <(
        "$SCANNER" -rootPath "$QML_SOURCE" -importPath "$QT_QML" 2>/dev/null \
            | sed -n 's/.*"relativePath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    )
    muted "qmlimportscanner  ${#QML_TOP_LEVEL[@]} imports from $(basename "$QML_SOURCE")"
else
    warn "qmlimportscanner not found; falling back to the known module list"
fi

# Always present, scanner or not. QtQml and QtQuick are the engine itself;
# Qt is the module qt_add_qml_module's generated code imports; QtCore is
# where QtQml.Base's value types live on 6.5 and later.
QML_TOP_LEVEL+=(QtQml QtQuick Qt QtCore)

declare -A QML_SEEN=()
for module in "${QML_TOP_LEVEL[@]}"; do
    [ -n "$module" ] || continue
    [ -n "${QML_SEEN[$module]:-}" ] && continue
    QML_SEEN["$module"]=1
    [ -d "${QT_QML}/${module}" ] || continue
    cp -aL "${QT_QML}/${module}" "${OUT}/qml/" 2>/dev/null || cp -a "${QT_QML}/${module}" "${OUT}/qml/"
done

# builtins.qmltypes sits at the root of the import path and is what the
# engine reads to know the types it has without loading anything.
for extra in builtins.qmltypes jsroot.qmltypes; do
    [ -f "${QT_QML}/${extra}" ] && cp -aL "${QT_QML}/${extra}" "${OUT}/qml/"
done

# Tooling for a QML debugger, and Designer's own copies of the controls.
# Neither runs here, and together they are a third of the tree.
rm -rf "${OUT}/qml/QtQuick/Controls/designer" "${OUT}/qml/QtQuick/Dialogs/quickimpl/qml/+Imagine" 2>/dev/null || true
find "${OUT}/qml" -name '*.debug' -delete 2>/dev/null || true
# Qt's own builds keep, beside each plugin, the object files and archives a
# program links when it takes Qt statically — objects-<config>/…/*.cpp.o —
# and Qt/test is QtTest's helpers for testing controls. Nothing here links
# or tests anything.
find "${OUT}/qml" -type d -name 'objects-*' -prune -exec rm -rf {} + 2>/dev/null || true
find "${OUT}/qml" -type f \( -name '*.o' -o -name '*.a' \) -delete 2>/dev/null || true
rm -rf "${OUT}/qml/Qt/test" 2>/dev/null || true

ok "qml      $(find "${OUT}/qml" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') modules"

# --- The dependency closure ----------------------------------------------
#
# Everything above is a starting point; this is what makes the bundle complete.
# Each ELF file in it is asked what it needs, anything not excluded is copied to
# lib/ and then asked the same question, until nothing new comes back.
#
# The question is asked with readelf rather than ldd, and the difference
# matters. `ldd` prints the whole transitive closure, so walking it means
# walking *through* the host libraries too: libdbus-1 is bundled and links
# libsystemd, which is not, and following ldd from there would drag lz4, lzma,
# zstd, gcrypt and libcap into the bundle for the sole benefit of a library the
# host is providing anyway. DT_NEEDED is the direct edge, and the direct edge is
# the one that belongs to us.
declare -A BUNDLED=()     # soname -> 1
declare -A BUNDLED_FROM=() # soname -> the file on this system it was copied from
declare -A HOST_DEPS=()   # soname -> 1, the ones we deliberately left behind
declare -A FALLBACK=()    # soname -> the file copied to lib/fallback/, for a host without one
declare -a WORKLIST=()

is_elf() {
    # `file` is not installed everywhere; the four magic bytes are.
    [ -f "$1" ] || return 1
    [ "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]
}

needed_of() {
    readelf -d "$1" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p'
}

# Resolved the way the loader would, then the way the rest of the system would.
# The first covers a library sitting in a prefix nobody registered; the second
# covers one this file does not itself link but that something else in the
# bundle opens by name.
resolve_soname() {
    local from="$1" soname="$2" path dir
    # Every awk here reads to the end rather than `exit` at the first match:
    # `ldconfig -p` runs well past a pipe's 64 KB, and an awk that stops early
    # leaves it writing into a closed pipe, which pipefail turns into a failure
    # that `set -e` ends the whole bundle on, without a word.
    path="$(ldd "$from" 2>/dev/null | awk -v n="$soname" '$1 == n && $3 != "" && !found { print $3; found = 1 }')"
    if [ -n "$path" ] && [ -f "$path" ]; then printf '%s' "$path"; return 0; fi
    path="$(ldconfig -p 2>/dev/null | awk -v n="$soname" '$1 == n && !found { print $NF; found = 1 }')"
    if [ -n "$path" ] && [ -f "$path" ]; then printf '%s' "$path"; return 0; fi
    for dir in "$QT_LIBS" /usr/local/lib /usr/lib; do
        [ -n "$dir" ] && [ -f "${dir}/${soname}" ] && { printf '%s' "${dir}/${soname}"; return 0; }
    done
    return 1
}

# An `if` rather than `is_elf && …`: that line's status is the loop's, and so
# the function's, whenever the last file find lists is not ELF, and under
# `set -e` that ended the whole bundle without a word.
enqueue_tree() {
    local root="$1" f
    [ -d "$root" ] || return 0
    while IFS= read -r -d '' f; do
        if is_elf "$f"; then WORKLIST+=("$f"); fi
    done < <(find "$root" -type f -print0)
}

# --- Qt WebEngine --------------------------------------------------------
#
# The Workbench and the Brain are web pages drawn by Chromium inside Qt
# WebEngine, and three parts of it are found by path at run time rather than
# linked, so no dependency walk reaches them: QtWebEngineProcess, the helper
# every page runs in; resources/, its .pak files, ICU's data and V8's snapshot;
# and translations/qtwebengine_locales. Missing any of them, the app starts and
# every surface stays blank. qt.conf below points at all three.
QT_LIBEXECS_TARGET="$(qt_query QT_INSTALL_LIBEXECS || true)"
QT_DATA="$(qt_query QT_INSTALL_DATA || true)"
QT_TRANSLATIONS="$(qt_query QT_INSTALL_TRANSLATIONS || true)"
WEBENGINE=0
if [ -f "${OUT}/bin/simorg-desktop" ] \
   && needed_of "${OUT}/bin/simorg-desktop" | grep -q '^libQt6WebEngine'; then
    [ -x "${QT_LIBEXECS_TARGET}/QtWebEngineProcess" ] \
        || die "the app links Qt WebEngine and there is no ${QT_LIBEXECS_TARGET}/QtWebEngineProcess"
    [ -d "${QT_DATA}/resources" ] || die "the app links Qt WebEngine and there is no ${QT_DATA}/resources"
    mkdir -p "${OUT}/libexec" "${OUT}/resources" "${OUT}/translations"
    cp -aL "${QT_LIBEXECS_TARGET}/QtWebEngineProcess" "${OUT}/libexec/"
    cp -aL "${QT_DATA}/resources/." "${OUT}/resources/"
    if [ -d "${QT_TRANSLATIONS}/qtwebengine_locales" ]; then
        cp -aL "${QT_TRANSLATIONS}/qtwebengine_locales" "${OUT}/translations/"
    fi
    WEBENGINE=1
    ok "webengine  QtWebEngineProcess, $(find "${OUT}/resources" -type f | wc -l | tr -d ' ') resources, $(find "${OUT}/translations" -name '*.pak' | wc -l | tr -d ' ') locales"
fi

enqueue_tree "${OUT}/bin"
enqueue_tree "${OUT}/libexec"
enqueue_tree "${OUT}/plugins"
enqueue_tree "${OUT}/qml"

# Qt 6 opens libssl and libcrypto by soname at run time rather than linking
# them, so the TLS backend plugin does not name them and no amount of walking
# DT_NEEDED will find them. Named here for that reason alone — and the symptom
# of getting this wrong is not a missing library, it is every HTTPS request and
# the Hub's own wss:// socket failing with "TLS initialization failed" on a
# machine that plainly has OpenSSL installed.
for runtime_dlopen in libssl.so.3 libcrypto.so.3 libssl.so.1.1 libcrypto.so.1.1; do
    found="$(ldconfig -p 2>/dev/null | awk -v n="$runtime_dlopen" '$1 == n && !found { print $NF; found = 1 }')"
    if [ -n "$found" ] && [ -f "$found" ] && [ -z "${BUNDLED[$runtime_dlopen]:-}" ]; then
        cp -L "$found" "${OUT}/lib/${runtime_dlopen}"
        chmod u+w "${OUT}/lib/${runtime_dlopen}"
        BUNDLED["$runtime_dlopen"]=1
        WORKLIST+=("${OUT}/lib/${runtime_dlopen}")
    fi
done

# Qt WebEngine's Chromium does the same with NSS: the software token (softokn,
# with freebl behind it) and the built-in root certificates (nssckbi) are
# PKCS#11 modules NSS opens by file name, from the directory the libnss3 it is
# running was loaded from — this bundle's lib/ — the first time it needs a key
# or a certificate. No NEEDED entry names them, and without the token Chromium
# cannot start NSS at all, so every page it loads over HTTPS goes with it.
# Debian and Ubuntu keep them in nss/ beside libnss3.
if [ "$WEBENGINE" -eq 1 ]; then
    nss_found="$(ldconfig -p 2>/dev/null | awk '$1 == "libnss3.so" && !found { print $NF; found = 1 }')"
    [ -n "$nss_found" ] || die "Qt WebEngine links NSS and there is no libnss3.so on this system"
    nss_dir="$(dirname "$(readlink -f "$nss_found")")"
    for module in libsoftokn3.so libfreeblpriv3.so libfreebl3.so libnssckbi.so; do
        found=""
        for candidate in "${nss_dir}/${module}" "${nss_dir}/nss/${module}"; do
            if [ -f "$candidate" ]; then found="$candidate"; break; fi
        done
        if [ -z "$found" ]; then
            [ "$module" = "libsoftokn3.so" ] && die "NSS's software token, ${module}, is not beside ${nss_found}"
            continue
        fi
        cp -L "$found" "${OUT}/lib/${module}"
        chmod u+w "${OUT}/lib/${module}"
        BUNDLED["$module"]=1
        WORKLIST+=("${OUT}/lib/${module}")
    done
fi

while [ ${#WORKLIST[@]} -gt 0 ]; do
    current="${WORKLIST[0]}"
    WORKLIST=("${WORKLIST[@]:1}")

    while read -r soname; do
        [ -n "$soname" ] || continue

        if is_excluded "$soname"; then
            HOST_DEPS["$soname"]=1
            # The host's, but carried too for a host that has none. In a
            # directory of its own, so that the launchers can offer it to the
            # loader alone — see "Launchers" below.
            if is_fallback "$soname" && [ -z "${FALLBACK[$soname]:-}" ]; then
                resolved="$(resolve_soname "$current" "$soname")" \
                    || die "${soname} is needed by $(basename "$current"), is carried for a host without one, and is nowhere on this system"
                mkdir -p "${OUT}/lib/fallback/${soname}"
                cp -L "$resolved" "${OUT}/lib/fallback/${soname}/${soname}"
                chmod u+w "${OUT}/lib/fallback/${soname}/${soname}"
                FALLBACK["$soname"]="$resolved"
                WORKLIST+=("${OUT}/lib/fallback/${soname}/${soname}")
            fi
            continue
        fi
        [ -n "${BUNDLED[$soname]:-}" ] && continue

        if ! resolved="$(resolve_soname "$current" "$soname")"; then
            die "${soname} is needed by $(basename "$current") and is nowhere on this system"
        fi

        cp -L "$resolved" "${OUT}/lib/${soname}"
        chmod u+w "${OUT}/lib/${soname}"
        BUNDLED["$soname"]=1
        BUNDLED_FROM["$soname"]="$resolved"
        WORKLIST+=("${OUT}/lib/${soname}")
    done < <(needed_of "$current")
done

ok "lib      ${#BUNDLED[@]} shared objects"
if [ ${#FALLBACK[@]} -gt 0 ]; then
    ok "fallback $(printf '%s\n' "${!FALLBACK[@]}" | sort | tr '\n' ' ')${DIM}for a host without its own${RESET}"
fi

# --- The notices of what was just bundled --------------------------------
#
# Every library copied into lib/ is somebody else's work under a licence that
# asks for its notice to travel with it — glib is LGPL, NSS is MPL, ICU, PCRE2,
# fontconfig, FreeType and the rest each have theirs. The build container is
# Debian, and Debian keeps every package's licence as
# /usr/share/doc/<package>/copyright (kept even in the slim images), so the
# notices are read from there and appended to the file cmake/SimorgNotices.cmake
# installed. Qt's own libraries come from the Qt installation rather than a
# package and are covered by the Qt section already in that file; anything
# else without a copyright file is listed by name rather than dropped.
NOTICES="${OUT}/share/licenses/simorg/THIRD-PARTY-NOTICES.txt"

# The Debian package a bundled file came from, or nothing — never a failure.
# Asked under every name the file goes by, because dpkg only knows the one its
# package shipped: /lib is a link into /usr/lib on both build systems, so
# readlink -f always answers in the /usr spelling, but Debian 12's database
# still records much of the base system under /lib (libcom_err, libz, libgcc)
# and answers "no path found" for the other. Ubuntu 24.04, the arm64 build,
# moved its packages to /usr, which is why only the x86-64 build ever met it.
package_of() {
    local real path pkg
    real="$(readlink -f "$1")"
    for path in "$real" "${real#/usr}" "$1"; do
        pkg="$(dpkg -S "$path" 2>/dev/null | awk -F: '!/^diversion / { print $1; exit }')" || true
        if [ -n "$pkg" ]; then printf '%s' "$pkg"; return 0; fi
    done
    return 0
}

if [ -f "$NOTICES" ] && command -v dpkg >/dev/null 2>&1; then
    declare -A NOTICED_PKGS=()
    unnoticed=()
    {
        printf '\n======================================================================\n'
        printf 'Libraries bundled beside the program on Linux\n'
        printf '======================================================================\n\n'
        printf 'Each is the work of its authors, under the licence in its notice below, as\n'
        printf 'recorded by the Debian package it was taken from.\n'
        for soname in $(printf '%s\n' "${!BUNDLED[@]}" "${!FALLBACK[@]}" | sort -u); do
            src="${BUNDLED_FROM[$soname]:-${FALLBACK[$soname]:-}}"
            [ -n "$src" ] || continue
            case "$src" in "${QT_LIBS}"/*) continue ;; esac
            pkg="$(package_of "$src")"
            if [ -z "$pkg" ] || [ ! -f "/usr/share/doc/${pkg}/copyright" ]; then
                unnoticed+=("$soname")
                continue
            fi
            [ -n "${NOTICED_PKGS[$pkg]:-}" ] && continue
            NOTICED_PKGS["$pkg"]=1
            printf '\n%s (Debian package %s)\n' "$soname" "$pkg"
            printf -- '----------------------------------------------------------------------\n'
            cat "/usr/share/doc/${pkg}/copyright"
            printf '\n'
        done
        if [ "${#unnoticed[@]}" -gt 0 ]; then
            printf '\nBundled without a Debian copyright file on the build system:\n'
            for soname in "${unnoticed[@]}"; do printf '  %s\n' "$soname"; done
        fi
    } >> "$NOTICES"
    ok "notices  ${#NOTICED_PKGS[@]} packages appended to share/licenses/simorg/THIRD-PARTY-NOTICES.txt"
else
    warn "no THIRD-PARTY-NOTICES.txt in the staged tree, or no dpkg; the bundled libraries' notices were not appended"
fi

# --- Where each file looks for its libraries -----------------------------
#
# $ORIGIN is resolved by the loader against the file asking, so a bundle rebuilt
# this way has no absolute paths in it anywhere and can be unpacked to any
# directory a user likes. DT_RUNPATH is not inherited by dependencies, which is
# why this is applied to every file rather than only to the two executables.
rel_to_lib() {
    local dir="$1"
    dir="${dir#"$OUT"}"; dir="${dir#/}"
    [ "$dir" = "lib" ] && { printf '$ORIGIN'; return; }
    local up="" segment
    local IFS='/'
    for segment in $dir; do [ -n "$segment" ] && up="../${up}"; done
    printf '$ORIGIN/%slib' "$up"
}

while IFS= read -r -d '' f; do
    is_elf "$f" || continue
    patchelf --set-rpath "$(rel_to_lib "$(dirname "$f")")" "$f" 2>/dev/null \
        || warn "could not set the library path on ${f#"$OUT"/}"
done < <(find "$OUT" -type f -print0)

if [ "$STRIP" -eq 1 ] && command -v strip >/dev/null 2>&1; then
    while IFS= read -r -d '' f; do
        is_elf "$f" && strip --strip-unneeded "$f" 2>/dev/null || true
    done < <(find "$OUT" -type f -print0)
    ok "stripped"
fi

# --- The oldest system it runs on ------------------------------------------
#
# A program asks for the C library by version, and the loader refuses it on a
# system whose glibc is older than the newest version any of its files names —
# before a line of it runs, and silently when it was opened from a file
# manager. Qt's own arm64 build is made on Ubuntu 24.04 and names glibc 2.38,
# so on Raspberry Pi OS bookworm (2.36) Simorg Desktop would do nothing at all
# when opened. Measured, the whole bundle asks for 2.37 and later for
# exactly three things:
#
#   the C23 number parsers   __isoc23_strtol, __isoc23_sscanf and their kin,
#                            which glibc 2.38 names differently only so they can
#                            accept a 0b binary prefix
#   strlcpy and strlcat      new in 2.38
#   fmod and fmodf           given a second version in 2.38
#
# and the C++ runtime for one marker, std::ios_base_library_init, which GCC 13
# names in every file that includes <iostream> purely to demand its own
# runtime: nothing calls it.
#
# polyfill-glibc rewrites those references after the fact. The number parsers
# become the classic ones — the same functions except that a string starting
# 0b is read as 0 — renamed to whatever version this machine's own libc gives
# the classic name; strlcpy and strlcat get a copy of their code inside the
# file; fmod goes back to its first version. The marker is renamed to an
# unversioned one, exported by a small library built here, which also
# constructs std::ios_base::Init: on GCC 12's runtime that is what makes
# std::cout usable, and Qt Positioning writes to it. On a newer runtime it is
# one more reference to an object that is already there.
#
# Nothing is compiled differently, so every system at or above the floor runs
# exactly the code it ran before. What proves the result is the verify stage of
# docker/Dockerfile.linux-build, which runs every check on the floor system
# itself; this only refuses to finish when a file still asks for more.
# Every GLIBC_x.y, or GLIBCXX_x.y.z, a file names in its version references.
# Written so that a file naming none (ICU's data library links nothing) is an
# empty answer rather than a failed pipeline, which set -e would end the run on.
glibc_versions_of() {
    { readelf -W -V "$1" 2>/dev/null || true; } | { grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' || true; } \
        | sed 's/^GLIBC_//' | sort -u -V
}
glibcxx_versions_of() {
    { readelf -W -V "$1" 2>/dev/null || true; } | { grep -oE 'GLIBCXX_[0-9]+\.[0-9]+\.[0-9]+' || true; } \
        | sed 's/^GLIBCXX_//' | sort -u -V
}
# Whether a file names the GCC 13 marker. Read to the end rather than with
# grep -q, which would stop reading and leave objdump to die of SIGPIPE.
names_iostream_marker() {
    [ "$({ objdump -T "$1" 2>/dev/null || true; } | grep -c '_ZSt21ios_base_library_initv' || true)" -gt 0 ]
}
# Whether version $1 is newer than version $2.
version_above() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

if [ -n "$GLIBC_FLOOR" ]; then
    FLOOR_WORK="$(mktemp -d)"

    # The version this machine's libc gives a classic name by default, which is
    # the one every glibc since has kept for it on this architecture.
    LIBC="$(ldd "$(command -v readelf)" | awk '$1 == "libc.so.6" && !found { print $3; found = 1 }')"
    [ -f "$LIBC" ] || die "could not find this machine's libc.so.6 to read the classic names from"
    default_version_of() {
        objdump -T "$LIBC" | awk -v n="$1" '$NF == n && $(NF-1) ~ /^GLIBC_/ && !found { print $(NF-1); found = 1 }'
    }
    renames="${FLOOR_WORK}/renames.txt"
    : > "$renames"
    for name in strtol strtoul strtoll strtoull strtoimax strtoumax \
                strtol_l strtoul_l strtoll_l strtoull_l \
                wcstol wcstoul wcstoll wcstoull wcstoimax wcstoumax \
                wcstol_l wcstoul_l wcstoll_l wcstoull_l; do
        version="$(default_version_of "$name")"
        [ -n "$version" ] || die "this machine's libc has no ${name}, which the C23 ${name} is renamed to"
        printf '__isoc23_%s@GLIBC_2.38 %s@%s\n' "$name" "$name" "$version" >> "$renames"
    done
    printf '_ZSt21ios_base_library_initv@GLIBCXX_3.4.32 _ZSt21ios_base_library_initv\n' >> "$renames"

    cat > "${FLOOR_WORK}/cxx-compat.cpp" <<'EOF'
// Simorg's C++ compatibility library, made by scripts/bundle-linux.sh.
//
// GCC 13 names std::ios_base_library_init in every file that includes
// <iostream>, to demand a runtime that sets up std::cout by itself. The files
// that named it name this library's copy instead, and on an older runtime the
// object below is what sets std::cout up for them.
#include <ios>
namespace std { void ios_base_library_init() {} }
static std::ios_base::Init simorg_iostream_init;
EOF
    c++ -O2 -shared -fPIC -Wl,-soname,libsimorg-cxx-compat.so \
        -o "${OUT}/lib/libsimorg-cxx-compat.so" "${FLOOR_WORK}/cxx-compat.cpp"
    if [ "$STRIP" -eq 1 ]; then strip --strip-unneeded "${OUT}/lib/libsimorg-cxx-compat.so"; fi
    compat_used=0

    lowered=0
    while IFS= read -r -d '' f; do
        is_elf "$f" || continue
        [ "$f" = "${OUT}/lib/libsimorg-cxx-compat.so" ] && continue
        newest="$(glibc_versions_of "$f" | tail -1)"
        marker=0
        if names_iostream_marker "$f"; then marker=1; fi
        if { [ -n "$newest" ] && version_above "$newest" "$GLIBC_FLOOR"; } || [ "$marker" -eq 1 ]; then
            extra=()
            if [ "$marker" -eq 1 ]; then
                extra=(--add-early-needed=libsimorg-cxx-compat.so)
                compat_used=1
            fi
            "$POLYFILL_GLIBC" --rename-dynamic-symbols="$renames" "${extra[@]}" \
                --target-glibc="$GLIBC_FLOOR" "$f" >"${FLOOR_WORK}/out" 2>&1 \
                || { cat "${FLOOR_WORK}/out" >&2; die "could not make ${f#"$OUT"/} load on glibc ${GLIBC_FLOOR}"; }
            lowered=$((lowered + 1))
        fi
    done < <(find "$OUT" -type f -print0)

    if [ "$compat_used" -eq 1 ]; then
        BUNDLED["libsimorg-cxx-compat.so"]=1
    else
        rm -f "${OUT}/lib/libsimorg-cxx-compat.so"
    fi

    # Nothing may still ask for more than the floor system has.
    too_new=()
    while IFS= read -r -d '' f; do
        is_elf "$f" || continue
        newest="$(glibc_versions_of "$f" | tail -1)"
        newest_cxx="$(glibcxx_versions_of "$f" | tail -1)"
        if { [ -n "$newest" ] && version_above "$newest" "$GLIBC_FLOOR"; } \
            || { [ -n "$newest_cxx" ] && version_above "$newest_cxx" "$GLIBCXX_FLOOR"; }; then
            too_new+=("${f#"$OUT"/} (GLIBC_${newest:-none}, GLIBCXX_${newest_cxx:-none})")
        fi
    done < <(find "$OUT" -type f -print0)
    if [ ${#too_new[@]} -gt 0 ]; then
        printf '  %s\n' "${too_new[@]}" >&2
        die "these still ask for more than glibc ${GLIBC_FLOOR} and GLIBCXX ${GLIBCXX_FLOOR}"
    fi
    rm -rf "$FLOOR_WORK"
    ok "floor    glibc ${GLIBC_FLOOR} and GLIBCXX ${GLIBCXX_FLOOR}; ${lowered} files rewritten by polyfill-glibc"
fi

# --- qt.conf -------------------------------------------------------------
#
# How the binaries find plugins/ and qml/ without an environment variable, a
# wrapper or a compiled-in path. Qt reads this from beside the executable, which
# is also the reason this bundle is a directory rather than a tree to unpack
# over /usr — a qt.conf in /usr/bin would answer for every Qt application on the
# machine, not only for ours.
cat > "${OUT}/bin/qt.conf" <<'EOF'
[Paths]
Prefix = ..
Libraries = lib
LibraryExecutables = libexec
Plugins = plugins
Imports = qml
Qml2Imports = qml
Data = .
Translations = translations
EOF
# QtWebEngineProcess reads its own qt.conf, beside it, to find the same tree.
if [ "$WEBENGINE" -eq 1 ]; then cp "${OUT}/bin/qt.conf" "${OUT}/libexec/qt.conf"; fi

# --- Launchers -----------------------------------------------------------
#
# The binaries in bin/ run perfectly well on their own. These exist to clear the
# three environment variables that would otherwise send Qt looking for plugins
# in a *different* Qt — the one a developer has installed — and produce a crash
# inside a library nobody in this bundle shipped.
#
# And to offer lib/fallback/ to a host that needs it. Every file's RUNPATH is
# searched before the host's own libraries, so a library the host must win for
# cannot sit in lib/; and no RUNPATH can say "only if the host has none". So the
# launcher asks the loader's cache, as `ldconfig -p`, whether it knows a copy
# built for this architecture, and puts the library's directory in front with
# LD_LIBRARY_PATH only when it does not. Inherited by QtWebEngineProcess, which
# links what the app links. The one way in that skips this is bin/ directly,
# which on a host without the library fails to load as it always did.
case "$(uname -m)" in
    x86_64)  LDCONFIG_ABI="libc6,x86-64" ;;
    aarch64) LDCONFIG_ABI="libc6,AArch64" ;;
    *)       LDCONFIG_ABI="libc6" ;;
esac
for program in simorg-desktop; do
    [ -x "${OUT}/bin/${program}" ] || continue
    cat > "${OUT}/${program}" <<EOF
#!/bin/sh
# Simorg — run from anywhere; nothing here is installed and nothing is absolute.
here="\$(cd "\$(dirname "\$(readlink -f "\$0")")" && pwd)"
unset QT_PLUGIN_PATH QML_IMPORT_PATH QML2_IMPORT_PATH QT_QPA_PLATFORM_PLUGIN_PATH
unset QTWEBENGINEPROCESS_PATH QTWEBENGINE_RESOURCES_PATH QTWEBENGINE_LOCALES_PATH
EOF
    if [ ${#FALLBACK[@]} -gt 0 ]; then
        cat >> "${OUT}/${program}" <<EOF
# What the system provides and this carries in case it does not (the end of
# MANIFEST.txt): the system's own copy whenever the loader knows one.
known="\$( (/sbin/ldconfig -p || ldconfig -p) 2>/dev/null)"
for dir in "\${here}"/lib/fallback/*/; do
    [ -d "\$dir" ] || continue
    case "\$known" in *"\$(basename "\$dir") (${LDCONFIG_ABI}"*) continue ;; esac
    LD_LIBRARY_PATH="\${dir%/}\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
    export LD_LIBRARY_PATH
done
EOF
    fi
    printf 'exec "${here}/bin/%s" "$@"\n' "$program" >> "${OUT}/${program}"
    chmod +x "${OUT}/${program}"
done

# --- What is in here, and what this still asks of the machine ------------
{
    printf 'Simorg — bundled Linux build\n\n'
    printf 'Architecture   %s\n' "$(uname -m)"
    printf 'Built against  Qt %s\n' "$(qt_query QT_VERSION 2>/dev/null || echo unknown)"
    if [ -n "$GLIBC_FLOOR" ]; then
        printf 'Runs on        glibc %s and GLIBCXX %s or newer\n' "$GLIBC_FLOOR" "$GLIBCXX_FLOOR"
    fi
    printf 'Contents       %s\n\n' 'simorg-desktop'

    printf 'BUNDLED LIBRARIES (%d)\n' "${#BUNDLED[@]}"
    printf '  Nothing below has to be installed on the machine that runs this.\n\n'
    for soname in $(printf '%s\n' "${!BUNDLED[@]}" | sort); do printf '  %s\n' "$soname"; done

    printf '\nPROVIDED BY THE TARGET SYSTEM (%d)\n' "${#HOST_DEPS[@]}"
    printf '  The C library, the C++ runtime, the graphics driver and the display\n'
    printf '  server'"'"'s own client libraries. Every one of these is already on any\n'
    printf '  Linux machine with a graphical session, and a bundled copy of any of\n'
    printf '  them would be loaded *instead of* the one the driver needs.\n\n'
    for soname in $(printf '%s\n' "${!HOST_DEPS[@]}" | sort); do printf '  %s\n' "$soname"; done

    if [ ${#FALLBACK[@]} -gt 0 ]; then
        printf '\nCARRIED FOR A SYSTEM WITHOUT ITS OWN (%d)\n' "${#FALLBACK[@]}"
        printf '  Provided by the system like the list above, but not on every one — WSL,\n'
        printf '  a server reached over ssh -X, a minimal install. A copy is in\n'
        printf '  lib/fallback/, and the launchers load it only on a system that has none;\n'
        printf '  where it has one, that one is loaded, as the system'"'"'s own plugins need.\n\n'
        for soname in $(printf '%s\n' "${!FALLBACK[@]}" | sort); do printf '  %s\n' "$soname"; done
    fi
} > "${OUT}/MANIFEST.txt"

# --- A note for whoever unpacks it ---------------------------------------
cat > "${OUT}/README.txt" <<'EOF'
Simorg
======

Unpack anywhere and run. Nothing is installed, nothing is registered, and no
package has to be added to this machine first.

    ./simorg-desktop            the desktop app

It also works from bin/ directly; the script beside this file only clears
environment variables left over from a Qt installed elsewhere on the machine.
To work from a terminal instead, Simorg CLI is an application of its own, with
an install line on its page on simorg.tech.

To remove Simorg, delete this directory.

MANIFEST.txt lists every library carried in here and the short list this still
expects the machine to have — the C library, the C++ runtime, the graphics
driver and the display server's client libraries, all of which are present on
any Linux system with a desktop on it.

INSTALLING IT PROPERLY (optional)
---------------------------------
    sudo mv <this directory> /opt/simorg
    sudo ln -sf /opt/simorg/simorg-desktop /usr/local/bin/simorg-desktop
    sudo cp share/applications/tech.simorg.desktop.desktop /usr/share/applications/
    sudo cp share/icons/hicolor/scalable/apps/tech.simorg.desktop.svg \
            /usr/share/icons/hicolor/scalable/apps/

The .desktop file runs `simorg-desktop`, so the symlink above is what makes the
application menu entry work.
EOF

printf '  %s✓%s %s%s%s\n' "${GREEN}" "${RESET}" "${BOLD}" \
    "$(du -sh "$OUT" 2>/dev/null | cut -f1) in $(basename "$OUT")" "${RESET}"
