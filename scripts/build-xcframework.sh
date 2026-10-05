#!/usr/bin/env bash
# Builds .build/PurseSecureFields.xcframework, unsigned, and checks it can be consumed. Shared by
# release.yml (which then signs and zips it) and CI's "Release build (macos-15)" job, so CI builds
# exactly what a release ships, with the toolchain the release uses.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf .build/ios.xcarchive .build/ios-sim.xcarchive .build/PurseSecureFields.xcframework

# Device archive — built UNSIGNED. A library XCFramework does not need a
# signed slice; the whole .xcframework bundle is signed after creation
# (release.yml). Forcing a manual identity here also fails the SPM-generated
# resource-bundle target (PurseSecureFields_PurseSecureFields), which has
# no development team.
xcodebuild archive \
  -scheme PurseSecureFields \
  -destination "generic/platform=iOS" \
  -archivePath .build/ios.xcarchive \
  -derivedDataPath .build/dd-ios \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  CODE_SIGNING_ALLOWED=NO \
  INSTALL_PATH='/Library/Frameworks'

# Simulator archive — also unsigned (Apple issues no simulator distribution certs).
xcodebuild archive \
  -scheme PurseSecureFields \
  -destination "generic/platform=iOS Simulator" \
  -archivePath .build/ios-sim.xcarchive \
  -derivedDataPath .build/dd-ios-sim \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  CODE_SIGNING_ALLOWED=NO \
  INSTALL_PATH='/Library/Frameworks'

# Archiving an SPM scheme (no .xcodeproj) leaves the framework wrapper with only
# the binary + Info.plist: the .swiftmodule stays behind in the archive
# intermediates, and the SPM resource bundle lands NEXT TO the framework in
# Products/Library/Frameworks, so -create-xcframework drops both. Without
# Modules/, `import PurseSecureFields` fails for every consumer of the
# published binary. Repackage them into each framework before assembly.
repackage() { # <archive> <derived-data> <platform-dir: Release-iphoneos|Release-iphonesimulator>
  local fw="$1/Products/Library/Frameworks/PurseSecureFields.framework"
  mkdir -p "$fw/Modules"
  cp -R "$2/Build/Intermediates.noindex/ArchiveIntermediates/PurseSecureFields/BuildProductsPath/$3/PurseSecureFields.swiftmodule" "$fw/Modules/"
  cp -R "$1/Products/Library/Frameworks/PurseSecureFields_PurseSecureFields.bundle" "$fw/"
  # Apple looks for the privacy manifest at the framework root. SPM processes it
  # into the resource bundle instead, so lift a copy out. This must happen before
  # the xcframework is assembled and signed, or the signature won't cover it.
  cp "$fw/PurseSecureFields_PurseSecureFields.bundle/PrivacyInfo.xcprivacy" "$fw/PrivacyInfo.xcprivacy"
}
repackage .build/ios.xcarchive     .build/dd-ios     Release-iphoneos
repackage .build/ios-sim.xcarchive .build/dd-ios-sim Release-iphonesimulator

# Create the (unsigned) XCFramework. Note: `xcodebuild -create-xcframework`
# has no -codesign flag — release.yml signs the bundle separately.
xcodebuild -create-xcframework \
  -framework .build/ios.xcarchive/Products/Library/Frameworks/PurseSecureFields.framework \
  -framework .build/ios-sim.xcarchive/Products/Library/Frameworks/PurseSecureFields.framework \
  -output .build/PurseSecureFields.xcframework

# Non-regression gate: v1.1.6–v1.5.0 shipped without Modules/ (so `import
# PurseSecureFields` failed for every consumer) and without the resource bundle.
# Fail before anything is signed or published if either regresses.
XCFW=.build/PurseSecureFields.xcframework
for slice in "$XCFW"/ios-*; do
  fw="$slice/PurseSecureFields.framework"
  ls "$fw/Modules/PurseSecureFields.swiftmodule/"*.swiftinterface > /dev/null \
    || { echo "::error::$slice is missing Modules/PurseSecureFields.swiftmodule/*.swiftinterface — consumers cannot import the SDK."; exit 1; }
  test -d "$fw/PurseSecureFields_PurseSecureFields.bundle" \
    || { echo "::error::$slice is missing PurseSecureFields_PurseSecureFields.bundle — badge assets would be absent at runtime."; exit 1; }
done

# Smoke test: actually compile an `import PurseSecureFields` against the
# simulator slice, exactly as a consumer's build would.
smoke=$(mktemp -t smoke).swift
echo 'import PurseSecureFields' > "$smoke"
xcrun -sdk iphonesimulator swiftc \
  -target arm64-apple-ios15.0-simulator \
  -F "$XCFW/ios-arm64_x86_64-simulator" \
  -emit-object -o /dev/null "$smoke" \
  || { echo "::error::'import PurseSecureFields' does not compile against the built XCFramework."; exit 1; }
echo "XCFramework verified: Modules/ + resource bundle present, import compiles."
