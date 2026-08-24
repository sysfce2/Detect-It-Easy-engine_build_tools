# Script-mode worker for content_fingerprint.cmake. Not meant to be included:
# it is run with cmake -P by the fingerprint custom target.
#
#   X_FINGERPRINT_SOURCE_ROOT  project root to hash
#   X_FINGERPRINT_BINARY_DIR   build tree to ignore (optional but expected)
#   X_FINGERPRINT_FILE         where the manifest is kept
#   X_FINGERPRINT_STAMP        touched only when the manifest changes
cmake_minimum_required(VERSION 3.18)

if(NOT DEFINED X_FINGERPRINT_SOURCE_ROOT OR X_FINGERPRINT_SOURCE_ROOT STREQUAL "")
    message(FATAL_ERROR "X_FINGERPRINT_SOURCE_ROOT is required")
endif()
if(NOT DEFINED X_FINGERPRINT_FILE OR X_FINGERPRINT_FILE STREQUAL "")
    message(FATAL_ERROR "X_FINGERPRINT_FILE is required")
endif()
if(NOT DEFINED X_FINGERPRINT_STAMP OR X_FINGERPRINT_STAMP STREQUAL "")
    message(FATAL_ERROR "X_FINGERPRINT_STAMP is required")
endif()

get_filename_component(X_FINGERPRINT_SOURCE_ROOT "${X_FINGERPRINT_SOURCE_ROOT}" ABSOLUTE)

# The project root alone is the right manifest in both layouts an application
# here is built in:
#
#   development tree       qt5/<app>_source, with the modules in qt5/_mylibs
#   published repository   <repo>, with the modules vendored under <repo>/dep
#
# _mylibs is a sibling in the first case and inside the root in the second, so
# add it when it is next to us and let the recursive glob find it otherwise.
# Naming the development directories explicitly, as the first version of this
# script did, made the manifest silently EMPTY everywhere else - including CI,
# where the whole feature then measured nothing at all.
set(_x_roots "${X_FINGERPRINT_SOURCE_ROOT}")
get_filename_component(_x_parent "${X_FINGERPRINT_SOURCE_ROOT}" DIRECTORY)
if(IS_DIRECTORY "${_x_parent}/_mylibs")
    list(APPEND _x_roots "${_x_parent}/_mylibs")
endif()

set(_x_patterns)
foreach(_x_root IN LISTS _x_roots)
    foreach(_x_pattern IN ITEMS
            "*.c" "*.cc" "*.cpp" "*.cxx"
            "*.h" "*.hh" "*.hpp" "*.hxx" "*.inl"
            "*.ui" "*.qrc" "*.rc"
            "*.cmake" "CMakeLists.txt")
        list(APPEND _x_patterns "${_x_root}/${_x_pattern}")
    endforeach()
endforeach()

# This script is itself part of the manifest, so a policy change also forces a
# one-time rebuild under the new policy. GLOB_RECURSE is intentional here:
# it detects additions and removals as well as byte changes, independently of
# source mtimes. Generated/build trees are not source inputs.
file(GLOB_RECURSE _x_files LIST_DIRECTORIES false ${_x_patterns})
list(FILTER _x_files EXCLUDE REGEX
    "[/\\\\](\\.git|\\.svn|build|build-[^/\\\\]*|cmake-build-[^/\\\\]*)[/\\\\]")

# The build tree can sit inside the project root (CI configures into
# <repo>/tmp_build). Hashing CMake's own generated files there would change the
# manifest on every build and rebuild the world every time.
#
# This is done by path prefix and not by adding the directory name to the
# EXCLUDE REGEX above: that regex is unanchored and matches anywhere in an
# absolute path, so a name like tmp_build would also erase every file on a
# machine whose sources live under C:/tmp_build - which is where these projects
# are developed. The binary directory is known exactly, so match it exactly.
if(DEFINED X_FINGERPRINT_BINARY_DIR AND NOT X_FINGERPRINT_BINARY_DIR STREQUAL "")
    get_filename_component(_x_binary_root "${X_FINGERPRINT_BINARY_DIR}" ABSOLUTE)
    set(_x_kept)
    foreach(_x_file IN LISTS _x_files)
        string(FIND "${_x_file}" "${_x_binary_root}/" _x_position)
        if(NOT _x_position EQUAL 0)
            list(APPEND _x_kept "${_x_file}")
        endif()
    endforeach()
    set(_x_files ${_x_kept})
endif()

list(SORT _x_files)

set(_x_snapshot "")
foreach(_x_file IN LISTS _x_files)
    file(SHA256 "${_x_file}" _x_hash)
    file(RELATIVE_PATH _x_relative "${X_FINGERPRINT_SOURCE_ROOT}" "${_x_file}")
    string(REPLACE "\\" "/" _x_relative "${_x_relative}")
    string(APPEND _x_snapshot "${_x_hash}  ${_x_relative}\n")
endforeach()

set(_x_previous "")
if(EXISTS "${X_FINGERPRINT_FILE}")
    file(READ "${X_FINGERPRINT_FILE}" _x_previous)
endif()

get_filename_component(_x_state_dir "${X_FINGERPRINT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${_x_state_dir}")

if(NOT "${_x_snapshot}" STREQUAL "${_x_previous}")
    file(WRITE "${X_FINGERPRINT_FILE}" "${_x_snapshot}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E touch "${X_FINGERPRINT_STAMP}"
        RESULT_VARIABLE _x_touch_result)
    if(NOT _x_touch_result EQUAL 0)
        message(FATAL_ERROR "Cannot update source fingerprint stamp")
    endif()
elseif(NOT EXISTS "${X_FINGERPRINT_STAMP}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E touch "${X_FINGERPRINT_STAMP}"
        RESULT_VARIABLE _x_touch_result)
    if(NOT _x_touch_result EQUAL 0)
        message(FATAL_ERROR "Cannot create source fingerprint stamp")
    endif()
endif()
