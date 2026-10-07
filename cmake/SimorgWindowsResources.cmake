# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# A Windows program's icon and version information, compiled into it.
#
#   simorg_add_windows_resources(<target> DESCRIPTION "Simorg")
#
# Without these a Windows program is a blank page in Explorer, in the Start
# menu shortcut the installer makes and in Apps & Features, and Task Manager
# lists it by file name — which is how Simorg Desktop 0.1.0 shipped. The icon is
# packaging/windows/simorg.ico, drawn by scripts/make-icons.sh; the version is
# the project's, which is simorg.toml's release tag.
#
# Nothing on other systems: macOS reads the bundle's .icns, and Linux the
# desktop entry's icon name.

function(simorg_add_windows_resources target)
    if(NOT WIN32)
        return()
    endif()
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "DESCRIPTION" "")
    if(NOT arg_DESCRIPTION)
        message(FATAL_ERROR "simorg_add_windows_resources(${target}) needs a DESCRIPTION")
    endif()

    get_target_property(SIMORG_RC_NAME ${target} OUTPUT_NAME)
    if(NOT SIMORG_RC_NAME)
        set(SIMORG_RC_NAME "${target}")
    endif()
    set(SIMORG_RC_DESCRIPTION "${arg_DESCRIPTION}")
    set(SIMORG_RC_ICON "${SIMORG_PACKAGING_DIR}/windows/simorg.ico")
    # 0x1L is VS_FF_DEBUG: a Debug build says so in its properties. Every build
    # of this project is single-configuration (Ninja), so the type is known here.
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(SIMORG_RC_FLAGS "0x1L")
    else()
        set(SIMORG_RC_FLAGS "0x0L")
    endif()

    set(generated "${CMAKE_CURRENT_BINARY_DIR}/${target}.rc")
    configure_file("${SIMORG_PACKAGING_DIR}/windows/program.rc.in" "${generated}" @ONLY)
    target_sources(${target} PRIVATE "${generated}")
    # The resource compiler reads the icon; a new drawing has to rebuild it.
    set_source_files_properties("${generated}" PROPERTIES OBJECT_DEPENDS "${SIMORG_RC_ICON}")
endfunction()
