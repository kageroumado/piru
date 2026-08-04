# `pipeline/`

**Read [`README.md`](README.md) before changing anything here.** It is the map:
what each script does, the order `build.sh` runs them in, where curated data
lives, and how to research a claim before it becomes a row.

Two rules that catch people who skip it:

- **Editing JSON does nothing without a rebuild.** Data changes land via
  `data/curated/`, then `pipeline/build.sh fast`.
- **Never hand-edit the bundled `.sqlite`.** Always rebuild the whole DB — a
  surgical edit hides build bugs and is clobbered on the next run.
