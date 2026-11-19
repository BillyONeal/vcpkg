vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO KhronosGroup/EGL-Registry
    REF 8e56e86e65687697ef54114cdb1afabdfac756bf
    SHA512 93dc83a7244506d7618be8863487d9aad3e225c1a7319af385f3bfd0bc842f7a487ae5f0b6911e4ff8fed2b5b450ea387a955a78bcc507a5d1861ae15b5f7f3e
    HEAD_REF main
)

file(
    COPY
       "${SOURCE_PATH}/api/KHR"
       "${SOURCE_PATH}/api/EGL"
    DESTINATION "${CURRENT_PACKAGES_DIR}/include"
)

file(
    COPY
        "${SOURCE_PATH}/api/egl.xml"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/opengl"
)

vcpkg_download_distfile(APACHE_LICENSE
    URLS "https://apache.org/licenses/LICENSE-2.0.txt"
    FILENAME 98f6b79b778f7b0a1541.txt
    SHA512 98f6b79b778f7b0a15415bd750c3a8a097d650511cb4ec8115188e115c47053fe700f578895c097051c9bc3dfb6197c2b13a15de203273e1a3218884f86e90e8
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/api/KHR/khrplatform.h" "${APACHE_LICENSE}")
