#!/bin/zsh
# Stages the iOS sources (stage.py) and compiles the Android app's Swift with Skip, in the two
# phases a Skip Gradle build runs:
#   1. transpile: Skip's own pre-build, an iOS-triple build of the package, whose skipstone
#      plugin run writes the Kotlin side and the Gradle project into .build/plugins/outputs.
#      The plugin runs before anything compiles, and the staged tree is Android's, so the
#      compile that follows fails by design; the phase passes when the Kotlin is there.
#   2. bridge: the same package in bridge mode (skip's default: SKIP_BRIDGE set), in its own
#      scratch path because its plugin run writes no Kotlin and would clear phase 1's, into
#      the jni-libs folder Gradle packages
# Skip's Gradle task would run phase 2 on its generated package, which resolves an unpatched
# skipstone because the SwiftPM mirrors belong to this package; package-apk.sh disables it.
# Writes every distinct compiler error, relative to the staged module, to
# $PIRU_ANDROID/build/app.errors and prints the count. Extra arguments go to both builds.
# PIRU_CONFIG=release builds the bridge optimized (the alpha APK); the default is debug.
set -e
TOOLS="${0:A:h}"
. "$TOOLS/env.sh"
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
python3 "$TOOLS/stage.py"
cd "$PIRU_ANDROID/stage"
LOG="$PIRU_ANDROID/build/app.log"
BRIDGE="$PIRU_ANDROID/stage/.build/Android/Piru"
set +e
KOTLIN="$PIRU_ANDROID/stage/.build/plugins/outputs/stage/Piru/destination/skipstone/Piru/src/main/kotlin"
# Resolve first: after stage.py purges a moved vendored package, the build alone does not
# check it out again, and would transpile nothing new.
xcrun swift package resolve --package-path . > "$PIRU_ANDROID/build/transpile.log" 2>&1
env -u SKIP_BRIDGE xcrun swift build --triple arm64-apple-ios --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
    --package-path . --build-system native >> "$PIRU_ANDROID/build/transpile.log" 2>&1
if grep -q "because of missing inputs" "$PIRU_ANDROID/build/transpile.log"; then
    echo "transpile could not read its sources; see $PIRU_ANDROID/build/transpile.log"
    STATUS=1
elif ! grep -q "/stage/Piru/destination/skipstone/Piru.skipcode.json: note:" "$PIRU_ANDROID/build/transpile.log"; then
    # Kotlin left by an earlier run would pass the check below while the plugin never reached
    # Piru, which happens when a dependency fails to compile first (a stale module left in .build
    # can shadow an SDK module).
    echo "transpile never reached Piru, so its Kotlin is stale; see $PIRU_ANDROID/build/transpile.log"
    STATUS=1
elif [[ -n $(find "$KOTLIN" -name '*.kt' -print -quit 2>/dev/null) ]]; then
    echo "transpiled $(find "$KOTLIN" -name '*.kt' | wc -l | tr -d ' ') Kotlin files"
    STATUS=0
else
    echo "transpile wrote no Kotlin; see $PIRU_ANDROID/build/transpile.log"
    STATUS=1
fi
if [[ $STATUS == 0 ]]; then
    TARGET_OS_ANDROID=1 skip android build --arch aarch64 --plain --ndk "$ANDROID_NDK_HOME" \
        -d "$BRIDGE/jni-libs" --scratch-path "$BRIDGE/swift" --product Piru \
        --configuration "${PIRU_CONFIG:-debug}" \
        -Xcc -fPIC -Xswiftc -DTARGET_OS_ANDROID \
        -Xswiftc -continue-building-after-errors "$@" > "$LOG" 2>&1
    STATUS=$?
fi
set -e
sed -E 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -E '^/.*: error: ' | sed -E 's|.*/Sources/Piru/||' | sort -u > "$PIRU_ANDROID/build/app.errors" || true
echo "build status $STATUS, $(wc -l < "$PIRU_ANDROID/build/app.errors" | tr -d ' ') distinct errors"
exit $STATUS
