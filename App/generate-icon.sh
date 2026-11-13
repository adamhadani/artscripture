#!/bin/sh
# Regenerates App/Artscripture.icns, the iOS icon and the launch screen's mark from
# App/GenerateIcon.swift when any is missing or out of date. The outputs are
# gitignored — the Swift file is the source.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
icns="$here/Artscripture.icns"
source_file="$here/GenerateIcon.swift"

# Both outputs must be present and fresh. Checking only the .icns was enough
# while it was the only one; with the iOS PNG added, a stale-but-newer .icns
# would have skipped the regeneration that creates the PNG, and the iPad target
# would build with no icon and no error.
ios_icon="$here/iOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
# The launch screen's mark, for the same reason: a missing one is not a build
# error. The storyboard names an image the catalog does not have, and the app
# launches to a bare field.
launch_mark="$here/iOS/Assets.xcassets/LaunchMark.imageset"

fresh=yes
for output in "$icns" "$ios_icon" "$launch_mark/LaunchMark@2x.png" "$launch_mark/LaunchMark@3x.png"; do
    if [ ! -f "$output" ] || [ ! "$output" -nt "$source_file" ]; then
        fresh=no
    fi
done
if [ "$fresh" = yes ]; then
    exit 0
fi

# **Run against the macOS SDK, whatever build invoked this.**
#
# This is a macOS command-line script that draws with CoreGraphics, but it is now
# a pre-build step of the *iOS* target as well — and Xcode exports SDKROOT,
# PLATFORM_NAME and friends into script phases. Inheriting those makes `swift`
# try to compile a macOS script for iOS and fail with
#
#     error: unable to load standard library for target 'arm64-apple-macosx26.0'
#
# which names macOS and so reads like the opposite problem.
#
# It passed locally and failed in CI for a reason worth remembering: the outputs
# are gitignored, so a working copy that already has them short-circuits above
# and never runs this line. Only a clean checkout does. Deleting both outputs
# before testing is what reproduces it.
exec env -u SDKROOT -u PLATFORM_NAME -u SUPPORTED_PLATFORMS -u TOOLCHAINS \
    xcrun --sdk macosx swift "$source_file" "$here"
