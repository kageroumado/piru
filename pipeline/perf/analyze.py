#!/usr/bin/env python3
"""Turn a perf run into findings: `report.json` (stable keys) and `report.md`.

    pipeline/perf/analyze.py --run <run dir> [--baseline <report.json>] [--ci]

Reads the app's own readings (`app/steps.json`: CPU, footprint, run-loop
stalls, counters) and, when the run recorded one, the Instruments trace
(`trace.py`: per-step samples, hangs, Core Data counts, SwiftUI updates).
Each metric is held against `thresholds.json`; a finding is `warn` or `fail`.
Exit status: 1 on any `fail` (or a baseline regression), else 0.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

SCHEMA_VERSION = 1


def level(value: float | None, limits: dict | None) -> str | None:
    if value is None or not limits:
        return None
    if "fail" in limits and value >= limits["fail"]:
        return "fail"
    if "warn" in limits and value >= limits["warn"]:
        return "warn"
    return None


class Findings:
    def __init__(self) -> None:
        self.items: list[dict] = []

    def check(
        self,
        kind: str,
        step: str,
        metric: str,
        value,
        limits: dict | None,
        detail: str = "",
        stacks=None,
    ) -> None:
        verdict = level(value, limits)
        if verdict is None:
            return
        threshold = limits[verdict]
        self.items.append(
            {
                "level": verdict,
                "kind": kind,
                "step": step,
                "metric": metric,
                "value": round(value, 2) if isinstance(value, float) else value,
                "threshold": threshold,
                "ratio": round(value / threshold, 2) if threshold else None,
                "detail": detail,
                "stacks": stacks or [],
            }
        )

    def sorted(self) -> list[dict]:
        order = {"fail": 0, "warn": 1, "info": 2}
        return sorted(self.items, key=lambda f: (order[f["level"]], -(f["ratio"] or 0)))


def step_key(step: dict) -> str:
    return f"{step['flow']}/{step['step']}#{step['loop']}"


# MARK: - In-app lane


def inapp_metrics(step: dict, th: dict) -> dict:
    stalls = step.get("stalls", [])
    hitch, hang = th["main_thread"]["hitch_ms"], th["main_thread"]["hang_ms"]
    over_hitch = [s["durationMs"] for s in stalls if s["durationMs"] >= hitch]
    wall = max(step["wallMs"], 1)
    return {
        "wall_ms": round(step["wallMs"], 1),
        "main_cpu_ms": round(step["mainCPUMs"], 1),
        "process_cpu_ms": round(step["processCPUMs"], 1),
        "main_cpu_share": round(step["mainCPUMs"] / wall, 3),
        "hitches": len([d for d in over_hitch if d < hang]),
        "hangs": len([d for d in over_hitch if d >= hang]),
        "longest_stall_ms": round(max([s["durationMs"] for s in stalls], default=0), 1),
        "total_stall_ms": round(sum(over_hitch), 1),
        "footprint_start_mb": round(step["footprintStartMB"], 1),
        "footprint_end_mb": round(step["footprintEndMB"], 1),
        "footprint_peak_mb": round(step["footprintPeakMB"], 1),
        "footprint_growth_mb": round(step["footprintEndMB"] - step["footprintStartMB"], 1),
        "voluntary_switches": step["voluntarySwitches"],
        "involuntary_switches": step["involuntarySwitches"],
        "involuntary_switches_per_s": round(step["involuntarySwitches"] / (wall / 1000), 1),
        "counters": dict(sorted(step.get("counters", {}).items())),
    }


def check_inapp(key: str, m: dict, th: dict, findings: Findings) -> None:
    findings.check(
        "main-thread",
        key,
        "longest_stall_ms",
        m["longest_stall_ms"],
        {"warn": th["main_thread"]["hitch_ms"], "fail": th["main_thread"]["hang_ms"]},
        f"{m['hangs']} hangs, {m['hitches']} hitches, {m['total_stall_ms']:.0f} ms stalled",
    )
    findings.check(
        "main-thread",
        key,
        "total_stall_ms",
        m["total_stall_ms"],
        th["main_thread"]["total_stall_ms_per_step"],
    )
    findings.check(
        "cpu",
        key,
        "main_cpu_ms",
        m["main_cpu_ms"],
        th["cpu"]["main_cpu_ms_per_step"],
        f"{m['main_cpu_share']:.0%} of {m['wall_ms']:.0f} ms wall",
    )
    findings.check(
        "cpu",
        key,
        "main_cpu_share",
        m["main_cpu_share"],
        th["cpu"]["main_cpu_share"],
        f"{m['main_cpu_ms']:.0f} ms of {m['wall_ms']:.0f} ms",
    )
    findings.check(
        "memory", key, "footprint_peak_mb", m["footprint_peak_mb"], th["memory"]["peak_mb"]
    )
    findings.check(
        "memory",
        key,
        "footprint_growth_mb",
        m["footprint_growth_mb"],
        th["memory"]["step_growth_mb"],
    )
    findings.check(
        "thread",
        key,
        "involuntary_switches_per_s",
        m["involuntary_switches_per_s"],
        th["thread"]["involuntary_switches_per_s"],
    )
    for counter, value in m["counters"].items():
        findings.check(
            "cache",
            key,
            f"counter.{counter}",
            value,
            th["counters"].get(counter),
            _counter_detail(counter),
        )


def _counter_detail(counter: str) -> str:
    return {
        "resolveFull": "full per-field resolves (~21 SQL each); belongs on detail screens only",
        "lookup.batchMiss": "lookups that missed the batch cache and fell through to the heavy resolve",
        "lookup": "overlay-aware catalog lookups",
    }.get(counter, "statements run on this connection" if counter.startswith("sql.") else "")


def loop_growth(steps: list[dict], th: dict, findings: Findings) -> dict:
    """Footprint growth per pass over the flows, by step: a leak or an unbounded cache."""
    by_step: dict[str, list[tuple[int, float]]] = defaultdict(list)
    for step in steps:
        by_step[f"{step['flow']}/{step['step']}"].append((step["loop"], step["footprintEndMB"]))
    growth = {}
    for name, readings in by_step.items():
        if len(readings) < 2:
            continue
        readings.sort()
        per_loop = (readings[-1][1] - readings[0][1]) / (readings[-1][0] - readings[0][0])
        growth[name] = round(per_loop, 1)
        findings.check(
            "memory",
            name,
            "loop_growth_mb",
            per_loop,
            th["memory"]["loop_growth_mb"],
            f"footprint after this step: {' → '.join(f'{r[1]:.0f}' for r in readings)} MB",
        )
    return growth


# MARK: - Report


def analyze_run(run_dir: Path, th: dict, ci: bool) -> dict:
    meta = (
        json.loads((run_dir / "meta.json").read_text()) if (run_dir / "meta.json").exists() else {}
    )
    if meta.get("platform") == "android":
        import android

        return android.analyze(run_dir, meta, th)
    steps_path = run_dir / "app" / "steps.json"
    app = json.loads(steps_path.read_text()) if steps_path.exists() else {"steps": []}
    findings = Findings()
    steps = []
    for raw in app.get("steps", []):
        key = step_key(raw)
        metrics = inapp_metrics(raw, th)
        check_inapp(key, metrics, th, findings)
        steps.append(
            {
                "key": key,
                "flow": raw["flow"],
                "step": raw["step"],
                "loop": raw["loop"],
                "note": raw.get("note"),
                "metrics": metrics,
            }
        )

    launch = app.get("launch") or {}
    growth = loop_growth(app.get("steps", []), th, findings)

    trace_summary = None
    trace_path = Path(meta["trace"]) if meta.get("trace") else None
    if trace_path and trace_path.exists():
        import tracelane

        trace_summary = tracelane.analyze(trace_path, steps, meta, th, findings)
        # In-app findings carry the trace's app hotspots for their step.
        by_key = {s["key"]: s for s in steps}
        for item in findings.items:
            step = by_key.get(item["step"])
            if not item["stacks"] and step and step.get("trace"):
                item["stacks"] = step["trace"]["app_hotspots"][:3]

    # A process launched under xctrace sits suspended before it runs, so the
    # kernel start time is meaningless there; the trace's first sample is the start.
    traced = (trace_summary or {}).get("launch") or {}
    launch_metrics = {
        "to_interactive_ms": traced.get("first_sample_to_interactive_ms")
        if trace_path
        else launch.get("toInteractiveMs"),
        "to_catalog_warm_ms": traced.get("first_sample_to_catalogWarm_ms")
        if trace_path
        else launch.get("toCatalogWarmMs"),
    }
    findings.check(
        "launch",
        "launch",
        "to_interactive_ms",
        launch_metrics["to_interactive_ms"],
        th["launch"]["to_interactive_ms"],
        "process start to the first idle main run loop over a warm catalog",
    )
    findings.check(
        "launch",
        "launch",
        "to_catalog_warm_ms",
        launch_metrics["to_catalog_warm_ms"],
        th["launch"]["to_catalog_warm_ms"],
    )

    crash = meta.get("crash")
    if crash:
        findings.items.append(
            {
                "level": "fail",
                "kind": "crash",
                "step": crash.get("step") or "?",
                "metric": "crash",
                "value": 1,
                "threshold": 1,
                "ratio": 99.0,
                "detail": f"the app crashed ({(crash.get('exception') or {}).get('type', '?')}); report {crash.get('report')}",
                "stacks": crash.get("frames", [])[:8],
            }
        )

    if ci:
        gate = set(th["ci"]["gate_counters"])
        for item in findings.items:
            gated = (
                item["kind"] == "crash"
                or (
                    item["metric"].startswith("counter.")
                    and item["metric"][len("counter.") :] in gate
                )
                or (item["metric"] == "longest_stall_ms" and item["value"] >= th["ci"]["hang_ms"])
            )
            if not gated:
                item["level"] = "info"

    ordered = findings.sorted()
    return {
        "schema": SCHEMA_VERSION,
        "run": meta,
        "fixture": app.get("fixture") or meta.get("fixture"),
        "configuration": app.get("configuration"),
        "launch": {
            "to_catalog_warm_ms": _round(launch_metrics["to_catalog_warm_ms"]),
            "to_interactive_ms": _round(launch_metrics["to_interactive_ms"]),
            "hook_to_interactive_ms": _round(launch.get("hookToInteractiveMs")),
            "footprint_mb": _round(launch.get("footprintMB")),
        },
        "steps": steps,
        "loop_growth_mb": growth,
        "trace": trace_summary,
        "findings": ordered,
        "status": "fail"
        if any(f["level"] == "fail" for f in ordered)
        else ("warn" if any(f["level"] == "warn" for f in ordered) else "pass"),
        "seconds": app.get("seconds"),
    }


def _round(value):
    return round(value, 1) if isinstance(value, (int, float)) else None


# MARK: - Baseline


def flatten(report: dict) -> dict[str, tuple[str, float]]:
    """`<step>.<metric>` → (class, value) for every comparable number."""
    out: dict[str, tuple[str, float]] = {}
    for key, value in (report.get("launch") or {}).items():
        if isinstance(value, (int, float)):
            out[f"launch.{key}"] = ("memory_mb" if key.endswith("_mb") else "time_ms", value)
    for step in report.get("steps", []):
        metrics = dict(step.get("metrics", {}))
        for name, value in metrics.pop("counters", {}).items():
            out[f"{step['key']}.counter.{name}"] = ("count", value)
        for name, value in (step.get("trace") or {}).get("counts", {}).items():
            out[f"{step['key']}.trace.{name}"] = ("count", value)
        for name, value in metrics.items():
            if (
                not isinstance(value, (int, float))
                or name.endswith("_share")
                or name.endswith("_per_s")
                or name.endswith("_switches")
            ):
                continue
            cls = (
                "memory_mb"
                if name.endswith("_mb")
                else ("time_ms" if name.endswith("_ms") else "count")
            )
            out[f"{step['key']}.{name}"] = (cls, value)
    return out


def compare(report: dict, baseline: dict, th: dict) -> list[dict]:
    new, old = flatten(report), flatten(baseline)
    regressions = []
    for key, (cls, value) in new.items():
        if key not in old:
            continue
        base = old[key][1]
        tolerance = th["baseline"][cls]
        limit = base + abs(base) * tolerance["relative"] + tolerance["absolute"]
        if value > limit:
            regressions.append(
                {
                    "metric": key,
                    "class": cls,
                    "baseline": base,
                    "value": value,
                    "limit": round(limit, 2),
                    "change": round(value - base, 2),
                }
            )
    regressions.sort(key=lambda r: -(r["value"] / max(r["limit"], 1e-9)))
    return regressions


# MARK: - Markdown


def markdown(report: dict) -> str:
    run = report.get("run", {})
    lines = [
        f"# Piru perf — {report.get('fixture')} on {run.get('platform', '?')}",
        "",
        f"**Status: {report['status'].upper()}** · {len([f for f in report['findings'] if f['level'] == 'fail'])} failures, "
        f"{len([f for f in report['findings'] if f['level'] == 'warn'])} warnings · {len(report['steps'])} steps · "
        f"build `{report.get('configuration') or '?'}` · device {run.get('device', '?')}",
        "",
    ]
    seed = run.get("seed") or {}
    if seed:
        lines += [
            f"Fixture: {seed.get('doses')} doses, {seed.get('sessions')} sessions, {seed.get('meds')} meds, "
            f"{seed.get('occurrences')} occurrences, {seed.get('inventory')} stock items, {seed.get('labs')} labs, "
            f"{seed.get('customSubstances')} custom substances, {seed.get('profiles')} profiles; seeded in {seed.get('seconds', 0):.1f} s.",
            "",
        ]
    launch = report.get("launch") or {}
    if any(launch.values()):
        lines += [
            "## Launch",
            "",
            "| start to catalog warm | start to interactive | store open to interactive | footprint |",
            "|---|---|---|---|",
            f"| {launch.get('to_catalog_warm_ms')} ms | {launch.get('to_interactive_ms')} ms | {launch.get('hook_to_interactive_ms')} ms | {launch.get('footprint_mb')} MB |",
            "",
        ]
    lines += ["## Findings (worst first)", ""]
    listed = [f for f in report["findings"] if f["level"] != "info"]
    shown = listed[:80]
    if not shown:
        lines.append("None above the thresholds.")
    for f in shown:
        lines.append(
            f"- **{f['level'].upper()}** `{f['step']}` — {f['kind']}: `{f['metric']}` = **{f['value']}** (threshold {f['threshold']}). {f['detail']}"
        )
        for stack in f.get("stacks", [])[:3]:
            lines.append(f"  - {stack}")
    if len(listed) > len(shown):
        lines.append(f"- … {len(listed) - len(shown)} more in `report.json`")
    regressions = report.get("regressions")
    if regressions is not None:
        lines += ["", "## Against the baseline", ""]
        lines += [
            f"- `{r['metric']}`: {r['baseline']} → **{r['value']}** (limit {r['limit']})"
            for r in regressions[:40]
        ] or ["No regressions."]
    if run.get("platform") == "android":
        lines += [
            "",
            "## Flows",
            "",
            "| flow | wall ms | main CPU ms | frames | slow | frozen | p95 ms | worst ms | PSS MB |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        for step in report["steps"]:
            m = step["metrics"]
            lines.append(
                f"| `{step['flow']}` | {m['wall_ms']} | {m['main_cpu_ms']:.0f} | {m['frames']} | {m['slow']} | {m['frozen']} | {m['p95_ms']} | {m['worst_ms']} | {m.get('pss_mb') or 0:.0f} |"
            )
        stacks = (report.get("trace") or {}).get("stacks") or []
        if stacks:
            lines += ["", "## Heaviest symbols (simpleperf)", ""] + [
                f"- `{s}`" for s in stacks[:20]
            ]
        return "\n".join(lines) + "\n"
    lines += [
        "",
        "## Steps",
        "",
        "| step | wall ms | main CPU ms | longest stall ms | hangs | peak MB | Δ MB | counters | trace |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for step in report["steps"]:
        m = step["metrics"]
        counters = ", ".join(f"{k} {v}" for k, v in m["counters"].items())
        tr = step.get("trace") or {}
        trace_cell = ", ".join(f"{k} {v}" for k, v in (tr.get("counts") or {}).items())
        lines.append(
            f"| `{step['key']}` | {m['wall_ms']:.0f} | {m['main_cpu_ms']:.0f} | {m['longest_stall_ms']:.0f} | {m['hangs']} | {m['footprint_peak_mb']:.0f} | {m['footprint_growth_mb']:+.0f} | {counters} | {trace_cell} |"
        )
    if report.get("trace"):
        lines += ["", "## Heaviest functions (whole run, main thread, self time)", ""]
        for row in report["trace"].get("top_self", [])[:15]:
            lines.append(f"- {row['ms']:.0f} ms — `{row['symbol']}`")
        lines += ["", "## Heaviest functions (whole run, main thread, inclusive, app code)", ""]
        for row in report["trace"].get("top_inclusive", [])[:15]:
            lines.append(f"- {row['ms']:.0f} ms — `{row['symbol']}`")
        for note in report["trace"].get("notes", []):
            lines.append(f"\n> {note}")
    notes = [s for s in report["steps"] if s.get("note")]
    if notes:
        lines += ["", "## Step notes", ""] + [f"- `{s['key']}`: {s['note']}" for s in notes]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument(
        "--thresholds", type=Path, default=Path(__file__).with_name("thresholds.json")
    )
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--ci", action="store_true")
    args = parser.parse_args(argv)
    th = json.loads(args.thresholds.read_text())
    report = analyze_run(args.run, th, args.ci)
    status = 1 if report["status"] == "fail" else 0
    if args.baseline:
        report["regressions"] = compare(report, json.loads(args.baseline.read_text()), th)
        if report["regressions"]:
            print(f"[perf] {len(report['regressions'])} regressions against {args.baseline}")
            for r in report["regressions"][:20]:
                print(f"  {r['metric']}: {r['baseline']} → {r['value']} (limit {r['limit']})")
            status = 1
    (args.run / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))
    (args.run / "report.md").write_text(markdown(report))
    fails = [f for f in report["findings"] if f["level"] == "fail"]
    print(
        f"[perf] {report['status']}: {len(fails)} failures, {len([f for f in report['findings'] if f['level'] == 'warn'])} warnings"
    )
    for f in fails[:10]:
        print(f"  FAIL {f['step']} {f['metric']} = {f['value']} (≥ {f['threshold']}) {f['detail']}")
    return status


if __name__ == "__main__":
    sys.exit(main())
