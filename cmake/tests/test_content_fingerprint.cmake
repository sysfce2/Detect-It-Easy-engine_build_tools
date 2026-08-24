# Self-test for the source content fingerprint.
#
#   cmake -P _mylibs/build_tools/cmake/tests/test_content_fingerprint.cmake
#
# Covers source_fingerprint.cmake, the worker that content_fingerprint.cmake
# runs. Every check here is a way it has already been wrong:
#   * naming the development directories (XFileUnpacker_source, _mylibs) under
#     the given root made the manifest EMPTY in a published repository, where
#     the modules live in dep/ - the feature ran and measured nothing;
#   * putting the build directory name in the EXCLUDE REGEX emptied the
#     manifest completely on the development machine, because that regex is
#     unanchored and these sources live under C:/tmp_build;
#   * a manifest that includes the build tree re-stamps on every build and
#     rebuilds the world every time.
#
# Runs standalone - no project, no compiler, no Qt.
cmake_minimum_required(VERSION 3.18)

set(_test_failures 0)

function(fail WHAT)
    message("FAIL ${WHAT}")
    math(EXPR _test_failures "${_test_failures} + 1")
    set(_test_failures "${_test_failures}" PARENT_SCOPE)
endfunction()

function(expect_contains WHAT TEXT NEEDLE)
    if("${TEXT}" MATCHES "${NEEDLE}")
        message("ok   ${WHAT}")
    else()
        fail("${WHAT}: \"${NEEDLE}\" not in the manifest")
        set(_test_failures "${_test_failures}" PARENT_SCOPE)
    endif()
endfunction()

function(expect_missing WHAT TEXT NEEDLE)
    if("${TEXT}" MATCHES "${NEEDLE}")
        fail("${WHAT}: \"${NEEDLE}\" is in the manifest and must not be")
        set(_test_failures "${_test_failures}" PARENT_SCOPE)
    else()
        message("ok   ${WHAT}")
    endif()
endfunction()

get_filename_component(_cmake_dir "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(_worker "${_cmake_dir}/source_fingerprint.cmake")
if(NOT EXISTS "${_worker}")
    message(FATAL_ERROR "worker not found: ${_worker}")
endif()

set(_probe "${CMAKE_CURRENT_BINARY_DIR}/x_fingerprint_probe")
file(REMOVE_RECURSE "${_probe}")

function(run_fingerprint ROOT BINARY_DIR STATE)
    execute_process(
        COMMAND "${CMAKE_COMMAND}"
            "-DX_FINGERPRINT_SOURCE_ROOT=${ROOT}"
            "-DX_FINGERPRINT_BINARY_DIR=${BINARY_DIR}"
            "-DX_FINGERPRINT_FILE=${STATE}/fingerprint.sha256"
            "-DX_FINGERPRINT_STAMP=${STATE}/fingerprint.stamp"
            -P "${_worker}"
        RESULT_VARIABLE _rc
        OUTPUT_QUIET
        ERROR_VARIABLE _err)
    if(NOT _rc EQUAL 0)
        message(FATAL_ERROR "worker failed (${_rc}): ${_err}")
    endif()
endfunction()

function(read_manifest OUT_VAR STATE)
    set(_text "")
    if(EXISTS "${STATE}/fingerprint.sha256")
        file(READ "${STATE}/fingerprint.sha256" _text)
    endif()
    set(${OUT_VAR} "${_text}" PARENT_SCOPE)
endfunction()

# --- published repository layout ---------------------------------------------
# <repo>/src, <repo>/dep, and a build tree the CI puts inside the repo.
set(_repo "${_probe}/repo")
file(WRITE "${_repo}/src/main.cpp" "int main(){return 0;}\n")
file(WRITE "${_repo}/dep/mod/foo.cpp" "void foo(){}\n")
file(WRITE "${_repo}/dep/mod/foo.h" "void foo();\n")
file(WRITE "${_repo}/tmp_build/CMakeFiles/generated.cmake" "set(x 1)\n")
file(WRITE "${_repo}/tmp_build/CMakeLists.txt" "# generated\n")

run_fingerprint("${_repo}" "${_repo}/tmp_build" "${_probe}/state_pub")
read_manifest(_pub "${_probe}/state_pub")

expect_contains("published layout hashes src/" "${_pub}" "src/main\.cpp")
expect_contains("published layout hashes vendored dep/" "${_pub}" "dep/mod/foo\.cpp")
expect_missing("the build tree stays out of the manifest" "${_pub}" "tmp_build")

# --- no spurious re-stamp ----------------------------------------------------
# The stamp is what every object file depends on. Touching it when nothing
# changed rebuilds everything, every time.
file(TIMESTAMP "${_probe}/state_pub/fingerprint.stamp" _stamp_before "%Y%m%d%H%M%S" UTC)
execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1.2)
run_fingerprint("${_repo}" "${_repo}/tmp_build" "${_probe}/state_pub")
file(TIMESTAMP "${_probe}/state_pub/fingerprint.stamp" _stamp_after "%Y%m%d%H%M%S" UTC)
if("${_stamp_before}" STREQUAL "${_stamp_after}")
    message("ok   an unchanged tree does not move the stamp")
