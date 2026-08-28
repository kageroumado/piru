# Contributing

Bug reports and fixes are welcome. Piru is a dose journal and pharmacology reference — people read its
dose ladders, interaction warnings, half-lives, and "still in your system" curves and **make real
decisions about what they put in their body**. That raises the bar past a normal app: a wrong number
here isn't a cosmetic defect, it's a safety defect. The most valuable contributions are the ones
grounded in a **primary source** or verified on a **real device** — not what looks plausible.

Read [CLAUDE.md](CLAUDE.md) for the architecture and house conventions before starting. It's written for
agents, but it's the fastest orientation for anyone.

## The rule that matters most: cite your sources

Any change to pharmacology — a dose range, a duration, a half-life, a mechanism, a receptor affinity, an
interaction rule — **must cite a primary or authoritative source in the PR**, and the reviewer will check
your change against it. "I think it's around 50 mg" is not acceptable. "The DailyMed label / PsychonautWiki /
the PDSP K<sub>i</sub> entry says X — here's the link" is. If you can't source it, open a **Data correction**
issue instead of a PR and let it be verified there. Unsourced data edits are rejected on sight: the entire
point of Piru is that every claim traces back to something real.

## Bugs

Open an issue with the **Bug report** template. For anything involving a dose, a curve, a timer, an
interaction, or a notification, the single most useful thing you can attach is a **shared session**: in the
app, **Share → Markdown** produces a clean, paste-able record of exactly what you logged and what Piru
computed. Redact anything you'd rather not share.

For a wrong dose, duration, half-life, interaction, or mechanism, use the **Data correction** template
instead — it asks for the substance, the field, the current value, the corrected value, and the source.

Security- or privacy-sensitive issues shouldn't go in public issues — see [SECURITY.md](SECURITY.md).

## Build

Open in Xcode and Run the **Piru** scheme on an iOS 26+ simulator or device:

```sh
open Piru.xcodeproj
```

Prefer building through Xcode over scripting `xcodebuild` — it surfaces errors and warnings far more
legibly, and it won't race another build against the same DerivedData. A headless build, when you need one:

```sh
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

Requires **Xcode 26+** and **Swift 6** (strict concurrency, `@MainActor` by default).

### Tests

The suite uses the **Apple Testing framework** (Swift Testing, not XCTest) — hundreds of tests across the
models, the data layer, the PK/effect math, the interaction rules, and navigation:

```sh
xcodebuild -scheme Piru -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

If you change any non-UI logic — a PK or effect formula, an interaction rule, a dose/duration resolver, the
tolerance model — **add or update a test**. Safety-relevant math without a test won't be merged.

## Substance data — never hand-edit the database

The bundled library ships as `Piru/Data/piru-substances.sqlite`, but that file is a **build artifact**.
Editing it by hand is silently clobbered on the next rebuild and it hides pipeline bugs. Instead:

1. Edit the curated source under `data/curated/`.
2. Rebuild the whole DB — it's offline and reproducible: `pipeline/build.sh fast`.
3. Commit the rebuilt `piru-substances.sqlite` + `manifest.json` + snapshots together.

The pre-commit hook runs `pipeline/build/validate_curated.py` over staged curated files.

## Localization

Piru ships **English, Simplified Chinese, and Traditional Chinese**, and **every user-facing string must be
localized**. A hardcoded `String` ships English to Chinese users at runtime — for a safety warning, that's a
real bug, not a nicety. Add the English `Text("…")`, then add the translations to `translate_catalog.py` and
run it; don't hand-edit `Localizable.xcstrings`. The full workflow is in [CLAUDE.md](CLAUDE.md).

## Style

SwiftFormat (`.swiftformat`) and SwiftLint (`.swiftlint.yml`) for Swift; ruff for the Python pipeline. A
pre-commit config wires all of them together — install it once and they run automatically:

```sh
pip install pre-commit && pre-commit install --hook-type pre-commit --hook-type pre-push
```

`swiftformat --lint .` runs as a pre-push gate and again in CI; a push that isn't format-clean is refused
before it leaves your machine.

## Layout

- `Piru/Models/` — `Substance`, `DoseRange`, `DurationProfile`, `DoseUnit`, and the category enums.
- `Piru/Views/` — SwiftUI; the four tabs (Journal, Library, Tools, Insights), plus `Insights/` and `Components/`.
- `Piru/Data/` — `SubstanceStore` (GRDB over the bundled SQLite, per-field source-priority resolution),
  `Interactions` (class-based severity rules), `StoreRecovery`, `BackupManager`.
- `Piru/Navigation/` — `AppNavigator` (tab / sheet / path state) and the `piru://` deep-link codec.
- `Shared/` — the SwiftData `@Model`s, `PKModel`, and formatting, shared with the widget and Live Activity.
- `PiruWidget/`, `PiruLiveActivityExtension/` — Home Screen widgets and the Lock Screen Live Activity.
- `pipeline/` — the offline Python pipeline that builds the substance DB from `data/`.

The safety-critical code — `Interactions`, `PKModel`, the effect engine, and the curated
data layer — is the high-value, fragile part. Read the relevant `Specs/` doc before touching it.

## Pull requests

Use the template. Reference the issue you fix and keep it focused. The checklist isn't decorative — for a
sensitive app it's the review:

- Sources cited for every pharmacology / dose / interaction change.
- Data changed through the pipeline, not by hand-editing the `.sqlite`.
- Tests added or updated for changed non-UI logic; the suite passes.
- Every new user-facing string localized (EN + zh-Hans + zh-Hant).
- No new network calls, telemetry, or anything that moves journal data off the device (see [SECURITY.md](SECURITY.md)).
- Verified on a real device or simulator for anything touching curves, interactions, or notifications.
- `swiftformat --lint .` passes.

Fill in the Authorship section: agent, model, and whether the session was attended or automatic.

Contributions are licensed under the **GNU General Public License v3**, the same license as the project.
