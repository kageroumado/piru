# Piru on Android

Piru's Android app compiles the iOS Swift sources through Skip Fuse, bridges SwiftUI views to Compose, and replaces SwiftData with a GRDB-backed compatibility layer. Android adaptations live under `android/`; the build reads the iOS tree and stages its output outside the repository.

<details>
<summary>Android implementation and build reference</summary>

## Scope

The iOS app remains the product source. Shared-code refactors must also improve iOS; Android-specific changes belong in the translation layer. Rebuild Android for every Piru release and repair translations that no longer apply.

Compose handles layouts SkipUI cannot express. Widgets, Live Activities, Health Connect, the watch app, skins, and a store are outside the current Android scope.

## Principles

1. **Translations adapt APIs; behavior stays in shared code.** An entry point that copies
   launch code drifts from it and silently skips store recovery, migrations or session
   recovery. Launch, store-open and lifecycle policy live in shared functions that both entry
   points call; the Android host only adapts platform events.
2. **PortableData honors the SwiftData contract the app relies on**, or the app loses data.
   The contract is below, enforced by tests using the app's real models. Otherwise every iOS
   model change is an Android data incident.
3. **A missing capability fails visibly; it never fakes success.** A share sheet that sends a
   file's path as text while the caller deletes the file is worse than a disabled button.
   Stand-ins for unavailable features disable or explain; they do not report completion.
4. **Divergences that change what data means are data-safety bugs**, not cosmetic ones: time
   zone resolution, which settings store a key lands in, which language catalog content
   uses, NaN coordinates, a catalog older than its manifest.
5. **Only debug builds seed demo data.** A debug build may reset the store with demo data, as
   the iOS simulator does; a release build never seeds.
6. **Every input is pinned and every output is checked.** Dependency graph locked, vendor
   revisions asserted, downloads hashed, the catalog verified against its manifest, the
   merged manifest's permissions allowlisted, notices generated from the dependency graph.

## How it works

```
Piru/ + Shared/ (iOS sources, read-only)
        │  stage.py
        ▼
  copy  ── exclude.txt drops iOS-only files
  patch ── patches/series (git apply, in order)
  rewrite ─ substitutions.txt (regex) and rewrite_chart_bodies (structured)
  add   ── app/ template: Package.swift, Skip.env, Gradle project, Android/*.swift stand-ins,
           Skip/*.kt composers
  generate ─ asset catalog (flattened), SF→Material symbolsets, material colorsets,
           Info.plist values, launcher icon (from Piru.icon's layers)
  vendor ── pinned clones of GRDB, skip, skipstone, skip-ui, skip-fuse-ui, each with
           vendor/<name>/*.patch, served through SwiftPM mirrors
        ▼
$PIRU_ANDROID_STAGE  (a Skip Fuse package: native Swift on Android, SwiftUI → Compose)
        │  build-app.sh   phase 1: iOS-triple pre-build → skipstone writes the Kotlin bridge
        │                 phase 2: Android bridge build → jni-libs
        │  package-apk.sh Gradle packages the APK (its own Swift build disabled)
        ▼
app-debug.apk / app-release.apk
```

Skip Fuse compiles the Swift natively for Android and bridges SwiftUI views to Compose through
SkipUI. SwiftData is replaced by `PortableData` (`android/Compat`), a SwiftData-shaped API over
GRDB, so `@Model`, `@Query`, `#Predicate` and `ModelContext` call sites compile unchanged.
Compat's `os`, `OSLog`, `CryptoKit` and `CoreLocation` modules serve the headless `PiruCore`
build.

Two asymmetries to know:

- skipstone (phase 1, the Kotlin side) evaluates every compile condition Skip does not define
  as false, so `#if DEBUG` and `#if !os(macOS)` diverge between the two phases.
- `#if os(iOS) … #else` compiles its macOS branch on Android.

A few things the build does by hand that Skip's own tooling would:

- **Two phases.** Phase 1's compile fails by design once skipstone has written the Kotlin.
  Phase 2 builds in its own scratch path. Gradle's Swift build is disabled because it would
  resolve an unpatched skipstone.
- **Resources.** `Bundle.module` is SwiftPM's Darwin accessor, which no Android bundle answers;
  `AndroidResources.bundle` maps to the module assets, and file resources (the catalog) are
  copied out of the APK.
- **Assets.** SkipUI finds an asset by folder name alone, so the catalog is flattened to
  namespaced names (`surface__background`) and the generated symbols ask for those.

## Where an Android difference goes

Use the first applicable form:

