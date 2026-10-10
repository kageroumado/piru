# Working on Piru for Android

@README.md

## Gotchas

- **A control `droid tree` lists twice is composed twice.** Two live copies bound to one
  `@FocusState` take focus from each other every frame, and the screen recomposes without
  pause. Count the copies before profiling a lag; vendor patch 0006 is why `.shadow` no longer
  makes them.
- **`package-apk.sh` does not restage.** A template, stand-in or `symbols.tsv` change needs
  `build-app.sh`, or at least `python3 android/tools/stage.py`.
- **Upstream edits go through patches.** Edit the file in `Piru/` or `Shared/`, run
  `mkpatch.py`, then `git checkout --` the paths. To revise a patch, `git apply` it, edit,
  rewrite it with its line-1 reason, and revert.
- **The dependency graph is locked** by `android/app/Package.resolved`, vendored clones included
  (their commits are deterministic). After changing a vendor patch or a dependency, build, then
  copy `$PIRU_ANDROID/stage/Package.resolved` back over it and commit both together.
- **A vendor patch can leave its Kotlin stale.** skipstone does not re-transpile a dependency
  whose checkout moved, and phase 1 stops before reaching it. After changing a skip-ui or
  skip-fuse-ui patch, run phase 1 for that target (`swift build --triple arm64-apple-ios …
  --target SkipUI` in the stage) and check the patch reached
  `.build/plugins/outputs/<package>/…/*.kt` before packaging.
- **Keep `/* SKIP @bridge */` a block comment.** skipstone drops a declaration whose marker
  became `/** */` or `//`; `android/.swiftformat` turns off the rules that would do that.
  Inside a worktree, format with `swiftformat --config .swiftformat` plus the options in
  `android/.swiftformat`, because the repository's config excludes `.claude`.
- **Typing on a slow emulator.** `droid type` drops characters while the app re-renders;
  send one character per `adb shell input text`, with a pause between.
- **Launcher cache.** The launcher caches the icon per `versionCode`. Never
  `pm clear com.google.android.apps.nexuslauncher`: it leaves a black home screen until a
  reboot.
- **Temporary probes.** `Logger(subsystem: "probe", …).error(...)` in an uncommitted upstream
  edit, then grep `adb logcat -d` for `PROBE`.
