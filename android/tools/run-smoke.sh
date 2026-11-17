#!/bin/zsh
# Builds piru-smoke for Android, boots the emulator if none is attached, and runs it against
# the real substance catalog and string catalog. Exits with the smoke test's status.
set -e
TOOLS="${0:A:h}"
. "$TOOLS/env.sh"
REPO="${TOOLS:h:h}"
PKG="$REPO/android/PiruCore"
DEVICE_DIR=/data/local/tmp/piru
BUILD="$PIRU_ANDROID_BUILD/PiruCore-android"
piru_require_ndk || exit 1
mkdir -p "$PIRU_ANDROID_BUILD"

(cd "$PKG" && "$TOOLS/swift-android-build" --scratch-path "$BUILD" --product piru-smoke)

if ! adb get-state > /dev/null 2>&1; then
  emulator -avd piru-spike -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect \
    > "$PIRU_ANDROID_BUILD/emulator.log" 2>&1 &
  adb wait-for-device
  until [[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; do sleep 2; done
fi

LIBCXX=$(find "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android -name libc++_shared.so | head -1)
adb shell "mkdir -p $DEVICE_DIR/work"
adb push -q "$BUILD/out/Products/Debug-android-aarch64/piru-smoke" "$LIBCXX" \
  "$REPO/Piru/Data/piru-substances.sqlite" "$REPO/Piru/Localizable.xcstrings" \
  "$PKG/Sources/piru-smoke/Info.plist" "$DEVICE_DIR/"
adb shell "cd $DEVICE_DIR && LD_LIBRARY_PATH=. ./piru-smoke piru-substances.sqlite Localizable.xcstrings work"
