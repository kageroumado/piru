"""iOS side of the perf pipeline: build, simulator, seeding and recording.

The app does the walking (`Piru/Utilities/Perf/`); this module builds it,
installs it on a simulator of its own, seeds the fixture in one launch and
records the flows in a second, cold one under `xctrace`.
"""

from __future__ import annotations

import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SSD = Path("/Volumes/Ugreen")

SIMULATOR_NAME = "Piru Perf"
# A CI runner's Xcode can be a release behind; both are overridable there.
DEVICE_TYPE = os.environ.get(
    "PIRU_PERF_DEVICE_TYPE", "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max"
)
RUNTIME_PREFIX = os.environ.get("PIRU_PERF_RUNTIME", "com.apple.CoreSimulator.SimRuntime.iOS-27")

# The Debug configuration compiled like Release: the DEBUG hooks stay in, the
# code generation matches what ships. Debug's -Onone numbers say nothing about
# CPU cost, and Release compiles the hooks out.
OPTIMIZED_DEBUG = [
    "SWIFT_OPTIMIZATION_LEVEL=-O",
    "SWIFT_COMPILATION_MODE=wholemodule",
    "GCC_OPTIMIZATION_LEVEL=s",
    "ENABLE_TESTABILITY=NO",
    "DEBUG_INFORMATION_FORMAT=dwarf-with-dsym",
    "CLANG_COVERAGE_MAPPING=NO",
    "CLANG_ENABLE_CODE_COVERAGE=NO",
]

# Instruments added to the Time Profiler template. Points of Interest carries
# the step signposts; Hangs is the main-thread hang detector; the three Data
# instruments count Core Data (SwiftData) fetches, saves and faults exactly.
DEFAULT_INSTRUMENTS = ["Hangs", "Points of Interest", "Data Fetches", "Data Saves", "Data Faults"]


def log(message: str) -> None:
    print(f"[perf] {message}", flush=True)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


# MARK: - Build


def build_settings_args(destination: str) -> list[str]:
    args = ["-scheme", "Piru", "-configuration", "Debug", "-destination", destination]
    if SSD.is_dir():
        build = SSD / "Build" / "piru"
        args += [
            "-derivedDataPath",
            str(build / "DerivedData-6"),
            "-clonedSourcePackagesDirPath",
            str(build / "SourcePackages"),
            "COMPILATION_CACHE_ENABLE_CACHING=YES",
            f"COMPILATION_CACHE_CAS_PATH={build / 'CompilationCache'}",
        ]
    return args + OPTIMIZED_DEBUG


