#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Builds and installs Simorg from a fresh clone.
#
#   ./install.sh                 the desktop app, system-wide
#   ./install.sh --user          install under ~/.local, no sudo
#
# The terminal command is Simorg CLI's, an application of its own, installed
# the way its own page says.
#
# Everything the build needs comes from the platform's own package manager —
# there are no third-party C++ libraries to hunt down.

set -euo pipefail

# ---------------------------------------------------------------- settings ---
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SOURCE_DIR}/build/install"

BUILD_TYPE="Release"
SKIP_DEPS=0
ASSUME_YES=0
BUNDLE_QT=0
USER_INSTALL=0
PREFIX=""
JOBS=""

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

usage() {
    cat <<EOF
${BOLD}Simorg installer${RESET}

  ./install.sh [options]

${BOLD}OPTIONS${RESET}
  --user               Install into ~/.local instead of a system directory.
                       Never needs sudo.
  --prefix <dir>       Install somewhere specific (default: /usr/local).
  --build-type <type>  Release (default), Debug, or RelWithDebInfo.
  --bundle-qt          Run Qt's own deployment step, which puts its frameworks
                       inside Simorg.app. macOS only — on Linux it does nothing,
                       and scripts/build-targets.sh is what makes an archive that
                       runs on a machine with no Qt.
  --skip-deps          Do not install build dependencies; assume they are there.
  --jobs <n>           Parallel compile jobs (default: all cores).
  -y, --yes            Do not ask before installing packages.
  -h, --help           This text.

${BOLD}AFTERWARDS${RESET}
  Open Simorg, which sets up the machine service and asks you to sign in.
EOF
}

# ------------------------------------------------------------------- flags ---
while [ $# -gt 0 ]; do
    case "$1" in
        --user) USER_INSTALL=1 ;;
        --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
        --build-type) BUILD_TYPE="${2:?--build-type needs a value}"; shift ;;
        --bundle-qt) BUNDLE_QT=1 ;;
        --skip-deps) SKIP_DEPS=1 ;;
        --jobs) JOBS="${2:?--jobs needs a number}"; shift ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option '$1' (try --help)" ;;
    esac
    shift
done

# --------------------------------------------------------------- platform ----
OS="$(uname -s)"
DISTRO=""

case "$OS" in
    Darwin) PLATFORM="macos" ;;
    Linux)
        PLATFORM="linux"
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            DISTRO="${ID:-}"
            DISTRO_LIKE="${ID_LIKE:-}"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*)
        die "run the Windows build from a Developer PowerShell — see README.md, 'Windows'"
        ;;
    *) die "unsupported system: $OS" ;;
esac

if [ -z "$PREFIX" ]; then
    if [ "$USER_INSTALL" -eq 1 ]; then
        PREFIX="${HOME}/.local"
    else
        PREFIX="/usr/local"
    fi
fi

# sudo is only for writing outside $HOME, and only when we are not already root.
SUDO=""
if [ "$(id -u)" -ne 0 ] && [ "${PREFIX#"$HOME"}" = "$PREFIX" ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        warn "sudo not found; installing to $PREFIX may fail"
    fi
fi

if [ -z "$JOBS" ]; then
    if [ "$PLATFORM" = "macos" ]; then
        JOBS="$(sysctl -n hw.ncpu)"
    else
        JOBS="$(nproc 2>/dev/null || echo 2)"
    fi
fi

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ ! -t 0 ] && return 0   # non-interactive (CI, piped) — carry on
    printf '  %s [Y/n] ' "$1"
    read -r reply
    case "$reply" in [nN]*) return 1 ;; *) return 0 ;; esac
}

# ---------------------------------------------------------- dependencies -----
# Package names differ between releases of the same distribution, so pick the
# first name that actually exists rather than pinning one and failing.
apt_available() { apt-cache show "$1" >/dev/null 2>&1; }

