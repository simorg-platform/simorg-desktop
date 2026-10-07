# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# The one thing Qt's macOS deployment cannot do on a Homebrew Qt.
#
# `qt_deploy_qml_imports()` copies each QML module's `qmldir` and plugin into
# the bundle with `file(INSTALL)`, which copies a symlink *as a symlink*. On an
# official Qt those are real files and nothing is wrong. Homebrew's Qt is not a
# directory of real files: `share/qt/qml` is a farm of relative links into the
# per-formula kegs, e.g.
#
#   QtQuick/libqtquick2plugin.dylib
#       -> ../../../../Cellar/qtdeclarative/6.11.1/share/qt/qml/QtQuick/libqtquick2plugin.dylib
#
# Copied verbatim into Simorg.app that same text resolves from
# Contents/PlugIns/ instead, which lands on /Cellar — a directory that exists on
# no Mac. Every QML plugin and every qmldir in the bundle becomes a dangling
# link, and the damage shows up twice:
#
#   * macdeployqt is handed each plugin with `-executable=` and cannot open one
#     of them, so an install prints several thousand lines of
#     `install_name_tool: can't open file: Simorg.app/Contents/PlugIns/…`;
#   * what survives is an application with no QML modules at all, which cannot
#     load QtQuick on the machine that built it, let alone on anybody else's.
#
# Neither is caught by anything downstream: a dangling link is not `-type f`,
# so the bundle audit in scripts/bundle-macos.sh walked straight past it.
#
# The fix is to put the bytes in before the deploy tool runs — which is why
# src/app/CMakeLists.txt writes its own deployment script on Apple rather than
# using the one Qt generates, whose two steps are adjacent with nothing between
# them.

# Replaces every QML file Qt deployed as a link to somewhere outside the bundle
# with the file itself.
#
#   bundle      the .app, absolute
#   qml_source  the Qt installation's QML directory the deployment copied from
#
# A no-op on a Qt whose QML directory holds real files, so it costs an official
# Qt, a Linux distribution's Qt and a Windows Qt one `find` and nothing else.
function(simorg_materialise_qml_symlinks bundle qml_source)
    set(qml_dir "${bundle}/Contents/Resources/qml")
    if(NOT IS_DIRECTORY "${qml_dir}")
        return()
    endif()

    # `find` rather than file(GLOB_RECURSE): a dangling link is exactly what is
    # being looked for here, and it is exactly what a glob that stats its
    # candidates will not return.
    execute_process(
        COMMAND find "${qml_dir}" -type l
        OUTPUT_VARIABLE links
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE listed
    )
    if(NOT listed EQUAL 0)
        message(FATAL_ERROR "Simorg: could not list the symlinks under ${qml_dir}")
    endif()
    string(REPLACE "\n" ";" links "${links}")

    set(copied 0)
    foreach(link IN LISTS links)
        # EXISTS follows the link, so this is "does it point at something".
        if(link STREQUAL "" OR EXISTS "${link}")
            continue()
        endif()

        # The deployed QML tree mirrors the Qt one directory for directory, so
        # a file's place in the bundle is also its place in the Qt installation.
        # That mapping, rather than the link's own text, is what makes this
        # recoverable: the text was written for a directory five levels up in
        # /opt/homebrew and means something else everywhere else.
        file(RELATIVE_PATH relative "${qml_dir}" "${link}")
        set(source "${qml_source}/${relative}")
        if(NOT EXISTS "${source}")
            message(FATAL_ERROR
                "Simorg: ${relative} is a dangling link in the bundle and there is no "
                "${source} to replace it with")
        endif()
        file(REAL_PATH "${source}" source)

        # Two kinds of dangling link, and they are repaired differently.
        #
        # Qt points a module's plugin at one copy in Contents/PlugIns, because
        # the App Store will not accept code anywhere else. That link is Qt's
        # own and is correct; it dangles only because the file at the far end of
        # it is the bad one. So the bytes go *there* and the link stays.
        #
        # Everything else — every qmldir — is a Homebrew link copied wholesale,
        # and the link itself is what is wrong.
        file(READ_SYMLINK "${link}" target)
        if(NOT IS_ABSOLUTE "${target}")
            get_filename_component(link_dir "${link}" DIRECTORY)
            get_filename_component(target "${link_dir}/${target}" ABSOLUTE)
        endif()

        # Telling the two apart by asking whether the far end is something the
        # deployment actually made. Qt's link names a file it installed a moment
        # ago — present as a dangling link of its own, which is exactly why this
        # asks about the link rather than about what it resolves to. A copied
        # Homebrew link names a directory that exists only under /opt/homebrew.
        #
        # "Is the target inside the bundle" was the first rule here and it is
        # not enough: ../../../../Cellar/… from four directories down the QML
        # tree lands on Simorg.app/Cellar, which is inside the bundle and is a
        # place nothing should ever write. It did, once — and the bundle then
        # failed to sign, because a .app with a stray directory in its root has
        # unsealed contents and codesign refuses it.
        set(into_bundle FALSE)
        string(FIND "${target}" "${bundle}/Contents/" within)
        if(within EQUAL 0 AND (EXISTS "${target}" OR IS_SYMLINK "${target}"))
            set(into_bundle TRUE)
        endif()
        if(NOT into_bundle)
            set(target "${link}")
        endif()

        # Removed first: writing to the path of a dangling link writes *through*
        # it, which would create the file out in /Cellar and leave the bundle
        # exactly as broken as it was.
        get_filename_component(target_dir "${target}" DIRECTORY)
        file(MAKE_DIRECTORY "${target_dir}")
        file(REMOVE "${target}")
        file(COPY_FILE "${source}" "${target}")

        math(EXPR copied "${copied} + 1")
    endforeach()

    if(copied GREATER 0)
        message(STATUS
            "Simorg: replaced ${copied} QML links into the Qt installation with the files themselves")
    endif()
endfunction()
