#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Builds Simorg for every platform it ships on, one directory per target.
#
#   ./scripts/build-targets.sh                    every target this host can do
#   ./scripts/build-targets.sh macos              just one
#   ./scripts/build-targets.sh --config dev       point the build at localhost
#   ./scripts/build-targets.sh --list             what the targets are
#
# Artifacts land under build/dist/<target>/, so which build is for which machine
# is a question you answer by reading a directory name rather than by inspecting
# a binary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${SOURCE_DIR}/build/dist"
WORK_DIR="${SOURCE_DIR}/build/targets"

# ------------------------------------------------------------------ output ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; BLUE=$'\033[38;5;39m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; BLUE=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

step()  { printf '\n%s▸ %s%s\n' "${BLUE}${BOLD}" "$*" "${RESET}"; }
info()  { printf '  %s\n' "$*"; }
muted() { printf '  %s%s%s\n' "${DIM}" "$*" "${RESET}"; }
warn()  { printf '%swarning:%s %s\n' "${YELLOW}" "${RESET}" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "${RED}" "${RESET}" "$*" >&2; exit 1; }
ok()    { printf '  %s✓%s %s\n' "${GREEN}" "${RESET}" "$*"; }

# ---------------------------------------------------------------- settings ---
#
# `--config` is the one flag most people will ever pass, so it is the one with a
# short spelling. It sets two things at once on purpose: a dev build is a Debug
# build *and* one that talks to localhost, and wanting one without the other has
# never come up.
#
#   dev   Debug, dev endpoints (localhost:10000), assertions on
#   prod  Release, production endpoints, stripped
CONFIG="prod"
PACKAGE=0
CLEAN=0

# Whether a dev build carries Qt inside the macOS bundle.
#
# It does not, by default, and that is the difference between a four-second
# macOS build and a five-minute one: copying Qt into Simorg.app means copying
# QtWebEngineCore, which is 204 MB of Chromium, and then signing all of it.
# Measured on an M-series Mac: 290 seconds, against 0.2 for the same install
# with the deployment switched off.
#
# Nothing is lost locally. An undeployed bundle links the Qt that built it, at
# the absolute paths Homebrew put it at, so it runs perfectly on this machine —
# it is only useless on anybody else's. A prod build always deploys; a dev build
# deploys when this is set.
PORTABLE=0
JOBS=""
REQUESTED=()

# The Qt a release is built against: one version, pinned, the same on every
# platform (build-windows.ps1 names it too), and one that carries Qt WebEngine —
# the Workbench and the Brain need 6.8 or later.
#
# A prod macOS build uses Qt's own universal build of it, not Homebrew's: a
# Homebrew bottle is one architecture, so it can never produce the Intel driver.
# `--install-qt` fetches it with aqtinstall into QT_ROOT; `--qt-prefix` points at
# any other Qt. A dev build keeps using Homebrew's, for speed.
QT_VERSION="6.11.2"
QT_ROOT="${SIMORG_QT_ROOT:-${HOME}/Qt-release}"
QT_PREFIX="${SIMORG_QT_PREFIX:-}"
INSTALL_QT=0
# What the app links beyond Qt's essentials (qtbase, qtdeclarative, qtsvg):
# WebEngine and the two it stands on, the image-format and shader plugins, and
# the serial port Qt Positioning's NMEA plugin links.
QT_MAC_MODULES=(qtwebengine qtwebchannel qtpositioning qtimageformats qtshadertools qtserialport)
# Pinned like every other build tool: a newer aqtinstall may lay Qt out differently.
AQT_VERSION="3.3.0"

# The distribution each Linux archive is compiled on — the oldest the Qt it
# carries can be built on, per architecture:
#
#   x64    Debian 12, glibc 2.36. Qt's x86-64 Linux binaries are built on RHEL 9
#          and need 2.34.
#   arm64  Ubuntu 24.04, glibc 2.39. Qt's arm64 Linux binaries are built on
#          Ubuntu 24.04 and Qt WebEngine names GLIBC_2.38.
#
# Neither is the oldest system the archive runs on. The bundler rewrites the few
# references to a newer C library (bundle-linux.sh --glibc-floor, driven by
# GLIBC_FLOOR in docker/Dockerfile.linux-build), so both run on glibc 2.35 and
# GCC 12's C++ runtime: Ubuntu 22.04, Debian 12 and Raspberry Pi OS bookworm on,
# which the Dockerfile's first verify stage proves on Ubuntu 22.04 itself.
#
# Pinned by digest, as every third-party image here is: a tag moves, and the
# same commit would build against a different image next month. Debian 12.15;
# move them deliberately, with the glibc table in docs/packaging.md. --base-image overrides both.
BASE_IMAGE_X64="debian:12-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251"
BASE_IMAGE_ARM64="ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3"
BASE_IMAGE=""

