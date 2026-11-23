# `pipeline/perf/` — performance runs

One command seeds a large store, walks scripted user journeys inside the app,
records them with Instruments, and writes a report of what was slow, with
thresholds that pass or fail.

```bash
pipeline/perf/run.py                                         # heavy fixture, every flow, iOS simulator
pipeline/perf/run.py --fixture stress --flows journal-scroll,quicklog --loops 3
pipeline/perf/run.py --no-build --baseline <earlier run>/report.json
pipeline/perf/run.py --analyze-only <run dir>                # re-read a run with new thresholds
pipeline/perf/run.py --ci                                    # the CI subset and gate
pipeline/perf/run.py --platform android --apk app-release-debugsigned.apk
```

The report lands in `<root>/<date>-<platform>-<fixture>/report.md` and
`report.json`. `<root>` is `/Volumes/Ugreen/Scratch/piru-perf` when that disk is
mounted, else `$PIRU_PERF_ROOT`, else `$TMPDIR/piru-perf`; nothing is written in
the repo. The exit status is 1 when a finding reaches failure level, or with
`--baseline` when a metric regressed past its tolerance; 2 when the flows did
not finish.

## How a run goes (iOS)

1. **Build** the `Piru` scheme in the **Debug configuration compiled like
   Release** (`-O`, whole module, no testability, no coverage, dSYM). Debug
   keeps the `#if DEBUG` hooks the flows need; `-Onone` numbers say nothing
   about CPU cost and Release compiles the hooks out. What remains different
   from a shipped build is DEBUG-only code (assertions, the fixtures). On the
   Mac Studio the build goes to `/Volumes/Ugreen/Build/piru/DerivedData-6`.
2. **Simulator** "Piru Perf" (iPhone 18 Pro Max, iOS 27), created on first use.
   `PIRU_PERF_DEVICE_TYPE` and `PIRU_PERF_RUNTIME` override both.
3. **Seed** (`-piruPerfSeedOnly`): one launch wipes the perf store and writes the
   fixture, then writes `app/seeded.json` and is terminated. The perf store is
   `perf.store`, its own file, so a run never touches a development journal.
4. **Record**: a second, cold launch under
   `xctrace record --template "Time Profiler"` plus Hangs, Points of Interest,
   Data Fetches, Data Saves and Data Faults (`--swiftui` adds the SwiftUI
   instrument, which records only on a device or the Mac). The app runs the
   flows and writes `app/steps.json`, then `app/done.json`. A step that makes
   no progress for 240 s ends the run.
5. **Analyze** (`analyze.py`, `tracelane.py`), then move the trace to the Trash
   unless `--keep-trace`.

Every date in a fixture is relative to the pinned present (`--now`, default
today 14:00), and both launches get the same `-piruNow`, so a run reproduces.

## Fixtures (`Piru/Utilities/Perf/PerfFixtures*.swift`)

Selected by `-piruPerfFixture <name>`; seeded rows go in directly with their
sessions assigned, so even 12,000 doses seed in seconds.

| Fixture | What it holds |
|---|---|
| `heavy` | ~5,300 doses over two years across 64 substances: redosed sessions, notes, tags, 12 places with coordinates, food state, grapefruit, approximate doses, brands (Concerta, Adderall, Vyvanse, Xanax…), salts, drinks by volume, a custom unit; three scheduled meds with occurrences and stock |
| `dailyMeds` | ten scheduled meds over 18 months, every routine occurrence (logged, skipped, missed), stock with monthly refills and corrections, three items low |
| `customData` | 15 custom substances with durations, 10 relabels, 8 duration overrides, picked colors, 6 custom units, over a 2,000-dose journal that logs the customs |
| `profiles` | the owner plus three profiles of 1,500 doses each, and 20 nights logged by all four as one shared session |
| `hormones` | two years of injected estradiol (valerate, then cypionate) with rotating sites, daily spironolactone, progesterone, 48 lab values |
| `stress` | 12,000 doses over three years plus the meds and custom layers |
| `empty` | nothing (the import target) |

To add one: a case in `PerfFixtures.Fixture`, a branch in `seed(_:container:)`,
and a generator next to the others. Keep it seeded (`PerfRNG`) and dated from
`DebugClock.now`.

## Flows (`Piru/Utilities/Perf/PerfTour+Flows.swift`)

| Flow | Steps |
|---|---|
| `journal-scroll` | each Journal grouping, scrolled end to end in flings and back |
| `timeline-scroll` | the vertical timeline opened and scrolled end to end |
| `open-close` | the 30 newest entries opened and closed, then the 30 newest sessions |
| `quicklog` | four rounds: open the quick log, type a search, close, commit three doses through `DoseLogService.logBatch` |
| `library-search` | Search typed one character at a time (70 ms apart), three queries |
| `substance-pages` | five substance pages scrolled, their pharmacology page, the dose-source comparison sheet |
| `insights` | the Insights overview and every insight and insight group |
| `stats-ranges` | the Usage model computed for every range over the whole log |
| `tab-storm` | 60 tab switches 50 ms apart |
| `skins` | the skin picker open, every skin worn in turn |
| `profile-switch` | every profile switched to and back, twice |
| `export-import` | the whole store exported, wiped, and the export imported |
| `backup-restore` | a passphrase-sealed backup written, then restored with replace |
| `storms` | 20 settings sheets presented and dismissed fast, double presents, reversed flings |

The cold launch is measured first in every run.

