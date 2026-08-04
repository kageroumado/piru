#!/usr/bin/env bash
#
# Put the bundled substance database in place for a build.
#
# The database is not tracked in git; manifest.json beside it is. This reads the
# expected SHA-256 from that manifest and downloads the database only when what
# is on disk does not already match, so it is a no-op on a correct checkout and
# safe to run on every build.
#
# Never track the database in Git LFS: SubstanceDBUpdater fetches it over plain
# HTTP, and raw.githubusercontent.com serves an LFS path as its 133-byte pointer
# rather than the file.
#
# USAGE
#   pipeline/fetch-db.sh              # ensure the DB is present and correct
#   pipeline/fetch-db.sh --force      # re-download even if the checksum matches
#
#   PIRU_DB_URL pins a single source (staging, a fork, a local file server).
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

DB_URL="${PIRU_DB_URL:-https://github.com/kageroumado/piru/releases/download/db/piru-substances.sqlite}"
MANIFEST="Piru/Data/manifest.json"
DB="Piru/Data/piru-substances.sqlite"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

[ -f "$MANIFEST" ] || {
    echo "error: $MANIFEST is missing — it is tracked, so this is a broken checkout" >&2
    exit 1
}

# The manifest is the authority on which database this checkout expects. Taking
# the checksum from the server instead would make the script always agree with
# whatever it just downloaded, which is not a check at all.
read -r EXPECTED_SHA EXPECTED_SIZE <<< "$(
    python3 -c "
import json
m = json.load(open('$MANIFEST'))
print(m['sqlite_sha256'], m['sqlite_size_bytes'])
"
)"

# Hashed via python3 rather than shasum/sha256sum: macOS ships the former and
# the Linux CI runner the latter, and python3 is already a hard requirement here.
actual_sha() {
    python3 -c "
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], 'rb') as f:
    for chunk in iter(lambda: f.read(1 << 20), b''):
        h.update(chunk)
print(h.hexdigest())
" "$1" 2> /dev/null
}

if [ "$FORCE" -eq 0 ] && [ -f "$DB" ] && [ "$(actual_sha "$DB")" = "$EXPECTED_SHA" ]; then
    echo "==> $DB already matches the manifest ($EXPECTED_SIZE bytes) — nothing to do"
    exit 0
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/piru-db.XXXXXX")"
trap 'rm -f "$TMP" 2>/dev/null || true' EXIT

echo "==> Fetching $DB_URL"
curl --fail --location --show-error --silent --retry 3 --retry-delay 2 \
    --output "$TMP" "$DB_URL"
GOT_SHA="$(actual_sha "$TMP")"

if [ "$GOT_SHA" != "$EXPECTED_SHA" ]; then
    echo "error: checksum mismatch — refusing to install" >&2
    echo "       expected $EXPECTED_SHA" >&2
    echo "       got      $GOT_SHA" >&2
    echo "       Publish the current build with pipeline/publish-db.sh, or re-run" >&2
    echo "       pipeline/build.sh so the manifest describes what is hosted." >&2
    exit 1
fi

# Move into place only after the checksum passes, so an interrupted or corrupt
# download can never leave a half-written database that later reads as valid.
mv -f "$TMP" "$DB"
trap - EXIT
chmod 644 "$DB"
echo "==> Installed $DB ($(wc -c < "$DB" | tr -d ' ') bytes, sha256 ${EXPECTED_SHA:0:16}…)"
