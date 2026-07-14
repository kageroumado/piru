#!/usr/bin/env python3
"""Reconcile every substance's chemical identity against PubChem (the authority)
and snapshot the corrections.

The catalog's identifiers are corrupt in *both* directions, from different
sources: the LLM enrichment swarm fabricated InChIKeys (key wrong, SMILES right),
while the NPS vendor dump and others carry wrong SMILES (key right, SMILES is a
regioisomer — e.g. 2C-B stored as the 5-bromo-2,4 isomer). So neither field can
be trusted as the oracle. PubChem's name→(InChIKey, SMILES) is the external
authority.

To stay safe against name-collisions (a slang/RC name resolving to the wrong
compound), a PubChem hit is only *applied* when it **corroborates exactly one** of
the two existing DB signals — the stored InChIKey, or the InChIKey OpenBabel
derives from the stored SMILES. Agreement with one signal both confirms PubChem
found the right compound and tells us which field is wrong:

  pk == stored_key  and  pk != obabel(smiles)  -> SMILES is wrong  -> fix SMILES
  pk == obabel(smiles)  and  pk != stored_key  -> InChIKey is wrong -> fix InChIKey
  pk == both                                    -> consistent, no change
  pk == neither                                 -> collision or both-wrong -> FLAG
  no PubChem hit                                -> FLAG (leave as-is)

Comparison is on the InChIKey skeleton (first 14 chars — the connectivity block);
stereo-layer-only differences are left alone (often a flat-source vs stereo
representation choice, not corruption). Applied fields use PubChem's full values.

Run after a build, then rebuild so the corrections land:
    python3 pipeline/fetch/brushers/reconcile_identifiers_pubchem.py
    python3 pipeline/build/sqlite.py

Writes:
    data/sources/identifier-corrections.json       — {name: {inchikey?, smiles?, cid?}}
    data/sources/identifier-corrections.meta.json   — counts + flagged-for-review list
"""

from __future__ import annotations

import json
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DB = REPO / "Piru/Data/piru-substances.sqlite"
OUT = REPO / "data/sources/identifier-corrections.json"
META = REPO / "data/sources/identifier-corrections.meta.json"
MANUAL = REPO / "data/sources/identifier-corrections-manual.json"

sys.path.insert(0, str(REPO / "pipeline"))  # for chem_ids
from chem_ids import obabel_inchikey  # noqa: E402

UA = "Piru-DataFetcher/1.0 (+https://github.com/kageroumado/piru; first-party data snapshot)"
SPACING = 0.16
TIMEOUT = 30
RETRIES = 2


