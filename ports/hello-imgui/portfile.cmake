vcpkg_check_linkage(ONLY_STATIC_LIBRARY) # this mirrors ImGui's portfile behavior

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO pthom/hello_imgui
    REF "v${VERSION}"
    SHA512 73f7e20a8af57ddfc3cb415d68781c847ff1b4f5bfc24b30d397e61e8b51f5dd7122178ab620c17eec39f24bb587f249903cfcdba1912fe4bb4072732b9b1bad
    HEAD_REF master
    PATCHES
        cmake-config.diff
        imgui-test-engine.diff
        disable-sdl-android.patch
        fix-vulkan-binding.patch
)
file(REMOVE_RECURSE
    "${SOURCE_PATH}/external/imgui"
    "${SOURCE_PATH}/external/nlohmann_json"
    "${SOURCE_PATH}/external/OpenGL_Loaders"
    "${SOURCE_PATH}/external/stb_hello_imgui/stb_image.h"
    "${SOURCE_PATH}/external/stb_hello_imgui/stb_image_write.h"
)

vcpkg_check_features(OUT_FEATURE_OPTIONS options
    FEATURES
        # "target platforms"
        opengl3-binding     HELLOIMGUI_HAS_OPENGL3
        metal-binding       HELLOIMGUI_HAS_METAL
        experimental-vulkan-binding HELLOIMGUI_HAS_VULKAN
        experimental-dx11-binding   HELLOIMGUI_HAS_DIRECTX11
        experimental-dx12-binding   HELLOIMGUI_HAS_DIRECTX12
        # "platform backends"
        glfw-binding        HELLOIMGUI_USE_GLFW3
        # sdl2-binding        HELLOIMGUI_USE_SDL2 # removed with imgui[sdl2-binding]
        # other
        test-engine         HELLOIMGUI_WITH_TEST_ENGINE
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${options}
        -DHELLO_IMGUI_IMGUI_SHARED=OFF
        -DHELLOIMGUI_BUILD_DEMOS=OFF
        -DHELLOIMGUI_BUILD_IMGUI=OFF
        -DHELLOIMGUI_FETCH_FORBIDDEN=ON
        -DHELLOIMGUI_FREETYPE_STATIC=OFF
        -DHELLOIMGUI_MACOS_NO_BUNDLE=OFF
        -DHELLOIMGUI_USE_IMGUI_CMAKE_PACKAGE=ON
        -DHELLOIMGUI_WIN32_NO_CONSOLE=ON
        -DHELLOIMGUI_WIN32_AUTO_WINMAIN=ON
        -DCMAKE_REQUIRE_FIND_PACKAGE_glad=ON
        -DCMAKE_REQUIRE_FIND_PACKAGE_nlohmann_json=ON
    MAYBE_UNUSED_VARIABLES
        CMAKE_REQUIRE_FIND_PACKAGE_glad
        HELLOIMGUI_WIN32_NO_CONSOLE
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(CONFIG_PATH "lib/cmake/hello_imgui" PACKAGE_NAME "hello-imgui")

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
    "${CURRENT_PACKAGES_DIR}/share/hello-imgui/hello_imgui_cmake/ios-cmake"
)

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
if (NOT HELLOIMGUI_HAS_OPENGL3
    AND NOT HELLOIMGUI_HAS_METAL
    AND NOT HELLOIMGUI_HAS_VULKAN
    AND NOT HELLOIMGUI_HAS_DIRECTX11
    AND NOT HELLOIMGUI_HAS_DIRECTX12)
    set(no_rendering_backend TRUE)
endif()
if (NOT HELLOIMGUI_USE_GLFW3
    AND NOT HELLOIMGUI_USE_SDL2)
    set(no_platform_backend TRUE)
endif()
if (no_rendering_backend OR no_platform_backend)
    file(APPEND "${CURRENT_PACKAGES_DIR}/share/${PORT}/usage" "
    ########################################################################
       !!!!                    WARNING                              !!!!!
       !!!!   Installed hello-imgui without a viable backend        !!!!!
    ########################################################################

    When installing hello-imgui, you should specify:

     - At least one (or more) rendering backend (OpenGL3, Metal, Vulkan, DirectX11, DirectX12)
       Make your choice according to your needs and your target platforms, between:
          opengl3-binding              # This is the recommended choice, especially for beginners
          metal-binding                # Apple only, advanced users only
          experimental-vulkan-binding  # Advanced users only
          experimental-dx11-binding    # Windows only, still experimental
          experimental-dx12-binding    # Windows only, advanced users only, still experimental

     - At least one (or more) platform backend (Glfw3*):
       Make your choice according to your needs and your target platforms, between:
          glfw-binding
       *) This port currently doesn't offer an SDL platform backend.

    For example, you could use:
        vcpkg install \"hello-imgui[opengl3-binding,glfw-binding]\"

    ########################################################################
       !!!!                    WARNING                              !!!!!
       !!!!   Installed hello-imgui without a viable backend        !!!!!
    ########################################################################
    ")
endif()

vcpkg_install_copyright(
    FILE_LIST
        "${SOURCE_PATH}/LICENSE"
        "${SOURCE_PATH}/src/hello_imgui/internal/whereami/LICENSE.MIT"
        "${SOURCE_PATH}/src/hello_imgui/internal/pnm.h"
        "${SOURCE_PATH}/src/hello_imgui/internal/imguial_term.h"
        "${SOURCE_PATH}/src/hello_imgui/internal/inicpp.h"
    COMMENT [[The Hello ImGui source archive does not include the full license texts for its bundled fonts:
DroidSans.ttf: Digitized data copyright (c) 2007, Google Corporation. Licensed under Apache-2.0.
https://github.com/google/fonts/blob/5fb32282c5969930c4268483ffa5664680bf73c8/apache/droidsans/LICENSE.txt
Font_Awesome_6_Free-Solid-900.otf (Font Awesome 6.5.1): Licensed under OFL-1.1.
https://github.com/FortAwesome/Font-Awesome/blob/deeea78c52bfe00b6e251ffddccf5570d5fdb05e/LICENSE.txt
fontawesome-webfont.ttf (Font Awesome 4.7.0): Copyright Dave Gandy 2016. All rights reserved.
Font Awesome 4.7.0 is licensed under OFL-1.1, as stated at:
https://github.com/FortAwesome/Font-Awesome/blob/a8386aae19e200ddb0f6845b5feeee5eb7013687/README.md#license
Only font files are installed from Font Awesome; the CC-BY-4.0 SVG/JS icons are not included.

The bundled inifile-cpp header identifies Fabian Meyer as its author and declares the MIT license,
but the Hello ImGui source archive does not include its full license text:
https://github.com/Rookfighter/inifile-cpp/blob/7bb1ec3534768e0d1fd9893d01027468b72af5ec/LICENSE.txt]]
)
