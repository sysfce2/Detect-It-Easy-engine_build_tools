# XOptions::convertPathName() decides where runtime data has to live; see
# x_data_destination.cmake for the full search order and why it is not a free
# choice. INSTALL_DESTINATION below names the LEAF directory ("lang", "qss",
# "db"); the platform-correct root in front of it is computed, not passed in.
include("${CMAKE_CURRENT_LIST_DIR}/x_data_destination.cmake")

# Resolve a caller-supplied leaf into a full install destination.
#   DATA_ROOT <dir>  - override the computed root (escape hatch)
function(_deploy_resolve_data_destination OUT_VAR LEAF)
    # Backward compatibility: INSTALL_DESTINATION used to be passed through
    # verbatim, and at least one project (xmachoviewer_source/src/CMakeLists.txt)
    # sets X_RESOURCES itself and hands us the COMPLETE path "${X_RESOURCES}/lang".
    # Prepending a computed root to that would double it - e.g.
    # /usr/lib/xmachoviewer/lib/x86_64-linux-gnu/xmachoviewer/lang. A leaf is a
    # single directory name ("lang", "qss", "db"), so anything containing a
    # separator is a caller-supplied full path and is used as-is. CMake writes
    # install destinations with forward slashes, so testing for "/" is enough.
    if("${LEAF}" MATCHES "/")
        message(STATUS "deploy: INSTALL_DESTINATION \"${LEAF}\" is a full path, using it verbatim")
        set(${OUT_VAR} "${LEAF}" PARENT_SCOPE)
        return()
    endif()

    if(DEFINED DEPLOY_DATA_ROOT AND NOT "${DEPLOY_DATA_ROOT}" STREQUAL "")
        set(_deploy_root "${DEPLOY_DATA_ROOT}")
    elseif(DEFINED X_RESOURCES AND NOT "${X_RESOURCES}" STREQUAL "")
        # X_RESOURCES *is* this project's data root - cpp_standart_setup.cmake sets
        # it from x_data_install_destination(). Honouring it lets a project that
        # deliberately overrides the root (e.g. a portable layout that puts data next
        # to the executable on every platform) still pass the plain leaf "lang"
        # instead of hand-building a full path, which is how the one project that
        # did hand-build it ended up on the multiarch libdir.
        set(_deploy_root "${X_RESOURCES}")
    else()
        x_data_install_destination(_deploy_root)
    endif()

    if("${_deploy_root}" STREQUAL "." OR "${_deploy_root}" STREQUAL "")
        set(${OUT_VAR} "${LEAF}" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "${_deploy_root}/${LEAF}" PARENT_SCOPE)
    endif()
endfunction()