| # | Form | Lives in | Use when | Per-release cost |
|---|---|---|---|---|
| 0 | iOS fix or refactor | `Piru/`, `Shared/` (on `main`) | the code is wrong on iOS too, or sharing it improves iOS | none after landing |
| 1 | Stand-in | `app/Sources/Piru/Android/*.swift` | an Apple API SkipFuseUI lacks can be written with the same name and signature | low; re-check when callers use more of the API |
| 2 | Twin + substitution | stand-in `androidX(...)` + a `substitutions.txt` rule | the API exists in SkipFuseUI but is unavailable or wrong | low; the rule's hit count is checked |
| 3 | Generated resource or structured rewrite | `tools/stage.py` | a resource needs converting, or a rewrite needs syntax awareness regex lacks | none; regenerated each build |
| 4 | Exclude | `exclude.txt` | a whole file is iOS-only, and a stand-in replaces what callers use from it | low unless the file's API grows |
| 5 | Patch | `patches/NNNN-*.patch` | the behavior itself must differ, with `#if os(Android)` in the hunk | a hunk can stop applying |
| 6 | Vendor patch | `vendor/<package>/*.patch` | Skip or GRDB is wrong | re-apply on upgrade; each goes upstream |
| 7 | Compose composer | `app/Sources/Piru/Skip/*.kt` | SkipUI cannot express the layout | Kotlin to keep compiling across Skip versions |

Rules:

- **A patch carries its reason on line 1**, puts Android code inside `#if os(Android)` with
  the original as the `#else` (not re-indented, no comments added to it), and adds nothing
  outside the `#if`.
- **Substitutions come in two kinds.** A *rename* (an unavailable API to its twin) must be
  unambiguous wherever it matches. A *semantic rule* (it changes what code does: a storage
  location, a language source, a trigger type) is marked `# semantic:` with the behavior it
  changes, and has a test. Rules rewrite `Upstream/` only, never the stand-ins.
- **Every rule has an expected hit count** in a committed baseline; a rule at zero is
  deleted, a changed count fails `stage.py --check`.
- **Stand-ins state what they approximate** in their doc comment, and follow principle 3.
- **`mkpatch.py` makes patches** from an edit in the worktree, which is then reverted.

## The persistence contract

PortableData must preserve these SwiftData behaviors. Tests use Piru's real `@Model` types with two contexts.

1. A stored property added with a default (or made optional) decodes old rows with that
   default; `@Attribute(originalName:)` reads the old key; unknown keys survive a save.
2. A row that cannot decode is skipped and reported; it never marks the entity loaded or
   hides the rest of the table.
3. A save writes only what changed (inserts, deletes, dirty rows), in one transaction, and
   fails whole if anything cannot encode (no `null` for a failed value).
4. After a save, other contexts see the change on their next fetch; an unrelated context's
   save never overwrites or resurrects rows it did not change.
5. `autosaveEnabled` saves pending changes on the next main-actor turn, and the app flushes
   on pause.
6. Assigning one side of a relationship updates the inverse immediately; `.cascade` and
   `.nullify` delete rules run on delete.
7. `rollback()` restores held objects to their committed values.
8. `.unique` attributes upsert; a read-only configuration cannot write.
9. Loading and saving are linear in the store size; relationships are resolved with a keyed
   index, not a scan per owner.
10. A context that ends frees the models it read, which the app's per-call background
    contexts depend on: each live model holds a JNI global reference, and ART aborts at 51,200.
    Where SwiftData differs: a model held past its context keeps its to-one relationships, but
    its to-many sides are emptied, where SwiftData's would keep the context alive.
11. Every model a context lets go of is unlinked from the rest through one function, whether
    the context ended, another context deleted its row, or a save or rollback discarded it:
    its to-many sides empty, it leaves its owners' inverse arrays, and it stays deleted.
12. A model's Compose bridge is made on its first main-thread read outside PortableData's own
    passes (loading, merging, rebuilding inverses, fetching, saving), and is called on the main
    thread only; Observation itself hears reads and writes on every thread.

## Distribution, signing and data

- **Distribution.** GitHub releases carry APKs for direct installation or Obtainium, with the corresponding source branch published. About includes the Android dependency notices: MPL-2.0 Skip modules and their modified source, Apache NOTICE files, Unicode/ICU, curl/OpenSSL, BSD-2, and Material Symbols.
- **Signing.** The release key follows Android's current guidance (RSA 4096, a validity far
  past 25 years, APK Signature Scheme v2+v3 so it can rotate) and lives in the macOS keychain.
  The build reads it at signing time, and a release build fails without it. Losing it strands
  every installed copy, so it is backed up.