apt_pick() {
    for candidate in "$@"; do
        if apt_available "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

install_deps_macos() {
    command -v brew >/dev/null 2>&1 || die \
        "Homebrew is required. Install it from https://brew.sh, then run this again."

    local packages=(cmake ninja qt)
    info "Homebrew packages: ${packages[*]}"
    confirm "Install them now?" || die "cannot build without them"
    brew install "${packages[@]}"

    # Homebrew keeps Qt out of the default CMake search path.
    local qt_prefix
    qt_prefix="$(brew --prefix qt)"
    export CMAKE_PREFIX_PATH="${qt_prefix}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
    ok "Qt found at ${qt_prefix}"
}

install_deps_apt() {
    local packages=(build-essential cmake ninja-build pkg-config git)
    packages+=("$(apt_pick qt6-base-dev qtbase6-dev)" )
    packages+=("$(apt_pick qt6-websockets-dev libqt6websockets6-dev)")

    packages+=("$(apt_pick qt6-declarative-dev)")
    packages+=("$(apt_pick libqt6svg6-dev qt6-svg-dev)")
    # Needed at run time, not build time: Qt Quick loads these as plugins.
    for module in qml6-module-qtquick qml6-module-qtquick-controls \
                  qml6-module-qtquick-layouts qml6-module-qtquick-shapes \
                  qml6-module-qtquick-templates qml6-module-qtqml-workerscript; do
        if apt_available "$module"; then
            packages+=("$module")
        fi
    done

    info "apt packages: ${packages[*]}"
    confirm "Install them now?" || die "cannot build without them"
    $SUDO apt-get update
    $SUDO apt-get install -y "${packages[@]}"
}

install_deps_dnf() {
    local packages=(gcc-c++ cmake ninja-build git qt6-qtbase-devel qt6-qtwebsockets-devel)
    packages+=(qt6-qtdeclarative-devel qt6-qtsvg-devel)

    info "dnf packages: ${packages[*]}"
    confirm "Install them now?" || die "cannot build without them"
    $SUDO dnf install -y "${packages[@]}"
}

install_deps_pacman() {
    local packages=(base-devel cmake ninja git qt6-base qt6-websockets)
    packages+=(qt6-declarative qt6-svg)

    info "pacman packages: ${packages[*]}"
    confirm "Install them now?" || die "cannot build without them"
    $SUDO pacman -S --needed --noconfirm "${packages[@]}"
}

install_deps_zypper() {
    local packages=(gcc-c++ cmake ninja git qt6-base-devel qt6-websockets-devel)
    packages+=(qt6-declarative-devel qt6-svg-devel)

    info "zypper packages: ${packages[*]}"
    confirm "Install them now?" || die "cannot build without them"
    $SUDO zypper install -y "${packages[@]}"
}

install_deps_apk() {
    local packages=(build-base cmake samurai git qt6-qtbase-dev qt6-qtwebsockets-dev)
    packages+=(qt6-qtdeclarative-dev qt6-qtsvg-dev)

    info "apk packages: ${packages[*]}"
    confirm "Install them now?" || die "cannot build without them"
    $SUDO apk add "${packages[@]}"
}

install_dependencies() {
    if [ "$SKIP_DEPS" -eq 1 ]; then
        muted "skipping dependency install (--skip-deps)"
        # Homebrew Qt still has to be findable even when we did not install it.
        if [ "$PLATFORM" = "macos" ] && command -v brew >/dev/null 2>&1; then
            local qt_prefix
            qt_prefix="$(brew --prefix qt 2>/dev/null || true)"
            [ -n "$qt_prefix" ] && export CMAKE_PREFIX_PATH="${qt_prefix}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
        fi
        return
    fi

    if [ "$PLATFORM" = "macos" ]; then
        install_deps_macos
        return
    fi

    case "${DISTRO}:${DISTRO_LIKE:-}" in
        debian:*|ubuntu:*|*:*debian*|*:*ubuntu*) install_deps_apt ;;
        fedora:*|rhel:*|centos:*|rocky:*|almalinux:*|*:*fedora*|*:*rhel*) install_deps_dnf ;;
        arch:*|manjaro:*|*:*arch*) install_deps_pacman ;;
        opensuse*:*|sles:*|*:*suse*) install_deps_zypper ;;
        alpine:*) install_deps_apk ;;
        *)
            warn "unrecognised distribution '${DISTRO:-unknown}'"
            info "install these yourself, then re-run with --skip-deps:"
            info "  a C++17 compiler, CMake 3.21+, Ninja"
            info "  Qt 6.4+ : QtBase (Core, Network)"
            info "            QtDeclarative (Quick, QuickControls2), QtSvg, QtWidgets"
            die "cannot install dependencies automatically"
            ;;
    esac
}

