"""The Instruments lane: cut a recorded `.trace` by the app's step signposts.

Built on the `swiftui-specialist` skill's `instruments_parser` (its xctrace
wrapper and its id/ref-resolving row stream), found through
`$PIRU_INSTRUMENTS_PARSER` or the skill's install path. Without it the trace
lane is reported as unavailable and the in-app lane still runs.

Per step, from the Time Profiler samples of the app's process:
- main-thread time classified by the leaf frame (the thread-state column is
  unreliable): idle in the run loop, waiting (locks, kevent, I/O, mach_msg
  outside the run loop) or on CPU;
- the heaviest functions by self time and by inclusive time;
- repeated heavy work: a watched symbol entered many times in one step,
  counted as separate bursts of main-thread samples carrying it.
Plus hangs (`potential-hangs`), Core Data fetches/saves/faults, and SwiftUI
body updates when the SwiftUI instrument recorded them.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

SKILL_SCRIPTS = Path.home() / ".claude" / "skills" / "swiftui-specialist" / "scripts"
PROCESS = "Piru"

IDLE_LEAVES = ("mach_msg2_trap", "mach_msg_trap")
RUNLOOP_FRAMES = ("__CFRunLoopServiceMachPort", "CFRunLoopRunSpecific", "__CFRunLoopRun")
WAIT_LEAVES = (
    "__ulock_wait",
    "__psynch_",
    "kevent",
    "__semwait",
    "semaphore_wait",
    "__workq_kernreturn",
    "pread",
    "__open",
    "read",
    "write",
    "fsync",
    "__select",
    "poll",
    "mach_msg",
)
# Frames of the SwiftUI instrument's own tracing; samples carrying them are discounted.
TRACING_FRAMES = ("SwiftUITracingSupport", "ktrace")


def _parser():
    for candidate in (os.environ.get("PIRU_INSTRUMENTS_PARSER"), str(SKILL_SCRIPTS)):
        if candidate and (Path(candidate) / "instruments_parser").is_dir():
            if candidate not in sys.path:
                sys.path.insert(0, candidate)
            from instruments_parser import events, xctrace, xml_utils

            return events, xctrace, xml_utils
    return None


def classify(frames: list[str]) -> str:
    if not frames:
        return "cpu"
    leaf = frames[0]
    if leaf.startswith(IDLE_LEAVES) and any(f.startswith(RUNLOOP_FRAMES) for f in frames[:12]):
        return "idle"
    if leaf.startswith(WAIT_LEAVES):
        return "wait"
    return "cpu"


# MARK: - Symbolication


class Symbolicator:
    """Resolves the app's unsymbolicated frames with `atos` against the dSYM."""

    def __init__(self, dsym: str | None) -> None:
        self.binary = None
        if dsym:
            dwarf = Path(dsym) / "Contents" / "Resources" / "DWARF"
            files = list(dwarf.glob("*")) if dwarf.is_dir() else []
            self.binary = files[0] if files else None
        self.cache: dict[tuple[str, str], str] = {}

    def resolve(self, pending: dict[str, set[str]]) -> None:
        """`pending`: load address → frame addresses in the app binary."""
        if self.binary is None:
            return
        for load, addresses in pending.items():
            todo = sorted(a for a in addresses if (load, a) not in self.cache)
            for chunk in range(0, len(todo), 2000):
                part = todo[chunk : chunk + 2000]
                proc = subprocess.run(
                    ["atos", "-arch", "arm64", "-o", str(self.binary), "-l", load, *part],
                    capture_output=True,
                    text=True,
                )
                for address, line in zip(part, proc.stdout.splitlines(), strict=False):
                    self.cache[(load, address)] = re.sub(r" \(in [^)]+\)", "", line).strip()


# MARK: - Samples


def read_samples(trace: Path, run: int, xctrace, xml_utils) -> list[dict]:
    stream = xml_utils.RowStream(xctrace.export_schema(trace, "time-profile", run=run))
    samples = []
    for row in stream:
        time_el, thread_el, stack_el = row.get("time"), row.get("thread"), row.get("stack")
        if time_el is None or thread_el is None or stack_el is None:
            continue
        thread = xml_utils.extract_thread(thread_el, stream)
        if (thread.get("process") or {}).get("name") != PROCESS:
            continue
        frames = []
        resolved = stream.resolve(stack_el)
        inner = resolved.find("backtrace")
        if inner is None:
            inner = resolved
        for frame_el in inner.findall("frame"):
            frame = stream.resolve(frame_el)
            binary_el = frame.find("binary")
            binary = stream.resolve(binary_el) if binary_el is not None else None
            frames.append(
                {
                    "name": frame.get("name") or "",
                    "addr": frame.get("addr") or "",
                    "binary": binary.get("name") if binary is not None else None,
                    "load": binary.get("load-addr") if binary is not None else None,
                }
            )
        weight_el = row.get("weight")
        samples.append(
            {
                "t": xml_utils.int_text(stream.resolve(time_el)) or 0,
                "w": (
                    xml_utils.int_text(stream.resolve(weight_el)) if weight_el is not None else None
                )
                or 1_000_000,
                "main": thread["is_main"],
                "frames": frames,
            }
        )
    samples.sort(key=lambda s: s["t"])
    return samples


