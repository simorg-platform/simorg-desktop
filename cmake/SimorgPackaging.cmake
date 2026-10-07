# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# CPack setup. Build a package with:
#   cmake --build build --target package
#
# Formats per platform:
#   macOS    .dmg (drag-and-drop) and .tar.gz
#   Windows  NSIS installer and .zip
#   Linux    .deb, .rpm where rpmbuild exists, and .tar.gz everywhere

set(CPACK_PACKAGE_NAME "simorg")
set(CPACK_PACKAGE_VENDOR "Simorg")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PROJECT_DESCRIPTION}")
set(CPACK_PACKAGE_HOMEPAGE_URL "${PROJECT_HOMEPAGE_URL}")
set(CPACK_PACKAGE_CONTACT "Simorg <hello@simorg.tech>")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "Simorg")
set(CPACK_STRIP_FILES ON)

# The architecture belongs in the file name: the same version is published for
# x86-64 and arm64, and one is useless on the other.
if(NOT CPACK_SYSTEM_NAME)
    set(CPACK_SYSTEM_NAME "${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
endif()
set(CPACK_PACKAGE_FILE_NAME "simorg-${PROJECT_VERSION}-${CPACK_SYSTEM_NAME}")

if(APPLE)
    set(CPACK_GENERATOR "DragNDrop;TGZ")
    set(CPACK_DMG_VOLUME_NAME "Simorg ${PROJECT_VERSION}")
elseif(WIN32)
    set(CPACK_GENERATOR "NSIS;ZIP")
    set(CPACK_NSIS_PACKAGE_NAME "Simorg")
    set(CPACK_NSIS_DISPLAY_NAME "Simorg")
    set(CPACK_NSIS_URL_INFO_ABOUT "${PROJECT_HOMEPAGE_URL}")
    set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
    # Nothing goes on PATH: the app is opened from the Start menu, and the terminal
    # command is Simorg CLI's, which puts itself there.
else()
    set(CPACK_GENERATOR "TGZ;DEB")
    find_program(SIMORG_RPMBUILD rpmbuild)
    if(SIMORG_RPMBUILD)
        list(APPEND CPACK_GENERATOR "RPM")
    endif()

    set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
    set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
    # Resolved from what the binaries actually link, rather than guessed.
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
    set(CPACK_RPM_PACKAGE_LICENSE "GPL-3.0-or-later")
    set(CPACK_RPM_PACKAGE_GROUP "Applications/Internet")
endif()

include(CPack)
