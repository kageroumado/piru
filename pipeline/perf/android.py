"""Android side of the perf pipeline: measured from outside the process.

The Android app is the same Swift source staged through `android/tools/stage.py`
and built with Skip in its release configuration, which compiles the DEBUG
flow hooks out. So this side drives the app with `adb shell input`, and reads:

- launch: `am start -W -S` (TotalTime), three cold starts;
- frames: `dumpsys gfxinfo <pkg> framestats` per flow, reset before it
  (frame time = FrameCompleted - IntendedVsync; slow > 16.7 ms, frozen > 700 ms);
- main-thread CPU: `/proc/<pid>/task/<pid>/stat` utime + stime per flow;
- memory: `dumpsys meminfo` TOTAL PSS after each flow;
- stacks: `simpleperf record` over the flows when `--simpleperf` is set, reported
  by self time: by pid as root on an emulator, `--app` on a phone (a profileable
  build); the recording is pulled to `android/perf.data`.

Measure a release APK re-signed with the debug key, on a headless emulator
started with `-no-window -gpu host`, with no build running on the host, or on a
phone with the `PIRU_PROFILE` builds (`pipeline/perf/README.md`).
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
        self.width, self.height = self.screen_size()
        # A rooted emulator answers `su 0`; a phone does not, and is reached through
        # `run-as` (the store) and `simpleperf --app` (stacks) instead.
        self.rooted = "uid=0" in self.shell("su 0 id 2>/dev/null")
        self._tabs: dict[str, tuple[int, int]] = {}

    def screen_size(self) -> tuple[int, int]:
        # `wm size` reports one screen of a foldable whichever is lit; the hierarchy's root is
        # the screen in use.
        self.shell("uiautomator dump /sdcard/piru-perf-ui.xml", timeout=30)
        match = re.search(
            r'bounds="\[0,0\]\[(\d+),(\d+)\]"', self.shell("cat /sdcard/piru-perf-ui.xml")
        )
        if not match:
            match = re.search(r"(\d+)x(\d+)", self.shell("wm size"))
        return (int(match.group(1)), int(match.group(2))) if match else (1080, 2400)

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

    def nodes(self) -> list[tuple[str, int, int]]:
        """Labeled on-screen nodes: (text or content description, center x, center y)."""
        self.shell("uiautomator dump /sdcard/piru-perf-ui.xml", timeout=30)
        xml = self.shell("cat /sdcard/piru-perf-ui.xml")
        found = []
        for label_a, label_b, x1, y1, x2, y2 in re.findall(
            r'text="([^"]*)"[^>]*?content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            xml,
        ):
            label = label_a or label_b
            if label:
                found.append((label, (int(x1) + int(x2)) // 2, (int(y1) + int(y2)) // 2))
        return found

    def tap_label(self, pattern: str, last: bool = False) -> bool:
        """Taps the node whose label matches `pattern` (a regex, whole label); navigation only,
        outside a measured window, because the hierarchy dump itself costs the app work."""
        matches = [(x, y) for label, x, y in self.nodes() if re.fullmatch(pattern, label)]
        if not matches:
            return False
        x, y = matches[-1] if last else matches[0]
        self.shell(f"input tap {x} {y}")
        return True

    def open_link(self, url: str) -> None:
        # The URL is quoted for the device shell: an unquoted `&` would end the command there.
        self.shell(f"am start -a android.intent.action.VIEW -d '{url}' {PACKAGE}")

    def tab_position(self, name: str) -> tuple[int, int]:
        if not self._tabs:
            names = ("Journal", "Library", "Tools", "Insights", "Search")
            for label, x, y in self.nodes():
                # The tab bar's labels are the lowest ones with these names.
                if label in names and (label not in self._tabs or y > self._tabs[label][1]):
                    self._tabs[label] = (x, y)
        return self._tabs.get(name, (0, 0))

    def swipe(self, fy0: float, fy1: float, ms: int) -> None:
        # A landscape screen (an unfolded phone) has its scrolling content in a narrow band
        # between the pinned header and the bottom bars: the gesture is mapped into it.
        if self.width > self.height:
            fy0, fy1 = (0.42 + (f - 0.2) / 0.7 * 0.26 for f in (fy0, fy1))
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


TAB_NAMES = ("Journal", "Library", "Tools", "Insights", "Search")


def tab(device: Device, index: int) -> None:
    x, y = device.tab_position(TAB_NAMES[index])
    if x and y:
        device.shell(f"input tap {x} {y}")
    else:
        # No labels read (a hung UI): the five tabs across the bottom of a phone screen.
        device.tap((index + 0.5) / 5, 0.947)


def scroll_page(device: Device, times: int) -> None:
    for _ in range(times):
        device.swipe(0.75, 0.35, 250)
        time.sleep(0.35)


def journal_layout(device: Device, name: str) -> None:
    """Switches the Journal to a layout from its ••• menu (navigation, before the measure)."""
    tab(device, 0)
    time.sleep(1.0)
    if device.tap_label("More"):
        time.sleep(1.5)
        device.tap_label(name)
        time.sleep(0.8)
        device.shell("input keyevent KEYCODE_BACK")
        time.sleep(1.5)


def quicklog(device: Device) -> None:
    # Opened and closed four times, then one dose staged from a favorite and recorded.
    tab(device, 0)
    time.sleep(1.0)
    # Closed with its own Close button: Back with nothing open would leave the app, and a
    # window that left takes its frame record with it.
    for _ in range(4):
        device.tap_label("Record an Entry")
        time.sleep(1.5)
        device.tap_label("Close")
        time.sleep(1.0)
    device.tap_label("Record an Entry")
    time.sleep(1.5)
    if device.tap_label(r"Log [0-9.]+ [µm]?g of .+"):
        time.sleep(1.0)
        device.tap_label("Record an Entry", last=True)
        time.sleep(2.0)
    else:
        device.tap_label("Close")


def insights(device: Device) -> None:
    for insight in ("usage", "inSystem", "receptorLoad", "bodyLoad", "adherence"):
        device.open_link(f"piru://insight/{insight}")
        time.sleep(2.5)
        # The next link replaces the screen; no Back, which on a split layout leaves the app.
        scroll_page(device, 3)


def tolerance(device: Device) -> None:
    device.open_link("piru://insight/tolerance")
    time.sleep(3.0)
    scroll_page(device, 4)


def substance_page(device: Device) -> None:
    device.open_link("piru://substance/MDMA")
    time.sleep(3.0)
    scroll_page(device, 12)


def session_charts(device: Device) -> None:
    # The newest session, from the Days layout's first card.
    journal_layout(device, "Days")
    if device.tap_label(r"\d.*entr(y|ies)"):
        time.sleep(3.0)
        scroll_page(device, 5)


def journal_scroll(device: Device) -> None:
    [device.swipe(0.75, 0.25, 120) or time.sleep(0.15) for _ in range(40)]
    [device.swipe(0.25, 0.85, 80) or time.sleep(0.1) for _ in range(40)]


def back_to_journal(device: Device, layout: str) -> None:
    # A screen the previous flow pushed is closed by its own back button first.
    device.tap_label("Back")
    time.sleep(1.0)
    journal_layout(device, layout)


# Navigation a flow needs before its measured window opens.
PREPARE = {
    "journal-days": lambda d: back_to_journal(d, "Days"),
    "journal-timeline": lambda d: back_to_journal(d, "Timeline"),
    "journal-scroll": lambda d: back_to_journal(d, "Timeline"),
}

# The flows the emulator runs have measured the same four since 2026-11-23; the phone set adds
# the screens a person opens most.
EMULATOR_FLOWS = ("journal-scroll", "tab-storm", "library-search", "reversed-flings")

FLOWS = {
    "journal-days": journal_scroll,
    "journal-timeline": journal_scroll,
    "quicklog": quicklog,
    "insights": insights,
    "tolerance": tolerance,
    "substance-page": substance_page,
    "session": session_charts,
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
    """Replaces the app's store with `store`. On a rooted emulator through `su 0`, the
    replaced files moved aside under /data/local/tmp; on a phone through `run-as`, which
    needs a debuggable build, streamed straight into the app's files (no copy anywhere else
    on the device) and the replaced files moved aside there. Nothing is deleted."""
    device.shell(f"am force-stop {PACKAGE}")
    if not device.rooted:
        files = f"/data/data/{PACKAGE}/files"
        with store.open("rb") as source:
            subprocess.run(
                [device.adb, "exec-in", f"run-as {PACKAGE} sh -c 'cat > {files}/fixture.incoming'"],
                stdin=source,
                check=True,
                capture_output=True,
            )
        aside = f"{files}/replaced-{int(time.time())}"
        device.shell(
            f"run-as {PACKAGE} sh -c 'mkdir -p {aside}; "
            f'for s in "" -wal -shm; do [ -e {files}/default.store$s ] && mv {files}/default.store$s {aside}/; done; '
            f"mv {files}/fixture.incoming {files}/default.store'"
        )
        return
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
    if simpleperf and device.rooted:
        # simpleperf sees the CPU clock events only as root.
        subprocess.run([device.adb, "root"], capture_output=True)
        subprocess.run([device.adb, "wait-for-device"], capture_output=True)
        time.sleep(2)
    pid = device.pid()
    names = list(FLOWS) if args.flows == "all" else [f for f in args.flows.split(",") if f in FLOWS]
    if simpleperf and pid:
        # Frame-pointer call graphs: DWARF unwinding (-g) fills an emulator's /data in a minute.
        # A phone is profiled through the app (a profileable build) at 1 kHz; the emulator by
        # pid as root at 500 Hz.
        target = (
            f"-p {pid} -e task-clock -f 500"
            if device.rooted
            else f"--app {PACKAGE} -e cpu-clock -f 1000"
        )
        recorder = subprocess.Popen(
            [
                device.adb,
                "shell",
                f"simpleperf record {target} --call-graph fp -o /data/local/tmp/piru-perf.data --duration 900",
            ]
        )
        time.sleep(2)
    steps = []
    restarted: list[str] = []
    for name in names:
        # Every flow starts with the app in front: a flow that left it is not
        # charged to the next one.
        device.shell(f"am start -n {ACTIVITY}")
        time.sleep(1.0)
        if name in PREPARE:
            PREPARE[name](device)
        device.shell(f"dumpsys gfxinfo {PACKAGE} reset")
        if device.pid() != pid:
            pid = device.pid()
            restarted.append(name)
        cpu = device.main_cpu_ms(pid)
        started = time.time()
        FLOWS[name](device)
        time.sleep(1.0)
        raw_frames = device.shell(f"dumpsys gfxinfo {PACKAGE} framestats")
        (out / f"framestats-{name}.txt").write_text(raw_frames)
        frames = parse_framestats(raw_frames)
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
        # The recording itself, for caller graphs on the host (`simpleperf report -g`).
        subprocess.run(
            [device.adb, "pull", "/data/local/tmp/piru-perf.data", str(out / "perf.data")],
            capture_output=True,
        )
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
