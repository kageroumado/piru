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

``--platform macos`` runs the same tour in the native Mac app. A sandboxed Mac
app can write nowhere this script can read, so the tour POSTs each request to a
loopback server here instead, and the window is captured with ``rocuronium
screenshot --pid``. The tour runs on its own store (``screenshots.store``), so
the persona reseed never touches the journal the installed Mac app reads.
Output goes to ``Store/shots-macos/``::

    pipeline/screenshots.py --platform macos --skins none --locales en

``--device-type`` creates the pass's simulator from another device type, and
``--pose`` / ``--orientation`` set it up first through Device Hub (Xcode 27.1+,
driven with ``rocuronium``): ``--pose closed|partially-open|open`` folds an iPhone
Duo and captures the display that pose lights, ``--orientation portrait|landscape``
turns the device for the pass and back afterwards::

    pipeline/screenshots.py --device "Piru Duo" --device-type iPhone-Duo --pose open
    pipeline/screenshots.py --device "Piru iPad" --device-type iPad-Pro-13-inch-M5-12GB --orientation landscape

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
import struct
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BUNDLE_ID = "glass.kagerou.piru"
SCHEME = "Piru"
DEVICE_TYPE = "iPhone-18-Pro-Max"
DEVICE_NAME = "Piru Screenshots"
LOCALES = {"en": "en_US", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW", "es": "es_ES"}
TOUR_SOURCE = REPO / "Piru/Utilities/ScreenshotTour.swift"
# Fixed so the Mac build never races the IDE's DerivedData; the internal disk
# holds source only, so it goes on the build SSD when that is mounted.
MAC_DERIVED_DATA = Path("/Volumes/Ugreen/Build/piru-mac")
MAC_WINDOW = "1280x820"
# Device Hub's button for each `--pose`, and the display that pose lights:
# `primary` is an iPhone Duo's outer screen, `primary-1` its inner one.
POSES = {
    "closed": ("Closed", "primary"),
    "partially-open": ("Partially Open", "primary-1"),
    "open": ("Open", "primary-1"),
}

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


def resolve_device(udid: str | None, name: str, device_type: str) -> str:
    """The UDID to run on, booted. Creates the dedicated device on first use."""
    if udid == "booted":
        booted = booted_devices()
        if not booted:
            sys.exit("✗ no booted simulator")
        preferred = [d for d in booted if "18 Pro Max" in d["name"]]
        return (preferred or booted)[0]["udid"]
    if udid:
        matches = [d for d in all_devices() if d["udid"] == udid]
        if not matches:
            sys.exit(f"✗ no simulator {udid}")
        device, name = matches[0], matches[0]["name"]
        if device["state"] != "Booted":
            print(f"▸ booting “{name}”")
            simctl("boot", udid)
            simctl("bootstatus", udid, "-b")
        return udid
    matches = [d for d in all_devices() if d["name"] == name]
    if matches:
        device = matches[0]
        udid = device["udid"]
    else:
        print(f"▸ creating simulator “{name}” ({device_type})")
        type_id = f"com.apple.CoreSimulator.SimDeviceType.{device_type}"
        udid = simctl("create", name, type_id, newest_ios_runtime()).strip()
        device = {"state": "Shutdown"}
    if device["state"] != "Booted":
        print(f"▸ booting “{name}”")
        simctl("boot", udid)
        simctl("bootstatus", udid, "-b")
    return udid


def device_name(udid: str) -> str:
    return next(d["name"] for d in all_devices() if d["udid"] == udid)


def device_hub_press(udid: str, button: str) -> None:
    """Press one of Device Hub's device controls (a pose, a rotation) for `udid`:
    simctl has no verb for either. Device Hub shows one device at a time, so its
    row in the sidebar is selected first — unless it is already showing, when the
    name also heads the detail pane and a label click would be ambiguous."""
    developer = Path(run("xcode-select", "-p").strip())
    hub = developer.parent / "Applications/DeviceHub.app"
    pids = run("pgrep", "-x", "DeviceHub", check=False).split()
    if not pids:
        run("open", "-g", str(hub))
        for _ in range(40):
            time.sleep(0.25)
            if pids := run("pgrep", "-x", "DeviceHub", check=False).split():
                break
        else:
            sys.exit("✗ Device Hub did not start")
        time.sleep(2)
    pid, name = pids[0], device_name(udid)
    # The compact device window has no device list; return to the full one.
    compact = run(
        "rocuronium", "find", "--pid", pid, "--label", "Show in Device Hub", "--exact",
        "--role", "button", "--json", check=False,
    )  # fmt: skip
    if compact.strip() and json.loads(compact).get("matches"):
        run("rocuronium", "click", "--pid", pid, "--label", "Show in Device Hub", "--exact")
        time.sleep(1.5)
    if not run("rocuronium", "windows", "--pid", pid).lstrip().startswith(f"'{name} –"):
        run("rocuronium", "click", "--pid", pid, "--label", name, "--exact", "--role", "statictext")
    # Not checked: the device animates after the press, so rocuronium can read
    # "nothing moved" and add a posted click of its own. Callers verify the result.
    run(
        "rocuronium",
        "click",
        "--pid",
        pid,
        "--label",
        button,
        "--exact",
        "--role",
        "button",
        check=False,
    )
    time.sleep(3)


def screen_orientation(udid: str, display: str | None) -> str:
    """The orientation the display is showing, read off a probe capture's shape."""
    probe = Path(f"/tmp/piru-orientation-{uuid.uuid4().hex}.png")
    display_flag = [f"--display={display}"] if display else []
    simctl("io", udid, "screenshot", *display_flag, str(probe))
    width, height = struct.unpack(">II", probe.read_bytes()[16:24])
    probe.unlink()
    return "landscape" if width > height else "portrait"


def turn_to(udid: str, display: str | None, orientation: str) -> None:
    """Rotate until the display shows `orientation`. One press can turn the
    device a quarter turn or, with rocuronium's fallback click, a half turn."""
    for _ in range(6):
        if screen_orientation(udid, display) == orientation:
            return
        device_hub_press(udid, "Rotate Left")
    sys.exit(f"✗ could not turn the device to {orientation}")


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


def capture_target(leaf: Path, file: str) -> Path:
    """Where a requested capture lands. The name comes from the app (or, on macOS,
    from anything that can reach the loopback port), so it must stay inside `leaf`."""
    target = (leaf / file).resolve()
    if not target.is_relative_to(leaf.resolve()) or target.suffix != ".png":
        sys.exit(f"✗ refusing capture outside {leaf}: {file!r}")
    return target


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def capture_pass(
    udid: str, leaf: Path, launch_args: list[str], timeout: float, label: str, display: str | None
) -> dict:
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
            target = capture_target(leaf, request["file"])
            target.parent.mkdir(parents=True, exist_ok=True)
            display_flag = [f"--display={display}"] if display else []
            simctl("io", udid, "screenshot", *display_flag, str(target))
            ack.touch()
            print(f"  [{request['index']:>3}/{request['total']}] {label}/{request['file']}")
            files.append({**request, "path": str(target.relative_to(leaf.resolve().parent))})
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


# MARK: - macOS


def mac_derived_data() -> list[str]:
    return ["-derivedDataPath", str(MAC_DERIVED_DATA)] if MAC_DERIVED_DATA.parent.is_dir() else []


def build_mac_app() -> None:
    print("▸ building Piru (Debug, macOS)")
    run(
        "xcodebuild", "-scheme", SCHEME, "-configuration", "Debug",
        "-destination", "platform=macOS,arch=arm64", *mac_derived_data(), "-quiet", "build",
        capture=False,
    )  # fmt: skip


def find_mac_app() -> Path:
    roots = [MAC_DERIVED_DATA] if mac_derived_data() else derived_data_roots()
    apps = [root / "Build/Products/Debug/Piru.app" for root in roots]
    apps = [app for app in apps if app.exists()]
    if not apps:
        sys.exit("✗ no Debug macOS build of this checkout — drop --no-build")
    return max(apps, key=lambda app: app.stat().st_mtime)


def capture_window(pid: int, target: Path) -> None:
    """The app's window, through rocuronium (it only writes under /tmp and a few user folders)."""
    scratch = Path(f"/tmp/piru-shot-{uuid.uuid4().hex}.png")
    run("rocuronium", "screenshot", "--pid", str(pid), "--path", str(scratch))
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(scratch, target)


def capture_pass_macos(
    app: Path, leaf: Path, launch_args: list[str], timeout: float, label: str
) -> dict:
    """One launch of the Mac app: answer every POSTed request until /done lands."""
    files: list[dict] = []
    state = {"pid": 0, "report": None, "last": time.monotonic()}
    done = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802 — the stdlib's name
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"] or 0)) or b"{}")
            if self.path == "/request":
                try:
                    target = capture_target(leaf, body["file"])
                except SystemExit as refusal:
                    print(refusal)
                    self.send_response(400)
                    self.end_headers()
                    return
                capture_window(state["pid"], target)
                print(f"  [{body['index']:>3}/{body['total']}] {label}/{body['file']}")
                files.append({**body, "path": str(target.relative_to(leaf.resolve().parent))})
            elif self.path == "/done":
                state["report"] = body
                done.set()
            state["last"] = time.monotonic()
            self.send_response(200)
            self.end_headers()

        def log_message(self, *_: object) -> None:
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    host = f"http://127.0.0.1:{server.server_address[1]}"
    binary = app / "Contents/MacOS/Piru"
    process = subprocess.Popen(
        [
            str(binary),
            *launch_args,
            "-piruScreenshotHost",
            host,
            "-piruScreenshotWindow",
            MAC_WINDOW,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    state["pid"] = process.pid
    try:
        while not done.wait(0.2):
            if process.poll() is not None:
                sys.exit(f"✗ Piru exited before the tour finished ({label})")
            if time.monotonic() - state["last"] > timeout:
                sys.exit(f"✗ no capture request for {timeout:.0f}s ({label}) — the tour is wedged")
    finally:
        process.terminate()
        server.shutdown()
    return {"files": files, "report": state["report"]}


# MARK: - Main


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--platform",
        choices=["ios", "macos"],
        default="ios",
        help="simulator or the native Mac app",
    )
    parser.add_argument(
        "--locales", default="en,zh-Hans", help="comma list of en, zh-Hans, zh-Hant, es"
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
        "--device-type",
        default=DEVICE_TYPE,
        help="device type for a newly created --device, e.g. iPhone-Duo (see simctl list devicetypes)",
    )
    parser.add_argument(
        "--pose", choices=list(POSES), default=None, help="fold an iPhone Duo first, via Device Hub"
    )
    parser.add_argument(
        "--orientation",
        choices=["portrait", "landscape"],
        default=None,
        help="turn the device for the pass, via Device Hub, and back afterwards",
    )
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
    if args.platform == "macos" and args.out == str(REPO / "Store/shots"):
        args.out = str(REPO / "Store/shots-macos")
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
    macos = args.platform == "macos"
    udid, display, original_orientation = "", None, ""
    if macos:
        if not args.no_build and not args.app:
            build_mac_app()
        app = Path(args.app) if args.app else find_mac_app()
        print(f"▸ running {app}")
    else:
        udid = resolve_device(args.udid, args.device, args.device_type)
        quiet_keyboard(udid)
        display = POSES[args.pose][1] if args.pose else None
        if args.pose:
            device_hub_press(udid, POSES[args.pose][0])
        original_orientation = screen_orientation(udid, display)
        if args.orientation:
            turn_to(udid, display, args.orientation)
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
        if not macos:
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
            if macos:
                # The app's own appearance; the system's is left alone.
                launch_args += ["-AppleInterfaceStyle", "Dark" if appearance == "dark" else "Light"]
                result = capture_pass_macos(app, leaf, launch_args, args.timeout, label)
            else:
                result = capture_pass(udid, leaf, launch_args, args.timeout, label, display)
            for entry in result["files"]:
                index.append({"locale": locale, "appearance": appearance, **entry})
            failed += [f"{label}/{file}" for file in result["report"]["failed"]]
            failed += [f"{label}/{file}" for file in result["report"]["skipped"]]

    if args.udid and not macos:
        simctl("status_bar", udid, "clear")
    if args.orientation and not macos:
        turn_to(udid, display, original_orientation)
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