Flows move through `AppNavigator` (tabs, pushes, sheets) and, on iOS, through
the UIKit views SwiftUI hosts (`PerfDriver`: the largest scroll view on the
front sheet, the search field), never screen coordinates. **To add a flow**,
append a `Flow` to `PerfTour.catalog`; each `Step` is an async closure that
returns an optional note for the report. Step names are part of the report's
keys, so a baseline compares only steps whose names did not change.

Each step is an `os_signpost` interval (`glass.kagerou.piru.perf`, Points of
Interest, name `step`) and a row in `steps.json` with what the app measured
itself: wall time, main-thread and process CPU, footprint at start, end and
peak (sampled every 50 ms off the main thread), context switches, every main
run-loop busy span over 50 ms, and counters (`PerfProbe`): SQL statements per
GRDB connection, `SubstanceLibrary.resolveFull` calls, `lookup` calls and
lookups that missed the batch cache.

## What the report checks (`thresholds.json`)

Every number has a `warn` and a `fail` level; edit the file to change them, or
pass `--thresholds <file>`.

| Area | Metric (per step unless named) | warn / fail |
|---|---|---|
| Main thread | longest run-loop stall; hangs from the Hangs instrument | 100 / 250 ms |
| | total stalled time over 100 ms | 500 / 2,000 ms |
| | share of the main thread blocked (locks, I/O, IPC), from the leaf frame | 25 / 60 % |
| CPU | main-thread CPU | 1.5 / 6 s |
| | main-thread CPU as a share of wall time | 60 / 90 % |
| Launch | process start to the first idle run loop over a warm catalog | 2.5 / 6 s |
| Memory | peak footprint | 700 / 1,400 MB |
| | growth across one step; growth per pass with `--loops` | 60 / 250 MB; 25 / 100 MB |
| Threads | involuntary context switches per second | 400 / 2,000 |
| Caches | `resolveFull` calls | 40 / 400 |
| | lookups that missed the batch cache | 1 / 50 |
| | SQL statements per connection | 300 / 3,000 |
| Data | Core Data fetches / saves / faults | 200 / 2,000; 20 / 200; 20k / 200k |
| Repeated work | a watched symbol entered ≥ 15 times in one step on the main thread | ≥ 40 / 400 ms in all |
| SwiftUI | body updates per step; one view's updates per step | 3,000 / 30,000; 500 / 5,000 |
| Android | slow (> 16.7 ms) / frozen (> 700 ms) frame share; cold launch | 15 / 40 %; 1 / 5 %; 2.5 / 6 s |

**Repeated work** is how a missing cache shows up in a sampling profiler: the
analyzer walks the main thread's samples in time order and counts the separate
bursts in which a watched symbol (`repeated_work.watch`: `resolveFull`, GRDB
statements, `ImageRenderer`, `ModelContext.fetch`, date formatters, the PK and
effect engines, JSON coding) is on the stack. Add a symbol to the list to watch
it.

## Reading the report

`report.md`, top to bottom: the status line, the fixture, launch times, the
findings worst first (each with its step, the number, the threshold and the
heaviest frames), regressions against the baseline, a table of every step, and
the heaviest functions on the main thread over the whole run by self and by
inclusive time. `report.json` has the same under stable keys: `steps[].key` is
`<flow>/<step>#<loop>`, `steps[].metrics` the in-app readings,
`steps[].trace` the trace readings, `findings[]` with `level`, `kind`, `step`,
`metric`, `value`, `threshold`.

Timings taken while other builds or simulators run are noisy: compare runs
taken under the same load, and read counts before times.

The trace lane uses the `swiftui-specialist` skill's `instruments_parser`
(found through `$PIRU_INSTRUMENTS_PARSER` or the skill's install path). The
main thread's time is classified by its leaf frame, because the thread-state
column calls a thread parked in the run loop "Running"; samples carrying the
SwiftUI instrument's own tracing frames are discounted. App frames the export
leaves unsymbolicated are resolved with `atos` against the build's dSYM.

## Baselines

`--baseline <report.json>` compares every step metric by key: a metric
regresses when `new > base × (1 + relative) + absolute` (`baseline` in
`thresholds.json`: counts 10 % + 2, times 30 % + 30 ms, memory 20 % + 15 MB).

## CI

`.github/workflows/perf.yml` runs on demand only (`workflow_dispatch`, a fixture
to pick). It runs `run.py --ci`: the flows `journal-scroll`, `open-close`,
`quicklog`, `library-search` and `tab-storm`, no Instruments recording, on the
runner's newest simulator. The gate is what does not depend on machine speed:
the cache counters (`resolveFull`, batch-cache misses, SQL statements per
connection) at their fail levels, and any main-thread stall over 2 s. Every
other finding is reported as `info`. The report and `steps.json` are uploaded
as an artifact.

## Android

The Android app compiles the Swift source in its release configuration, which
has no DEBUG hooks, so `--platform android` measures from outside the process
over `adb`: three cold starts (`am start -W -S`), then per flow
(`journal-scroll`, `tab-storm`, `library-search`, `reversed-flings`, driven by
`adb shell input`) the frames from `dumpsys gfxinfo framestats`, main-thread CPU
from `/proc`, and PSS; `--simpleperf` adds `simpleperf record -g` stacks (needs
`adb root`). It drives whatever store the app holds: install a fixture store
first (the 2k–12k matrix recipe pushes one with `su 0`). Measure a release APK
re-signed with the debug key, on a headless emulator (`-no-window -gpu host`),
with no build running on the host.