def symbolicate(samples: list[dict], symbolicator: Symbolicator) -> None:
    pending: dict[str, set[str]] = defaultdict(set)
    for sample in samples:
        for frame in sample["frames"]:
            if (
                frame["binary"] == PROCESS
                and frame["load"]
                and (not frame["name"] or frame["name"].startswith("0x"))
            ):
                pending[frame["load"]].add(frame["addr"])
    symbolicator.resolve(pending)
    for sample in samples:
        names = []
        for frame in sample["frames"]:
            name = frame["name"]
            if frame["binary"] == PROCESS and frame["load"] and (not name or name.startswith("0x")):
                name = symbolicator.cache.get((frame["load"], frame["addr"]), name or frame["addr"])
            names.append(name or frame["addr"])
        sample["names"] = names
        sample["app"] = [
            n for n, f in zip(names, sample["frames"], strict=False) if f["binary"] == PROCESS
        ]


# MARK: - Tables counted per window


def count_rows(trace: Path, run: int, schema: str, xctrace, xml_utils) -> list[int]:
    """Start times of every row of `schema` in the app's process."""
    stream = xml_utils.RowStream(xctrace.export_schema(trace, schema, run=run))
    times = []
    for row in stream:
        time_el = xml_utils.first_present(row, "start", "time", "timestamp")
        if time_el is None:
            continue
        process_el = row.get("process")
        if process_el is not None and xml_utils.extract_process(process_el, stream).get(
            "name"
        ) not in (PROCESS, None, ""):
            continue
        value = xml_utils.int_text(stream.resolve(time_el))
        if value is not None:
            times.append(value)
    return sorted(times)


def hangs(trace: Path, run: int, xctrace, xml_utils) -> list[tuple[int, int]]:
    stream = xml_utils.RowStream(xctrace.export_schema(trace, "potential-hangs", run=run))
    out = []
    for row in stream:
        start, duration = row.get("start"), row.get("duration")
        if start is None or duration is None:
            continue
        thread_el = row.get("thread")
        if thread_el is not None and (
            xml_utils.extract_thread(thread_el, stream).get("process") or {}
        ).get("name") not in (PROCESS, None):
            continue
        out.append(
            (
                xml_utils.int_text(stream.resolve(start)) or 0,
                xml_utils.int_text(stream.resolve(duration)) or 0,
            )
        )
    return out


def swiftui_updates(
    trace: Path, run: int, schemas: frozenset[str], xctrace, xml_utils
) -> list[tuple[int, str]] | None:
    if "swiftui-updates" not in schemas:
        return None
    stream = xml_utils.RowStream(xctrace.export_schema(trace, "swiftui-updates", run=run))
    out = []
    for row in stream:
        time_el = xml_utils.first_present(row, "start", "time")
        desc_el = xml_utils.first_present(row, "description", "view-name", "name")
        if time_el is None or desc_el is None:
            continue
        description = (
            xml_utils.str_text(stream.resolve(desc_el)) or stream.resolve(desc_el).get("fmt") or ""
        )
        if description.endswith(".body") or "body" in description:
            out.append((xml_utils.int_text(stream.resolve(time_el)) or 0, description))
    return out


# MARK: - Per step


def repeated_work(main: list[dict], watch: list[str]) -> dict[str, dict]:
    """Per watched pattern: bursts (entries) and time of main samples carrying it."""
    out = {}
    for pattern in watch:
        entries, total, inside = 0, 0, False
        for sample in main:
            hit = any(pattern in name for name in sample["names"])
            if hit:
                total += sample["w"]
                if not inside:
                    entries += 1
            inside = hit
        if entries:
            out[pattern] = {"entries": entries, "ms": round(total / 1e6, 1)}
    return out


# Frames on every stack, or the linker's folded copies that name nothing.
ROOT_FRAMES = ("main", "static PiruApp.$main()", "<deduplicated_symbol>")
# The flow harness itself: work it triggers is charged to the app code below it.
HARNESS = ("PerfDriver", "PerfTour", "PerfProbe", "FootprintSampler", "RunLoopStallMonitor")


def app_frames(sample: dict) -> list[str]:
    return [
        n
        for n in sample["app"]
        if not n.startswith(ROOT_FRAMES) and "$main" not in n and not any(h in n for h in HARNESS)
    ]


