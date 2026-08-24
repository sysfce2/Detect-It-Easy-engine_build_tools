# Where an application's runtime data must be installed.
#
# "Runtime data" is everything the application looks up through
# XOptions::convertPathName("$data/...") at run time: translations (lang),
# stylesheets (qss), signature databases (db), and so on.
#
# This is NOT a free choice. XOptions::convertPathName() (see
# _mylibs/XOptions/xoptions.cpp) hardcodes the list of directories it will
# search, and only accepts a candidate if it exists on disk. In order:
#
#   1. <bundle>/Contents/MacOS/../Resources      (macOS only)
#   2. applicationDirPath()                      (portable / Windows)
#   3. QStandardPaths::AppDataLocation
#   4. <prefix>/usr/local/lib/<applicationName>  (when the exe is in /usr/local/bin)
#   5. <prefix>/app/lib/<applicationName>        (when the exe is in /app/bin - Flatpak)
#   6. <mount>/app/lib/<applicationName>         (when the exe is under /tmp/.mount_ - AppImage)
#   7. qApp->property("dataPathAlt0".."dataPathAlt9")
#   8. /usr/local/lib/<applicationName>
#   9. /usr/lib/<applicationName>
#
# Two consequences drive everything below.
#
# * <applicationName> is qApp->applicationName(), i.e. the X_APPLICATIONNAME from
#   the project's global.h - NOT the CMake PROJECT_NAME. Those differ in almost
#   every project here ("xocalc" vs "XOpcodeCalc", "die" vs "DetectItEasy",
#   "nfd" vs "NauzFileDetector"), so keying the install path off PROJECT_NAME
#   installs data where the application will never look. X_ORIGINAL_FILENAME is
#   the CMake-side variable that matches X_APPLICATIONNAME in every project in
#   this tree, and it is also what every project passes to OUTPUT_NAME - so it
#   names the macOS bundle as well.
#
# * The library directory must be the literal "lib", NOT ${CMAKE_INSTALL_LIBDIR}.
#   On a Debian/Ubuntu host with CMAKE_INSTALL_PREFIX=/usr, GNUInstallDirs
#   resolves CMAKE_INSTALL_LIBDIR to the multiarch "lib/x86_64-linux-gnu", and
#   entries 8 and 9 above do not search there. Using the literal "lib" lands on
#   /usr/lib/<app> (entry 9), /usr/local/lib/<app> (entry 8) and /app/lib/<app>
#   (entries 5 and 6) - i.e. every Linux prefix the runtime actually knows.
#   FHS would prefer share/ for architecture-independent data; the runtime
#   lookup decides, not FHS.
#
# Set X_RESOURCES (or pass DESTINATION explicitly) before including this file to
# override any of it.

if(DEFINED X_DATA_DESTINATION_INCLUDED)
    return()
endif()
set(X_DATA_DESTINATION_INCLUDED TRUE)

