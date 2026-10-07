# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# simorg-app-model — what the desktop app's windows bind to, on the Simorg machine
# service.
#
# One object per QML singleton, each keeping the members its windows read and
# backed by the service's API and topics through Simorg::Client. Qt Core and
# Network only, so the app's UI tests can link it without the app.
find_package(Qt6 ${SIMORG_QT_MIN_VERSION} REQUIRED COMPONENTS Core Network)

# --- Generated: files the library carries, embedded as C++ --------------------
#
# The document a Workbench or a Brain loads, and its script, served over the
# surface scheme from a handler with no filesystem to fall back to; and the
# script Simorg Desktop hands its own update to once it has closed,
# written out beside the new
# version when it is needed. Embedded rather than a Qt resource, which inside a
# static library initialises only if every consumer links it just so.
set(SIMORG_APPMODEL_EMBED_SURFACE_HTML "${SIMORG_CONFIG_DIR}/surface/host.html")
set(SIMORG_APPMODEL_EMBED_SURFACE_JS "${SIMORG_CONFIG_DIR}/surface/host.js")
set(SIMORG_APPMODEL_EMBED_HANDOVER_SH "${SIMORG_CONFIG_DIR}/update/desktop-handover.sh")
set(SIMORG_APPMODEL_EMBED_HANDOVER_PS1 "${SIMORG_CONFIG_DIR}/update/desktop-handover.ps1")
set(_embedded_files SURFACE_HTML SURFACE_JS HANDOVER_SH HANDOVER_PS1)
foreach(_embedded IN LISTS _embedded_files)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${SIMORG_APPMODEL_EMBED_${_embedded}}")
endforeach()
file(READ "${SIMORG_APPMODEL_EMBED_SURFACE_JS}" _surface_js)
if("${_surface_js}" MATCHES "</script")
    message(FATAL_ERROR "config/surface/host.js contains a closing script tag")
endif()
# As bytes rather than string literals: MSVC refuses a literal longer than about
# 16 KB (C2026) and concatenated ones past 64 KB, and host.js is beyond the
# first. An array has no such limit on any compiler. Sixteen bytes to a line.
string(REPEAT "0x..," 16 _embedded_row)
foreach(_embedded IN LISTS _embedded_files)
    file(READ "${SIMORG_APPMODEL_EMBED_${_embedded}}" _embedded_hex HEX)
    string(REGEX REPLACE "(..)" "0x\\1," _embedded_bytes "${_embedded_hex}")
    string(REGEX REPLACE "(${_embedded_row})" "\\1\n" SIMORG_EMBEDDED_${_embedded} "${_embedded_bytes}")
endforeach()
foreach(_generated IN ITEMS EmbeddedSurface EmbeddedHandover)
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/src/${_generated}.cpp.in"
        "${CMAKE_CURRENT_BINARY_DIR}/generated/${_generated}.cpp"
        @ONLY
    )
endforeach()

qt_add_library(simorg-app-model STATIC
    include/simorg/appmodel/AccessGrantsModel.h
    include/simorg/appmodel/ActivityModel.h
    include/simorg/appmodel/AgentModels.h
    include/simorg/appmodel/AuthModel.h
    include/simorg/appmodel/DesktopPeer.h
    include/simorg/appmodel/DesktopUpdateModel.h
    include/simorg/appmodel/DockerListModels.h
    include/simorg/appmodel/DockerModel.h
    include/simorg/appmodel/GraphicsCards.h
    include/simorg/appmodel/HubModel.h
    include/simorg/appmodel/LegalModel.h
    include/simorg/appmodel/MachineCatalogModel.h
    include/simorg/appmodel/MachineSetupModel.h
    include/simorg/appmodel/PeersModel.h
    include/simorg/appmodel/ApplicationsModel.h
    include/simorg/appmodel/PreflightModel.h
    include/simorg/appmodel/Profile.h
    include/simorg/appmodel/ServiceInstallModel.h
    include/simorg/appmodel/ServiceLinkModel.h
    include/simorg/appmodel/SettingsModels.h
    include/simorg/appmodel/ShutdownModel.h
    include/simorg/appmodel/Slug.h
    include/simorg/appmodel/SurfaceModels.h
    include/simorg/appmodel/SurfaceRouter.h
    include/simorg/appmodel/TelemetryModel.h
    include/simorg/appmodel/UninstallModel.h
    include/simorg/appmodel/UpdatesModel.h
    include/simorg/appmodel/WorkspaceModels.h
    src/AccessGrantsModel.cpp
    src/ActivityModel.cpp
    src/AgentModels.cpp
    src/AuthModel.cpp
    src/DesktopPeer.cpp
    src/DesktopUpdateModel.cpp
    src/DockerListModels.cpp
    src/DockerModel.cpp
    src/GraphicsCards.cpp
    src/HubModel.cpp
    src/PeersModel.cpp
    src/ApplicationsModel.cpp
    src/LegalModel.cpp
    src/MachineCatalogModel.cpp
    src/MachineSetupModel.cpp
    src/PreflightModel.cpp
    src/Profile.cpp
    src/ServiceInstallModel.cpp
    src/ServiceLinkModel.cpp
    src/SettingsModels.cpp
    src/ShutdownModel.cpp
    src/Slug.cpp
    src/EmbeddedHandover.h
    src/EmbeddedSurface.h
    src/SurfaceModels.cpp
    src/SurfaceRouter.cpp
    "${CMAKE_CURRENT_BINARY_DIR}/generated/EmbeddedHandover.cpp"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/EmbeddedSurface.cpp"
    src/Support.h
    src/TelemetryModel.cpp
    src/UninstallModel.cpp
    src/UpdatesModel.cpp
    src/WorkspaceModels.cpp
)
add_library(Simorg::AppModel ALIAS simorg-app-model)

target_include_directories(simorg-app-model
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(simorg-app-model PUBLIC Simorg::Client Qt6::Core Qt6::Network)

simorg_set_warnings(simorg-app-model)