# Linux x64 on an Apple silicon Mac is built in a Colima VM of its own that runs
# x86-64 through Rosetta: under the default VM's QEMU emulation GCC segfaults,
# and the default VM is left alone because other work runs in it.
# Inside Simorg's own repository, which Docker builds each Linux platform
# natively is decided once, by the scripts/native-docker.sh at its root, and
# SIMORG_NATIVE_DOCKER can point at a copy. Without it, this computer's own
# Docker builds both platforms, emulating the one its processor is not.
NATIVE_DOCKER_LIB="${SIMORG_NATIVE_DOCKER:-${SOURCE_DIR}/../../../../scripts/native-docker.sh}"
if [ -f "$NATIVE_DOCKER_LIB" ]; then
    # shellcheck source=../../../../../scripts/native-docker.sh
    source "$NATIVE_DOCKER_LIB"
fi
X64_PROFILE="${NATIVE_DOCKER_X64_PROFILE:-${SIMORG_X64_COLIMA_PROFILE:-simorg-x64}}"

# The release tag simorg.toml publishes, which CMakeLists.txt reads too, so an
# archive's name and the version its binary reports are one number.
PROJECT_VERSION="$(sed -n 's/^tag = "\([0-9][0-9.]*\)".*/\1/p' "${SOURCE_DIR}/simorg.toml" | head -1)"
[ -n "$PROJECT_VERSION" ] || PROJECT_VERSION="0.0.0"

usage() {
    cat <<EOF
${BOLD}Simorg release builds${RESET}

  ./scripts/build-targets.sh [options] [target ...]

${BOLD}TARGETS${RESET}
  ${BLUE}macos${RESET}             One bundle that runs natively on Apple silicon and Intel.
                    Falls back to this Mac's own architecture when the installed
                    Qt is not universal — which Homebrew's is not.
  ${BLUE}linux-x64${RESET}         Linux on x86-64, built in Docker. On an Apple silicon Mac
                    that is a Colima VM of its own, ${X64_PROFILE}, which runs
                    x86-64 through Rosetta; it is created and started when
                    needed and stopped afterwards. A dev build on an x86-64
                    Linux host is built natively instead.
  ${BLUE}linux-arm64${RESET}       Linux on ARM64. Same.
  ${BLUE}all${RESET}               Everything this host can produce. The default.

${BOLD}OPTIONS${RESET}
  --config <dev|prod>  dev is a Debug build pointed at localhost; prod is an
                       optimised build pointed at the public estate. Default: prod.
  --package            Also produce installers (.dmg, .deb, .rpm) via CPack.
  --clean              Delete each target's build directory first.
  --portable           Carry Qt inside the macOS bundle even for a dev build,
                       so it runs on a Mac that has no Qt. Adds about five
                       minutes; a prod build always does it.
  --install-qt         Fetch Qt ${QT_VERSION} (universal, with WebEngine) into
                       ${QT_ROOT} with aqtinstall first. A prod macOS build
                       needs it. Needs python3.
  --qt-prefix <dir>    Build against this Qt instead. Also SIMORG_QT_PREFIX.
  --jobs <n>           Parallel compile jobs. Default: all cores.
  --base-image <img>   Distribution the Linux archives are compiled on. The
                       oldest glibc they run on is GLIBC_FLOOR in the Dockerfile.
                       Default: ${BASE_IMAGE_X64} for x64,
                       ${BASE_IMAGE_ARM64} for arm64.
  --list               Print the targets and what each one produces.
  --help               This.

${BOLD}OUTPUT${RESET}
  build/dist/<target>/       the artifacts, one directory per target
  build/targets/<target>/    intermediate build trees, safe to delete

Every target produces one archive that is unpacked and run: it carries Qt, Qt's
plugins, Qt's QML modules and everything underneath them, so nothing has to be
installed on the machine that receives it. Each Linux archive is proved to be
that way by running it in a container with no Qt in it, on its own base image
and on Ubuntu 24.04, rendering a web page there as the Workbench and the Brain
do, before the build is allowed to finish.

${BOLD}WINDOWS${RESET}
  Windows builds are made on Windows, by scripts/build-windows.ps1. One Intel
  machine produces both the x64 and the ARM64 build:

      .\\scripts\\build-windows.bat -Config dev
EOF
}

