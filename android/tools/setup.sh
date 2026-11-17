#!/bin/zsh
# One-time install of everything the Android build needs, at the paths env.sh resolves
# (under $PIRU_ANDROID unless overridden): the swift.org
# toolchain (the Android SDK must match it exactly; Xcode's Swift is not accepted), the Swift
# SDK for Android, NDK r30, SQLite, and an emulator with an Android 36 arm64 image.
set -e
. "${0:A:h}/env.sh"

# Host tools this script does not fetch. Versions are the ones the pipeline is built and
# tested with; the skip CLI must match the vendored skip/skipstone tag (1.9.13).
missing=()
[[ "$(skip version 2>/dev/null)" == *"1.9.13"* ]] || missing+=("skip 1.9.13 (brew install skiptools/skip/skip)")
command -v gradle > /dev/null || missing+=("gradle 9.x (brew install gradle)")
piru_require_java 2> /dev/null || missing+=("JDK 21 (brew install --cask temurin@21, or set JAVA_HOME)")
command -v rsvg-convert > /dev/null || missing+=("rsvg-convert (brew install librsvg)")
python3 -c "import PIL" 2> /dev/null || missing+=("Pillow (pip install pillow)")
command -v trash > /dev/null || missing+=("trash (brew install trash)")
if (( ${#missing} )); then
  printf 'missing host tools:\n'; printf '  %s\n' "${missing[@]}"; exit 1
fi
mkdir -p "$PIRU_ANDROID"/{downloads,swift-sdks} "${PIRU_SWIFT_TOOLCHAIN:h}" "$ANDROID_AVD_HOME"
cd "$PIRU_ANDROID/downloads"
fetch() { [[ -f "$2" ]] || curl -fL --progress-bar -o "$2" "$1"; }

fetch "https://download.swift.org/${SWIFT_VERSION_TAG:l}/xcode/$SWIFT_VERSION_TAG/$SWIFT_VERSION_TAG-osx.pkg" swift.pkg
fetch "https://download.swift.org/${SWIFT_VERSION_TAG:l}/android-sdk/$SWIFT_VERSION_TAG/${SWIFT_VERSION_TAG}_android.artifactbundle.tar.gz" android.artifactbundle.tar.gz
echo "21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43  android.artifactbundle.tar.gz" | shasum -a 256 -c
fetch https://dl.google.com/android/repository/android-ndk-r30-Darwin.zip ndk.zip
fetch "https://sqlite.org/2026/$SQLITE_AMALGAMATION.zip" sqlite.zip
fetch https://dl.google.com/android/repository/commandlinetools-mac-15641748_latest.zip cmdline-tools.zip

if [[ ! -d "$PIRU_SWIFT_TOOLCHAIN" ]]; then
  pkgutil --check-signature swift.pkg | grep -q 'Notarization: trusted'
  pkgutil --expand-full swift.pkg expanded
  mv expanded/*-package.pkg/Payload "$PIRU_SWIFT_TOOLCHAIN"
  trash expanded
fi
swift sdk list --swift-sdks-path "$PIRU_ANDROID/swift-sdks" | grep -q android \
  || swift sdk install android.artifactbundle.tar.gz --swift-sdks-path "$PIRU_ANDROID/swift-sdks"
if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  unzip -qo ndk.zip -d ndk-expanded
  mkdir -p "${ANDROID_NDK_HOME:h}"
  mv ndk-expanded/android-ndk-r30 "$ANDROID_NDK_HOME"
  trash ndk-expanded
fi
piru_require_ndk
sh "$PIRU_ANDROID/swift-sdks/${SWIFT_VERSION_TAG}_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh"
[[ -d "$SQLITE_AMALGAMATION" ]] || unzip -qo sqlite.zip
"${0:A:h}/build-sqlite.sh"

if [[ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]]; then
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  unzip -qo cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
fi
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
  platform-tools emulator "system-images;android-36;google_apis;arm64-v8a" > /dev/null
echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd -n piru-spike \
  -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_8 --force > /dev/null
# The default 2 GB fails the app's startup under memory pressure (ANR "failed to complete startup").
sed -i '' 's/^hw.ramSize=.*/hw.ramSize=6G/' "$ANDROID_AVD_HOME/piru-spike.avd/config.ini"
echo "ready: $PIRU_ANDROID (stage $PIRU_ANDROID_STAGE, output $PIRU_ANDROID_BUILD)"
