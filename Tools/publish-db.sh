#!/usr/bin/env bash
#
# Publish a freshly built substance database to the host that serves it.
#
# The database is untracked and manifest.json is committed, so a rebuild is only
# half-published when it is committed: the manifest describes a database nobody
# can fetch yet, and Tools/fetch-db.sh fails its checksum check until this runs.
# Publish BEFORE pushing the manifest, so the host is never behind the repo.
#
# USAGE
#   Tools/publish-db.sh
#
#   PIRU_DB_HOST / PIRU_DB_REMOTE_DIR override the destination.
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# `piru-db` is an ssh alias; define it in ~/.ssh/config.
HOST="${PIRU_DB_HOST:-piru-db}"
REMOTE_DIR="${PIRU_DB_REMOTE_DIR:-/var/www/piru-db/Piru/Data}"
DB="Piru/Data/piru-substances.sqlite"
MANIFEST="Piru/Data/manifest.json"

[ -f "$DB" ] || {
    echo "error: $DB is missing — run pipeline/build.sh first" >&2
    exit 1
}

sha() {
    python3 -c "
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], 'rb') as f:
    for chunk in iter(lambda: f.read(1 << 20), b''):
        h.update(chunk)
print(h.hexdigest())
" "$1"
}

# The manifest is what every consumer validates against, so a mismatch here
# means the pipeline was not re-run after the DB changed. Publishing anyway
# would put a file on the host that no checkout will accept.
LOCAL_SHA="$(sha "$DB")"
MANIFEST_SHA="$(python3 -c "import json; print(json.load(open('$MANIFEST'))['sqlite_sha256'])")"
if [ "$LOCAL_SHA" != "$MANIFEST_SHA" ]; then
    echo "error: $DB does not match $MANIFEST" >&2
    echo "       db       $LOCAL_SHA" >&2
    echo "       manifest $MANIFEST_SHA" >&2
    echo "       Re-run pipeline/build.sh so the manifest describes this database." >&2
    exit 1
fi

echo "==> Uploading to $HOST:$REMOTE_DIR"
scp -q "$DB" "$MANIFEST" "$HOST:/tmp/"
ssh "$HOST" "sudo install -o caddy -g caddy -m 644 /tmp/$(basename "$DB") '$REMOTE_DIR/' \
    && sudo install -o caddy -g caddy -m 644 /tmp/$(basename "$MANIFEST") '$REMOTE_DIR/' \
    && rm -f /tmp/$(basename "$DB") /tmp/$(basename "$MANIFEST")"

# The release asset is what CI and fresh clones fetch: kagerou.glass sits behind
# Cloudflare Bot Fight Mode, which 403s CI runners. Both must carry the same
# file or Tools/fetch-db.sh falls through to the slower source on every build.
echo "==> Uploading to the release mirror"
gh release upload db "$DB" --clobber

BASE_URL="${PIRU_DB_BASE_URL:-https://kagerou.glass/piru-db}"
echo "==> Verifying what the host now serves"
SERVED_SHA="$(curl --fail --silent --location "$BASE_URL/$DB" | python3 -c "
import hashlib, sys
h = hashlib.sha256()
for chunk in iter(lambda: sys.stdin.buffer.read(1 << 20), b''):
    h.update(chunk)
print(h.hexdigest())
")"
if [ "$SERVED_SHA" != "$LOCAL_SHA" ]; then
    echo "error: the host is serving $SERVED_SHA, expected $LOCAL_SHA" >&2
    echo "       A stale CDN edge is the usual cause; retry shortly." >&2
    exit 1
fi
RELEASE_SHA="$(curl --fail --silent --location "https://github.com/kageroumado/piru/releases/download/db/$(basename "$DB")" | python3 -c "
import hashlib, sys
h = hashlib.sha256()
for chunk in iter(lambda: sys.stdin.buffer.read(1 << 20), b''):
    h.update(chunk)
print(h.hexdigest())
")"
if [ "$RELEASE_SHA" != "$LOCAL_SHA" ]; then
    echo "error: the release mirror is serving $RELEASE_SHA, expected $LOCAL_SHA" >&2
    exit 1
fi
echo "==> Published and verified on both sources (sha256 ${LOCAL_SHA:0:16}…)"
echo "    Safe to commit the manifest and push."