list_targets() {
    cat <<EOF
${BOLD}macos${RESET}
  Simorg.app          the desktop app bundle
  arm64 + x86_64 when Qt is universal, otherwise this Mac's architecture

${BOLD}linux-x64${RESET}, ${BOLD}linux-arm64${RESET}
  simorg-<version>-linux-<arch>.tar.gz   unpack anywhere and run
  MANIFEST.txt                           every library carried, and the short
                                         list the target still has to have
  SHA256SUMS

${BOLD}windows-x64${RESET}, ${BOLD}windows-arm64${RESET}
  Not built here. Run scripts/build-windows.ps1 on a Windows machine; one
  Intel machine makes both.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --config)    CONFIG="${2:-}"; shift 2 ;;
        --config=*)  CONFIG="${1#*=}"; shift ;;
        --package)   PACKAGE=1; shift ;;
        --clean)     CLEAN=1; shift ;;
        --portable)  PORTABLE=1; shift ;;
        --install-qt) INSTALL_QT=1; shift ;;
        --qt-prefix)   QT_PREFIX="${2:-}"; shift 2 ;;
        --qt-prefix=*) QT_PREFIX="${1#*=}"; shift ;;
        --jobs)      JOBS="${2:-}"; shift 2 ;;
        --jobs=*)    JOBS="${1#*=}"; shift ;;
        --base-image)   BASE_IMAGE="${2:-}"; shift 2 ;;
        --base-image=*) BASE_IMAGE="${1#*=}"; shift ;;
        --list)      list_targets; exit 0 ;;
        --help|-h)   usage; exit 0 ;;
        -*)          die "unknown option '$1' — try --help" ;;
        *)           REQUESTED+=("$1"); shift ;;
    esac
done

case "$CONFIG" in
    dev)  BUILD_TYPE="Debug";   SIMORG_ENV="dev" ;;
    prod) BUILD_TYPE="Release"; SIMORG_ENV="prod" ;;
    *)    die "--config must be 'dev' or 'prod', not '${CONFIG}'" ;;
esac