def deepest_app(samples: list[dict], limit: int = 3) -> list[str]:
    """The app code under the main thread's CPU time: per sample, the leaf-most
    app frame and its caller, weighted by sample time."""
    paths: Counter = Counter()
    for sample in samples:
        if classify(sample["names"]) != "cpu":
            continue
        frames = app_frames(sample)
        if frames:
            paths[" ← ".join(frames[:3])] += sample["w"]
    return [f"{ms / 1e6:.0f} ms in `{path}`" for path, ms in paths.most_common(limit)]


def top_stack(samples: list[dict], symbol: str, depth: int = 6) -> str:
    stacks = Counter()
    for sample in samples:
        if symbol in sample["names"]:
            index = sample["names"].index(symbol)
            app = [n for n in sample["names"][index:] if n in sample["app"]][:depth]
            stacks[" ← ".join([symbol, *[a for a in app if a != symbol]][:depth])] += sample["w"]
    return stacks.most_common(1)[0][0] if stacks else symbol


def analyze(trace: Path, steps: list[dict], meta: dict, th: dict, findings) -> dict:
    parsed = _parser()
    if parsed is None:
        return {
            "available": False,
            "notes": [
                "instruments_parser not found: set PIRU_INSTRUMENTS_PARSER to the swiftui-specialist skill's scripts folder."
            ],
        }
    events, xctrace, xml_utils = parsed
    info = xctrace.toc(trace)
    run = info.runs[-1].number
    schemas = info.runs[-1].schemas
    notes = []

    signpost_data = events.list_signposts(trace, schemas, run=run)
    signposts = signpost_data["intervals"]
    # The paired begin/end rows can come back twice; one window per step.
    windows = sorted(
        {
            (i["start_ns"], i["end_ns"])
            for i in signposts
            if i.get("name") == "step" and (i.get("subsystem") or "").endswith(".perf")
        },
    )
    if len(windows) != len(steps):
        notes.append(f"{len(windows)} step signposts for {len(steps)} steps; matched in order.")

    samples = read_samples(trace, run, xctrace, xml_utils) if "time-profile" in schemas else []
    symbolicate(samples, Symbolicator(meta.get("dsym")))
    samples = [s for s in samples if not any(t in n for n in s["names"] for t in TRACING_FRAMES)]
    hang_rows = hangs(trace, run, xctrace, xml_utils) if "potential-hangs" in schemas else []
    tables = {}
    for label, candidates in {
        "fetches": ("core-data-fetch", "coredata-fetch", "core-data-fetches"),
        "saves": ("core-data-save", "coredata-save", "core-data-saves"),
        "faults": ("core-data-fault", "coredata-fault", "core-data-faults"),
    }.items():
        schema = next((s for s in candidates if s in schemas), None) or next(
            (s for s in schemas if label[:-1] in s and ("core-data" in s or "coredata" in s)), None
        )
        if schema:
            tables[label] = count_rows(trace, run, schema, xctrace, xml_utils)
    body = swiftui_updates(trace, run, schemas, xctrace, xml_utils)
    if body is None:
        notes.append(
            "No SwiftUI body updates in this trace (the SwiftUI instrument records only on a device or the Mac; pass --swiftui there)."
        )

    watch = th["repeated_work"]["watch"]
    rw = th["repeated_work"]
    whole_self: Counter = Counter()
    whole_inclusive: Counter = Counter()
    for step, (start, end) in zip(steps, windows, strict=False):
        inside = [s for s in samples if start <= s["t"] <= end]
        main = [s for s in inside if s["main"]]
        classes = Counter()
        for sample in main:
            classes[classify(sample["names"])] += sample["w"]
        self_time: Counter = Counter()
        inclusive: Counter = Counter()
        for sample in main:
            if classify(sample["names"]) != "cpu":
                continue
            self_time[sample["names"][0] if sample["names"] else "?"] += sample["w"]
            for name in set(app_frames(sample)):
                inclusive[name] += sample["w"]
        whole_self.update(self_time)
        whole_inclusive.update(inclusive)
        wall = max(end - start, 1)
        step_hang_rows = [(t, d) for (t, d) in hang_rows if start <= t <= end]
        step_hangs = [d for (_, d) in step_hang_rows]
        worst = max(step_hang_rows, key=lambda row: row[1], default=None)
        in_hang = [m for m in main if worst[0] <= m["t"] <= worst[0] + worst[1]] if worst else []
        hang_stacks = deepest_app(in_hang)
        # Time Profiler samples a thread only while it runs: a hang the main
        # thread spent mostly off the CPU was blocked, or starved by host load.
        hang_cpu_ms = sum(m["w"] for m in in_hang if classify(m["names"]) == "cpu") / 1e6
        hotspots = deepest_app(main, 5)
        counts = {
            name: len([t for t in times if start <= t <= end]) for name, times in tables.items()
        }
        if body is not None:
            views = Counter(d for (t, d) in body if start <= t <= end)
            counts["body_updates"] = sum(views.values())
            step_views = views.most_common(8)
        else:
            step_views = []
        repeated = repeated_work(main, watch)
        step["trace"] = {
            "window_ms": round(wall / 1e6, 1),
            "main_cpu_ms": round(classes["cpu"] / 1e6, 1),
            "main_wait_ms": round(classes["wait"] / 1e6, 1),
            "other_threads_cpu_ms": round(
                sum(s["w"] for s in inside if not s["main"] and classify(s["names"]) == "cpu")
                / 1e6,
                1,
            ),
            "hangs": len(step_hangs),
            "longest_hang_ms": round(max(step_hangs, default=0) / 1e6, 1),
            "counts": counts,
            "top_self": [
                {"symbol": k, "ms": round(v / 1e6, 1)} for k, v in self_time.most_common(5)
            ],
            "top_inclusive": [
                {"symbol": k, "ms": round(v / 1e6, 1)} for k, v in inclusive.most_common(8)
            ],
            "repeated": repeated,
            "views": [{"view": v, "updates": n} for v, n in step_views],
            "app_hotspots": hotspots,
            "worst_hang_stacks": hang_stacks,
            "worst_hang_cpu_ms": round(hang_cpu_ms, 1),
        }
        key = step["key"]
        stacks = hotspots[:3]
        findings.check(
            "main-thread",
            key,
            "trace.longest_hang_ms",
            step["trace"]["longest_hang_ms"],
            {"warn": th["main_thread"]["hitch_ms"], "fail": th["main_thread"]["hang_ms"]},
            f"{len(step_hangs)} hangs reported by the Hangs instrument; the main thread was on the CPU "
            f"for {hang_cpu_ms:.0f} ms of the worst ({'CPU-bound' if worst and hang_cpu_ms * 1e6 >= 0.5 * worst[1] else 'mostly blocked or starved'}); "
            + ("app code under it" if hang_stacks else "app code in the step"),
            hang_stacks or stacks,
        )
        findings.check(
            "thread",
            key,
            "trace.main_wait_share",
            step["trace"]["main_wait_ms"] / max(step["trace"]["window_ms"], 1),
            th["thread"]["main_wait_share"],
            f"{step['trace']['main_wait_ms']:.0f} ms of the main thread blocked (locks, I/O, IPC)",
            stacks,
        )
        for name, limits in (
            ("fetches", th["data"]["fetches_per_step"]),
            ("saves", th["data"]["saves_per_step"]),
            ("faults", th["data"]["faults_per_step"]),
        ):
            if name in counts:
                findings.check(
                    "data",
                    key,
                    f"trace.{name}",
                    counts[name],
                    limits,
                    f"Core Data {name} (SwiftData)",
                )
        if "body_updates" in counts:
            findings.check(
                "swiftui",
                key,
                "trace.body_updates",
                counts["body_updates"],
                th["swiftui"]["body_updates_per_step"],
                ", ".join(f"{v} ×{n}" for v, n in step_views[:4]),
            )
            if step_views:
                findings.check(
                    "swiftui",
                    key,
                    "trace.single_view_updates",
                    step_views[0][1],
                    th["swiftui"]["single_view_updates_per_step"],
                    step_views[0][0],
                )
        for pattern, hit in repeated.items():
            if hit["entries"] >= rw["min_entries"] and hit["ms"] >= rw["min_total_ms"]:
                findings.check(
                    "repeated-work",
                    key,
                    f"repeated.{pattern}",
                    hit["ms"],
                    {"warn": rw["min_total_ms"], "fail": rw["fail_total_ms"]},
                    f"entered {hit['entries']} times on the main thread ({hit['ms']:.0f} ms): a cache missed or bypassed",
                    [
                        top_stack(
                            main,
                            next((n for s in main for n in s["names"] if pattern in n), pattern),
                        )
                    ],
                )
    launch = {}
    marks = {
        e["name"]: e["time_ns"]
        for e in signpost_data["events"]
        if (e.get("subsystem") or "").endswith(".perf")
    }
    if samples:
        first = samples[0]["t"]
        for name in ("catalogWarm", "interactive"):
            if name in marks:
                launch[f"first_sample_to_{name}_ms"] = round((marks[name] - first) / 1e6, 1)
    return {
        "available": True,
        "launch": launch,
        "run": run,
        "samples": len(samples),
        "schemas": sorted(schemas),
        "top_self": [{"symbol": k, "ms": round(v / 1e6, 1)} for k, v in whole_self.most_common(20)],
        "top_inclusive": [
            {"symbol": k, "ms": round(v / 1e6, 1)} for k, v in whole_inclusive.most_common(20)
        ],
        "notes": notes,
    }
