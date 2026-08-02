#!/usr/bin/env bash
# promote.sh <newfile1> [newfile2 ...]
# For each top-level `private`/`fileprivate` struct/class/enum in the given
# (just-split-out) files, verify the name isn't defined elsewhere in the module,
# then promote it to internal (remove the access modifier) so cross-file
# references from the origin file still resolve.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
for f in "$@"; do
  names=$(grep -oE '^(private|fileprivate) (struct|final class|class|enum) [A-Za-z_]\w*' "$f" \
            | awk '{print $NF}' | sort -u)
  for nm in $names; do
    others=$(grep -rlE "(struct|final class|class|enum) +$nm\b" Piru Shared --include="*.swift" 2>/dev/null \
              | grep -vxF "$f" || true)
    if [ -n "$others" ]; then
      echo "COLLISION: $nm also defined in: $others (NOT promoting — resolve manually)"
    else
      perl -i -pe "s/^(private|fileprivate) ((?:final class|class|struct|enum) $nm\b)/\$2/" "$f"
      echo "promoted: $nm -> internal  ($(basename "$f"))"
    fi
  done
done
