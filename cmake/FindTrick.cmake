#[=======================================================================[.rst:
FindTrick
---------

Use a built NASA Trick tree (https://github.com/nasa/trick) as a regular CMake
dependency.

Trick's code generators (configuration_processor, ICG, convert_swig, SWIG) are
still used to turn an ``S_define`` + model headers into C++ sources, but CMake
compiles and links everything. The result is an ordinary executable.

Inputs
^^^^^^
``TRICK_HOME``  (cache var or environment variable) root of the Trick tree.

Result
^^^^^^
``Trick_FOUND``, ``Trick_VERSION``
``Trick::Trick``  INTERFACE target: Trick headers, defines, libraries and
                  their third-party dependencies (Python, GSL, UDUNITS2).

Functions
^^^^^^^^^
.. code-block:: cmake

  trick_add_simulation(<target>
      S_DEFINE <file>
      [MODELS <model-target>...]       # libraries implementing the S_define jobs
      [INCLUDE_DIRS <dir>...]          # extra search paths for CP/ICG
  )
#]=======================================================================]

include(FindPackageHandleStandardArgs)

if(NOT TRICK_HOME AND DEFINED ENV{TRICK_HOME})
    set(TRICK_HOME "$ENV{TRICK_HOME}")
endif()
set(TRICK_HOME "${TRICK_HOME}" CACHE PATH "Root of the built Trick tree")

find_file(TRICK_VERSION_FILE share/trick/trick_ver.txt PATHS "${TRICK_HOME}" NO_DEFAULT_PATH)
find_library(TRICK_LIBRARY trick PATHS "${TRICK_HOME}/lib" NO_DEFAULT_PATH)
find_path(TRICK_INCLUDE_DIR trick/Executive.hh PATHS "${TRICK_HOME}/include" NO_DEFAULT_PATH)

if(TRICK_VERSION_FILE)
    file(STRINGS "${TRICK_VERSION_FILE}" _ver REGEX "^current_version")
    if(_ver MATCHES [[([0-9]+)\.([0-9]+)\.([0-9]+)]])
        set(Trick_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}")
        set(Trick_VERSION_MAJOR "${CMAKE_MATCH_1}")
        set(Trick_VERSION_MINOR "${CMAKE_MATCH_2}")
    endif()
endif()

find_package_handle_standard_args(Trick
    REQUIRED_VARS TRICK_LIBRARY TRICK_INCLUDE_DIR TRICK_VERSION_FILE
    VERSION_VAR Trick_VERSION)

if(NOT Trick_FOUND OR TARGET Trick::Trick)
    return()
endif()

# --- Read the tool/dependency choices Trick was configured with ---------------
set(_trick_cfg "${TRICK_HOME}/share/trick/makefiles/config_user.mk")
function(_trick_cfg_value var out)
    file(STRINGS "${_trick_cfg}" _line REGEX "^${var}[ \t]*=")
    string(REGEX REPLACE "^${var}[ \t]*=[ \t]*" "" _line "${_line}")
    string(STRIP "${_line}" _line)
    set(${out} "${_line}" PARENT_SCOPE)
endfunction()

_trick_cfg_value(PYTHON _trick_python)
_trick_cfg_value(GSL_HOME _trick_gsl_home)
_trick_cfg_value(USE_ER7_UTILS _trick_use_er7)
_trick_cfg_value(HDF5 _trick_hdf5)

# SWIG-generated code is compiled against Trick's Python, so use the same one.
if(_trick_python AND NOT Python3_EXECUTABLE)
    set(Python3_EXECUTABLE "${_trick_python}")
endif()
find_package(Python3 REQUIRED COMPONENTS Interpreter Development.Embed)
find_package(Threads REQUIRED)

if(_trick_gsl_home)
    list(APPEND CMAKE_PREFIX_PATH "${_trick_gsl_home}")
    find_package(GSL REQUIRED)
endif()

if(_trick_hdf5)
    set(HDF5_ROOT "${_trick_hdf5}")
    find_package(HDF5 REQUIRED COMPONENTS C HL)
endif()

find_path(UDUNITS2_INCLUDE_DIR udunits2.h PATH_SUFFIXES udunits2)
find_library(UDUNITS2_LIBRARY udunits2)
if(NOT UDUNITS2_INCLUDE_DIR OR NOT UDUNITS2_LIBRARY)
    message(FATAL_ERROR "Trick requires UDUNITS2 (brew install udunits)")
endif()

# --- Trick::Trick --------------------------------------------------------------
add_library(Trick::Trick INTERFACE IMPORTED)
target_include_directories(Trick::Trick SYSTEM INTERFACE
    "${TRICK_HOME}/trick_source"
    "${TRICK_HOME}/include"
    "${TRICK_HOME}/include/trick/compat"
    "${UDUNITS2_INCLUDE_DIR}")
target_compile_definitions(Trick::Trick INTERFACE
    TRICK_VER=${Trick_VERSION_MAJOR}
    TRICK_MINOR=${Trick_VERSION_MINOR})

set(_trick_libs trick trick_pyip trick_comm trick_math trick_units trick_mm trick_connection_handlers)
if(_trick_use_er7 STREQUAL "1")
    list(APPEND _trick_libs er7_utils)
    target_compile_definitions(Trick::Trick INTERFACE USE_ER7_UTILS_INTEGRATORS)
endif()
foreach(_lib IN LISTS _trick_libs)
    add_library(Trick::${_lib} STATIC IMPORTED)
    set_target_properties(Trick::${_lib} PROPERTIES
        IMPORTED_LOCATION "${TRICK_HOME}/lib/lib${_lib}.a")
    # Trick registers jobs/classes through static initializers, so every object
    # in its archives must be kept.
    target_link_libraries(Trick::Trick INTERFACE "$<LINK_LIBRARY:WHOLE_ARCHIVE,Trick::${_lib}>")
endforeach()

target_link_libraries(Trick::Trick INTERFACE
    Python3::Python
    "${UDUNITS2_LIBRARY}"
    Threads::Threads
    ${CMAKE_DL_LIBS})
if(TARGET GSL::gsl)
    target_link_libraries(Trick::Trick INTERFACE GSL::gsl)
    target_compile_definitions(Trick::Trick INTERFACE _HAVE_GSL)
endif()
if(HDF5_FOUND)
    target_link_libraries(Trick::Trick INTERFACE ${HDF5_HL_LIBRARIES} ${HDF5_C_LIBRARIES})
endif()
if(APPLE)
    target_link_libraries(Trick::Trick INTERFACE "-framework CoreFoundation")
endif()

# --- trick_add_simulation ------------------------------------------------------
set(_TRICK_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}")

function(trick_add_simulation target)
    cmake_parse_arguments(PARSE_ARGV 1 ARG "" "S_DEFINE" "MODELS;INCLUDE_DIRS")
    if(NOT ARG_S_DEFINE)
        message(FATAL_ERROR "trick_add_simulation: S_DEFINE is required")
    endif()
    cmake_path(ABSOLUTE_PATH ARG_S_DEFINE BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")

    # Search paths for CP/ICG: explicit dirs + the models' public include dirs.
    set(_inc ${ARG_INCLUDE_DIRS})
    foreach(_m IN LISTS ARG_MODELS)
        get_target_property(_m_inc ${_m} INTERFACE_INCLUDE_DIRECTORIES)
        foreach(_d IN LISTS _m_inc)
            string(REGEX REPLACE [[^\$<BUILD_INTERFACE:(.*)>$]] [[\1]] _d "${_d}")
            if(_d AND NOT _d MATCHES [[\$<]])
                list(APPEND _inc "${_d}")
            endif()
        endforeach()
    endforeach()
    list(REMOVE_DUPLICATES _inc)
    list(TRANSFORM _inc PREPEND "-I")
    list(JOIN _inc " " _trick_cflags)

    # Stage the S_define in the build tree so Trick never writes into sources.
    set(_stage "${CMAKE_CURRENT_BINARY_DIR}/${target}_trick")
    file(MAKE_DIRECTORY "${_stage}")
    configure_file("${ARG_S_DEFINE}" "${_stage}/S_define" COPYONLY)

    # Same makefile trick-CP would write, but we only ask for code generation.
    file(READ "${TRICK_HOME}/bin/trick-CP" _cp)
    string(FIND "${_cp}" "\n__END__\n" _pos)
    math(EXPR _pos "${_pos} + 9")
    string(SUBSTRING "${_cp}" ${_pos} -1 _mk)
    string(REPLACE "SUB_TRICK_HOME" "${TRICK_HOME}" _mk "${_mk}")
    string(REPLACE "SUB_TRICK_BIN" "${TRICK_HOME}/bin" _mk "${_mk}")
    file(WRITE "${_stage}/makefile" "${_mk}")

    message(STATUS "Trick: generating sources for ${target} (CP, ICG, SWIG)")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E env
            "TRICK_HOME=${TRICK_HOME}"
            "TRICK_SIM_DIR=${_stage}/"
            "TRICK_BUILD_DIR="
            "TRICK_CFLAGS=${_trick_cflags}"
            "TRICK_CXXFLAGS=${_trick_cflags}"
            make -f makefile S_source.hh trick.zip
        WORKING_DIRECTORY "${_stage}"
        RESULT_VARIABLE _rc
        OUTPUT_FILE "${_stage}/codegen.log"
        ERROR_FILE "${_stage}/codegen.log")
    if(NOT _rc EQUAL 0)
        file(READ "${_stage}/codegen.log" _log)
        message(FATAL_ERROR "Trick code generation failed:\n${_log}")
    endif()

    # Trick's link lists name the objects it would build; we want their sources.
    set(_gen "${_stage}/build/S_source.cpp")
    foreach(_list io_link_list py_link_list)
        file(STRINGS "${_stage}/build/${_list}" _objs)
        foreach(_o IN LISTS _objs)
            string(REGEX REPLACE [[\.o$]] ".cpp" _cpp "${_o}")
            list(APPEND _gen "${_stage}/${_cpp}")
        endforeach()
    endforeach()

    # Re-run generation whenever the S_define or any processed header changes.
    file(STRINGS "${_stage}/build/ICG_processed" _hdrs)
    list(FILTER _hdrs EXCLUDE REGEX "S_source\\.hh$")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${ARG_S_DEFINE}" ${_hdrs})

    add_executable(${target} ${_gen} "${_TRICK_MODULE_DIR}/trick_runtime_env.cpp")
    target_include_directories(${target} PRIVATE "${_stage}" ${ARG_INCLUDE_DIRS})
    target_link_libraries(${target} PRIVATE ${ARG_MODELS} Trick::Trick)
    set_source_files_properties(${_gen} PROPERTIES
        COMPILE_OPTIONS "$<$<COMPILE_LANG_AND_ID:CXX,Clang,AppleClang,GNU>:-w>")

    # Let the exe run from anywhere: bake in TRICK_HOME and the trick.zip location.
    target_compile_definitions(${target} PRIVATE
        "TRICK_RT_HOME=\"${TRICK_HOME}\""
        "TRICK_RT_TRICK_ZIP=\"$<TARGET_FILE_DIR:${target}>/trick.zip\"")
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_stage}/trick.zip" "$<TARGET_FILE_DIR:${target}>/trick.zip"
        VERBATIM)
endfunction()
