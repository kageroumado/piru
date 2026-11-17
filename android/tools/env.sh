# Sourced by every android/tools script (zsh or bash). Every path comes from the environment
# or from a default derived from it; set a variable before sourcing to move that piece.
#
#   PIRU_ANDROID          root for what setup.sh installs and the build caches
#                         default ${XDG_CACHE_HOME:-~/.cache}/piru-android
#   PIRU_ANDROID_STAGE    the staged Skip package the APK is built from     $PIRU_ANDROID/stage
#   PIRU_ANDROID_BUILD    logs, compiler errors, screenshots, PiruCore scratch  $PIRU_ANDROID/build
#   PIRU_SWIFT_TOOLCHAIN  the swift.org toolchain     $PIRU_ANDROID/toolchains/<tag>.xctoolchain
#   ANDROID_HOME          Android SDK                 $PIRU_ANDROID/android-sdk
#   ANDROID_NDK_HOME      Android NDK r30             $PIRU_ANDROID/android-ndk-r30
#   ANDROID_AVD_HOME      emulator images             $PIRU_ANDROID/avd
#   GRADLE_USER_HOME      Gradle caches               $PIRU_ANDROID/gradle-home
#   JAVA_HOME             JDK 21; when unset or another version, `/usr/libexec/java_home -v 21`
#
# The same defaults for the Python tools are in android_paths.py; keep the two in step.
export PIRU_ANDROID="${PIRU_ANDROID:-${XDG_CACHE_HOME:-$HOME/.cache}/piru-android}"
export PIRU_ANDROID_STAGE="${PIRU_ANDROID_STAGE:-$PIRU_ANDROID/stage}"
export PIRU_ANDROID_BUILD="${PIRU_ANDROID_BUILD:-$PIRU_ANDROID/build}"
# Where skipstone writes the Kotlin: SwiftPM names a root package's plugin output folder after
# its directory, lowercased.
PIRU_STAGE_OUTPUTS="$PIRU_ANDROID_STAGE/.build/plugins/outputs/$(basename "$PIRU_ANDROID_STAGE" | tr '[:upper:]' '[:lower:]')"
export PIRU_STAGE_OUTPUTS
export SWIFT_VERSION_TAG="swift-6.4.0-RELEASE"
export SQLITE_AMALGAMATION="sqlite-amalgamation-3530400"
export PIRU_SWIFT_TOOLCHAIN="${PIRU_SWIFT_TOOLCHAIN:-$PIRU_ANDROID/toolchains/$SWIFT_VERSION_TAG.xctoolchain}"
# Empty, so xcrun and swift resolve to the toolchain on PATH, never a selected Xcode one.
export TOOLCHAINS=
export PATH="$PIRU_SWIFT_TOOLCHAIN/usr/bin:$PATH"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$PIRU_ANDROID/android-ndk-r30}"
export ANDROID_HOME="${ANDROID_HOME:-$PIRU_ANDROID/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$PIRU_ANDROID/avd}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PIRU_ANDROID/gradle-home}"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

piru_error() { printf 'android/tools: %s\n' "$*" >&2; }

# Exports JAVA_HOME as a JDK 21: the one JAVA_HOME names when it is 21, else macOS's pick.
piru_require_java() {
  local found=""
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]] \
    && "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "21'; then
    found="$JAVA_HOME"
  elif [[ -x /usr/libexec/java_home ]]; then
    found=$(/usr/libexec/java_home -v 21 2> /dev/null) || found=""
  fi
  if [[ -z "$found" ]]; then
    piru_error "no JDK 21: set JAVA_HOME to one (brew install --cask temurin@21)"
    return 1
  fi
  export JAVA_HOME="$found"
}

# Fails unless ANDROID_NDK_HOME holds NDK r30, the release the Swift SDK for Android is built
# against.
piru_require_ndk() {
  local props="$ANDROID_NDK_HOME/source.properties"
  if [[ ! -f "$props" ]]; then
    piru_error "no Android NDK at $ANDROID_NDK_HOME: run android/tools/setup.sh, or set ANDROID_NDK_HOME to NDK r30"
    return 1
  fi
  if ! grep -Eq '^Pkg\.Revision *= *30\.' "$props"; then
    piru_error "$ANDROID_NDK_HOME is NDK $(sed -n 's/^Pkg\.Revision *= *//p' "$props"); the build needs r30"
    return 1
  fi
}

# Fails unless ANDROID_HOME holds an Android SDK with build-tools (zipalign, apksigner, aapt2).
piru_require_sdk() {
  if [[ -z "$(ls "$ANDROID_HOME/build-tools" 2> /dev/null)" ]]; then
    piru_error "no Android SDK build-tools under $ANDROID_HOME: run android/tools/setup.sh, or set ANDROID_HOME"
    return 1
  fi
}

# piru_require_command <command> <how to install it>
piru_require_command() {
  command -v "$1" > /dev/null 2>&1 && return 0
  piru_error "$1 is not on PATH ($2)"
  return 1
}

# An emulator on another Mac: PIRU_ADB_SSH=user@host routes adb through that host's adb
# server over an SSH tunnel, so every tool here drives its emulator.
if [[ -n "${PIRU_ADB_SSH:-}" ]]; then
  export ADB_SERVER_SOCKET=tcp:localhost:5038
  pgrep -f "5038:localhost:5037" > /dev/null \
    || ssh -f -N -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -L 5038:localhost:5037 "$PIRU_ADB_SSH"
fi