function(deploy_install_directory)
    set(options)
    set(oneValueArgs SOURCE_DIR INSTALL_DESTINATION WINDOWS_APPDATA_SUBDIR DATA_ROOT)
    set(multiValueArgs)
    cmake_parse_arguments(DEPLOY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT DEPLOY_SOURCE_DIR)
        message(WARNING "deploy_install_directory: SOURCE_DIR is empty.")
        return()
    endif()

    if(NOT EXISTS "${DEPLOY_SOURCE_DIR}")
        message(WARNING "deploy_install_directory: SOURCE_DIR does not exist: ${DEPLOY_SOURCE_DIR}")
        return()
    endif()

    if(NOT DEPLOY_INSTALL_DESTINATION)
        message(WARNING "deploy_install_directory: INSTALL_DESTINATION is empty.")
        return()
    endif()

    _deploy_resolve_data_destination(_deploy_full_destination "${DEPLOY_INSTALL_DESTINATION}")
    message(STATUS "deploy_install_directory: ${DEPLOY_INSTALL_DESTINATION} -> ${_deploy_full_destination}")

    install(DIRECTORY "${DEPLOY_SOURCE_DIR}/" DESTINATION "${_deploy_full_destination}")

    if(WIN32 AND DEPLOY_WINDOWS_APPDATA_SUBDIR)
        set(_deploy_install_code "string(FIND \"\${CMAKE_INSTALL_PREFIX}\" \"_CPack_Packages\" _deploy_cpack_index)\n")
        string(APPEND _deploy_install_code "if(_deploy_cpack_index EQUAL -1)\n")
        string(APPEND _deploy_install_code "    set(_deploy_source_dir \"\${CMAKE_INSTALL_PREFIX}/${_deploy_full_destination}\")\n")
        string(APPEND _deploy_install_code "    if(EXISTS \"\${_deploy_source_dir}\")\n")
        string(APPEND _deploy_install_code "        if(NOT \"\$ENV{APPDATA}\" STREQUAL \"\")\n")
        string(APPEND _deploy_install_code "            file(TO_CMAKE_PATH \"\$ENV{APPDATA}\" _deploy_appdata_dir)\n")
        string(APPEND _deploy_install_code "            set(_deploy_target_dir \"\${_deploy_appdata_dir}/${DEPLOY_WINDOWS_APPDATA_SUBDIR}/${DEPLOY_INSTALL_DESTINATION}\")\n")
        string(APPEND _deploy_install_code "            file(MAKE_DIRECTORY \"\${_deploy_target_dir}\")\n")
        string(APPEND _deploy_install_code "            file(COPY \"\${_deploy_source_dir}/\" DESTINATION \"\${_deploy_target_dir}\")\n")
        string(APPEND _deploy_install_code "        endif()\n")
        string(APPEND _deploy_install_code "    endif()\n")
        string(APPEND _deploy_install_code "endif()\n")

        install(CODE "${_deploy_install_code}")
    endif()
endfunction()

