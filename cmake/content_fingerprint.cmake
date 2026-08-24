# Rebuild on source CONTENT change, not on mtime.
#
#   include("${CMAKE_CURRENT_LIST_DIR}/../../_mylibs/build_tools/cmake/content_fingerprint.cmake")
#   x_enable_content_fingerprint("${CMAKE_CURRENT_LIST_DIR}/..")
#
# mtimes lie. A restored backup, a sync tool, a checkout of an older branch and
# a VM clock skew all hand the generator files that are byte-different but not
# newer, so nothing rebuilds and the binary silently no longer matches the
# source. This hashes the source manifest instead and touches one stamp file
# when the hash moves; every compiled object depends on that stamp.
#
# The cost is one SHA256 pass over the source trees per build (a few seconds
# for ~8000 files), so it is opt-in per project and only under Ninja/Makefiles,
# where a custom target can run before the compile step.
include_guard(GLOBAL)

function(_x_fingerprint_collect_targets directory result_variable)
    get_property(_x_local_targets DIRECTORY "${directory}" PROPERTY BUILDSYSTEM_TARGETS)
    get_property(_x_subdirectories DIRECTORY "${directory}" PROPERTY SUBDIRECTORIES)

    set(_x_targets ${_x_local_targets})
    foreach(_x_subdirectory IN LISTS _x_subdirectories)
        _x_fingerprint_collect_targets("${_x_subdirectory}" _x_child_targets)
        list(APPEND _x_targets ${_x_child_targets})
    endforeach()

    list(REMOVE_DUPLICATES _x_targets)
    set(${result_variable} "${_x_targets}" PARENT_SCOPE)
endfunction()

# source_root is the PROJECT root - the directory holding src/, res/ and (in a
# published repository) dep/. The worker script adds the sibling _mylibs when it
# is there, which is what makes the development tree and the published tree
# produce the same manifest. Call this AFTER every add_subdirectory(), because
# it wires up the targets that exist at the point of the call.
function(x_enable_content_fingerprint source_root)
    if(NOT CMAKE_GENERATOR MATCHES "Ninja|Makefiles")
        return()
    endif()

    # Names are per-project so two applications configured in one build tree do
    # not collide on the target or on the state directory.
    string(TOLOWER "${PROJECT_NAME}" _x_project)
    string(REGEX REPLACE "[^a-z0-9]+" "_" _x_project "${_x_project}")
    if(_x_project STREQUAL "")
        set(_x_project "x")
    endif()

    set(_x_state_dir "${CMAKE_BINARY_DIR}/CMakeFiles/${_x_project}-source-state")
    set(_x_fingerprint "${_x_state_dir}/fingerprint.sha256")
    set(_x_stamp "${_x_state_dir}/fingerprint.stamp")
    set(_x_script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/source_fingerprint.cmake")

    if(NOT EXISTS "${_x_script}")
        message(STATUS "Skipping content fingerprint - source_fingerprint.cmake missing")
        return()
    endif()

    add_custom_target(${_x_project}_source_fingerprint
        COMMAND "${CMAKE_COMMAND}"
            "-DX_FINGERPRINT_SOURCE_ROOT=${source_root}"
            "-DX_FINGERPRINT_BINARY_DIR=${CMAKE_BINARY_DIR}"
            "-DX_FINGERPRINT_FILE=${_x_fingerprint}"
            "-DX_FINGERPRINT_STAMP=${_x_stamp}"
            -P "${_x_script}"
        BYPRODUCTS "${_x_fingerprint}" "${_x_stamp}"
        COMMENT "Checking source content fingerprint"
        VERBATIM)

    _x_fingerprint_collect_targets("${CMAKE_SOURCE_DIR}" _x_targets)
    foreach(_x_target IN LISTS _x_targets)
        if(_x_target STREQUAL "${_x_project}_source_fingerprint")
            continue()
        endif()

        get_target_property(_x_imported "${_x_target}" IMPORTED)
        get_target_property(_x_type "${_x_target}" TYPE)
        if(_x_imported OR NOT _x_type MATCHES
                "^(EXECUTABLE|STATIC_LIBRARY|SHARED_LIBRARY|MODULE_LIBRARY|OBJECT_LIBRARY)$")
            continue()
        endif()

        add_dependencies("${_x_target}" ${_x_project}_source_fingerprint)
        set_property(TARGET "${_x_target}" APPEND PROPERTY
            AUTOGEN_TARGET_DEPENDS "${_x_stamp}")

        get_target_property(_x_sources "${_x_target}" SOURCES)
        get_target_property(_x_source_dir "${_x_target}" SOURCE_DIR)
        get_target_property(_x_binary_dir "${_x_target}" BINARY_DIR)
        foreach(_x_source IN LISTS _x_sources)
            if(_x_source MATCHES "^\$<")
                continue()
            endif()

            if(IS_ABSOLUTE "${_x_source}")
                set(_x_absolute "${_x_source}")
            elseif(EXISTS "${_x_source_dir}/${_x_source}")
                get_filename_component(_x_absolute
                    "${_x_source_dir}/${_x_source}" ABSOLUTE)
            elseif(EXISTS "${_x_binary_dir}/${_x_source}")
                get_filename_component(_x_absolute
                    "${_x_binary_dir}/${_x_source}" ABSOLUTE)
            else()
                continue()
            endif()

            get_filename_component(_x_extension "${_x_absolute}" EXT)
            string(TOLOWER "${_x_extension}" _x_extension)
            if(_x_extension MATCHES "^\.(c|cc|cpp|cxx|m|mm|rc)$")
                set_property(SOURCE "${_x_absolute}"
                    TARGET_DIRECTORY "${_x_target}" APPEND PROPERTY
                    OBJECT_DEPENDS "${_x_stamp}")
            endif()
        endforeach()
    endforeach()
endfunction()
