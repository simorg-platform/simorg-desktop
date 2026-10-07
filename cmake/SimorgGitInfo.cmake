# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Records the commit a build came from, for `simorg --version` and bug reports.
# Absent git or a tarball checkout is normal, not an error.

function(simorg_resolve_git_sha out_var)
    set(sha "unknown")

    find_package(Git QUIET)
    # Whether this tree is in a repository is git's question to answer, not a
    # guess at how many directories up `.git` sits: the answer is the same
    # wherever this project is checked out or moved to.
    set(_inside "")
    if(GIT_FOUND)
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" rev-parse --is-inside-work-tree
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
            OUTPUT_VARIABLE _inside
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
    endif()
    if(_inside STREQUAL "true")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" rev-parse --short HEAD
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
            OUTPUT_VARIABLE sha
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(NOT sha)
            set(sha "unknown")
        endif()
    endif()

    set(${out_var} "${sha}" PARENT_SCOPE)
endfunction()