function(deploy_create_missing_ts_files)
    set(options)
    set(oneValueArgs LUPDATE_EXECUTABLE SOURCE_DIR)
    set(multiValueArgs SOURCE_DIRS TS_FILES LUPDATE_HINTS LUPDATE_OPTIONS)
    cmake_parse_arguments(DEPLOY_CREATE_TS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(DEPLOY_CREATE_TS_SOURCE_DIR)
        list(APPEND DEPLOY_CREATE_TS_SOURCE_DIRS "${DEPLOY_CREATE_TS_SOURCE_DIR}")
    endif()

    if(NOT DEPLOY_CREATE_TS_SOURCE_DIRS)
        set(DEPLOY_CREATE_TS_SOURCE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()

    if(NOT DEPLOY_CREATE_TS_TS_FILES)
        message(WARNING "deploy_create_missing_ts_files: TS_FILES is empty.")
        return()
    endif()

    set(_deploy_missing_ts_files "")
    foreach(_deploy_ts_file ${DEPLOY_CREATE_TS_TS_FILES})
        if(NOT EXISTS "${_deploy_ts_file}")
            list(APPEND _deploy_missing_ts_files "${_deploy_ts_file}")
        endif()
    endforeach()

    if(NOT _deploy_missing_ts_files)
        return()
    endif()

    foreach(_deploy_source_dir ${DEPLOY_CREATE_TS_SOURCE_DIRS})
        if(NOT EXISTS "${_deploy_source_dir}")
            message(FATAL_ERROR "deploy_create_missing_ts_files: SOURCE_DIR does not exist: ${_deploy_source_dir}")
        endif()
    endforeach()

    set(_deploy_lupdate_executable "")
    if(DEPLOY_CREATE_TS_LUPDATE_EXECUTABLE)
        set(_deploy_lupdate_executable "${DEPLOY_CREATE_TS_LUPDATE_EXECUTABLE}")
    endif()

    if(NOT _deploy_lupdate_executable)
        foreach(_deploy_lupdate_target Qt6::lupdate Qt5::lupdate)
            if(TARGET ${_deploy_lupdate_target})
                get_target_property(_deploy_lupdate_target_location ${_deploy_lupdate_target} IMPORTED_LOCATION)
                if(_deploy_lupdate_target_location)
                    set(_deploy_lupdate_executable "${_deploy_lupdate_target_location}")
                    break()
                endif()
            endif()
        endforeach()
    endif()

    if(NOT _deploy_lupdate_executable)
        set(_deploy_lupdate_hints ${DEPLOY_CREATE_TS_LUPDATE_HINTS})
        if(CMAKE_PREFIX_PATH)
            foreach(_deploy_qt_prefix_path ${CMAKE_PREFIX_PATH})
                list(APPEND _deploy_lupdate_hints "${_deploy_qt_prefix_path}/bin")
            endforeach()
        endif()

        find_program(_deploy_lupdate_program
            NAMES lupdate lupdate.exe
            HINTS ${_deploy_lupdate_hints}
        )

        if(_deploy_lupdate_program)
            set(_deploy_lupdate_executable "${_deploy_lupdate_program}")
        endif()
    endif()

    if(NOT _deploy_lupdate_executable)
        string(REPLACE ";" "\n  " _deploy_missing_ts_message "${_deploy_missing_ts_files}")
        message(FATAL_ERROR
            "lupdate was not found, and missing translation source files cannot be generated:\n"
            "  ${_deploy_missing_ts_message}"
        )
    endif()

    foreach(_deploy_ts_file ${_deploy_missing_ts_files})
        get_filename_component(_deploy_ts_dir "${_deploy_ts_file}" DIRECTORY)
        file(MAKE_DIRECTORY "${_deploy_ts_dir}")
    endforeach()

    execute_process(
        COMMAND "${_deploy_lupdate_executable}"
            -recursive
            ${DEPLOY_CREATE_TS_LUPDATE_OPTIONS}
            ${DEPLOY_CREATE_TS_SOURCE_DIRS}
            -ts ${_deploy_missing_ts_files}
        RESULT_VARIABLE _deploy_lupdate_result
        OUTPUT_VARIABLE _deploy_lupdate_output
        ERROR_VARIABLE _deploy_lupdate_error
    )

    if(NOT _deploy_lupdate_result EQUAL 0)
        message(FATAL_ERROR
            "Failed to create missing translation source files.\n"
            "${_deploy_lupdate_output}\n"
            "${_deploy_lupdate_error}"
        )
    endif()
endfunction()

function(deploy_add_translations)
    set(options ADD_TO_ALL)
    set(oneValueArgs TARGET_NAME INSTALL_DESTINATION OUTPUT_DIR WINDOWS_APPDATA_SUBDIR SOURCE_DIR LUPDATE_EXECUTABLE DATA_ROOT)
    set(multiValueArgs TS_FILES LRELEASE_HINTS SOURCE_DIRS LUPDATE_HINTS LUPDATE_OPTIONS)
    cmake_parse_arguments(DEPLOY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT DEPLOY_TARGET_NAME)
        set(DEPLOY_TARGET_NAME translations)
    endif()

    if(NOT DEPLOY_INSTALL_DESTINATION)
        set(DEPLOY_INSTALL_DESTINATION translations)
    endif()

    if(NOT DEPLOY_OUTPUT_DIR)
        set(DEPLOY_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/translations")
    endif()

    if(NOT DEPLOY_TS_FILES)
        message(WARNING "deploy_add_translations: TS_FILES is empty.")
        return()
    endif()

    set(_deploy_create_ts_args
        TS_FILES ${DEPLOY_TS_FILES}
        SOURCE_DIRS ${DEPLOY_SOURCE_DIRS}
        LUPDATE_HINTS ${DEPLOY_LUPDATE_HINTS}
        LUPDATE_OPTIONS ${DEPLOY_LUPDATE_OPTIONS}
    )

    if(DEPLOY_SOURCE_DIR)
        list(APPEND _deploy_create_ts_args SOURCE_DIR "${DEPLOY_SOURCE_DIR}")
    endif()

    if(DEPLOY_LUPDATE_EXECUTABLE)
        list(APPEND _deploy_create_ts_args LUPDATE_EXECUTABLE "${DEPLOY_LUPDATE_EXECUTABLE}")
    endif()

    deploy_create_missing_ts_files(${_deploy_create_ts_args})

    set(_lrelease_hints ${DEPLOY_LRELEASE_HINTS})
    if(CMAKE_PREFIX_PATH)
        set(_qt_prefix_paths ${CMAKE_PREFIX_PATH})
        list(GET _qt_prefix_paths 0 _qt_prefix_first)
        list(APPEND _lrelease_hints "${_qt_prefix_first}/bin")
    endif()

    find_program(_deploy_lrelease_executable lrelease HINTS ${_lrelease_hints})

    if(NOT _deploy_lrelease_executable)
        message(WARNING "lrelease was not found. Translation files will not be generated.")
        return()
    endif()

    set(_deploy_qm_files "")
    foreach(_deploy_ts_file ${DEPLOY_TS_FILES})
        get_filename_component(_deploy_ts_name "${_deploy_ts_file}" NAME_WE)
        set(_deploy_qm_file "${DEPLOY_OUTPUT_DIR}/${_deploy_ts_name}.qm")

        add_custom_command(
            OUTPUT "${_deploy_qm_file}"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${DEPLOY_OUTPUT_DIR}"
            COMMAND "${_deploy_lrelease_executable}" "${_deploy_ts_file}" -qm "${_deploy_qm_file}"
            DEPENDS "${_deploy_ts_file}"
            VERBATIM
        )

        list(APPEND _deploy_qm_files "${_deploy_qm_file}")
    endforeach()

    if(_deploy_qm_files)
        if(DEPLOY_ADD_TO_ALL)
            add_custom_target(${DEPLOY_TARGET_NAME} ALL DEPENDS ${_deploy_qm_files})
        else()
            add_custom_target(${DEPLOY_TARGET_NAME} DEPENDS ${_deploy_qm_files})
        endif()

        _deploy_resolve_data_destination(_deploy_full_destination "${DEPLOY_INSTALL_DESTINATION}")
        message(STATUS "deploy_add_translations: ${DEPLOY_INSTALL_DESTINATION} -> ${_deploy_full_destination}")

        install(FILES ${_deploy_qm_files} DESTINATION "${_deploy_full_destination}")

        if(WIN32 AND DEPLOY_WINDOWS_APPDATA_SUBDIR)
            set(_deploy_install_code "string(FIND \"\${CMAKE_INSTALL_PREFIX}\" \"_CPack_Packages\" _deploy_cpack_index)\n")
            string(APPEND _deploy_install_code "if(_deploy_cpack_index EQUAL -1)\n")
            string(APPEND _deploy_install_code "    set(_deploy_source_dir \"\${CMAKE_INSTALL_PREFIX}/${_deploy_full_destination}\")\n")
            string(APPEND _deploy_install_code "    if(EXISTS \"\${_deploy_source_dir}\")\n")
            string(APPEND _deploy_install_code "        if(NOT \"\$ENV{APPDATA}\" STREQUAL \"\")\n")
            string(APPEND _deploy_install_code "            file(TO_CMAKE_PATH \"\$ENV{APPDATA}\" _deploy_appdata_dir)\n")
            string(APPEND _deploy_install_code "            set(_deploy_target_dir \"\${_deploy_appdata_dir}/${DEPLOY_WINDOWS_APPDATA_SUBDIR}/${DEPLOY_INSTALL_DESTINATION}\")\n")
            string(APPEND _deploy_install_code "            file(MAKE_DIRECTORY \"\${_deploy_target_dir}\")\n")
            string(APPEND _deploy_install_code "            file(COPY \"\${_deploy_source_dir}/\" DESTINATION \"\${_deploy_target_dir}\")\n")
            string(APPEND _deploy_install_code "        endif()\n")
            string(APPEND _deploy_install_code "    endif()\n")
            string(APPEND _deploy_install_code "endif()\n")

            install(CODE "${_deploy_install_code}")
        endif()

        set(${DEPLOY_TARGET_NAME}_QM_FILES ${_deploy_qm_files} PARENT_SCOPE)
    endif()
endfunction()