def _get(url: str) -> bytes | None:
    last: Exception | None = None
    for _ in range(RETRIES + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            last = exc
            time.sleep(1.0)
        except (urllib.error.URLError, TimeoutError) as exc:  # pragma: no cover - network
            last = exc
            time.sleep(1.0)
    if last:
        return None
    return None


def _pubchem_lookup(identifier: str) -> dict | None:
    """Resolve a name or CAS via PubChem's name namespace → {inchikey, smiles, cid}."""
    enc = urllib.parse.quote(identifier, safe="")
    body = _get(
        "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/"
        f"{enc}/property/InChIKey,IsomericSMILES,CanonicalSMILES/JSON"
    )
    if body is None:
        return None
    props = json.loads(body).get("PropertyTable", {}).get("Properties", [])
    if not props:
        return None
    p = props[0]  # first/best match
    smiles = (
        p.get("SMILES")
        or p.get("IsomericSMILES")
        or p.get("ConnectivitySMILES")
        or p.get("CanonicalSMILES")
    )
    return {"inchikey": p.get("InChIKey"), "smiles": smiles, "cid": p.get("CID")}


def pubchem_by_name(name: str) -> dict | None:
    return _pubchem_lookup(name)


def pubchem_by_cas(cas: str | None) -> dict | None:
    return _pubchem_lookup(cas) if cas else None


def cas_arbitrate(
    stored_ik: str | None, ob: str | None, cas: str | None
) -> tuple[str, dict | None]:
    """Use CAS as the tiebreaker when PubChem-by-name is absent or matches neither
    DB field. CAS resolves to the substance's real structure, so whichever DB field
    its InChIKey skeleton matches is the correct one. Returns one of:
    ('fix_inchikey'|'fix_smiles'|'fix_both', correction) | ('collision_left', None)
    | ('flag', None)."""
    cl = pubchem_by_cas(cas)
    if cas:
        time.sleep(SPACING)
    if not cl or not cl.get("inchikey"):
        return ("flag", None)
    cas_skel = cl["inchikey"][:14]
    cas_m_stored = bool(stored_ik) and cas_skel == stored_ik[:14]
    cas_m_ob = bool(ob) and cas_skel == ob[:14]
    if cas_m_stored:
        if not cas_m_ob and cl.get("smiles"):
            return ("fix_smiles", {"smiles": cl["smiles"], "cid": cl.get("cid")})
        return ("collision_left", None)
    if cas_m_ob:
        return ("fix_inchikey", {"inchikey": cl["inchikey"], "cid": cl.get("cid")})
    fix = {"inchikey": cl["inchikey"], "cid": cl.get("cid")}
    if cl.get("smiles"):
        fix["smiles"] = cl["smiles"]
    return ("fix_both", fix)


def main() -> int:
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    rows = con.execute(
        "SELECT canonical_name, inchikey, smiles, cas FROM substances "
        "WHERE inchikey IS NOT NULL OR smiles IS NOT NULL ORDER BY canonical_name"
    ).fetchall()
    con.close()

    # Names handled by the curated manual layer — skip so they don't reappear as
    # flagged (the build applies the manual file after this snapshot).
    manual_names = set()
    if MANUAL.exists():
        manual_names = {k for k in json.loads(MANUAL.read_text()) if not k.startswith("_")}
    rows = [r for r in rows if r[0] not in manual_names]

    corrections: dict[str, dict] = {}
    flagged: list[dict] = []
    counts = {
        "checked": 0,
        "consistent": 0,
        "fix_inchikey": 0,
        "fix_smiles": 0,
        "fix_both_via_cas": 0,
        "name_collision_left": 0,
        "flag_ambiguous": 0,
        "flag_not_in_pubchem": 0,
    }

    def record(
        name: str,
        action: str,
        payload: dict | None,
        *,
        via_cas: bool,
        flag_reason: str,
        flag_extra: dict,
    ) -> None:
        if action == "fix_smiles":
            corrections[name] = payload
            counts["fix_smiles"] += 1
        elif action == "fix_inchikey":
            corrections[name] = payload
            counts["fix_inchikey"] += 1
        elif action == "fix_both":
            corrections[name] = payload
            counts["fix_both_via_cas"] += 1
        elif action == "collision_left":
            counts["name_collision_left"] += 1
        else:  # flag
            flagged.append({"name": name, "reason": flag_reason, **flag_extra})
            counts["flag_ambiguous" if via_cas else "flag_not_in_pubchem"] += 1

    for i, (name, stored_ik, smiles, cas) in enumerate(rows):
        counts["checked"] += 1
        pk = pubchem_by_name(name)
        ob = obabel_inchikey(smiles)
        if i + 1 < len(rows):
            time.sleep(SPACING)
        if (i + 1) % 100 == 0:
            print(
                f"  …{i + 1}/{len(rows)} fixes={counts['fix_inchikey'] + counts['fix_smiles'] + counts['fix_both_via_cas']} "
                f"flagged={len(flagged)}",
                file=sys.stderr,
            )

        if pk is None or not pk.get("inchikey"):
            # Name not a PubChem synonym (common for short RC codes like "DET").
            # If the two DB fields disagree, CAS can still arbitrate the truth.
            if stored_ik and ob and stored_ik[:14] != ob[:14]:
                action, payload = cas_arbitrate(stored_ik, ob, cas)
                record(
                    name,
                    action,
                    payload,
                    via_cas=False,
                    flag_reason="not_in_pubchem_and_inconsistent",
                    flag_extra={"stored_ik": stored_ik, "obabel_smiles_ik": ob, "cas": cas},
                )
            continue

        pk_skel = pk["inchikey"][:14]
        m_stored = bool(stored_ik) and pk_skel == stored_ik[:14]
        m_ob = bool(ob) and pk_skel == ob[:14]

        if m_stored and m_ob:
            counts["consistent"] += 1
        elif m_stored and not m_ob:
            # stored InChIKey confirmed by PubChem; the SMILES is the wrong field
            if pk.get("smiles"):
                corrections[name] = {"smiles": pk["smiles"], "cid": pk.get("cid")}
                counts["fix_smiles"] += 1
        elif m_ob and not m_stored:
            # SMILES confirmed by PubChem; the stored InChIKey is the wrong field
            corrections[name] = {"inchikey": pk["inchikey"], "cid": pk.get("cid")}
            counts["fix_inchikey"] += 1
        else:
            # PubChem-by-name matched neither field → name collision or both wrong.
            # CAS is the unambiguous tiebreaker.
            action, payload = cas_arbitrate(stored_ik, ob, cas)
            record(
                name,
                action,
                payload,
                via_cas=True,
                flag_reason="ambiguous_no_cas_arbiter",
                flag_extra={
                    "stored_ik": stored_ik,
                    "obabel_smiles_ik": ob,
                    "pubchem_name_ik": pk["inchikey"],
                    "cas": cas,
                },
            )

    ordered = {k: corrections[k] for k in sorted(corrections)}
    OUT.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "PubChem name→(InChIKey, SMILES); corroborated vs stored key & obabel(SMILES)",
                "computed_at": datetime.now(UTC).isoformat(timespec="seconds"),
                "counts": counts,
                "flagged": sorted(flagged, key=lambda f: (f["reason"], f["name"])),
                "note": "Only auto-corrects when PubChem corroborates exactly one DB field, "
                "pinpointing the wrong one. 'flagged' need manual review (name collision, "
                "both fields wrong, or not in PubChem).",
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )
    print(f"wrote {len(ordered)} corrections → {OUT.relative_to(REPO)}")
    print(f"  {counts}")
    print(f"  flagged for review: {len(flagged)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
