vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO blitzpp/blitz
    REF f24a250a43dff88c31ad92916da828b7ea9a98b7
    SHA512 82a175b8912bd80f9b22fae57acc116f7e0f594662ce4ca4d294e97a0174b233d9f2e71238d8771112fdd998314ef52b6f9193292bee560095c95d803b04372c
    HEAD_REF main
    PATCHES
        fix-vcpkg-integration.patch
)

vcpkg_find_acquire_program(PYTHON3)
get_filename_component(PYTHON3_DIR "${PYTHON3}" DIRECTORY)
vcpkg_add_to_path("${PYTHON3_DIR}")

set(HOST_TOOLS_OPTIONS "")
if(VCPKG_CROSSCOMPILING)
    list(APPEND HOST_TOOLS_OPTIONS
        "-DBLITZ_HOST_TOOLS_DIR=${CURRENT_HOST_INSTALLED_DIR}/tools/${PORT}"
        "-DBLITZ_HOST_EXECUTABLE_SUFFIX=${VCPKG_HOST_EXECUTABLE_SUFFIX}"
    )
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DBUILD_DOC=OFF
        -DBUILD_TESTING=OFF
        # A defined false value prevents find_library from searching for PAPI.
        -DBZ_HAVE_LIBPAPI=OFF
        ${HOST_TOOLS_OPTIONS}
)

vcpkg_cmake_install()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/blitz/blitz.h"
        "#include <blitz/bzconfig.h>"
        "#ifndef BZ_STATIC_LIB\n#define BZ_STATIC_LIB\n#endif\n#include <blitz/bzconfig.h>"
    )
endif()

if(NOT VCPKG_CROSSCOMPILING)
    vcpkg_copy_tools(
        TOOL_NAMES
            genarrbops genarruops genmatbops genmatuops genvecbops genvecuops
            genvecwhere genvecbfn genmathfunc genpromote
        AUTO_CLEAN
    )
endif()

vcpkg_copy_pdbs()

vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake)
vcpkg_fixup_pkgconfig()

vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/blitz/matbops.h" "${SOURCE_PATH}" "" IGNORE_UNCHANGED)
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/blitz/matuops.h" "${SOURCE_PATH}" "" IGNORE_UNCHANGED)
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/blitz/mathfunc.h" "${SOURCE_PATH}" "" IGNORE_UNCHANGED)
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/blitz/promote-old.h" "${SOURCE_PATH}" "" IGNORE_UNCHANGED)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
