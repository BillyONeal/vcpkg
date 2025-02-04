# Automatically generated by scripts/boost/generate-ports.ps1

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO boostorg/foreach
    REF boost-${VERSION}
    SHA512 9ec2431151570a7cc0efa8e9651a6ea5484e8e483a50067faa221e26c2bfbaf26e7ff97de7bb8fa82cbffaead5710f9df28ef1781aff83320e747110d678c531
    HEAD_REF master
)

set(FEATURE_OPTIONS "")
boost_configure_and_install(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS ${FEATURE_OPTIONS}
)
