# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# simorg-client — the Simorg machine service, found and reached from a front end.
#
# Qt Core and Qt Network only: the CLI links this alone, and the desktop app with
# Simorg::AppModel over it.
find_package(Qt6 ${SIMORG_QT_MIN_VERSION} REQUIRED COMPONENTS Core Network)

qt_add_library(simorg-client STATIC
    include/simorg/client/Discovery.h
    include/simorg/client/HttpTransport.h
    include/simorg/client/ServiceClient.h
    include/simorg/client/ServiceSession.h
    src/Discovery.cpp
    src/HttpTransport.cpp
    src/PeerCheck.cpp
    src/PeerCheck.h
    src/ServiceClient.cpp
    src/ServiceSession.cpp
    src/ServiceStarter.cpp
    src/ServiceStarter.h
)
add_library(Simorg::Client ALIAS simorg-client)

target_include_directories(simorg-client
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_link_libraries(simorg-client PUBLIC Qt6::Core Qt6::Network)
if(WIN32)
    target_link_libraries(simorg-client PRIVATE advapi32)
endif()

simorg_set_warnings(simorg-client)