def build(destination: str) -> None:
    log("building Piru (Debug, optimized)…")
    started = time.time()
    proc = subprocess.run(
        ["xcodebuild", *build_settings_args(destination), "-quiet", "build"],
        cwd=REPO,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        errors = [
            line for line in proc.stdout.splitlines() + proc.stderr.splitlines() if "error:" in line
        ]
        sys.exit("build failed:\n" + "\n".join(errors[:30] or proc.stderr.splitlines()[-30:]))
    log(f"built in {time.time() - started:.0f} s")


def app_path(destination: str) -> Path:
    out = run(
        ["xcodebuild", *build_settings_args(destination), "-showBuildSettings", "-json"], cwd=REPO
    ).stdout
    for target in json.loads(out):
        settings = target.get("buildSettings", {})
        if settings.get("PRODUCT_NAME") == "Piru" and settings.get("WRAPPER_EXTENSION") == "app":
            return Path(settings["TARGET_BUILD_DIR"]) / settings["FULL_PRODUCT_NAME"]
    sys.exit("could not find the Piru app product in the build settings")


def bundle_id(app: Path) -> str:
    with open(app / "Info.plist", "rb") as handle:
        return plistlib.load(handle)["CFBundleIdentifier"]


def dsym_path(app: Path) -> Path | None:
    candidate = app.parent / f"{app.name}.dSYM"
    return candidate if candidate.exists() else None


# MARK: - Simulator


def simulator(name: str = SIMULATOR_NAME) -> str:
    """The UDID of the named simulator, created on first use and booted."""
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"]).stdout)["devices"]
    udid = None
    for runtime, entries in devices.items():
        for device in entries:
            if (
                device["name"] == name
                and device.get("isAvailable", True)
                and runtime.startswith(RUNTIME_PREFIX)
            ):
                udid = device["udid"]
    if udid is None:
        runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "-j"]).stdout)["runtimes"]
        candidates = sorted(
            (
                r
                for r in runtimes
                if r["identifier"].startswith(RUNTIME_PREFIX) and r.get("isAvailable")
            ),
            key=lambda r: r["version"],
        )
        if not candidates:
            sys.exit(f"no simulator runtime installed matching {RUNTIME_PREFIX}*")
        udid = run(
            ["xcrun", "simctl", "create", name, DEVICE_TYPE, candidates[-1]["identifier"]]
        ).stdout.strip()
        log(f"created simulator {name} ({udid})")
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    # The 9:41 bar keeps every capture comparable and silences the clock. It
    # can hang while another simulator is busy; it is cosmetic, so it may fail.
    status_bar = [
        "xcrun",
        "simctl",
        "status_bar",
        udid,
        "override",
        "--time",
        "9:41",
        "--batteryState",
        "charged",
        "--batteryLevel",
        "100",
    ]
    try:
        subprocess.run(status_bar, capture_output=True, timeout=15)
    except subprocess.TimeoutExpired:
        log("status bar override timed out; continuing")
    return udid


def install(udid: str, app: Path) -> None:
    run(["xcrun", "simctl", "install", udid, str(app)])


def terminate(udid: str, bundle: str) -> None:
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], capture_output=True)


def wait_for(
    path: Path,
    timeout: float,
    progress: Path | None = None,
    process: subprocess.Popen | None = None,
    stall: float = 240,
    crashed=None,
) -> bool:
    """Waits for `path`; gives up at `timeout`, when `crashed()` finds a crash
    report, or when `progress` names the same step for `stall` seconds."""
    deadline = time.time() + timeout
    last = None
    changed = time.time()
    polls = 0
    while time.time() < deadline:
        polls += 1
        if crashed is not None and polls % 10 == 0 and crashed():
            log(f"the app crashed during {last}")
            return False
        if last is not None and time.time() - changed > stall:
            log(f"no progress for {stall:.0f} s on {last}: the app crashed or wedged")
            return False
        if path.exists():
            return True
        if process is not None and process.poll() is not None:
            log(f"recorder exited early ({process.returncode})")
            return path.exists()
        if progress is not None and progress.exists():
            try:
                step = json.loads(progress.read_text()).get("step")
            except (OSError, json.JSONDecodeError):
                step = None
            if step and step != last:
                log(f"  {step}")
                last = step
                changed = time.time()
        time.sleep(0.5)
    return False


REPORTS = Path.home() / "Library" / "Logs" / "DiagnosticReports"


def find_crash(udid: str, since: float) -> dict | None:
    """The newest crash report of the app on this simulator since `since`:
    the exception and the top frames of the crashed thread."""
    for path in sorted(REPORTS.glob("Piru-*.ips"), key=lambda p: p.stat().st_mtime, reverse=True):
        if path.stat().st_mtime < since:
            break
        try:
            header, body = path.read_text().split("\n", 1)
            report = json.loads(body)
        except (OSError, ValueError):
            continue
        if udid not in report.get("procPath", ""):
            continue
        images = report.get("usedImages", [])
        thread = next((t for t in report.get("threads", []) if t.get("triggered")), {})
        frames = [
            f"{images[f['imageIndex']].get('name', '?')} {f.get('symbol', '?')}"
            for f in thread.get("frames", [])[:16]
            if f.get("imageIndex") is not None and f["imageIndex"] < len(images)
        ]
        return {"report": str(path), "exception": report.get("exception"), "frames": frames}
    return None