else()
    fail("an unchanged tree moved the stamp - every build would rebuild everything")
endif()

# A generated file changing inside the build tree must not move it either.
file(WRITE "${_repo}/tmp_build/CMakeFiles/generated.cmake" "set(x 2)\n")
run_fingerprint("${_repo}" "${_repo}/tmp_build" "${_probe}/state_pub")
file(TIMESTAMP "${_probe}/state_pub/fingerprint.stamp" _stamp_generated "%Y%m%d%H%M%S" UTC)
if("${_stamp_before}" STREQUAL "${_stamp_generated}")
    message("ok   a regenerated build file does not move the stamp")
else()
    fail("a change inside the build tree moved the stamp")
endif()

# --- a byte change is detected even with the mtime moving backwards ----------
file(WRITE "${_repo}/src/main.cpp" "int main(){return 1;}\n")
run_fingerprint("${_repo}" "${_repo}/tmp_build" "${_probe}/state_pub")
file(TIMESTAMP "${_probe}/state_pub/fingerprint.stamp" _stamp_changed "%Y%m%d%H%M%S" UTC)
if("${_stamp_before}" STREQUAL "${_stamp_changed}")
    fail("a changed source did not move the stamp - nothing would rebuild")
else()
    message("ok   a changed source moves the stamp")
endif()

# --- development tree layout -------------------------------------------------
# qt5/<app>_source with the shared modules in the sibling qt5/_mylibs.
set(_dev "${_probe}/qt5")
file(WRITE "${_dev}/App_source/src/main.cpp" "int main(){return 0;}\n")
file(WRITE "${_dev}/_mylibs/Formats/xbinary.h" "class XBinary{};\n")

run_fingerprint("${_dev}/App_source" "${_probe}/build_dev" "${_probe}/state_dev")
read_manifest(_devtext "${_probe}/state_dev")

expect_contains("development layout hashes the project" "${_devtext}" "src/main\.cpp")
expect_contains("development layout hashes the sibling _mylibs" "${_devtext}" "\.\./_mylibs/Formats/xbinary\.h")

# --- the unanchored-regex trap -----------------------------------------------
# Sources here live under C:/tmp_build. A build-directory NAME in the EXCLUDE
# REGEX matches that too and silently empties the whole manifest.
set(_under "${_probe}/tmp_build/qt5/App_source")
file(WRITE "${_under}/src/main.cpp" "int main(){return 0;}\n")
run_fingerprint("${_under}" "${_probe}/build_under" "${_probe}/state_under")
read_manifest(_undertext "${_probe}/state_under")
expect_contains("a source root under a path named tmp_build is still hashed"
    "${_undertext}" "src/main\.cpp")

# --- required arguments ------------------------------------------------------
execute_process(
    COMMAND "${CMAKE_COMMAND}" -P "${_worker}"
    RESULT_VARIABLE _rc OUTPUT_QUIET ERROR_QUIET)
if(_rc EQUAL 0)
    fail("the worker accepted a run with no arguments")
else()
    message("ok   missing arguments are refused")
endif()

file(REMOVE_RECURSE "${_probe}")

if(_test_failures GREATER 0)
    message(FATAL_ERROR "FAILED: ${_test_failures} check(s)")
endif()

message("OK: the content fingerprint behaves as documented")
