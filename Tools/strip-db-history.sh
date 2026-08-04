#!/usr/bin/env bash
#
# Discard the accumulated revisions of the repo's large regenerable artifacts,
# keeping only the copy at HEAD.
#
# WHY THIS EXISTS
#   The bundled substance DB is ~19 MB and is rewritten wholesale on every data
#   pass. It cannot be untracked: the app target bundles it (SubstanceStore
#   fatalErrors without it) and SubstanceDBUpdater serves it to installed builds
#   straight from raw.githubusercontent.com on main. It cannot go in Git LFS
#   either — raw.githubusercontent serves an LFS path as its 133-byte pointer,
#   which would ship pointer text to every device asking for an update.
#
#   So the file stays an ordinary tracked blob and its OLD revisions are thrown
#   away periodically instead. Only the newest content is ever of use; a rebuild
#   from three passes ago is reproducible from the pipeline and worthless as
#   history. Left alone this grew to 2.2 GB across 142 revisions.
#
# WHAT IT DOES
#   Rewrites history so that, for each path below, every blob EXCEPT the one at
#   HEAD is removed. Commits, messages, authorship and the commit graph are all
#   preserved (--prune-empty never) — only the file content disappears from the
#   older commits. HEAD's tree is left byte-identical.
#
# COST
#   This is a history rewrite: every commit SHA after the oldest stripped blob
#   changes, so it requires a force-push and invalidates existing clones and
#   forks. Run it deliberately — after a release, not mid-review.
#
# USAGE
#   Tools/strip-db-history.sh            # rewrite locally, print the push command
#   Tools/strip-db-history.sh --push     # rewrite and force-push main + tags
#
set -euo pipefail

# Paths whose history is disposable. Each keeps exactly its HEAD revision.
PATHS=(
    "Piru/Data/piru-substances.sqlite"
    "data/snapshots/substances.json"
    "data/snapshots/substances.csv"
    "data/snapshots/gaps.csv"
)

DO_PUSH=0
[ "${1:-}" = "--push" ] && DO_PUSH=1

cd "$(git rev-parse --show-toplevel)"

command -v git-filter-repo > /dev/null 2>&1 || {
    echo "error: git-filter-repo not installed (brew install git-filter-repo)" >&2
    exit 1
}

# A rewrite silently discards uncommitted work, so refuse to start on a dirty
# tree rather than ask the user to trust that it doesn't.
if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree is dirty — commit or stash first" >&2
    exit 1
fi

REMOTE_URL="$(git remote get-url origin 2> /dev/null || true)"
WORK="$(mktemp -d)"
BACKUP="${PIRU_STRIP_BACKUP:-$WORK/backup.git}"

echo "==> Mirror backup → $BACKUP"
git clone --quiet --mirror . "$BACKUP"

# The blob at HEAD is the one revision worth keeping. Everything else that ever
# occupied these paths is a candidate for removal.
: > "$WORK/keep.txt"
for p in "${PATHS[@]}"; do
    if blob="$(git rev-parse "HEAD:$p" 2> /dev/null)"; then
        echo "$blob" >> "$WORK/keep.txt"
    else
        echo "note: $p is not present at HEAD — every revision of it will go"
    fi
done

# `git rev-list --objects` reports each blob with the path it was last seen at,
# which is what lets a path-keyed filter work at all.
git rev-list --objects --all \
    | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
    | awk -v want="$(printf '%s\n' "${PATHS[@]}" | tr '\n' '|')" '
        BEGIN { n = split(want, a, "|"); for (i = 1; i <= n; i++) if (a[i] != "") W[a[i]] = 1 }
        $1 == "blob" && ($4 in W) { print $2, $3, $4 }
      ' > "$WORK/candidates.txt"

grep -vFf "$WORK/keep.txt" "$WORK/candidates.txt" > "$WORK/strip-detail.txt" || true

if [ ! -s "$WORK/strip-detail.txt" ]; then
    echo "==> Nothing to strip; history already holds only the current revisions."
    exit 0
fi

awk '{print $1}' "$WORK/strip-detail.txt" | sort -u > "$WORK/strip-blobs.txt"

echo "==> Removing:"
awk '{s[$3] += $2; n[$3]++} END {for (k in s) printf "    %8.1f MB  %4d revs  %s\n", s[k] / 1048576, n[k], k}' \
    "$WORK/strip-detail.txt" | sort -rn
awk '{s += $2} END {printf "    %8.1f MB total across %d blobs\n", s / 1048576, NR}' "$WORK/strip-detail.txt"

PRE_TREE="$(git rev-parse 'HEAD^{tree}')"
PRE_COMMITS="$(git rev-list --count HEAD)"

git filter-repo --strip-blobs-with-ids "$WORK/strip-blobs.txt" --prune-empty never --force

# filter-repo drops the remote so a rewritten history can't be pushed by
# reflex. This script's whole purpose is to push it, so put it back.
[ -n "$REMOTE_URL" ] && git remote add origin "$REMOTE_URL" 2> /dev/null || true

# The one invariant that matters: the checked-out tree must be untouched. If
# HEAD's tree moved, a live file was stripped and the rewrite must be discarded.
POST_TREE="$(git rev-parse 'HEAD^{tree}')"
if [ "$PRE_TREE" != "$POST_TREE" ]; then
    echo "error: HEAD tree changed ($PRE_TREE -> $POST_TREE) — a live file was stripped." >&2
    echo "       Restore from the mirror backup at $BACKUP and investigate:" >&2
    echo "       git fetch $BACKUP 'refs/*:refs/*' --force" >&2
    exit 1
fi
echo "==> HEAD tree unchanged ($POST_TREE)"
echo "==> Commits preserved: $(git rev-list --count HEAD) (was $PRE_COMMITS)"

git reflog expire --expire=now --all
git gc --prune=now --quiet

if [ "$DO_PUSH" -eq 1 ]; then
    echo "==> Force-pushing main + tags"
    git push --force origin main
    git push --force --tags origin
    echo "==> Done. Existing clones and forks now diverge; re-clone rather than pull."
else
    echo
    echo "Rewrite complete, NOT pushed. Backup: $BACKUP"
    echo "To publish:"
    echo "    git push --force origin main && git push --force --tags origin"
fi