@dataclass
class LaunchPlan:
    udid: str
    bundle: str
    app: Path
    run_dir: Path
    fixture: str
    flows: list[str]
    loops: int
    now: str
    extra: list[str]

    def arguments(self, seed_only: bool) -> list[str]:
        args = [
            "-piruPerf",
            str(self.run_dir / "app"),
            "-piruPerfFixture",
            self.fixture,
            "-piruNow",
            self.now,
            "-piruOwnEverything",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        if seed_only:
            return args + ["-piruPerfSeedOnly"]
        return args + [
            "-piruPerfFlows",
            ",".join(self.flows) or "all",
            "-piruPerfLoops",
            str(self.loops),
            *self.extra,
        ]


def seed(plan: LaunchPlan, timeout: float = 900) -> dict:
    out = plan.run_dir / "app"
    out.mkdir(parents=True, exist_ok=True)
    seeded = out / "seeded.json"
    if seeded.exists():
        seeded.unlink()
    terminate(plan.udid, plan.bundle)
    log(f"seeding fixture '{plan.fixture}'…")
    run(
        [
            "xcrun",
            "simctl",
            "launch",
            "--terminate-running-process",
            plan.udid,
            plan.bundle,
            *plan.arguments(seed_only=True),
        ]
    )
    if not wait_for(seeded, timeout):
        sys.exit(f"fixture seeding timed out after {timeout:.0f} s")
    # The store must be closed cleanly before the measured launch opens it.
    time.sleep(2)
    terminate(plan.udid, plan.bundle)
    time.sleep(1)
    summary = json.loads(seeded.read_text())
    log(f"seeded {summary.get('doses', 0)} doses in {summary.get('seconds', 0):.1f} s")
    return summary


def record(plan: LaunchPlan, trace: Path | None, instruments: list[str], timeout: float) -> bool:
    """Launch cold and run the flows, under xctrace when `trace` is set."""
    out = plan.run_dir / "app"
    done = out / "done.json"
    for stale in ("done.json", "steps.json", "progress.json"):
        (out / stale).unlink(missing_ok=True)
    terminate(plan.udid, plan.bundle)
    if trace is None:
        log("running flows (no trace)…")
        run(["xcrun", "simctl", "launch", plan.udid, plan.bundle, *plan.arguments(seed_only=False)])
        started = time.time()
        finished = wait_for(
            done,
            timeout,
            progress=out / "progress.json",
            crashed=lambda: find_crash(plan.udid, started),
        )
        terminate(plan.udid, plan.bundle)
        return finished
    cmd = [
        "xcrun",
        "xctrace",
        "record",
        "--template",
        "Time Profiler",
        "--device",
        plan.udid,
        "--output",
        str(trace),
    ]
    for instrument in instruments:
        cmd += ["--instrument", instrument]
    cmd += [
        "--time-limit",
        f"{int(timeout)}s",
        "--launch",
        "--",
        str(plan.app),
        *plan.arguments(seed_only=False),
    ]
    log(f"recording to {trace} …")
    recorder = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    started = time.time()
    finished = wait_for(
        done,
        timeout,
        progress=out / "progress.json",
        process=recorder,
        crashed=lambda: find_crash(plan.udid, started),
    )
    time.sleep(1.5)
    if recorder.poll() is None:
        recorder.send_signal(signal.SIGINT)
    try:
        output, _ = recorder.communicate(timeout=300)
    except subprocess.TimeoutExpired:
        recorder.kill()
        output, _ = recorder.communicate()
    terminate(plan.udid, plan.bundle)
    if not trace.exists():
        log("xctrace wrote no trace:\n" + (output or "")[-2000:])
    return finished


def remove_trace(trace: Path) -> None:
    """Moves an analyzed trace to the Trash (it is hundreds of MB)."""
    if not trace.exists():
        return
    trash = shutil.which("trash")
    if trash:
        subprocess.run([trash, str(trace)], check=False)
    else:
        subprocess.run(
            ["osascript", "-e", f'tell application "Finder" to delete POSIX file "{trace}"'],
            check=False,
            capture_output=True,
        )