- **Backups and secrets.** No app data goes to Google's cloud backup, and key material never
  leaves the device. Automatic backup, iOS's iCloud backup on Android, writes a
  passphrase-sealed `.piruenc` into a folder the user picks through the Storage Access
  Framework (`app/Sources/Piru/Android/Backup/`). A cloud folder is uploaded by its
  provider's app. The one connection Piru opens is the daily update check, which asks GitHub
  for the newest release, sends nothing about the user, and turns off in Settings.
  Keychain items (the share identities' private keys) are files sealed under an Android
  Keystore key (`app/Sources/Piru/Skip/AndroidKeystore.kt`).
- **Sharing between phones.** A session share is the same `.pirushare` file as on iOS, read
  and written byte for byte alike: zlib writes the raw DEFLATE Apple's Compression does, and
  swift-crypto seals the same HPKE suite. A file sent to Piru arrives through the manifest's
  `application/octet-stream` filters and is copied in by `Skip/AndroidIncomingFiles.kt`.
  Android shows its pairing QR code but has no scanner: an iPhone scans it and sends a
  session, and accepting that session pairs the two.
- **Migration.** Import accepts every format iOS does, including PsychonautWiki Journal's
  (PsyLog), through the Storage Access Framework.

## Building

```bash
android/tools/setup.sh         # once: toolchain, Android SDK/NDK, emulator (~6 GB)
pipeline/fetch-db.sh           # the catalog, as for any checkout
android/tools/build-app.sh     # stage + both Skip phases
android/tools/package-apk.sh   # Gradle → APK, installs on a running emulator
```

`PIRU_CONFIG=release` on both scripts builds the optimized APK. `build-app.sh` writes every
bridge compiler error to `$PIRU_ANDROID_BUILD/app.errors`.

The build runs on macOS with Xcode. Every path it uses comes from the environment, with the
defaults below (`tools/env.sh` for the shell tools, `tools/android_paths.py` for the Python
ones). Export a variable to move that piece; the scripts stop with the variable's name when
something they need is missing.

| Variable | Holds | Default |
|---|---|---|
| `PIRU_ANDROID` | what `setup.sh` installs, downloads, vendored-clone cache | `${XDG_CACHE_HOME:-~/.cache}/piru-android` |
| `PIRU_ANDROID_STAGE` | the staged Skip package and its build products | `$PIRU_ANDROID/stage` |
| `PIRU_ANDROID_BUILD` | logs, `app.errors`, screenshots, `PiruCore` scratch | `$PIRU_ANDROID/build` |
| `PIRU_SWIFT_TOOLCHAIN` | the swift.org 6.4.0 toolchain | `$PIRU_ANDROID/toolchains/swift-6.4.0-RELEASE.xctoolchain` |
| `ANDROID_HOME` | Android SDK | `$PIRU_ANDROID/android-sdk` |
| `ANDROID_NDK_HOME` | Android NDK r30 (checked) | `$PIRU_ANDROID/android-ndk-r30` |
| `ANDROID_AVD_HOME`, `GRADLE_USER_HOME` | emulator images, Gradle caches | `$PIRU_ANDROID/avd`, `$PIRU_ANDROID/gradle-home` |
| `JAVA_HOME` | JDK 21 | `/usr/libexec/java_home -v 21` when unset or another version |

The default sits outside the checkout so every clone and worktree shares one ~6 GB toolchain
install. To keep it on another disk, set `PIRU_ANDROID` in the shell profile
(`export PIRU_ANDROID=/Volumes/External/piru-android`); `skip`, `gradle` and `xcrun` come from
`PATH`.

To change an upstream file for Android: edit it in place, run
`android/tools/mkpatch.py <name> <paths> --message "why"`, then `git checkout -- <paths>`.
`stage.py --check` reports any patch that no longer applies.

### Driving the emulator

`android/tools/droid` drives adb and uiautomator using the SwiftUI accessibility labels reported by Compose.

```bash
android/tools/droid restart                       # force-stop and relaunch Piru
android/tools/droid wait --label Journal          # until it is up
android/tools/droid tap --label "Record an entry" # --index N when a label repeats
android/tools/droid tree                          # labels with center coordinates
android/tools/droid shot quicklog                 # → $PIRU_ANDROID_BUILD/quicklog.png
android/tools/droid logs                          # the app's fatal and error lines
```

An emulator on another Mac: `PIRU_ADB_SSH=user@host` (with `env.sh` sourced) tunnels adb to
that Mac's adb server, and every tool drives its emulator. The emulator needs 6 GB
(`setup.sh` sets it): at 2 GB the app's startup is killed under memory pressure.

</details>
