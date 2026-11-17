"""Where the Android build keeps its toolchains, stage and output: env.sh's defaults, for the
Python tools that run without it. Keep the two in step."""

import os
import shutil
from pathlib import Path


def _env_path(name: str, default: Path) -> Path:
    value = os.environ.get(name)
    return Path(value) if value else default


_CACHE_HOME = _env_path("XDG_CACHE_HOME", Path.home() / ".cache")
PIRU_ANDROID = _env_path("PIRU_ANDROID", _CACHE_HOME / "piru-android")
STAGE = _env_path("PIRU_ANDROID_STAGE", PIRU_ANDROID / "stage")
BUILD = _env_path("PIRU_ANDROID_BUILD", PIRU_ANDROID / "build")
ANDROID_HOME = _env_path("ANDROID_HOME", PIRU_ANDROID / "android-sdk")


def adb() -> str:
    """The SDK's adb, else the first on PATH."""
    bundled = ANDROID_HOME / "platform-tools" / "adb"
    if bundled.exists():
        return str(bundled)
    found = shutil.which("adb")
    if found is None:
        raise SystemExit(
            f"no adb under {ANDROID_HOME} or on PATH: run android/tools/setup.sh, or set ANDROID_HOME"
        )
    return found
