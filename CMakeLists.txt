# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Simorg Desktop — the windowed front end of the Simorg machine service. Its
# terminal counterpart is Simorg CLI, an application of its own.
#
#   simorg-client     Qt Core + Qt Network. Finds, starts and talks to the service.
#   simorg-frontend   Qt Core + Qt Network. Build facts, logging, autostart,
#                     artifact references, the window-level guard.
#   simorg-app-model  Qt Core + Qt Network. What the windows bind to.
#   simorg-desktop    The tray app. Qt Quick for the interface, Qt Widgets for
#                     the system tray icon; with `update desktop`, its own update
#                     with no window, which the machine service runs.
#
# Configure with a preset (see CMakePresets.json) or by hand:
#   cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
#   cmake --build build

cmake_minimum_required(VERSION 3.21)

# The version is the release tag simorg.toml publishes (the first `tag = "…"`
# line, in [release]), and nothing else names it. Simorg Desktop compares the
# version it reports with the platform's latest tag to offer itself an update,
# and a release raises that tag before it builds the drivers, so a second
# number kept here would publish an app that offers its own release to itself
# for ever. build-targets.sh and
# build-windows.ps1 read the same line.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/simorg.toml" _simorg_tag_line REGEX "^tag = \"" LIMIT_COUNT 1)
string(REGEX REPLACE "^tag = \"([0-9]+\\.[0-9]+\\.[0-9]+)\".*$" "\\1" SIMORG_RELEASE_TAG "${_simorg_tag_line}")
if(NOT SIMORG_RELEASE_TAG MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR "simorg.toml's release tag is not three numbers (it reads: ${_simorg_tag_line})")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/simorg.toml")

project(simorg-desktop
    VERSION ${SIMORG_RELEASE_TAG}
    DESCRIPTION "Simorg desktop application"
    HOMEPAGE_URL "https://simorg.tech"
    LANGUAGES CXX
)

# --- Options ------------------------------------------------------------------
option(SIMORG_BUILD_GUI "Build the desktop app (needs Qt Quick and Qt Widgets)" ON)
option(SIMORG_BUILD_TESTS "Build the unit tests" OFF)
option(SIMORG_WARNINGS_AS_ERRORS "Turn compiler warnings into errors" OFF)
option(SIMORG_DEPLOY_QT "Copy Qt's libraries and QML modules next to the binary" OFF)
# Set by the scripts that make a release's driver archives (build-targets.sh,
# build-windows.ps1, docker/Dockerfile.linux-build) and by nothing else: only a
# copy unpacked from a published archive replaces itself with a newer release.
# A development build or one
# installed from source by install.sh is updated the way it was built.
option(SIMORG_ARCHIVE_BUILD "A build for a published driver archive, which may replace itself with a newer release" OFF)

# Application menu entries only mean something on a Linux desktop.
if(UNIX AND NOT APPLE)
    option(SIMORG_LINUX_DESKTOP_FILES "Install .desktop, icon and AppStream metadata" ON)
else()
    set(SIMORG_LINUX_DESKTOP_FILES OFF)
endif()

if(NOT SIMORG_BUILD_GUI AND NOT SIMORG_BUILD_TESTS)
    message(FATAL_ERROR "Nothing to build: enable SIMORG_BUILD_GUI or SIMORG_BUILD_TESTS")
endif()

# --- Project-wide settings ----------------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# <windows.h> defines min and max as macros unless told not to, and they turn
# std::numeric_limits<T>::max() into a syntax error in every file that includes
# it. Qt's own headers ask for the same.
if(WIN32)
    add_compile_definitions(NOMINMAX)
endif()

# A single-configuration generator with no build type produces an unoptimised
# binary with no debug info — never what anyone wants.
get_property(_is_multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(NOT _is_multi_config AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS Debug Release RelWithDebInfo MinSizeRel)
    message(STATUS "CMAKE_BUILD_TYPE was unset; defaulting to Release")
endif()

# Everything lands in one place, which is what the deployment tools and the
# `install.sh` script expect to find.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# Let an installed build find the Qt libraries shipped beside it.
if(APPLE)
    set(CMAKE_INSTALL_RPATH "@executable_path/../Frameworks")

    # And let it still find the Qt it was compiled against, which sounds like
    # the opposite of the line above and is what makes that line work.
    #
    # Homebrew's Qt uses @rpath install names, so `otool -L` on this binary says
    # `@rpath/QtCore.framework/...` and nothing more. macdeployqt — which runs
    # during `cmake --install`, and is what puts the frameworks in the bundle in
    # the first place — resolves those by reading the binary's own rpaths. With
    # only the line above, the one pointing at Homebrew is gone by the time it
    # looks, and every framework fails with
    #
    #   ERROR: Cannot resolve rpath "@rpath/QtCore.framework/Versions/A/QtCore"
    #
    # leaving a bundle with an empty Contents/Frameworks that runs on this Mac
    # and on no other. Deployment strips this path back out afterwards.
    set(CMAKE_INSTALL_RPATH_USE_LINK_PATH ON)
elseif(UNIX)
    set(CMAKE_INSTALL_RPATH "$ORIGIN/../lib")
endif()

include(GNUInstallDirs)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(SimorgWarnings)
include(SimorgGitInfo)
include(SimorgWindowsResources)

# 6.4 is the floor because that is what the current Ubuntu LTS ships; nothing
# in the app reaches for anything newer.
set(SIMORG_QT_MIN_VERSION 6.4)

set(SIMORG_CMAKE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
set(SIMORG_CONFIG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/config")
set(SIMORG_RESOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/resources")
set(SIMORG_PACKAGING_DIR "${CMAKE_CURRENT_SOURCE_DIR}/packaging")

simorg_resolve_git_sha(SIMORG_GIT_SHA)

# --- Qt -----------------------------------------------------------------------
find_package(Qt6 ${SIMORG_QT_MIN_VERSION} REQUIRED COMPONENTS Core)
qt_standard_project_setup(REQUIRES ${SIMORG_QT_MIN_VERSION})

# qt_standard_project_setup turns AUTOUIC on for .ui files this project does
# not have; leaving it on only slows every build down.
set(CMAKE_AUTOUIC OFF)

message(STATUS "Simorg ${PROJECT_VERSION} (${SIMORG_GIT_SHA}) — Qt ${Qt6_VERSION}")
message(STATUS "  Desktop: ${SIMORG_BUILD_GUI}")

# --- Targets ------------------------------------------------------------------
add_subdirectory(src/client)
add_subdirectory(src/frontend)

add_subdirectory(src/appmodel)

if(SIMORG_BUILD_GUI)
    add_subdirectory(src/app)
endif()

# The tests live beside the sources in Simorg's own repository and are not
# published with them, so a tree without them builds the same with the option on.
if(SIMORG_BUILD_TESTS AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/CMakeLists.txt")
    enable_testing()
    add_subdirectory(tests)
elseif(SIMORG_BUILD_TESTS)
    message(STATUS "SIMORG_BUILD_TESTS is on, but this tree has no tests/")
endif()

install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/licenses/simorg"
    COMPONENT desktop
)

# The notices the LGPL asks to travel with a program built on Qt; see the file.
include(SimorgNotices)

include(SimorgPackaging)
