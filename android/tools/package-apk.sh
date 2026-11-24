#!/bin/zsh
# Packages the Android Swift that build-app.sh compiled into an APK (PIRU_CONFIG=release for
# the release APK, debug otherwise), and installs it on the running emulator when one is
# attached. Prints the APK path. PIRU_UNSIGNED=1 leaves a release APK unsigned, for a build
# host without the release key; sign it with sign-apk.sh where the key is.
set -e
TOOLS="${0:A:h}"
. "$TOOLS/env.sh"
piru_require_java || exit 1
piru_require_command gradle "brew install gradle" || exit 1
mkdir -p "$PIRU_ANDROID_BUILD"
CONFIG="${PIRU_CONFIG:-debug}"
# A measuring build (PIRU_PROFILE, app/build.gradle.kts) is never signed with the release key.
if [[ -n "${PIRU_PROFILE:-}" && $CONFIG == release && -z "${PIRU_UNSIGNED:-}" ]]; then
    piru_error "PIRU_PROFILE builds are for measuring: set PIRU_UNSIGNED=1 and sign with a debug key"
    exit 1
fi
# The app depends on the included skipstone build's Piru project, which packages
# <its build dir>/jni-libs; build-app.sh compiled into the root build's copy. A release
# packages a stripped copy: the symbols triple the APK and help no one on a device.
INCLUDED="$PIRU_STAGE_OUTPUTS/Piru/destination/skipstone/Piru/build"
JNI="$PIRU_ANDROID_STAGE/.build/Android/Piru/jni-libs"
mkdir -p "$INCLUDED"
if [[ $CONFIG == release ]]; then
    piru_require_ndk || exit 1
    STRIPPED="$PIRU_ANDROID_STAGE/.build/Android/Piru/jni-libs-stripped"
    STRIP=$(print -r -- "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip(N[1]))
    [[ -x "$STRIP" ]] || { echo "error: no llvm-strip in $ANDROID_NDK_HOME" >&2; exit 1; }
    rsync -a --delete "$JNI/" "$STRIPPED/"
    find "$STRIPPED" -name '*.so' -exec "$STRIP" --strip-unneeded {} +
    ln -sfn "$STRIPPED" "$INCLUDED/jni-libs"
else
    ln -sfn "$JNI" "$INCLUDED/jni-libs"
fi
cd "$PIRU_ANDROID_STAGE/Android"
LOG="$PIRU_ANDROID_BUILD/gradle.log"
SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 SKIP_BRIDGE_ROBOLECTRIC_BUILD_DISABLED=1 \
    gradle "assemble${(C)${PIRU_CONFIG:-debug}}" --console=plain > "$LOG" 2>&1 || { grep -E '^e: |What went wrong' -A4 "$LOG" | head -40; exit 1; }
OUT="$PIRU_ANDROID_STAGE/.build/Android/app/outputs/apk/$CONFIG"
# The APK ships arm64-v8a alone, with libPiru.so in it: an ABI directory without libPiru.so
# would let a device of that ABI install an app that cannot load.
BUILT="$OUT/app-$CONFIG.apk"
[[ $CONFIG == release ]] && BUILT="$OUT/app-release-unsigned.apk"
LIBS=$(unzip -Z1 "$BUILT" 'lib/*' 2>/dev/null || true)
OTHER=$(print -r -- "$LIBS" | sed -n 's|^lib/\([^/]*\)/.*|\1|p' | sort -u | grep -vx 'arm64-v8a' || true)
if [[ -n "$OTHER" ]]; then
    echo "error: $BUILT holds native libraries for ABIs other than arm64-v8a: ${OTHER//$'\n'/ }" >&2
    exit 1
fi
if ! print -r -- "$LIBS" | grep -qx 'lib/arm64-v8a/libPiru.so'; then
    echo "error: $BUILT lacks lib/arm64-v8a/libPiru.so" >&2
    exit 1
fi
if [[ $CONFIG == release && -n "${PIRU_UNSIGNED:-}" ]]; then
    echo "$OUT/app-release-unsigned.apk"
    exit 0
elif [[ $CONFIG == release ]]; then
    APK="$OUT/app-release.apk"
    "$TOOLS/sign-apk.sh" "$OUT/app-release-unsigned.apk" "$APK"
else
    APK="$OUT/app-$CONFIG.apk"
fi
echo "$APK"
if adb get-state > /dev/null 2>&1; then
    adb install -r "$APK" > /dev/null && echo "installed on $(adb get-serialno)"
fi
