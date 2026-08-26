#!/usr/bin/env bash
# Run the Piru test suite with a hard cutoff, so a wedged run costs seconds
# rather than the rest of the afternoon.
#
# Two independent cutoffs, because the two failure modes are different:
#
#   · per-test  — xcodebuild's own `-test-timeouts-enabled`. A single test that
#     hangs fails that test and the run continues. Covers a real bug in a test.
#   · whole-run — the wall-clock cap below. Covers the failure this repo actually
#     hits: the test host never pairs with `testmanagerd` and NOTHING runs, so no
#     per-test timeout ever fires and xcodebuild sits there indefinitely. See the
#     `xcode-test-hang-lldb-attach` memory. When that happens the log has no
#     `Test Suite` line at all, which is how this script tells "hung" from "slow".
#
# Usage:
#   pipeline/run-tests.sh                 # full suite
#   pipeline/run-tests.sh -only SomeSuite # one suite (repeatable)
#   RUN_TIMEOUT=600 pipeline/run-tests.sh # raise the whole-run cap (default 300s)
set -uo pipefail

RUN_TIMEOUT="${RUN_TIMEOUT:-180}"     # whole-run wall clock, seconds (healthy ≈ 17s)
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-45}"  # seconds of silence before calling it wedged
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"    # per-test allowance, seconds
SIM_NAME="${SIM_NAME:-iPhone 17 Pro Max}"
SIM_OS="${SIM_OS:-26.5}"              # never float to a beta — see ios27-beta-unstable
APP_BUNDLE_ID="${APP_BUNDLE_ID:-dev.yumeji.piru}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

