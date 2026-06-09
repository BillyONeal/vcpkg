# A do-nothing port: it installs no files and only exists to demonstrate the
# check-for-common-mistakes workflow.
# This edit changes the port without bumping the version, exercising the
# PR-against-PR case where the in-progress version's git-tree is overwritten.
set(VCPKG_POLICY_EMPTY_PACKAGE enabled)
