# Self-test for the runtime-data install destination rules.
#
#   cmake -P _mylibs/build_tools/cmake/tests/test_data_destination.cmake
#
# Covers x_data_destination.cmake and the leaf-vs-full-path contract that
# deploy_add_translations()'s INSTALL_DESTINATION obeys. Both have already broken
# once each:
#   * keying the path off PROJECT_NAME / CMAKE_INSTALL_LIBDIR put data where
#     XOptions::convertPathName() never looks;
#   * treating INSTALL_DESTINATION as a leaf doubled the path for the one project
#     that passes a complete one (xmachoviewer_source).
#
# Runs standalone - no project, no compiler, no Qt.
cmake_minimum_required(VERSION 3.14)

set(_test_failures 0)

function(expect_equal WHAT ACTUAL EXPECTED)
    if(NOT "${ACTUAL}" STREQUAL "${EXPECTED}")
        message("FAIL ${WHAT}: got \"${ACTUAL}\", wanted \"${EXPECTED}\"")
        math(EXPR _test_failures "${_test_failures} + 1")
        set(_test_failures "${_test_failures}" PARENT_SCOPE)
    else()
        message("ok   ${WHAT}: ${ACTUAL}")
    endif()
endfunction()

get_filename_component(_cmake_dir "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
include("${_cmake_dir}/x_data_destination.cmake")

# --- x_data_name -------------------------------------------------------------
# The runtime looks data up by qApp->applicationName(); X_ORIGINAL_FILENAME is the
# CMake-side variable that matches it.
set(X_ORIGINAL_FILENAME "xocalc")
set(PROJECT_NAME "XOpcodeCalc")
x_data_name(_name)
expect_equal("x_data_name prefers X_ORIGINAL_FILENAME over PROJECT_NAME" "${_name}" "xocalc")

# --- x_data_install_destination ----------------------------------------------
# Assert ALL THREE platforms on EVERY host. These checks used to sit in the
# branches of if(WIN32)/elseif(APPLE)/else(), which meant that on the Windows dev
# box - the only place this test is ever actually run - just the "." case
# executed. The multiarch regression the test exists to catch could not have
# failed here. x_data_install_destination() reads WIN32 and APPLE as ordinary
# variables, so a function scope can stand in for a host.
function(destination_for OUT_VAR PLATFORM)
    set(WIN32 FALSE)
    set(APPLE FALSE)
    if("${PLATFORM}" STREQUAL "windows")
        set(WIN32 TRUE)
    elseif("${PLATFORM}" STREQUAL "macos")
        set(APPLE TRUE)
    endif()
    x_data_install_destination(_r)
    set(${OUT_VAR} "${_r}" PARENT_SCOPE)
endfunction()

destination_for(_root_win "windows")
expect_equal("Windows root is the application directory" "${_root_win}" ".")

destination_for(_root_mac "macos")
expect_equal("macOS root is inside the bundle" "${_root_mac}" "xocalc.app/Contents/Resources")

# Literal "lib", never CMAKE_INSTALL_LIBDIR: on Debian with prefix=/usr the
# latter is lib/<arch-triplet>, which convertPathName() does not search.
destination_for(_root_linux "linux")
expect_equal("Linux root is lib/<app>" "${_root_linux}" "lib/xocalc")
if("${_root_linux}" MATCHES "linux-gnu" OR "${_root_linux}" MATCHES "\$\{CMAKE_INSTALL_LIBDIR\}")
    message("FAIL Linux root must not be multiarch")
    math(EXPR _test_failures "${_test_failures} + 1")
endif()

# --- the leaf-vs-full-path contract ------------------------------------------
# Reimplemented here rather than included, because the real one lives inside
# deploy_translation.cmake next to install() calls that a script-mode run cannot
# execute. Keep the two in step.
function(resolve OUT_VAR LEAF PLATFORM)
    if("${LEAF}" MATCHES "/")
        set(${OUT_VAR} "${LEAF}" PARENT_SCOPE)
        return()
    endif()
    if(DEFINED X_RESOURCES AND NOT "${X_RESOURCES}" STREQUAL "")
        set(_r "${X_RESOURCES}")
    else()
        destination_for(_r "${PLATFORM}")
    endif()
    if("${_r}" STREQUAL "." OR "${_r}" STREQUAL "")
        set(${OUT_VAR} "${LEAF}" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "${_r}/${LEAF}" PARENT_SCOPE)
    endif()
endfunction()

resolve(_leaf_win "lang" "windows")
expect_equal("a leaf resolves next to the executable" "${_leaf_win}" "lang")

resolve(_leaf_mac "lang" "macos")
expect_equal("a leaf resolves inside the bundle" "${_leaf_mac}" "xocalc.app/Contents/Resources/lang")

resolve(_leaf_linux "lang" "linux")
expect_equal("a leaf resolves under lib/<app>" "${_leaf_linux}" "lib/xocalc/lang")

# The xmachoviewer case: a caller that computed the whole path itself.
resolve(_full "lib/x86_64-linux-gnu/xmachoviewer/lang" "linux")
expect_equal("a full path is used verbatim, not doubled" "${_full}" "lib/x86_64-linux-gnu/xmachoviewer/lang")

resolve(_bundle "xmachoviewer.app/Contents/Resources/lang" "macos")
expect_equal("a full bundle path is used verbatim" "${_bundle}" "xmachoviewer.app/Contents/Resources/lang")

# A project may legitimately override the data root - xmachoviewer's portable
# layout puts data next to the executable on every platform. The resolver honours
# X_RESOURCES so such a project can still pass the plain leaf; before, its only
# option was to hand-build the full path, which is how it ended up on the
# multiarch libdir in the first place.
set(X_RESOURCES ".")
resolve(_portable "lang" "linux")
expect_equal("an overridden X_RESOURCES wins over the computed root" "${_portable}" "lang")

set(X_RESOURCES "lib/xmachoviewer")
resolve(_override "lang" "linux")
expect_equal("a non-trivial X_RESOURCES override is prepended to the leaf" "${_override}" "lib/xmachoviewer/lang")
unset(X_RESOURCES)

# --- the X_APPLICATIONNAME cross-check ---------------------------------------
# The path only works because X_ORIGINAL_FILENAME equals the X_APPLICATIONNAME the
# running app reports. Projects have let those drift (XPEIDScanner: "xpeid" vs
# "xpeidscanner"), so x_data_name() reads global.h and warns. This exercises that
# code path - it parses a header, and a mistake there is a hard configure error,
# which is exactly how it escaped the first time.
set(_probe_dir "${CMAKE_CURRENT_BINARY_DIR}/x_data_probe")
file(MAKE_DIRECTORY "${_probe_dir}")

file(WRITE "${_probe_dir}/global.h" "#define X_APPLICATIONNAME \"xocalc\"
")
set(CMAKE_CURRENT_SOURCE_DIR "${_probe_dir}")
set(X_ORIGINAL_FILENAME "xocalc")
x_data_name(_matching)
expect_equal("a matching X_APPLICATIONNAME parses and is accepted" "${_matching}" "xocalc")

file(WRITE "${_probe_dir}/global.h" "#define X_APPLICATIONNAME \"xpeidscanner\"
")
set(X_ORIGINAL_FILENAME "xpeid")
x_data_name(_mismatching)
expect_equal("a mismatching X_APPLICATIONNAME still returns X_ORIGINAL_FILENAME" "${_mismatching}" "xpeid")
message("     (the CMake warning above is the point of that check)")

expect_equal("the mismatch is reported as a value, not just a warning" "${X_DATA_NAME_LAST_CHECK}" "mismatch")

file(WRITE "${_probe_dir}/global.h" "#define X_APPLICATIONNAME \"xocalc\"
")
set(X_ORIGINAL_FILENAME "xocalc")
x_data_name(_ignored)
expect_equal("a match is reported as a value too" "${X_DATA_NAME_LAST_CHECK}" "match")

# The regression that made all of the above pointless in practice: every project
# in this tree reaches x_data_name() from src/gui (through cpp_standart_setup.cmake),
# where neither <dir>/global.h nor <dir>/src/global.h exists. The probe found
# nothing, said nothing, and the guard silently never ran.
set(_probe_gui "${_probe_dir}/gui")
file(MAKE_DIRECTORY "${_probe_gui}")
file(WRITE "${_probe_dir}/global.h" "#define X_APPLICATIONNAME \"xpeidscanner\"
")
set(CMAKE_CURRENT_SOURCE_DIR "${_probe_gui}")
set(X_ORIGINAL_FILENAME "xpeid")
x_data_name(_from_gui)
expect_equal("the drift check still fires when called from a src/gui scope" "${X_DATA_NAME_LAST_CHECK}" "mismatch")

# And a header that genuinely cannot be found must say so rather than pass silently.
# NB: this must sit outside _probe_dir - the widened probe also looks at
# <dir>/../global.h, so a bare directory nested under the probe root would
# legitimately find the parent's header and the case would test nothing.
set(_probe_bare "${CMAKE_CURRENT_BINARY_DIR}/x_data_bare/sub")
file(MAKE_DIRECTORY "${_probe_bare}")
set(CMAKE_CURRENT_SOURCE_DIR "${_probe_bare}")
set(PROJECT_SOURCE_DIR "${_probe_bare}")
set(CMAKE_SOURCE_DIR "${_probe_bare}")
x_data_name(_no_header)
expect_equal("a header that cannot be found is reported as unchecked" "${X_DATA_NAME_LAST_CHECK}" "unchecked")
message("     (the two CMake warnings above are the point of those checks)")

file(REMOVE_RECURSE "${CMAKE_CURRENT_BINARY_DIR}/x_data_bare")
file(REMOVE_RECURSE "${_probe_dir}")
set(X_ORIGINAL_FILENAME "xocalc")

# --- fallback ----------------------------------------------------------------
# A project that never set X_ORIGINAL_FILENAME keeps the old behaviour.
unset(X_ORIGINAL_FILENAME)
x_data_name(_fallback)
expect_equal("falls back to PROJECT_NAME when X_ORIGINAL_FILENAME is unset" "${_fallback}" "XOpcodeCalc")

if(_test_failures GREATER 0)
    message(FATAL_ERROR "FAILED: ${_test_failures} check(s)")
endif()

message("OK: data destination rules behave as documented")
