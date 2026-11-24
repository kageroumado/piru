#!/usr/bin/env python3
"""Run a perf scenario end to end and leave a report.

    pipeline/perf/run.py                                   # heavy fixture, every flow, iOS simulator
    pipeline/perf/run.py --fixture stress --flows journal-scroll,quicklog --loops 3
    pipeline/perf/run.py --no-build --baseline <root>/<run>/report.json
    pipeline/perf/run.py --ci                              # the CI subset and gate (see README)
    pipeline/perf/run.py --platform android --apk app-release.apk

Writes `<root>/<run>/report.md` and `report.json`; `<root>` is
`$PIRU_PERF_ROOT`, else `$TMPDIR/piru-perf`. Exits 1 when a finding reaches
failure level (or, with `--baseline`, a metric regressed past its tolerance).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze  # noqa: E402

CI_FLOWS = ["journal-scroll", "open-close", "quicklog", "library-search", "tab-storm"]


def output_root() -> Path:
    if os.environ.get("PIRU_PERF_ROOT"):
        return Path(os.environ["PIRU_PERF_ROOT"])
    return Path(tempfile.gettempdir()) / "piru-perf"


def parse(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--platform", choices=["ios", "android"], default="ios")
    parser.add_argument(
        "--fixture",
        default="heavy",
        help="heavy, dailyMeds, customData, profiles, hormones, stress, empty",
    )
    parser.add_argument(
        "--flows", default="all", help="comma-separated flow names (default: every flow)"
    )
    parser.add_argument(
        "--loops",
        type=int,
        default=1,
        help="passes over the flow list; memory growth is read across them",
    )
    parser.add_argument("--no-build", action="store_true", help="install the app already built")
    parser.add_argument(
        "--no-trace", action="store_true", help="in-app readings only, no Instruments recording"
    )
    parser.add_argument("--keep-trace", action="store_true", help="keep the .trace after analysis")
    parser.add_argument(
        "--swiftui",
        action="store_true",
        help="add the SwiftUI instrument (body counts; device only)",
    )
    parser.add_argument(
        "--instrument", action="append", default=[], help="extra Instruments instrument to record"
    )
    parser.add_argument("--simulator", default=None, help="simulator name (default 'Piru Perf')")
    parser.add_argument(
        "--baseline", type=Path, help="report.json of an earlier run to compare against"
    )
    parser.add_argument(
        "--thresholds", type=Path, default=Path(__file__).with_name("thresholds.json")
    )
    parser.add_argument(
        "--now",
        default=None,
        help="pinned present for fixture and app (ISO 8601; default today 14:00 local)",
    )
    parser.add_argument("--timeout", type=float, default=1800, help="seconds the flows may take")
    parser.add_argument(
        "--ci", action="store_true", help="the CI subset: fixed flows, no trace, deterministic gate"
    )
    parser.add_argument(
        "--apk", type=Path, help="Android: the APK to install (release, debug-signed)"
    )
    parser.add_argument(
        "--android-store",
        type=Path,
        help="Android: a store file to install first (rooted emulator)",
    )
    parser.add_argument(
        "--simpleperf",
        action="store_true",
        help="Android: record stacks with simpleperf (needs adb root)",
    )
    parser.add_argument("--analyze-only", type=Path, help="re-analyze an existing run directory")
    args = parser.parse_args(argv)
    if args.ci:
        args.flows = ",".join(CI_FLOWS)
        args.no_trace = True
    return args


def default_now() -> str:
    today = dt.datetime.now().astimezone().replace(hour=14, minute=0, second=0, microsecond=0)
    return today.isoformat(timespec="seconds")


def main(argv: list[str] | None = None) -> int:
    args = parse(argv)
    thresholds = json.loads(args.thresholds.read_text())
    if args.analyze_only:
        return analyze.main(
            ["--run", str(args.analyze_only), "--thresholds", str(args.thresholds)]
            + (["--baseline", str(args.baseline)] if args.baseline else [])
            + (["--ci"] if args.ci else [])
        )

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = output_root() / f"{stamp}-{args.platform}-{args.fixture}"
    run_dir.mkdir(parents=True, exist_ok=True)
    flows = [] if args.flows == "all" else [f for f in args.flows.split(",") if f]
    meta = {
        "platform": args.platform,
        "fixture": args.fixture,
        "flows": flows or "all",
        "loops": args.loops,
        "started": stamp,
    }

    if args.platform == "ios":
        import ios

        name = args.simulator or ios.SIMULATOR_NAME
        udid = ios.simulator(name)
        destination = f"platform=iOS Simulator,id={udid}"
        if not args.no_build:
            ios.build(destination)
        app = ios.app_path(destination)
        if not app.exists():
            sys.exit(f"no app at {app}; build first or drop --no-build")
        ios.install(udid, app)
        plan = ios.LaunchPlan(
            udid=udid,
            bundle=ios.bundle_id(app),
            app=app,
            run_dir=run_dir,
            fixture=args.fixture,
            flows=flows,
            loops=args.loops,
            now=args.now or default_now(),
            extra=[],
        )
        meta.update({"device": name, "udid": udid, "app": str(app), "now": plan.now})
        meta["seed"] = ios.seed(plan)
        trace = None if args.no_trace else run_dir / "flows.trace"
        instruments = (
            ios.DEFAULT_INSTRUMENTS + (["SwiftUI"] if args.swiftui else []) + args.instrument
        )
        meta["instruments"] = [] if trace is None else ["Time Profiler", *instruments]
        recording_started = time.time()
        finished = ios.record(plan, trace, instruments, args.timeout)
        meta["finished"] = finished
        crash = ios.find_crash(udid, recording_started)
        if crash:
            progress = run_dir / "app" / "progress.json"
            crash["step"] = (
                json.loads(progress.read_text()).get("step") if progress.exists() else None
            )
            meta["crash"] = crash
        if trace is not None and trace.exists():
            meta["trace"] = str(trace)
            dsym = ios.dsym_path(app)
            meta["dsym"] = str(dsym) if dsym else None
    else:
        import android

        meta.update(android.run(run_dir, args, thresholds))
        finished = meta.get("finished", False)

    (run_dir / "meta.json").write_text(json.dumps(meta, indent=2, sort_keys=True))
    analyze_args = ["--run", str(run_dir), "--thresholds", str(args.thresholds)]
    if args.baseline:
        analyze_args += ["--baseline", str(args.baseline)]
    if args.ci:
        analyze_args.append("--ci")
    status = analyze.main(analyze_args)
    if args.platform == "ios" and meta.get("trace") and not args.keep_trace:
        import ios

        ios.remove_trace(Path(meta["trace"]))
    if not finished:
        print(
            "[perf] the flows did not finish: the report covers the steps that ran", file=sys.stderr
        )
        status = status or 2
    print(f"[perf] report: {run_dir / 'report.md'}")
    return status


if __name__ == "__main__":
    sys.exit(main())