[ ${#REQUESTED[@]} -eq 0 ] && REQUESTED=("all")

# A dev build says so in the file name. Two archives called the same thing, one
# pointed at localhost and one at the public estate, is the mistake this avoids.
if [ "$CONFIG" = "dev" ]; then
    ARCHIVE_VERSION="${PROJECT_VERSION}-dev"
else
    ARCHIVE_VERSION="${PROJECT_VERSION}"
fi

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

if [ -z "$JOBS" ]; then
    JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- long steps ---
#
# Runs something slow and quiet, and keeps saying so.
#
# The macOS install is minutes of macdeployqt walking a gigabyte of Qt
# WebEngine, and it prints almost nothing while it does. Run with its output
# sent to /dev/null it would cost twice: the terminal sitting on the last line
# the compiler printed, looking hung — the last thing anybody wants to see after
# a five minute build — and a failure coming back as an exit code with no
# output at all to explain it.
#
# So the output goes to a file, a counter says how long it has been going, and
# the file is printed if it fails.
#
#   patiently <message> <logfile> <command...>
patiently() {
    local message="$1" logfile="$2"
    shift 2

    "$@" >"$logfile" 2>&1 &
    local job=$!

    local seconds=0
    while kill -0 "$job" 2>/dev/null; do
        sleep 1
        seconds=$((seconds + 1))
        # Only once it has been long enough to be worth saying. A step that
        # takes two seconds should not leave a line about how long it took.
        if [ $((seconds % 5)) -eq 0 ] && [ "$seconds" -ge 5 ] && [ -t 1 ]; then
            printf '\r  %s%s — %ds%s' "${DIM}" "$message" "$seconds" "${RESET}"
        fi
    done

    wait "$job"
    local status=$?
    [ -t 1 ] && printf '\r\033[K'

    if [ "$status" -ne 0 ]; then
        printf '%serror:%s %s failed:\n' "${RED}" "${RESET}" "$message" >&2
        sed 's/^/    /' "$logfile" >&2
        return "$status"
    fi

    # Succeeded — but "succeeded" is not the same as "said nothing".
    #
    # macdeployqt exits 0 while printing thousands of lines about files it could
    # not open, which is exactly how a bundle with no QML modules in it shipped
    # once already. Hiding its output behind an exit code would put that trap
    # straight back, so anything it called an error is surfaced whatever the
    # status was.
    local complaints
    complaints="$(grep -c '^ERROR' "$logfile" 2>/dev/null || true)"
    if [ "${complaints:-0}" -gt 0 ]; then
        warn "${message} finished, and the deploy tool reported ${complaints} error(s):"
        # sed reads to the end, where `head -5` would not: thousands of ERROR
        # lines run past a pipe's 64 KB, grep dies writing them, and pipefail
        # would end the build here instead of warning and carrying on.
        grep '^ERROR' "$logfile" | sed -n '1,5s/^/    /p' >&2
        [ "$complaints" -gt 5 ] && muted "…and $((complaints - 5)) more in ${logfile}"
    fi

    [ "$seconds" -ge 5 ] && muted "${message} — ${seconds}s"
    return 0
}

# ------------------------------------------------------------------- macOS ---
#
# Apple silicon first, Intel as the fallback, and a universal binary when the
# toolchain can produce one — which is what "runs on the Mac someone actually
# has" means in practice.
#
# The catch is Qt. A universal binary needs a universal Qt, and Homebrew ships
# one architecture per bottle: on an Apple silicon Mac that is arm64 only, and
# asking for both anyway fails at link time with an error about a missing slice
# that reads like a compiler bug. So the universal build is *attempted* and the
# fallback is silent-but-announced rather than fatal — the arm64-only bundle is
# a perfectly good build, and the person running this should be told which one
# they got rather than handed a failure.
build_macos() {
    [ "$HOST_OS" = "Darwin" ] || { warn "skipping macos: not building on a Mac"; return 0; }
    have cmake || die "cmake is not installed"

    local qt_prefix="" architectures="" label
    if [ -n "$QT_PREFIX" ]; then
        qt_prefix="$QT_PREFIX"
    elif [ "$CONFIG" = "prod" ]; then
        # A release is always the pinned Qt: universal, with WebEngine, the same
        # version as every other platform's.
        [ "$INSTALL_QT" -eq 1 ] && install_release_qt
        qt_prefix="$(release_qt_prefix)"
        [ -f "${qt_prefix}/lib/QtWebEngineCore.framework/Versions/A/QtWebEngineCore" ] \
            || die "a release is built against Qt ${QT_VERSION} at ${qt_prefix}, which is not there; run with --install-qt"
    elif have brew; then
        qt_prefix="$(brew --prefix qt 2>/dev/null || true)"
    fi

    if macos_qt_is_universal "$qt_prefix"; then
        architectures="arm64;x86_64"
        label="universal (arm64 + x86_64)"
    elif [ "$HOST_ARCH" = "arm64" ]; then
        architectures="arm64"
        label="arm64 only — the installed Qt is not universal"
    else
        architectures="x86_64"
        label="x86_64 only — Intel Mac"
    fi

    # Carrying Qt is what makes a macOS build slow, and a dev build does not
    # need it carried. See PORTABLE at the top of this file.
    local deploy_qt="ON"
    if [ "$CONFIG" = "dev" ] && [ "$PORTABLE" -eq 0 ]; then
        deploy_qt="OFF"
        label="${label} · local"
    fi

    step "macos · ${label}"

    local build_dir="${WORK_DIR}/macos-${CONFIG}"
    local out_dir="${DIST_DIR}/macos"
    [ "$CLEAN" -eq 1 ] && rm -rf "$build_dir"

    # A tree configured against another Qt keeps it: CMake caches Qt6_DIR and
    # never looks again, so a new CMAKE_PREFIX_PATH is ignored and the link
    # mixes two Qts — arm64-only Homebrew symbols missing for x86_64. Such a
    # tree starts again.
    local cached_qt=""
    [ -f "${build_dir}/CMakeCache.txt" ] \
        && cached_qt="$(sed -n 's/^Qt6_DIR:PATH=//p' "${build_dir}/CMakeCache.txt")"
    if [ -n "$cached_qt" ] && [ -n "$qt_prefix" ] \
       && [ "${cached_qt#"$qt_prefix"}" = "$cached_qt" ] \
       && [ "${cached_qt#"$(cd "$qt_prefix" 2>/dev/null && pwd -P)"}" = "$cached_qt" ]; then
        muted "the build tree was configured against ${cached_qt%/lib/cmake/Qt6}; starting it again"
        rm -rf "$build_dir"
    fi
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    local -a args=(
        -S "$SOURCE_DIR" -B "$build_dir" -G Ninja
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
        -DCMAKE_OSX_ARCHITECTURES="$architectures"
        # 13.0 is the floor of the Qt a release carries: every framework of Qt
        # 6.11 is built for macOS 13 (`otool -l QtCore`, minos), so anything
        # older cannot run this whatever we compile for.
        -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
        -DSIMORG_DEPLOY_QT="$deploy_qt"
        # What this makes is a driver archive, so it may replace itself with a newer release.
        -DSIMORG_ARCHIVE_BUILD=ON
    )
    # WebEngine said rather than inherited: left to its default it is whether Qt
    # WebEngine was found when this build folder was first configured, and
    # CMake keeps that answer for good (build-windows.ps1 says what that cost).
    # ON makes a missing WebEngine stop the configure.
    args+=(-DSIMORG_BUILD_GUI=ON -DSIMORG_BUILD_WEBENGINE=ON)
    [ -n "$qt_prefix" ] && args+=(-DCMAKE_PREFIX_PATH="$qt_prefix")

    cmake "${args[@]}" >/dev/null
    cmake --build "$build_dir" --parallel "$JOBS"

    # Installed rather than copied out of the build tree, and that is the whole
    # of what was wrong with the macOS build before.
    #
    # SIMORG_DEPLOY_QT does not act at build time: qt_generate_deploy_qml_app_script
    # writes a script and hands it to install(SCRIPT), so the frameworks are
    # copied into the bundle when somebody installs it and at no other moment.
    # A `cp -a build/bin/.` straight into dist would produce a Simorg.app with no
    # Contents/Frameworks at all — one that runs perfectly on the Mac that
    # compiled it, because Homebrew's Qt is still at the absolute path baked into
    # it, and dies on every other Mac with
    # "Library not loaded: /opt/homebrew/opt/qt/lib/QtCore.framework".
    #
    # And this is the slow part of a macOS build, by a long way. macdeployqt
    # walks every Mach-O file in the bundle and copies in what it depends on,
    # and one of those dependencies is Qt WebEngine — a framework of about a
    # gigabyte with Chromium inside it. Several minutes is normal and it prints
    # almost nothing, which is why it is run through `patiently`.
    local stage_dir="${build_dir}/stage"
    rm -rf "$stage_dir"

    if [ "$deploy_qt" = "OFF" ]; then
        # The fast path, and the one a dev build takes.
        #
        # No deployment, so the install is a copy of the bundle and nothing
        # else: a fifth of a second against nearly five minutes. What
        # comes out links the Qt on this Mac and runs here, which is the whole
        # of what a dev build is for. It is not an archive and there is
        # deliberately no .zip beside it — handing somebody this directory would
        # hand them an application that cannot start.
        cmake --install "$build_dir" --prefix "$stage_dir" >"${build_dir}/install.log" 2>&1 \
            || { sed 's/^/    /' "${build_dir}/install.log" >&2
                 die "the install step failed"; }

        [ -d "${stage_dir}/Simorg.app" ] && cp -R "${stage_dir}/Simorg.app" "${out_dir}/Simorg.app"

        cat > "${out_dir}/README.txt" <<EOF
This is a local build.

Qt is not inside Simorg.app: it links the Qt on the machine that built
it, at the absolute paths that machine keeps it at. So it runs here and starts
on no other Mac, which is the trade that makes this build take seconds instead
of five minutes.

To produce one that runs anywhere:

    ./scripts/build-targets.sh --config dev --portable macos
EOF
        muted "Qt not bundled — runs on this Mac only; --portable for one that travels"
    else
        # And this is the slow part of a macOS build, by a long way. macdeployqt
        # walks every Mach-O file in the bundle and copies in what it depends
        # on, and one of those is Qt WebEngine — 204 MB of Chromium, which is
        # then signed along with everything else. Several minutes is normal and
        # it prints almost nothing, which is why it is run through `patiently`.
        patiently "bundling Qt into Simorg.app" "${build_dir}/install.log" \
            cmake --install "$build_dir" --prefix "$stage_dir" \
            || die "the install step failed; see ${build_dir}/install.log"

        # Finishes the bundle, archives it, leaves the unpacked copy beside it,
        # and proves that nothing in it points at a path that exists only on
        # this Mac.
        SIMORG_VERSION="$ARCHIVE_VERSION" "${SCRIPT_DIR}/bundle-macos.sh" --stage "$stage_dir" --out "$out_dir"
    fi

    if [ "$PACKAGE" -eq 1 ]; then
        ( cd "$build_dir" && cpack ) || warn "cpack failed for macos"
        find "$build_dir" -maxdepth 1 \( -name '*.dmg' -o -name '*.tar.gz' \) \
            -exec cp {} "$out_dir/" \;
    fi

    write_build_info "$out_dir" "macos" "$architectures" "$label"
    ok "macos → ${out_dir#"${SOURCE_DIR}"/}"
}

# Where --install-qt puts the pinned Qt, which is aqtinstall's own layout.
release_qt_prefix() {
    printf '%s/%s/macos' "$QT_ROOT" "$QT_VERSION"
}

# The pinned Qt, fetched from Qt's own download servers with aqtinstall (a
# pinned version of it, in a virtualenv under build/, so nothing is installed
# on the Mac itself). Does nothing when it is already there.
install_release_qt() {
    local prefix venv
    prefix="$(release_qt_prefix)"
    if [ -f "${prefix}/lib/QtWebEngineCore.framework/Versions/A/QtWebEngineCore" ]; then
        muted "Qt ${QT_VERSION} is already at ${prefix}"
        return 0
    fi
    have python3 || die "--install-qt needs python3"
    venv="${WORK_DIR}/aqt-venv"
    if [ ! -x "${venv}/bin/aqt" ]; then
        step "aqtinstall ${AQT_VERSION}"
        python3 -m venv "$venv" || die "could not create ${venv}"
        "${venv}/bin/pip" install --quiet "aqtinstall==${AQT_VERSION}" || die "could not install aqtinstall"
    fi
    step "Qt ${QT_VERSION} for macOS, universal, into ${QT_ROOT}"
    mkdir -p "$QT_ROOT"
    # From the work directory: aqt writes aqtinstall.log wherever it runs, and
    # in the artifact's root that log would travel in the next upload.
    ( cd "$WORK_DIR" && "${venv}/bin/aqt" install-qt mac desktop "$QT_VERSION" clang_64 \
        -m "${QT_MAC_MODULES[@]}" -O "$QT_ROOT" ) || die "aqt could not install Qt ${QT_VERSION}"
    ok "Qt ${QT_VERSION} → ${prefix}"
}

# True when Qt's own core library carries both slices, which is the only honest
# way to know before the link step tells us the hard way.
macos_qt_is_universal() {
    local prefix="$1"
    [ -n "$prefix" ] || return 1
    have lipo || return 1

    # lib/QtCore.framework/Versions/A/QtCore: four levels down, and the copy at
    # the framework's top is a symlink, which -type f skips.
    local core
    core="$(find "${prefix}/lib" -maxdepth 4 -name 'QtCore' -type f 2>/dev/null | head -1)"
    [ -n "$core" ] || return 1

    lipo -archs "$core" 2>/dev/null | grep -q 'arm64' \
        && lipo -archs "$core" 2>/dev/null | grep -q 'x86_64'
}

# ------------------------------------------------------------------- Linux ---
#
# A release is built in Docker, in the pinned image, on every host; a dev build
# natively when this host already is that architecture. Docker rather than a
# cross-toolchain because the hard part of
# cross-compiling Qt is not the compiler, it is having a Qt built for the target
# — and `apt-get install qt6-base-dev` inside a linux/arm64 image is a solved
# version of that problem.
build_linux() {
    local arch="$1"                     # x64 | arm64
    local docker_platform dpkg_arch uname_arch
    case "$arch" in
        x64)   docker_platform="linux/amd64"; dpkg_arch="amd64"; uname_arch="x86_64" ;;
        arm64) docker_platform="linux/arm64"; dpkg_arch="arm64"; uname_arch="aarch64" ;;
        *)     die "unknown linux architecture '${arch}'" ;;
    esac

    local out_dir="${DIST_DIR}/linux-${arch}"
    [ "$CLEAN" -eq 1 ] && rm -rf "${WORK_DIR}/linux-${arch}-${CONFIG}"
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    # A release is always compiled in the pinned image, never on the host: the
    # image decides the oldest glibc the archive runs against and the Qt inside
    # it, and a host — a WSL distribution on a Windows computer, a developer's
    # Ubuntu — would decide both by whatever it happens to have installed.
    if [ "$CONFIG" = "dev" ] && [ "$HOST_OS" = "Linux" ] && [ "$HOST_ARCH" = "$uname_arch" ]; then
        step "linux-${arch} · native"
        build_linux_native "$arch" "$out_dir"
    elif have docker; then
        step "linux-${arch} · docker (${docker_platform})"
        build_linux_docker "$docker_platform" "$out_dir"
    else
        warn "skipping linux-${arch}: $([ "$CONFIG" = prod ] && echo "a release is compiled in Docker" || echo "not this architecture"), and docker is not installed"
        rmdir "$out_dir" 2>/dev/null || true
        return 0
    fi

    write_build_info "$out_dir" "linux-${arch}" "$dpkg_arch" "Linux ${dpkg_arch}"
    ok "linux-${arch} → ${out_dir#"${SOURCE_DIR}"/}"
}

