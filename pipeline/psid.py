"""PSID (Piru Substance ID) primitives — the stable substance-identity scheme.

Grammar (see Specs/stereoisomer-and-release-form-axes.md):

    P1-<FAMILY>-<stereo>-<salt>-<release>-<chk>

* ``P1`` — scheme version, so the grammar can evolve without stranding stored ids.
* ``FAMILY`` — a 14-char skeleton hash. For a structure-bearing substance whose
  InChIKey connectivity block (block 1) is unique and trusted in the catalog, the
  FAMILY *is* that block 1 verbatim (14 uppercase letters), so it cross-references
  PubChem. For a structure-less row, or a member of a same-block-1 collision of
  *distinct* drugs, the FAMILY is a name-hash in the same alphabet with a
  **sentinel leading digit** — real block-1s are always 14 letters, so a leading
  digit unambiguously marks "this is a name-hash, not an InChIKey".
* ``<stereo>`` / ``<salt>`` / ``<release>`` — the three orthogonal form facets;
  ``0`` = racemic/freebase/standard (unspecified). Populated by Stage A/B.
* ``<chk>`` — an ISO 7064 MOD 37,36 hybrid check character over the key body
  (scheme + family + facets, separators stripped). It detects every single-char
  substitution and nearly all adjacent transpositions, so a truncated or mistyped
  PSID fails fast instead of silently resolving to a *different* valid substance.

Kept stdlib-only and side-effect-free so the build, audit, and tests can import
it. The check-character algorithm is ported verbatim to Swift for the app's
deep-link / import boundary (Stage 0.2).
"""

from __future__ import annotations

import hashlib

SCHEME = "P1"
UNSPECIFIED_FACET = "0"

# ISO 7064 radix-36 alphabet: a character's value is its index (0-9, then A-Z).
_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_M = 36  # radix
_N = 37  # modulus (M + 1)

_FAMILY_LEN = 14


def iso7064_check_char(body: str) -> str:
    """ISO 7064 MOD 37,36 hybrid check character over ``body`` (all chars in the
    radix-36 alphabet). Detects every single-character substitution and nearly
    all adjacent transpositions."""
    p = _M
    for ch in body:
        p = (p + _ALPHABET.index(ch)) % _M
        if p == 0:
            p = _M
        p = (p * 2) % _N
    return _ALPHABET[(_N - p) % _M]


def name_hash_family(name: str) -> str:
    """A deterministic 14-char name-hash FAMILY for a row without a trusted
    block 1: a sentinel leading digit + 13 uppercase letters (base-26 of a SHA-256
    of ``name``). The leading digit is what distinguishes it from a real InChIKey
    block 1 (always 14 letters)."""
    digest = hashlib.sha256(name.encode("utf-8")).digest()
    num = int.from_bytes(digest, "big")
    letters = []
    for _ in range(_FAMILY_LEN - 1):
        num, rem = divmod(num, 26)
        letters.append(_LETTERS[rem])
    sentinel = str(digest[0] % 10)
    return sentinel + "".join(letters)


def is_block1_family(family: str) -> bool:
    """True when FAMILY is a real InChIKey connectivity block (14 uppercase
    letters), as opposed to a sentinel-digit name-hash."""
    return len(family) == _FAMILY_LEN and family.isalpha() and family.isupper()


def is_name_hash_family(family: str) -> bool:
    """True when FAMILY is a name-hash (sentinel leading digit + 13 letters)."""
    return (
        len(family) == _FAMILY_LEN
        and family[0].isdigit()
        and family[1:].isalpha()
        and family[1:].isupper()
    )


def is_wellformed_family(family: str) -> bool:
    """A FAMILY is either a real block-1 or a name-hash — never anything else."""
    return is_block1_family(family) or is_name_hash_family(family)


def _body(family: str, stereo: str, salt: str, release: str) -> str:
    return SCHEME + family + stereo + salt + release


def compose(
    family: str,
    stereo: str = UNSPECIFIED_FACET,
    salt: str = UNSPECIFIED_FACET,
    release: str = UNSPECIFIED_FACET,
) -> str:
    """The full check-valid PSID string for a FAMILY + facets."""
    body = _body(family, stereo, salt, release)
    return f"{SCHEME}-{family}-{stereo}-{salt}-{release}-{iso7064_check_char(body)}"


def parse(psid: str) -> dict | None:
    """Parse a PSID string into ``{family, stereo, salt, release}`` when it is
    well-formed AND its check character is valid; otherwise ``None``. This is the
    fail-fast gate for PSIDs arriving from deep links / imports."""
    parts = psid.split("-")
    if len(parts) != 6:
        return None
    scheme, family, stereo, salt, release, chk = parts
    if scheme != SCHEME or not is_wellformed_family(family):
        return None
    if any(not seg or not all(c in _ALPHABET for c in seg) for seg in (stereo, salt, release)):
        return None
    if iso7064_check_char(_body(family, stereo, salt, release)) != chk:
        return None
    return {"family": family, "stereo": stereo, "salt": salt, "release": release}


def is_valid(psid: str) -> bool:
    """True when ``psid`` parses and its check character verifies."""
    return parse(psid) is not None
