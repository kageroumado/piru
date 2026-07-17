<!-- Thanks for contributing to Piru! Fill in what's relevant; delete what isn't. -->

## Summary

<!-- One or two sentences: what this changes, and why. -->

## Related issue(s)

<!-- e.g. "Fixes #12" or "Relates to #12". Delete if none. -->

## Changes

<!-- Bullet the key changes. Keep it skimmable. -->

-

## Sources

<!--
REQUIRED for any pharmacology / dose / duration / half-life / interaction / PK change. Link the primary
or authoritative source for every value you changed — a reviewer will check the change against it.
Write "N/A — no pharmacology data changed" if this PR touches none.
-->

## How it was tested

<!-- For curves, interactions, and notifications, exercise a real run — don't rely on "it builds". -->

- **iOS / device**: <!-- e.g. iOS 26.1 on iPhone 17 Pro Max, or Simulator -->
- **What you exercised**: <!-- the actual flow you ran -->
- **Result**: <!-- what you observed; screenshots / recordings welcome -->

## Risk / regressions

<!--
What could this break? Flag anything safety-relevant: an interaction that might stop firing, a curve that
now reads shorter than reality, a change near the backup crypto or the SwiftData store, a new external
input surface.
-->

## Checklist

- [ ] Sources cited above for every pharmacology/dose/interaction change (or marked N/A)
- [ ] Substance data changed via the pipeline (`pipeline/build.sh`), not by hand-editing the `.sqlite`
- [ ] Tests added/updated for changed non-UI logic; the suite passes
- [ ] Every new user-facing string is localized (EN + zh-Hans + zh-Hant)
- [ ] No new network calls, telemetry, or off-device data flow (see SECURITY.md)
- [ ] Verified on a real device/simulator for curves, interactions, or notifications
- [ ] `swiftformat --lint .` passes
- [ ] No unrelated changes bundled in

---

## Authorship

<!-- These PRs are often written by an agent — record who wrote it and how. -->

- **Agent**: <!-- the agent's name (e.g. Sora), or the human author -->
- **Model**: <!-- the model the agent runs on, e.g. Opus 4.8 (1M context) — leave blank if human-authored -->
- **Session**: <!-- "attended" (a human participated / reviewed live) or "automatic" (unattended agent run) -->
