set(SRPC_LIBRARIES srpc::srpc)
if(TARGET srpc::srpc)
    return()
endif()

include(CMakeFindDependencyMacro)
find_dependency(OpenSSL)
find_dependency(Protobuf CONFIG)
find_dependency(Snappy CONFIG)
find_dependency(lz4 CONFIG)
find_dependency(ZLIB)
find_dependency(Threads)

find_library(SRPC_LIBRARY_RELEASE NAMES srpc
    PATHS "${CMAKE_CURRENT_LIST_DIR}/../../lib" NO_DEFAULT_PATH REQUIRED)
find_library(SRPC_LIBRARY_DEBUG NAMES srpc
    PATHS "${CMAKE_CURRENT_LIST_DIR}/../../debug/lib" NO_DEFAULT_PATH)
find_library(SRPC_WORKFLOW_LIBRARY_RELEASE NAMES workflow
    PATHS "${CMAKE_CURRENT_LIST_DIR}/../../lib" NO_DEFAULT_PATH REQUIRED)
find_library(SRPC_WORKFLOW_LIBRARY_DEBUG NAMES workflow
    PATHS "${CMAKE_CURRENT_LIST_DIR}/../../debug/lib" NO_DEFAULT_PATH)

include(SelectLibraryConfigurations)
select_library_configurations(SRPC_WORKFLOW)

add_library(srpc::srpc UNKNOWN IMPORTED)
set_target_properties(srpc::srpc PROPERTIES
    IMPORTED_CONFIGURATIONS RELEASE
    IMPORTED_LOCATION_RELEASE "${SRPC_LIBRARY_RELEASE}"
    INTERFACE_INCLUDE_DIRECTORIES "${SRPC_INCLUDE_DIR}"
)
if(SRPC_LIBRARY_DEBUG)
    set_property(TARGET srpc::srpc APPEND PROPERTY IMPORTED_CONFIGURATIONS DEBUG)
    set_target_properties(srpc::srpc PROPERTIES
        IMPORTED_LOCATION_DEBUG "${SRPC_LIBRARY_DEBUG}"
    )
endif()
target_link_libraries(srpc::srpc INTERFACE
    ${SRPC_WORKFLOW_LIBRARIES}
    protobuf::libprotobuf
    Snappy::snappy
    lz4::lz4
    OpenSSL::SSL
    OpenSSL::Crypto
    ZLIB::ZLIB
    Threads::Threads
)
if(WIN32)
    target_link_libraries(srpc::srpc INTERFACE ws2_32 crypt32 advapi32 user32)
endif()
