vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO talesm/SDL3pp
    REF "${VERSION}"
    SHA512 9734502388b26d377a235afb2a6ee545742b2e3f1dcb837eb38de0f2b8dc72b82b5fd69a0deca9183bfc3aab293d7540018cef4714dacc31e152cef3ebecc5e9
    HEAD_REF main
)

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        image SDL3PP_ENABLE_IMAGE
        mixer SDL3PP_ENABLE_MIXER
        ttf   SDL3PP_ENABLE_TTF
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${FEATURE_OPTIONS}
        -DSDL3PP_FORCE_BUNDLED=OFF
        -DSDL3PP_BUILD_EXAMPLES=OFF
        -DSDL3PP_BUILD_TESTING=OFF
        -DSDL3PP_GEN_DOCS=OFF
        -DSDL3PP_GEN_HEADERS=OFF
)

vcpkg_cmake_install()

# Configure installed headers as well as CMake linkage, including for direct consumers.
set(SDL3PP_FEATURE_CONFIG "")
foreach(integration IN ITEMS IMAGE MIXER NET TTF)
    if(SDL3PP_ENABLE_${integration})
        string(APPEND SDL3PP_FEATURE_CONFIG "#define SDL3PP_ENABLE_${integration}\n")
    else()
        string(APPEND SDL3PP_FEATURE_CONFIG "#define SDL3PP_DISABLE_${integration}\n")
    endif()
endforeach()
vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/SDL3pp/SDL3pp_version.h"
    "// Check if SDL_image is available"
    "${SDL3PP_FEATURE_CONFIG}\n// Check if SDL_image is available"
)

vcpkg_cmake_config_fixup(
    PACKAGE_NAME SDL3pp
    CONFIG_PATH lib/cmake/SDL3pp
)

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug"
    "${CURRENT_PACKAGES_DIR}/lib"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt")
