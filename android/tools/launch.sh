#!/bin/zsh
# Restarts Piru on the attached emulator, waits, and saves a screenshot to
# $PIRU_ANDROID_BUILD/<name>.png (default "launch"). Prints the app's Swift and Java
# fatal lines, and the full logcat lands in $PIRU_ANDROID_BUILD/logcat.txt.
TOOLS="${0:A:h}"
. "$TOOLS/env.sh"
NAME="${1:-launch}"
WAIT="${2:-12}"
mkdir -p "$PIRU_ANDROID_BUILD"
adb shell am force-stop glass.kagerou.piru
adb logcat -c
adb shell am start -n glass.kagerou.piru/piru.module.MainActivity > /dev/null
sleep "$WAIT"
adb exec-out screencap -p > "$PIRU_ANDROID_BUILD/$NAME.png"
adb logcat -d > "$PIRU_ANDROID_BUILD/logcat.txt"
echo "pid: $(adb shell pidof glass.kagerou.piru)  screenshot: $PIRU_ANDROID_BUILD/$NAME.png"
grep -E "SwiftRuntime|Abort message|FATAL EXCEPTION|Caused by|AndroidRuntime: [a-z].*Exception" "$PIRU_ANDROID_BUILD/logcat.txt" | cut -c1-300 | head -20
