vcpkg_download_distfile(IPC_UTF8_PATCH
    URLS https://github.com/zeromq/libzmq/commit/86a42e1e4379120db7d6dcddaead86b82505b0dd.patch?full_index=1
    FILENAME zeromq-86a42e1e4379120db7d6dcddaead86b82505b0dd.patch
    SHA512 a5c6e7d57e2a419bbb0afc8757a5ed73944b15af7730d64b06b7a1b00c788bbce9f009eaf1b569c01ea25b6e478167568ded4f9cc56cd05677831d212e2d17a5
)
vcpkg_download_distfile(IPC_WILDCARD_PATCH
    URLS https://github.com/zeromq/libzmq/commit/0ed7a08cd946e0832ac4655b7a76c09ac221f63b.patch?full_index=1
    FILENAME zeromq-0ed7a08cd946e0832ac4655b7a76c09ac221f63b.patch
    SHA512 02ffbccb1a856aea23a44dfa44c2cd73bf0c1288c509430a9c107bdbe4c380fc4b72d417a6b7c832028a22ea51e0025cb20227d67f7d7f3f6a9fd3d6a02158c6
)
vcpkg_download_distfile(IPC_FALLBACK_PATCH
    URLS https://github.com/zeromq/libzmq/commit/1f4dd54f94009cb57bb68bfc856edc1c0bd3df06.patch?full_index=1
    FILENAME zeromq-1f4dd54f94009cb57bb68bfc856edc1c0bd3df06.patch
    SHA512 9e9d75c2d576ea0ba91e00a134c4ddde3335783b4e964488f2cc96e294169581018c8fa0dc51a1a33dfc1022316a6778227a04d471fa84e4ca9a7473cb1c6d6f
)
vcpkg_download_distfile(IPC_COMPILE_PATCH
    URLS https://github.com/zeromq/libzmq/commit/a23330dbe249f7ebd81bb5be47c892e8fa9cc4f8.patch?full_index=1
    FILENAME zeromq-a23330dbe249f7ebd81bb5be47c892e8fa9cc4f8.patch
    SHA512 ec65d1fe3bc861437469b6b640d071e9facaf9b53c216406ac883245f250d54c177d85c86423254d16b72311e405696e0f1fa967568cf1a22beb678df7dcfe3c
)
vcpkg_download_distfile(IPC_INCLUDES_PATCH
    URLS https://github.com/zeromq/libzmq/commit/aa885c5a154256612108636b0fb22f44ae0e247a.patch?full_index=1
    FILENAME zeromq-aa885c5a154256612108636b0fb22f44ae0e247a.patch
    SHA512 d188c6766c826514a2db03f593e196b15d5d8ea85df559b37a74a099238d6bd5b8c126c406da8542dcdef14fe8f3cd183d5790885bec5205c8bdf41335bd868e
)
# Unmerged upstream hardening: https://github.com/zeromq/libzmq/pull/4950
vcpkg_download_distfile(IPC_HARDENING_PATCH
    URLS https://github.com/zeromq/libzmq/commit/1e6075fe8728e222c73b9c303275f51aa7485686.patch?full_index=1
    FILENAME zeromq-1e6075fe8728e222c73b9c303275f51aa7485686.patch
    SHA512 487234ce30d92e8490c8ec5f84e7ed4701c7b267af27ace92e027c764938e92f3f6f3d7bebc25c271ea967d32919509256185183ddf442e83a8ab56ce0bcf68b
)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO zeromq/libzmq
    REF "v${VERSION}"
    SHA512 108d9c5fa761c111585c30f9c651ed92942dda0ac661155bca52cc7b6dbeb3d27b0dd994abde206eacfc3bc88d19ed24e45b291050c38469e34dca5f8c9a037d
    PATCHES
        fix-arm.patch
        pkgconfig.diff
        rename-sha1.diff
        "${IPC_UTF8_PATCH}"
        "${IPC_WILDCARD_PATCH}"
        "${IPC_FALLBACK_PATCH}"
        "${IPC_COMPILE_PATCH}"
        "${IPC_INCLUDES_PATCH}"
        "${IPC_HARDENING_PATCH}"
)

string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "static" BUILD_STATIC)
string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" BUILD_SHARED)

vcpkg_check_features(
    OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        sodium            WITH_LIBSODIUM
        draft             ENABLE_DRAFTS
        websockets        ENABLE_WS
        websockets-secure WITH_TLS
        curve             ENABLE_CURVE
)

set(PLATFORM_OPTIONS "")
if(VCPKG_TARGET_IS_MINGW)
    list(APPEND PLATFORM_OPTIONS "-DCMAKE_SYSTEM_VERSION=6.0" "-DZMQ_HAVE_IPC=0")
endif()

vcpkg_find_acquire_program(PKGCONFIG)
set(ENV{PKG_CONFIG} "${PKGCONFIG}")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DBUILD_STATIC=${BUILD_STATIC}
        -DBUILD_SHARED=${BUILD_SHARED}
        -DCMAKE_POLICY_DEFAULT_CMP0057=NEW  # IN_LIST
        -DCMAKE_REQUIRE_FIND_PACKAGE_GnuTLS=ON
        -DWITH_DOCS=OFF
        -DWITH_PERF_TOOL=OFF
        -DWITH_LIBBSD=OFF
        -DWITH_LIBSODIUM_STATIC=${BUILD_STATIC}
        -DWITH_NSS=OFF
        -DZEROMQ_CMAKECONFIG_INSTALL_DIR=share/${PORT}
        -DZMQ_BUILD_TESTS=OFF
        ${FEATURE_OPTIONS}
        ${PLATFORM_OPTIONS}
    OPTIONS_DEBUG
        "-DCMAKE_PDB_OUTPUT_DIRECTORY=${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg"
    MAYBE_UNUSED_VARIABLES
        CMAKE_REQUIRE_FIND_PACKAGE_GnuTLS
        WITH_LIBBSD
        WITH_PERF_TOOL
        WITH_TLS
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup()
vcpkg_fixup_pkgconfig()

if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    file(GLOB libzmq_release "${CURRENT_PACKAGES_DIR}/lib/libzmq*.lib")
    cmake_path(GET libzmq_release STEM LAST_ONLY libzmq_spec)
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/lib/pkgconfig/libzmq.pc" " -lzmq" " -l${libzmq_spec}")
    if(NOT VCPKG_BUILD_TYPE)
        file(GLOB libzmq_debug "${CURRENT_PACKAGES_DIR}/debug/lib/libzmq*.lib")
        cmake_path(GET libzmq_debug STEM LAST_ONLY libzmq_spec)
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/libzmq.pc" " -lzmq" " -l${libzmq_spec}")
    endif()
endif()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zmq.h" "defined ZMQ_STATIC" "(1)")
      file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin" "${CURRENT_PACKAGES_DIR}/bin") # empty
endif()

file(COPY
    "${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}"
)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include" "${CURRENT_PACKAGES_DIR}/debug/share" "${CURRENT_PACKAGES_DIR}/share/zmq")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