only_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -only) only_args+=("-only-testing:PiruTests/$2"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Which DerivedData belongs to THIS checkout. Every `Piru-<hash>` directory that
# has ever been built carries an `info.plist` naming the project it was built
# from, so the answer is exact and costs a plist read — no `xcodebuild
# -showBuildSettings` round trip.
#
# The filter is the whole point. Worktrees and second clones all produce
# `Piru-*` directories, so an unfiltered newest-by-mtime glob happily hands one
# checkout another's binary: the run goes green, none of the caller's tests were
# in it, and nothing says so. Set DERIVED_DATA to point at an explicit
# `-derivedDataPath` build instead.
if [[ -n "${DERIVED_DATA:-}" ]]; then
  roots=("$DERIVED_DATA")
else
  roots=()
  for candidate in ~/Library/Developer/Xcode/DerivedData/Piru-*/; do
    workspace="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' \
      "$candidate/info.plist" 2>/dev/null)" || continue
    [[ "$workspace" == "$REPO/"* ]] && roots+=("$candidate")
  done
fi

xctestrun=""
if [[ ${#roots[@]} -gt 0 ]]; then
  xctestrun="$(find "${roots[@]/%//Build/Products}" \
    -maxdepth 1 -name '*.xctestrun' -print0 2>/dev/null \
    | xargs -0 stat -f '%m %N' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
fi

if [[ -z "$xctestrun" ]]; then
  echo "No .xctestrun built from $REPO — run: xcodebuild build-for-testing -scheme Piru \\"
  echo "  -destination 'platform=iOS Simulator,name=$SIM_NAME,OS=$SIM_OS'"
  echo "(or set DERIVED_DATA=<path> if you built with an explicit -derivedDataPath)"
  exit 2
fi

udid="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
want = '${SIM_OS}'.replace('.', '-')
for runtime, devices in json.load(sys.stdin)['devices'].items():
    if not runtime.endswith(want):
        continue
    for d in devices:
        if d['name'] == '''$SIM_NAME''':
            print(d['udid']); raise SystemExit
")"
[[ -n "$udid" ]] || { echo "No booted-able '$SIM_NAME' on iOS $SIM_OS." >&2; exit 2; }

fired="$(mktemp -t piru-tests-timeout)"
echo "▸ $(basename "$xctestrun") on $SIM_NAME ($SIM_OS)"
echo "▸ cutoffs: ${STARTUP_TIMEOUT}s to first test, ${RUN_TIMEOUT}s whole-run, ${TEST_TIMEOUT}s per-test"

run_suite() {
  # A FRESH log per attempt, never a truncated one. A killed xcodebuild leaves
  # children holding the old descriptor; they keep writing at their own offset,
  # so a reused file ends up interleaving a dead run's failures with a live run's
  # summary — which reads as a broken suite when nothing is broken. Cost an hour.
  log="$(mktemp -t piru-tests)"
  : >"$fired"
  echo "▸ log: $log"

  # Uninstall before every attempt. `test-without-building` reinstalls the app,
  # but a run killed mid-install leaves a HALF-installed container behind and the
  # next run happily reuses it — with the bundled substance .sqlite missing or
  # truncated. Every SubstanceLibrary lookup then returns nil and ~24 tests fail
  # with what looks exactly like a data regression. It is not; it is a dirty
  # simulator. Uninstalling costs a second and removes the whole failure mode.
  xcrun simctl uninstall "$udid" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true

  # `test-without-building` skips the build, so it never races Xcode's DerivedData
  # the way plain `xcodebuild test` does (run-tests-via-xcode-mcp).
  #
  # Run in its own process group and kill the group on timeout: xcodebuild spawns
  # testmanagerd helpers that survive a bare SIGTERM to the parent and then wedge
  # the *next* run, which is what makes this hang look intermittent.
  set -m
  xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "platform=iOS Simulator,id=$udid" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$TEST_TIMEOUT" \
    ${only_args[@]+"${only_args[@]}"} >"$log" 2>&1 &
  pid=$!
  set +m

  (
    # Early bail on the wedge. A healthy run prints its first test line within a
    # few seconds; the testmanagerd-pairing failure prints none, ever. Waiting the
    # full whole-run cap to learn that costs minutes for a suite that finishes in
    # ~17s, so give startup its own much shorter deadline and kill on silence.
    for _ in $(seq 1 "$STARTUP_TIMEOUT"); do
      sleep 1
      grep -qE '^Test Suite|Test run with|◇|✔|✘' "$log" 2>/dev/null && break
      kill -0 "$pid" 2>/dev/null || exit 0
    done
    if ! grep -qE '^Test Suite|Test run with|◇|✔|✘' "$log" 2>/dev/null; then
      echo fired >"$fired"
      kill -TERM -"$pid" 2>/dev/null; sleep 5; kill -KILL -"$pid" 2>/dev/null
      exit 0
    fi
    # Tests are running — fall back to the whole-run cap for the rest.
    sleep "$RUN_TIMEOUT"
    echo fired >"$fired"
    kill -TERM -"$pid" 2>/dev/null; sleep 5; kill -KILL -"$pid" 2>/dev/null
  ) &
  watchdog=$!

  wait "$pid"; status=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
}

run_suite
# One automatic retry, and only for the wedge. A previous killed run can leave the
# simulator's testmanagerd unable to pair, and it stays that way for every
# subsequent run until the device is cycled — so the cure is a shutdown/boot, not
# patience. Retry once so an environment fault does not read as a code failure;
# fail hard the second time, because twice is not a fluke.
if [[ -s "$fired" ]] && ! grep -qE '^Test Suite|Test run with' "$log"; then
  echo "▸ no tests started — cycling the simulator and retrying once"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  xcrun simctl boot "$udid" >/dev/null 2>&1
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  run_suite
fi

# The verdict line is Swift Testing's `✔/✘ Test run with N tests …`. The legacy
# XCTest reporter also prints `Test Suite 'PiruTests.xctest' passed … Executed 0
# tests` on every run — that 0 is the XCTest count, not the real one, and reading
# it as the result makes a green filtered run look vacuous (and a vacuous one look
# green). Key on the Swift Testing line; use the XCTest one only as a liveness tell.
#
# Only dump failures when there ARE failures: StoreRecovery deliberately opens a
# readonly store, so a *passing* run still emits pages of CoreData `[error]` lines.
# Printing those on green trains you to ignore the one place real errors appear.
[[ $status -eq 0 ]] || grep -E '^✘|\*\* TEST .* FAILED' "$log" | tail -25
grep -E '^[✔✘] Test run with' "$log" | tail -3

# Blowing the cutoff IS a failure. This suite runs in well under a minute when
# it is healthy, so "still going after ${RUN_TIMEOUT}s" is never just slowness —
# it means something wedged, and reporting it as inconclusive would let a broken
# run pass for a green one. Exit non-zero either way; only the diagnosis differs.
if [[ -s "$fired" ]]; then
  if grep -qE '^Test Suite|Test run with' "$log"; then
    cat <<EOF

✗ FAILED — cut off after ${RUN_TIMEOUT}s. Tests had started but the run never
  finished. Look for the last 'Test Suite … started' in the log: whatever comes
  after it is where it stuck. Log: $log
EOF
  else
    cat <<EOF

✗ FAILED — cut off with ZERO tests executed (no test output in ${STARTUP_TIMEOUT}s).

  Not a slow suite — the test host never paired with testmanagerd, so nothing
  ever started. Almost always the LLDB attach on the scheme's Test action:
  Product ▸ Scheme ▸ Edit Scheme ▸ Test ▸ Info ▸ uncheck "Debug executable".
  Full detail (and what has already been ruled out) in the memory
  \`xcode-test-hang-lldb-attach\`. Log: $log
EOF
  fi
  rm -f "$fired"
  exit 124
fi
rm -f "$fired"

# A run that completes but executed nothing is also a failure — that is exactly
# how the handshake bug presents when xcodebuild happens to give up on its own.
if ! grep -qE '^Test Suite|Test run with' "$log"; then
  echo; echo "✗ FAILED — xcodebuild exited $status without executing a single test. Log: $log"
  exit 125
fi

echo; echo "▸ exit $status — full log: $log"
exit $status