# The name the running application will use to look its data up again.
function(x_data_name OUT_VAR)
    if(DEFINED X_ORIGINAL_FILENAME AND NOT "${X_ORIGINAL_FILENAME}" STREQUAL "")
        # X_ORIGINAL_FILENAME only works as the data directory name because it
        # happens to equal X_APPLICATIONNAME, which is what qApp->applicationName()
        # returns and therefore what convertPathName() looks for. When a project
        # lets the two drift the data installs under a name the application never
        # probes, and the failure is silent - the app just comes up with no
        # translations and no database. Say so at configure time.
        #   XPEIDScanner_source : X_ORIGINAL_FILENAME "xpeid" vs X_APPLICATIONNAME "xpeidscanner"
        #   xdataextractor_source : X_ORIGINAL_FILENAME "xde" vs bundle XDataExtractor.app
        # Find global.h WITHOUT assuming which directory called us. This used to
        # probe only CMAKE_CURRENT_SOURCE_DIR and CMAKE_CURRENT_SOURCE_DIR/src,
        # which meant the check silently did nothing for every project that
        # reaches this function from src/gui (i.e. through cpp_standart_setup.cmake
        # - all 33 consumers in this tree). It fired only on the path through
        # deploy_add_translations(), which projects call from src/. The result was
        # a guard that appeared to pass while never having run: xdataextractor,
        # one of the two projects named in the comment above, was never checked.
        # A project can also point at the header explicitly with X_GLOBAL_HEADER.
        set(_x_global_header "")
        foreach(_x_candidate
                "${X_GLOBAL_HEADER}"
                "${CMAKE_CURRENT_SOURCE_DIR}/global.h"
                "${CMAKE_CURRENT_SOURCE_DIR}/src/global.h"
                "${CMAKE_CURRENT_SOURCE_DIR}/../global.h"
                "${PROJECT_SOURCE_DIR}/global.h"
                "${PROJECT_SOURCE_DIR}/src/global.h"
                "${CMAKE_SOURCE_DIR}/src/global.h")
            if(_x_global_header STREQUAL "" AND NOT _x_candidate STREQUAL "" AND EXISTS "${_x_candidate}")
                set(_x_global_header "${_x_candidate}")
            endif()
        endforeach()

        # Report the outcome as a value, not only as a warning. A message(WARNING)
        # cannot be asserted on, so nothing could tell "the names agree" apart from
        # "the check never ran" - which is exactly how the broken probe survived.
        # X_DATA_NAME_LAST_CHECK is one of: match | mismatch | unchecked.
        set(X_DATA_NAME_LAST_CHECK "unchecked" PARENT_SCOPE)

        if(NOT EXISTS "${_x_global_header}")
            # Say so rather than staying quiet: "not checked" and "names agree"
            # are not the same outcome, and the old code reported them the same way.
            message(WARNING
                "x_data_name: could not locate global.h from \"${CMAKE_CURRENT_SOURCE_DIR}\", so "
                "X_ORIGINAL_FILENAME (\"${X_ORIGINAL_FILENAME}\") was NOT checked against "
                "X_APPLICATIONNAME. If they differ, runtime data installs under a name the "
                "application never probes. Set X_GLOBAL_HEADER to the header's path to enable the check.")
        endif()

        if(EXISTS "${_x_global_header}")
            file(STRINGS "${_x_global_header}" _x_appname_line REGEX "^#define[ 	]+X_APPLICATIONNAME[ 	]+\"")
            if(_x_appname_line)
                string(REGEX REPLACE "^[^\"]*\"([^\"]*)\".*$" "\\1" _x_appname "${_x_appname_line}")
                if("${_x_appname}" STREQUAL "${X_ORIGINAL_FILENAME}")
                    set(X_DATA_NAME_LAST_CHECK "match" PARENT_SCOPE)
                else()
                    set(X_DATA_NAME_LAST_CHECK "mismatch" PARENT_SCOPE)
                endif()

                if(NOT "${_x_appname}" STREQUAL "${X_ORIGINAL_FILENAME}")
                    message(WARNING
                        "x_data_name: X_ORIGINAL_FILENAME (\"${X_ORIGINAL_FILENAME}\") does not match "
                        "X_APPLICATIONNAME (\"${_x_appname}\") in ${_x_global_header}. Runtime data is "
                        "installed under the former but looked up under the latter, so translations, "
                        "stylesheets and databases will not be found. Make them equal.")
                endif()
            endif()
        endif()

        set(${OUT_VAR} "${X_ORIGINAL_FILENAME}" PARENT_SCOPE)
    else()
        # Fall back to the old behaviour rather than guessing, and say so: a
        # project that does not set X_ORIGINAL_FILENAME gets what it got before.
        message(WARNING
            "x_data_name: X_ORIGINAL_FILENAME is not set, falling back to PROJECT_NAME "
            "(\"${PROJECT_NAME}\"). Runtime data lookup uses qApp->applicationName(), so "
            "set X_ORIGINAL_FILENAME to the project's X_APPLICATIONNAME if they differ.")
        set(${OUT_VAR} "${PROJECT_NAME}" PARENT_SCOPE)
    endif()
endfunction()

# Install destination, relative to CMAKE_INSTALL_PREFIX, for this project's
# runtime data root. Append the leaf ("lang", "qss", "db", ...) to it.
function(x_data_install_destination OUT_VAR)
    x_data_name(_x_data_name)

    if(WIN32)
        # Portable layout: everything sits next to the executable, which is
        # entry 2 in the search order.
        set(_x_data_destination ".")
    elseif(APPLE)
        # Entry 1. The bundle is named after OUTPUT_NAME, which every project
        # here sets from X_ORIGINAL_FILENAME.
        set(_x_data_destination "${_x_data_name}.app/Contents/Resources")
    else()
        # Entries 5, 6, 8 and 9 - see the note above on the literal "lib".
        set(_x_data_destination "lib/${_x_data_name}")
    endif()

    set(${OUT_VAR} "${_x_data_destination}" PARENT_SCOPE)
endfunction()
