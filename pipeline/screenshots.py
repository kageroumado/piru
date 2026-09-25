#!/usr/bin/env python3
"""Capture every app screen on the simulator, in every language and every skin.

The app does the walking (``ScreenshotTour``, DEBUG builds, enabled by
``-piruScreenshots <dir>``): it seeds a persona, lands on each screen through
``AppNavigator``, and asks for a capture by writing ``<dir>/.tour/request.json``.
This script answers each request with ``simctl io screenshot`` — the status bar
reads 9:41 and every pixel is the real one — and acks with ``<dir>/.tour/ack``.
One launch is one language, so the run is a launch per locale (and per
appearance when both are asked for).

By default the pass runs on its own simulator, "Piru Screenshots" (an iPhone
18 Pro Max created on first use), so the persona reseed never touches the
journal on the simulator you develop on. Pass ``--udid booted`` to use that one
anyway.

Output, under ``Store/shots/`` (gitignored with the rest of ``Store/``)::

    en/01-journal.png                      the piru skin
    en/skins/tsuki/01-journal-tsuki.png    every other skin the picker offers
    zh-Hans/…                              the same in Simplified Chinese
    en-dark/…                              with --appearance dark|both
    index.json                             every file with its locale, skin, screen

Usage::

    pipeline/screenshots.py                          # build, then everything
    pipeline/screenshots.py --no-build --skins none  # just the piru skin, quick
    pipeline/screenshots.py --screens journal,quicklog --skins tsuki,yuki
    pipeline/screenshots.py --locales en --appearance both
    pipeline/screenshots.py --list                   # the screen and skin names
    pipeline/screenshots.py --wallpapers --appearance both
                                                     # every skin's backdrop alone

``--wallpapers`` shows the skin backdrop and nothing else (no chrome, no
status bar) and captures one frame per skin, ``<skin>.png`` under
``Store/wallpapers/`` — the scenes as phone wallpapers. Language is
irrelevant there, so it runs one locale.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BUNDLE_ID = "dev.yumeji.piru"
SCHEME = "Piru"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max"
DEVICE_NAME = "Piru Screenshots"
LOCALES = {"en": "en_US", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW"}
TOUR_SOURCE = REPO / "Piru/Utilities/ScreenshotTour.swift"
SKIN_SOURCE = REPO / "Shared/Skin/Skin.swift"


def run(*args: str, check: bool = True, capture: bool = True) -> str:
    result = subprocess.run(args, check=False, text=True, capture_output=capture, encoding="utf-8")
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip() if capture else ""
        sys.exit(f"✗ {' '.join(args[:4])}… failed ({result.returncode})\n{detail}")
    return (result.stdout or "") if capture else ""


def simctl(*args: str, check: bool = True) -> str:
    return run("xcrun", "simctl", *args, check=check)


# MARK: - Catalog (parsed from the Swift, so --list never drifts)


def catalog_screens() -> list[str]:
    return re.findall(r'Screen\(name: "([^"]+)"\)', TOUR_SOURCE.read_text())


def catalog_skins() -> list[str]:
    source = SKIN_SOURCE.read_text()
    body = source[source.index("enum Skin:") : source.index("var id: String")]
    cases = re.findall(r"^\s*case (\w+)$", body, re.MULTILINE)
    shelved = set(
        re.findall(r"\.(\w+)", re.search(r"shelved: Set<Skin> = \[([^\]]*)\]", source)[1])
    )
    return [case for case in cases if case not in shelved and case != "piru"]


# MARK: - Simulator


def booted_devices() -> list[dict]:
    listing = json.loads(simctl("list", "devices", "booted", "-j"))
    return [device for devices in listing["devices"].values() for device in devices]


def all_devices() -> list[dict]:
    listing = json.loads(simctl("list", "devices", "available", "-j"))
    return [device for devices in listing["devices"].values() for device in devices]


def newest_ios_runtime() -> str:
    runtimes = json.loads(simctl("list", "runtimes", "available", "-j"))["runtimes"]
    ios = [r for r in runtimes if r["platform"] == "iOS"]
    if not ios:
        sys.exit("✗ no iOS simulator runtime installed")
    return max(ios, key=lambda r: [int(n) for n in r["version"].split(".")])["identifier"]


def resolve_device(udid: str | None, name: str) -> str:
    """The UDID to run on, booted. Creates the dedicated device on first use."""
    if udid == "booted":
        booted = booted_devices()
        if not booted:
            sys.exit("✗ no booted simulator")
        preferred = [d for d in booted if "18 Pro Max" in d["name"]]
        return (preferred or booted)[0]["udid"]
    if udid:
        return udid
    matches = [d for d in all_devices() if d["name"] == name]
    if matches:
        device = matches[0]
        udid = device["udid"]
    else:
        print(f"▸ creating simulator “{name}” (iPhone 18 Pro Max)")
        udid = simctl("create", name, DEVICE_TYPE, newest_ios_runtime()).strip()
        device = {"state": "Shutdown"}
    if device["state"] != "Booted":
        print(f"▸ booting “{name}”")
        simctl("boot", udid)
        simctl("bootstatus", udid, "-b")
    return udid


def quiet_keyboard(udid: str) -> None:
    """A fresh device covers the first typed search with the QuickPath intro."""
    simctl(
        "spawn", udid, "defaults", "write", "com.apple.keyboard.preferences",
        "DidShowContinuousPathIntroduction", "-bool", "true",
    )  # fmt: skip


# MARK: - Build


def derived_data_roots() -> list[Path]:
    """Every DerivedData built from THIS checkout — worktrees build their own."""
    roots = []
    for candidate in sorted(Path.home().glob("Library/Developer/Xcode/DerivedData/Piru-*")):
        info = candidate / "info.plist"
        if not info.exists():
            continue
        with info.open("rb") as handle:
            workspace = plistlib.load(handle).get("WorkspacePath", "")
        if workspace.startswith(str(REPO) + "/"):
            roots.append(candidate)
    return roots


def build_app(udid: str) -> None:
    print("▸ building Piru (Debug, simulator)")
    run(
        "xcodebuild",
        "-scheme",
        SCHEME,
        "-configuration",
        "Debug",
        "-destination",
        f"platform=iOS Simulator,id={udid}",
        "-quiet",
        "build",
        capture=False,
    )


def find_app() -> Path:
    apps = [
        root / "Build/Products/Debug-iphonesimulator/Piru.app"
        for root in derived_data_roots()
        if (root / "Build/Products/Debug-iphonesimulator/Piru.app").exists()
    ]
    if not apps:
        sys.exit("✗ no Debug simulator build of this checkout — drop --no-build")
    return max(apps, key=lambda app: app.stat().st_mtime)


# MARK: - Capture


def clear_tour(tour: Path) -> None:
    tour.mkdir(parents=True, exist_ok=True)
    for name in ("request.json", "ack", "done.json"):
        (tour / name).unlink(missing_ok=True)


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def capture_pass(udid: str, leaf: Path, launch_args: list[str], timeout: float, label: str) -> dict:
    """One launch: answer every request until done.json lands."""
    tour = leaf / ".tour"
    clear_tour(tour)
    simctl("terminate", udid, BUNDLE_ID, check=False)
    output = simctl("launch", udid, BUNDLE_ID, *launch_args)
    pid = int(output.rsplit(":", 1)[1])
    request_file, ack, done = tour / "request.json", tour / "ack", tour / "done.json"
    last_activity = time.monotonic()
    files: list[dict] = []
    while True:
        if done.exists():
            report = json.loads(done.read_text())
            break
        if request_file.exists():
            try:
                request = json.loads(request_file.read_text())
            except (json.JSONDecodeError, OSError):
                time.sleep(0.02)
                continue
            target = leaf / request["file"]
            target.parent.mkdir(parents=True, exist_ok=True)
            simctl("io", udid, "screenshot", str(target))
            ack.touch()
            print(f"  [{request['index']:>3}/{request['total']}] {label}/{request['file']}")
            files.append({**request, "path": str(target.relative_to(leaf.parent))})
            while request_file.exists() or ack.exists():
                time.sleep(0.02)
            last_activity = time.monotonic()
            continue
        if not process_alive(pid):
            sys.exit(f"✗ Piru exited before the tour finished ({label})")
        if time.monotonic() - last_activity > timeout:
            simctl("terminate", udid, BUNDLE_ID, check=False)
            sys.exit(f"✗ no capture request for {timeout:.0f}s ({label}) — the tour is wedged")
        time.sleep(0.05)
    simctl("terminate", udid, BUNDLE_ID, check=False)
    shutil.rmtree(tour, ignore_errors=True)
    return {"files": files, "report": report}


# MARK: - Main


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--locales", default="en,zh-Hans", help="comma list of en, zh-Hans, zh-Hant"
    )
    parser.add_argument("--appearance", choices=["light", "dark", "both"], default="light")
    parser.add_argument("--screens", default="all", help="comma list of screen names, or all")
    parser.add_argument("--skins", default="all", help="all, none, or a comma list of skin ids")
    parser.add_argument(
        "--skin-screens",
        default=None,
        help="screens captured per skin (default: the tour's subset)",
    )
    parser.add_argument("--persona", default="week", help="-piruPersona fixture to seed")
    parser.add_argument("--out", default=str(REPO / "Store/shots"), help="output directory")
    parser.add_argument(
        "--device", default=DEVICE_NAME, help="simulator to create/boot for the pass"
    )
    parser.add_argument("--udid", default=None, help="an existing simulator's UDID, or booted")
    parser.add_argument(
        "--app", default=None, help="Piru.app to install (default: this checkout's Debug build)"
    )
    parser.add_argument("--no-build", action="store_true", help="install the existing Debug build")
    parser.add_argument(
        "--clock", default="9:41", help="the time on the status bar and the timeline's Now"
    )
    parser.add_argument(
        "--settle", type=float, default=1.2, help="seconds to wait after each navigation"
    )
    parser.add_argument(
        "--timeout", type=float, default=90, help="seconds without a request before giving up"
    )
    parser.add_argument(
        "--no-fake-vitals", action="store_true", help="leave the synthetic heart-rate series out"
    )
    parser.add_argument(
        "--list", action="store_true", help="print the screen and skin names and exit"
    )
    parser.add_argument(
        "--wallpapers",
        action="store_true",
        help="capture each skin's backdrop alone, as <skin>.png (default out: Store/wallpapers)",
    )
    args = parser.parse_args()
    if args.wallpapers:
        if args.out == str(REPO / "Store/shots"):
            args.out = str(REPO / "Store/wallpapers")
        if args.locales == "en,zh-Hans":
            args.locales = "en"
        # A capture taken too soon after the root is re-created for a skin
        # change lands with the simulator's Dynamic Island painted black.
        if args.settle == 1.2:
            args.settle = 3.0
    return args


def status_bar_time(clock: str) -> str:
    """The status bar's 12-hour reading of `--clock`, so an evening clock reads 9:41, not 21:41."""
    hour, minute = clock.split(":")
    return f"{int(hour) % 12 or 12}:{minute}"