build_linux_native() {
    local arch="$1" out_dir="$2"
    have cmake || die "cmake is not installed"
    local build_dir="${WORK_DIR}/linux-${arch}-${CONFIG}"
    local stage_dir="${build_dir}/stage"

    local -a args=(
        -S "$SOURCE_DIR" -B "$build_dir" -G Ninja
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
        -DSIMORG_ARCHIVE_BUILD=ON
        -DCMAKE_INSTALL_PREFIX=/usr
    )
    # WebEngine said rather than inherited: left to its default it is whether Qt
    # WebEngine was found when this build folder was first configured, and
    # CMake keeps that answer for good (build-windows.ps1 says what that cost).
    # ON makes a missing WebEngine stop the configure.
    args+=(-DSIMORG_BUILD_GUI=ON -DSIMORG_BUILD_WEBENGINE=ON)

    cmake "${args[@]}" >/dev/null
    cmake --build "$build_dir" --parallel "$JOBS"

    rm -rf "$stage_dir"
    patiently "staging the build" "${build_dir}/install.log" \
        env DESTDIR="$stage_dir" cmake --install "$build_dir" \
        || die "the install step failed; see ${build_dir}/install.log"

    # The same bundling the Docker path does, so a native build and a
    # cross-built one produce the same archive rather than two things that
    # happen to share a name.
    local name="simorg-${ARCHIVE_VERSION}-linux-${arch}"
    local bundle_dir="${build_dir}/${name}"

    local -a bundle_args=(--stage "${stage_dir}/usr" --out "$bundle_dir"
                          --qml-source "${SOURCE_DIR}/src/app/qml")
    [ "$BUILD_TYPE" = "Release" ] && bundle_args+=(--strip)
    "${SCRIPT_DIR}/bundle-linux.sh" "${bundle_args[@]}"

    tar -C "$(dirname "$bundle_dir")" -czf "${out_dir}/${name}.tar.gz" "$name"
    cp "${bundle_dir}/MANIFEST.txt" "${out_dir}/MANIFEST.txt"
    ( cd "$out_dir" && sha256sum ./*.tar.gz > SHA256SUMS )

    # Weaker than the Docker path's check and worth saying so: this machine has
    # Qt installed, so a library the bundle forgot can still be found here. What
    # it does catch is a file that is missing outright.
    "${SCRIPT_DIR}/verify-linux-bundle.sh" "$bundle_dir" \
        || die "the bundle is not self-contained"
    muted "verified on this machine; the container check is the strict one"

    if [ "$PACKAGE" -eq 1 ]; then
        ( cd "$build_dir" && cpack ) || warn "cpack failed for linux-${arch}"
        find "$build_dir" -maxdepth 1 \( -name '*.deb' -o -name '*.rpm' \) \
            -exec cp {} "$out_dir/" \;
    fi
}

build_linux_docker() {
    local platform="$1" out_dir="$2" base context=""

    docker buildx version >/dev/null 2>&1 \
        || die "docker buildx is required to cross-build Linux targets"

    case "$platform" in
        linux/amd64) base="${BASE_IMAGE:-$BASE_IMAGE_X64}" ;;
        *)           base="${BASE_IMAGE:-$BASE_IMAGE_ARM64}" ;;
    esac
    LINUX_BASE_USED="$base"

    # The Docker that builds this platform on its own kind of processor: the
    # Rosetta VM for x86-64 on an Apple silicon Mac, and QEMU only where nothing
    # here is native. Without native-docker.sh, the active Docker builds it, and
    # buildx emulates a platform the processor does not run.
    if declare -F native_docker >/dev/null; then
        native_docker "$platform" --or-emulate || die "nothing on this computer can build ${platform}"
        context="$NATIVE_DOCKER_CONTEXT"
    fi

    local status=0
    # --context for that one command: the active context stays what it was.
    docker ${context:+--context "$context"} buildx build \
        --platform "$platform" \
        --file "${SOURCE_DIR}/docker/Dockerfile.linux-build" \
        --build-arg BASE_IMAGE="$base" \
        --build-arg QT_VERSION="$QT_VERSION" \
        --build-arg AQT_VERSION="$AQT_VERSION" \
        --build-arg BUILD_TYPE="$BUILD_TYPE" \
        --build-arg VERSION="$ARCHIVE_VERSION" \
        --target export \
        --output "type=local,dest=${out_dir}" \
        "$SOURCE_DIR" || status=$?

    if declare -F native_docker_done >/dev/null; then
        native_docker_done
    fi
    return "$status"
}

# A note beside the binaries saying what they are. Nobody remembers three weeks
# later which of two tarballs was the Debug one. `version` is the version the
# binary reports, never the archive's name with -dev on it: a dev build says so
# on `configuration`, and Simorg Desktop refuses an update whose BUILD-INFO.txt
# names another version than the release.
write_build_info() {
    local out_dir="$1" target="$2" arch="$3" note="$4"
    # The oldest C library a Linux archive runs on, as the bundler wrote it into
    # MANIFEST.txt; nothing for a build that was not given a floor.
    runs_on_line() {
        local floor
        floor="$(sed -n 's/^Runs on  *//p' "$1/MANIFEST.txt" 2>/dev/null | head -1)"
        [ -n "$floor" ] && printf '\n  runs on         %s' "$floor"
        return 0
    }
    cat > "${out_dir}/BUILD-INFO.txt" <<EOF
Simorg — ${target}

  configuration   ${CONFIG} (${BUILD_TYPE})
  endpoints       ${SIMORG_ENV}
  architecture    ${arch}
  contents        desktop app
  version         ${PROJECT_VERSION}
  built           $(date -u '+%Y-%m-%d %H:%M:%SZ')
  commit          $(git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  note            ${note}$([ "${target#linux}" != "$target" ] && printf '\n  compiled on     %s' "${LINUX_BASE_USED:-$BASE_IMAGE_X64}")$(runs_on_line "$out_dir")

The endpoint set is chosen at run time, not baked in: this build carries both
and picks with SIMORG_ENV, --env, or the build type. A dev build defaults to
localhost; a prod build defaults to the public estate.

The archive here is self-contained: Qt, Qt's plugins, Qt's QML modules and
everything underneath them travel inside it, so nothing has to be installed on
the machine that receives it. MANIFEST.txt lists what is carried and the short
list a target still has to have — the C library, the C++ runtime, the graphics
driver and the display server's own client libraries.
EOF
}

# -------------------------------------------------------------------- main ---
mkdir -p "$DIST_DIR" "$WORK_DIR"

# cmake is asked for by the builds that run it on this computer (macOS, and a
# native Linux dev build); a Linux build in Docker brings its own, so a
# computer with only Docker — WSL on a Windows computer — can make the Linux driver.

WANTED=()
for target in "${REQUESTED[@]}"; do
    case "$target" in
        all)          WANTED+=(macos linux-x64 linux-arm64) ;;
        macos|darwin) WANTED+=(macos) ;;
        linux-x64|linux-amd64|linux_x64) WANTED+=(linux-x64) ;;
        linux-arm64|linux-arm|linux_arm) WANTED+=(linux-arm64) ;;
        *) die "unknown target '${target}' — try --list" ;;
    esac
done

printf '\n%s%s%s  %s\n' "${BOLD}" "Simorg build" "${RESET}" \
    "${DIM}${CONFIG} · ${BUILD_TYPE} · ${JOBS} jobs${RESET}"

for target in "${WANTED[@]}"; do
    case "$target" in
        macos)       build_macos ;;
        linux-x64)   build_linux x64 ;;
        linux-arm64) build_linux arm64 ;;
    esac
done

step "Done"
if [ -d "$DIST_DIR" ]; then
    for dir in "$DIST_DIR"/*/; do
        [ -d "$dir" ] || continue
        info "$(basename "$dir")  ${DIM}$(du -sh "$dir" 2>/dev/null | cut -f1)${RESET}"
    done
fi
muted "artifacts in ${DIST_DIR#"${SOURCE_DIR}"/}"
