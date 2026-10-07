# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# THIRD-PARTY-NOTICES.txt: the notices the LGPL asks to travel with a program
# built on Qt, written at configure time from packaging/notices/ and installed
# beside the program on every platform.
#
#   macOS    Simorg.app/Contents/Resources/THIRD-PARTY-NOTICES.txt, with LICENSE
#   Windows  next to simorg-desktop.exe (build-windows.ps1 ships bin/ whole)
#   Linux    share/licenses/simorg/, which bundle-linux.sh carries and then
#            extends with the notices of the libraries it bundles
#
# The file is also written to the build tree's bin/ so a development build,
# and Settings → Licences in it, read the same text an installed one does.

set(SIMORG_NOTICES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/packaging/notices")
set(SIMORG_NOTICES_OUTPUT "${CMAKE_BINARY_DIR}/bin/THIRD-PARTY-NOTICES.txt")

set(QT_VERSION_LINE "${Qt6_VERSION}")
string(REGEX REPLACE "^([0-9]+\\.[0-9]+)\\..*$" "\\1" QT_VERSION_SERIES "${Qt6_VERSION}")

set(_simorg_qt_modules "Qt Core, Qt Gui, Qt Network, Qt Qml, Qt Quick, Qt Quick Controls, Qt Svg, Qt Widgets")
if(SIMORG_BUILD_WEBENGINE)
    string(APPEND _simorg_qt_modules ", Qt WebEngine Core, Qt WebEngine Quick")
endif()
set(QT_MODULES_LINE "${_simorg_qt_modules}")

if(SIMORG_BUILD_WEBENGINE)
    file(READ "${SIMORG_NOTICES_DIR}/qtwebengine-third-party.txt" _simorg_webengine_list)
    set(WEBENGINE_SECTION "\n${_simorg_webengine_list}")
else()
    set(WEBENGINE_SECTION "")
endif()

if(UNIX AND NOT APPLE)
    set(LINUX_SECTION "\nOn Linux, the libraries carried beside the program in lib/ are listed, each\nwith its own notice, at the end of this file.\n")
else()
    set(LINUX_SECTION "")
endif()

file(READ "${SIMORG_NOTICES_DIR}/LGPL-3.0.txt" LGPL_TEXT)

configure_file("${SIMORG_NOTICES_DIR}/THIRD-PARTY-NOTICES.txt.in" "${SIMORG_NOTICES_OUTPUT}" @ONLY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${SIMORG_NOTICES_DIR}/THIRD-PARTY-NOTICES.txt.in"
    "${SIMORG_NOTICES_DIR}/qtwebengine-third-party.txt"
    "${SIMORG_NOTICES_DIR}/LGPL-3.0.txt"
)

# The Linux bundle: beside the licence.
install(FILES "${SIMORG_NOTICES_OUTPUT}"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/licenses/simorg"
    COMPONENT desktop
)

# The Mac bundle: in Resources, where Settings → Licences reads it, with the
# licence itself, which no other rule puts inside the bundle.
if(APPLE AND SIMORG_BUILD_GUI)
    install(FILES "${SIMORG_NOTICES_OUTPUT}" "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE"
        DESTINATION "Simorg.app/Contents/Resources"
    )
endif()