def main() -> None:
    args = parse_args()
    screens, skins = catalog_screens(), catalog_skins()
    if args.list:
        print("screens:", ", ".join(screens))
        print("skins:  ", ", ".join(skins))
        return
    for name in [] if args.screens == "all" else args.screens.split(","):
        if name not in screens:
            sys.exit(f"✗ unknown screen {name!r} — see --list")
    for name in [] if args.skins in ("all", "none") else args.skins.split(","):
        if name not in skins:
            sys.exit(f"✗ unknown skin {name!r} — see --list")
    locales = [locale.strip() for locale in args.locales.split(",") if locale.strip()]
    for locale in locales:
        if locale not in LOCALES:
            sys.exit(f"✗ unknown locale {locale!r} — one of {', '.join(LOCALES)}")

    started = time.monotonic()
    udid = resolve_device(args.udid, args.device)
    quiet_keyboard(udid)
    if not args.no_build and not args.app:
        build_app(udid)
    app = Path(args.app) if args.app else find_app()
    print(f"▸ installing {app}")
    simctl("install", udid, str(app))
    simctl(
        "status_bar", udid, "override",
        "--time", status_bar_time(args.clock), "--batteryState", "charged", "--batteryLevel", "100",
        "--dataNetwork", "wifi", "--wifiBars", "3", "--cellularBars", "4", "--operatorName", "",
    )  # fmt: skip

    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    appearances = ["light", "dark"] if args.appearance == "both" else [args.appearance]
    index: list[dict] = []
    failed: list[str] = []
    for appearance in appearances:
        simctl("ui", udid, "appearance", appearance)
        for locale in locales:
            label = locale if appearance == "light" else f"{locale}-dark"
            leaf = out / label
            leaf.mkdir(parents=True, exist_ok=True)
            print(f"▸ {label}: {args.persona} persona, skins={args.skins}")
            launch_args = [
                "-piruScreenshots", str(leaf),
                "-piruScreenshotScreens", args.screens,
                "-piruScreenshotSkins", args.skins,
                "-piruScreenshotSettle", str(args.settle),
                "-piruPersona", args.persona,
                "-piruNow", args.clock,
                "-piruOwnEverything",
                "-hasCompletedOnboarding", "YES",
                "-install.firstBuild", "999999",
                "-AppNavigator.selectedTab", "journal",
                "-AppleLanguages", f"({locale})",
                "-AppleLocale", LOCALES[locale],
            ]  # fmt: skip
            if args.skin_screens:
                launch_args += ["-piruScreenshotSkinScreens", args.skin_screens]
            if args.wallpapers:
                launch_args.append("-piruWallpapers")
            if not args.no_fake_vitals:
                launch_args.append("-piruFakeVitals")
            result = capture_pass(udid, leaf, launch_args, args.timeout, label)
            for entry in result["files"]:
                index.append({"locale": locale, "appearance": appearance, **entry})
            failed += [f"{label}/{file}" for file in result["report"]["failed"]]
            failed += [f"{label}/{file}" for file in result["report"]["skipped"]]

    if args.udid:
        simctl("status_bar", udid, "clear")
    (out / "index.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
    elapsed = time.monotonic() - started
    print(f"\n{len(index)} screenshots in {out} ({elapsed / 60:.1f} min)")
    by_skin: dict[str, int] = {}
    for entry in index:
        by_skin[entry["skin"]] = by_skin.get(entry["skin"], 0) + 1
    print("  " + ", ".join(f"{skin} {count}" for skin, count in by_skin.items()))
    if failed:
        print(f"✗ {len(failed)} not captured:\n  " + "\n  ".join(failed))
        sys.exit(1)


if __name__ == "__main__":
    main()
