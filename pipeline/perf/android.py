"""Android side of the perf pipeline: measured from outside the process.

The Android app is the same Swift source staged through `android/tools/stage.py`
and built with Skip in its release configuration, which compiles the DEBUG
flow hooks out. So this side drives the app with `adb shell input`, and reads:

- launch: `am start -W -S` (TotalTime), three cold starts;
- frames: `dumpsys gfxinfo <pkg> framestats` per flow, reset before it
  (frame time = FrameCompleted - IntendedVsync; slow > 16.7 ms, frozen > 700 ms);
- main-thread CPU: `/proc/<pid>/task/<pid>/stat` utime + stime per flow;
- memory: `dumpsys meminfo` TOTAL PSS after each flow;
- stacks: `simpleperf record -g` over the flows when `--simpleperf` is set
  (needs `adb root`), reported by self time.

Measure a release APK re-signed with the debug key, on a headless emulator
started with `-no-window -gpu host`, with no build running on the host.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

PACKAGE = "glass.kagerou.piru"
ACTIVITY = f"{PACKAGE}/piru.module.MainActivity"
SLOW_MS = 1000 / 60
FROZEN_MS = 700


def adb_path() -> str:
    for candidate in (
        shutil.which("adb"),
        os.environ.get("ANDROID_HOME")
        and str(Path(os.environ["ANDROID_HOME"]) / "platform-tools" / "adb"),
        os.environ.get("PIRU_ANDROID")
        and str(Path(os.environ["PIRU_ANDROID"]) / "android-sdk" / "platform-tools" / "adb"),
    ):
        if candidate and Path(candidate).exists():
            return candidate
    raise SystemExit(
        "adb not found: put platform-tools on PATH, or set ANDROID_HOME or PIRU_ANDROID"
    )


class Device:
    def __init__(self) -> None:
        self.adb = adb_path()
        out = self.shell("wm size")
        match = re.search(r"(\d+)x(\d+)", out)
        self.width, self.height = (
            (int(match.group(1)), int(match.group(2))) if match else (1080, 2400)
        )

    def shell(self, command: str, timeout: float = 120) -> str:
        proc = subprocess.run(
            [self.adb, "shell", command], capture_output=True, text=True, timeout=timeout
        )
        return proc.stdout

    def pid(self) -> int | None:
        out = self.shell(f"pidof {PACKAGE}").strip()
        return int(out.split()[0]) if out else None

    def tap(self, fx: float, fy: float) -> None:
        self.shell(f"input tap {int(fx * self.width)} {int(fy * self.height)}")

    def swipe(self, fy0: float, fy1: float, ms: int) -> None:
        x = self.width // 2
        self.shell(f"input swipe {x} {int(fy0 * self.height)} {x} {int(fy1 * self.height)} {ms}")

    def type(self, text: str, pause: float) -> None:
        # One character per call: a slow emulator drops characters while the app re-renders.
        for character in text:
            self.shell(f"input text {character}")
            time.sleep(pause)

    def main_cpu_ms(self, pid: int | None) -> float:
        if pid is None:
            return 0.0
        fields = self.shell(f"cat /proc/{pid}/task/{pid}/stat").rsplit(")", 1)[-1].split()
        if len(fields) < 13:
            return 0.0
        return (int(fields[11]) + int(fields[12])) * 10.0

    def pss_mb(self) -> float | None:
        match = re.search(r"TOTAL PSS:\s+(\d+)", self.shell(f"dumpsys meminfo {PACKAGE}"))
        return int(match.group(1)) / 1024 if match else None


# Tab bar: five tabs across the bottom; Journal, Library, Tools, Insights, Search.
TAB_Y = 0.947


def tab(device: Device, index: int) -> None:
    device.tap((index + 0.5) / 5, TAB_Y)


FLOWS = {
    "journal-scroll": lambda d: (
        [d.swipe(0.75, 0.25, 120) or time.sleep(0.15) for _ in range(40)]
        + [d.swipe(0.25, 0.85, 80) or time.sleep(0.1) for _ in range(40)]
    ),
    "tab-storm": lambda d: [tab(d, i % 5) or time.sleep(0.05) for i in range(60)],
    "library-search": lambda d: [
        tab(d, 4),
        time.sleep(1.0),
        d.type("methylphenidate", 0.08),
        time.sleep(1.0),
        # Escape closes the keyboard; Back at a tab root would leave the app.
        d.shell("input keyevent KEYCODE_ESCAPE"),
    ],
    "reversed-flings": lambda d: [
        (d.swipe(0.8, 0.2, 60), time.sleep(0.12), d.swipe(0.3, 0.8, 60), time.sleep(0.12))
        for _ in range(12)
    ],
}


def parse_framestats(text: str) -> list[float]:
    """Frame durations (ms) from `dumpsys gfxinfo … framestats`."""
    frames: list[float] = []
    header: list[str] | None = None
    in_block = False
    for line in text.splitlines():
        if line.startswith("---PROFILEDATA---"):
            in_block = not in_block
            header = None
            continue
        if not in_block:
            continue
        cells = [c for c in line.strip().split(",") if c != ""]
        if header is None:
            header = cells
            continue
        try:
            row = dict(zip(header, (int(c) for c in cells), strict=False))
        except ValueError:
            continue
        if row.get("Flags", 0) != 0:
            continue
        start, end = row.get("IntendedVsync"), row.get("FrameCompleted")
        if start and end and end > start:
            frames.append((end - start) / 1e6)
    return frames


def install_store(device: Device, store: Path) -> None:
    """Replaces the app's store with `store` (a rooted emulator: `su 0`). The
    replaced files are moved aside under /data/local/tmp, never deleted."""
    device.shell(f"am force-stop {PACKAGE}")
    subprocess.run(
        [device.adb, "push", str(store), "/data/local/tmp/fixture.store"],
        check=True,
        capture_output=True,
    )
    owner = device.shell(f"su 0 stat -c %u /data/data/{PACKAGE}").strip()
    target = f"/data/data/{PACKAGE}/files/default.store"
    aside = f"/data/local/tmp/replaced-{int(time.time())}"
    device.shell(
        f'su 0 sh -c \'mkdir -p {aside}; for s in "" -wal -shm; do [ -e {target}$s ] && mv {target}$s {aside}/; done; '
        f"cp /data/local/tmp/fixture.store {target}; chown {owner}:{owner} {target}; restorecon {target}'"
    )


def run(run_dir: Path, args, thresholds: dict) -> dict:
    device = Device()
    out = run_dir / "android"
    out.mkdir(parents=True, exist_ok=True)
    if args.apk:
        subprocess.run(
            [device.adb, "install", "-r", str(args.apk)], check=True, capture_output=True
        )
    if getattr(args, "android_store", None):
        install_store(device, args.android_store)
    launches = []
    for _ in range(3):
        result = device.shell(f"am start -W -S -n {ACTIVITY}")
        match = re.search(r"TotalTime:\s+(\d+)", result)
        launches.append(int(match.group(1)) if match else None)
        time.sleep(6)
    simpleperf = getattr(args, "simpleperf", False)
    if simpleperf:
        # simpleperf sees the CPU clock events only as root.
        subprocess.run([device.adb, "root"], capture_output=True)
        subprocess.run([device.adb, "wait-for-device"], capture_output=True)
        time.sleep(2)
    pid = device.pid()
    names = list(FLOWS) if args.flows == "all" else [f for f in args.flows.split(",") if f in FLOWS]
    if simpleperf and pid:
        recorder = subprocess.Popen(
            [
                device.adb,
                "shell",
                # Frame-pointer call graphs at 500 Hz: DWARF unwinding (-g) fills an
                # emulator's /data in a minute.
                f"simpleperf record -p {pid} -e task-clock -f 500 --call-graph fp -o /data/local/tmp/piru-perf.data --duration 600",
            ]
        )
    steps = []
    restarted: list[str] = []
    for name in names:
        # Every flow starts with the app in front: a flow that left it is not
        # charged to the next one.
        device.shell(f"am start -n {ACTIVITY}")
        time.sleep(1.0)
        device.shell(f"dumpsys gfxinfo {PACKAGE} reset")
        if device.pid() != pid:
            pid = device.pid()
            restarted.append(name)
        cpu = device.main_cpu_ms(pid)
        started = time.time()
        FLOWS[name](device)
        time.sleep(1.0)
        frames = parse_framestats(device.shell(f"dumpsys gfxinfo {PACKAGE} framestats"))
        steps.append(
            {
                "flow": name,
                "wall_ms": round((time.time() - started) * 1000),
                "main_cpu_ms": device.main_cpu_ms(pid) - cpu,
                "frames": len(frames),
                "slow": sum(f > SLOW_MS for f in frames),
                "frozen": sum(f > FROZEN_MS for f in frames),
                "p50_ms": _percentile(frames, 50),
                "p95_ms": _percentile(frames, 95),
                "worst_ms": round(max(frames, default=0), 1),
                "pss_mb": device.pss_mb(),
            }
        )
    stacks = []
    if simpleperf and pid:
        subprocess.run([device.adb, "shell", "pkill -INT simpleperf"], capture_output=True)
        try:
            recorder.wait(timeout=60)
        except subprocess.TimeoutExpired:
            recorder.kill()
        report = device.shell(
            "simpleperf report -i /data/local/tmp/piru-perf.data --sort symbol -n --percent-limit 0.5",
            timeout=300,
        )
        stacks = [line.strip() for line in report.splitlines() if "%" in line][:30]
    data = {
        "restarted_before": restarted,
        "launch_ms": launches,
        "steps": steps,
        "stacks": stacks,
        "pid": pid,
        "screen": [device.width, device.height],
    }
    (out / "android.json").write_text(json.dumps(data, indent=2))
    return {"device": "android", "finished": True}


def _percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    return round(ordered[min(len(ordered) - 1, int(len(ordered) * p / 100))], 1)


def analyze(run_dir: Path, meta: dict, th: dict) -> dict:
    from analyze import Findings

    data = json.loads((run_dir / "android" / "android.json").read_text())
    findings = Findings()
    limits = th["android"]
    launches = [v for v in data["launch_ms"] if v]
    if launches:
        findings.check(
            "launch",
            "launch",
            "launch_ms",
            min(launches),
            limits["launch_ms"],
            f"cold starts: {launches} ms",
        )
    steps = []
    for step in data["steps"]:
        frames = max(step["frames"], 1)
        metrics = {
            **step,
            "slow_share": round(step["slow"] / frames, 3),
            "frozen_share": round(step["frozen"] / frames, 3),
            "counters": {},
        }
        findings.check(
            "frames",
            step["flow"],
            "slow_frame_share",
            metrics["slow_share"],
            limits["slow_frame_share"],
            f"{step['slow']} of {step['frames']} frames over 16.7 ms; p95 {step['p95_ms']} ms",
        )
        findings.check(
            "frames",
            step["flow"],
            "frozen_frame_share",
            metrics["frozen_share"],
            limits["frozen_frame_share"],
            f"worst frame {step['worst_ms']} ms",
        )
        steps.append(
            {
                "key": f"{step['flow']}#1",
                "flow": step["flow"],
                "step": step["flow"],
                "loop": 1,
                "metrics": metrics,
            }
        )
    for flow in data.get("restarted_before", []):
        findings.items.append(
            {
                "level": "fail",
                "kind": "crash",
                "step": flow,
                "metric": "process_restarted",
                "value": 1,
                "threshold": 1,
                "ratio": 99.0,
                "detail": "the app's process changed before this flow: it died during the previous one",
                "stacks": [],
            }
        )
    ordered = findings.sorted()
    return {
        "schema": 1,
        "run": meta,
        "fixture": meta.get("fixture"),
        "configuration": "android-release",
        "launch": {"to_interactive_ms": min(launches) if launches else None},
        "steps": steps,
        "trace": {"top_self": [], "top_inclusive": [], "stacks": data["stacks"], "notes": []},
        "findings": ordered,
        "status": "fail"
        if any(f["level"] == "fail" for f in ordered)
        else ("warn" if ordered else "pass"),
    }