# ------------------------------------------------------------------ build ----
configure_and_build() {
    local args=(
        -S "$SOURCE_DIR"
        -B "$BUILD_DIR"
        -G Ninja
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
        -DCMAKE_INSTALL_PREFIX="$PREFIX"
    )

    if [ "$BUNDLE_QT" -eq 1 ]; then
        args+=(-DSIMORG_DEPLOY_QT=ON)

        # Said here rather than left to be discovered. SIMORG_DEPLOY_QT turns on
        # qt_generate_deploy_qml_app_script, and Qt's deployment supports macOS
        # and Windows; on Linux it is a no-op that prints a warning, so this
        # flag would produce an installed tree that still needs Qt on the
        # machine and would say nothing about it.
        if [ "$PLATFORM" != "macos" ]; then
            local target="linux-x64"
            [ "$(uname -m)" = "aarch64" ] && target="linux-arm64"
            warn "--bundle-qt does nothing on Linux: Qt has no deployment step here"
            info "for an archive that runs on a machine with no Qt, use:"
            info "  ./scripts/build-targets.sh ${target}"
        fi
    fi

    command -v cmake >/dev/null 2>&1 || die "cmake not found after dependency install"

    # Ninja is `samurai` on Alpine, which provides /usr/bin/ninja too.
    command -v ninja >/dev/null 2>&1 || die "ninja not found after dependency install"

    cmake "${args[@]}"
    cmake --build "$BUILD_DIR" --parallel "$JOBS"
}

# ---------------------------------------------------------------- install ----
install_linux() {
    $SUDO cmake --install "$BUILD_DIR"

    if [ "$USER_INSTALL" -eq 1 ] && [ "${PATH#*"$PREFIX/bin"}" = "$PATH" ]; then
        warn "$PREFIX/bin is not on your PATH"
        info "add this to your shell profile:"
        info "  export PATH=\"$PREFIX/bin:\$PATH\""
    fi
}

install_macos() {
    # The install tree is staged first so the .app can go to /Applications,
    # which one `cmake --install` prefix cannot express.
    local stage="${BUILD_DIR}/stage"
    rm -rf "$stage"
    cmake --install "$BUILD_DIR" --prefix "$stage"

    local app="${stage}/Simorg.app"
    [ -d "$app" ] || die "expected an app bundle at $app"
    $SUDO rm -rf "/Applications/Simorg.app"
    $SUDO cp -R "$app" "/Applications/Simorg.app"
    ok "Simorg.app → /Applications"
}

# -------------------------------------------------------------------- run ----
printf '\n%s  ◆ Simorg%s %s\n' "${BLUE}${BOLD}" "${RESET}" "${DIM}installer${RESET}"
muted "  source     ${SOURCE_DIR}"
muted "  build      ${BUILD_DIR}"
muted "  prefix     ${PREFIX}"
muted "  targets    simorg-desktop"

step "Checking build dependencies"
install_dependencies

step "Configuring and building (${BUILD_TYPE}, ${JOBS} jobs)"
configure_and_build

step "Installing"
if [ "$PLATFORM" = "macos" ]; then
    install_macos
else
    install_linux
fi

step "Done"
ok "installed to ${PREFIX}"
info ""
if [ "$PLATFORM" = "macos" ]; then
    info "  ${BOLD}open -a Simorg${RESET}                    start the desktop app"
else
    info "  ${BOLD}simorg-desktop${RESET}                    start the desktop app"
fi
info ""
