# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# simorg-frontend — what the app keeps for itself: the build facts, its log
# category, starting the tray app at login, the grammar of an artifact reference,
# the window-level single-instance guard, taking
# away the `simorg` and `sim` an older release put on PATH, and finding Simorg
# CLI's version for Settings → Overview. Everything else the
# product does is the Simorg machine service's, reached through Simorg::Client.
#
# Qt Core and Qt Network only (Network for the guard's local socket).
find_package(Qt6 ${SIMORG_QT_MIN_VERSION} REQUIRED COMPONENTS Core Network)

# --- Generated: version and build metadata ------------------------------------
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/include/simorg/frontend/BuildInfo.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/simorg/frontend/BuildInfo.h"
    @ONLY
)

qt_add_library(simorg-frontend STATIC
    include/simorg/frontend/AutostartService.h
    include/simorg/frontend/GetDocker.h
    include/simorg/frontend/Logging.h
    include/simorg/frontend/ResourceRef.h
    include/simorg/frontend/SingleInstanceGuard.h
    include/simorg/frontend/OldTerminalCommands.h
    include/simorg/frontend/SimorgCli.h
    src/AutostartService.cpp
    src/Logging.cpp
    src/ResourceRef.cpp
    src/SingleInstanceGuard.cpp
    src/OldTerminalCommands.cpp
    src/SimorgCli.cpp
    "${CMAKE_CURRENT_BINARY_DIR}/generated/simorg/frontend/BuildInfo.h"
)

add_library(Simorg::Frontend ALIAS simorg-frontend)

target_include_directories(simorg-frontend
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

target_link_libraries(simorg-frontend PUBLIC Qt6::Core Qt6::Network)

# Static libraries that end up inside a shared object or a macOS bundle need
# position-independent code; harmless everywhere else.
set_target_properties(simorg-frontend PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    AUTOMOC ON
)

simorg_set_warnings(simorg-frontend)
