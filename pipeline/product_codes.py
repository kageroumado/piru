"""Product-code primitives shared by the fetcher (`fetch/product_codes.py`), the
build step (`build/sqlite.py::build_product_codes`) and their tests.

A product code is the barcode printed on a medication box, normalized to a
14-digit GTIN so every registry lands in one key space:

- **US NDC** — the package NDC-10 is wrapped as ``0`` + ``03`` + NDC-10 + check
  (the UPC-A on the box is the same digits without the leading ``00``).
- **US UPC** — a retail UPC-A (OTC boxes) is a GTIN-12; left-pad to 14.
- **FR CIP13** — an EAN-13 (prefix ``340``); left-pad to 14.

Name matching folds every name the same way on both sides: NFKD → ASCII →
lowercase → alphanumeric words, then a salt-stripped variant, so
``"CHLORHYDRATE DE MÉTHYLPHÉNIDATE"`` and ``"Methylphenidate Hydrochloride"``
both reach ``"methylphenidate"``.
"""

from __future__ import annotations

import re
import unicodedata

# Salt / hydrate / counter-ion words in English and French. Stripping them from a
# folded name leaves the parent molecule, which is what the alias index knows.
_SALT_WORDS = {
    # English
    "hydrochloride",
    "hcl",
    "dihydrochloride",
    "hydrobromide",
    "hbr",
    "sulfate",
    "sulphate",
    "bisulfate",
    "sodium",
    "potassium",
    "calcium",
    "magnesium",
    "zinc",
    "citrate",
    "tartrate",
    "bitartrate",
    "maleate",
    "malate",
    "mesylate",
    "dimesylate",
    "besylate",
    "tosylate",
    "fumarate",
    "hemifumarate",
    "succinate",
    "acetate",
    "phosphate",
    "diphosphate",
    "bromide",
    "chloride",
    "dihydrate",
    "monohydrate",
    "trihydrate",
    "hemihydrate",
    "hydrate",
    "anhydrous",
    "pamoate",
    "lactate",
    "gluconate",
    "carbonate",
    "oxalate",
    "nitrate",
    "salicylate",
    "napsylate",
    "saccharate",
    "aspartate",
    "base",
    "free",
    "sesquihydrate",
    "hydroxide",
    "oxide",
    "decanoate",
    "enanthate",
    "palmitate",
    "valerate",
    "propionate",
    "butyrate",
    "stearate",
    "benzoate",
    "embonate",
    "edisylate",
    "hyclate",
    "monohydrochloride",
    "trifluoroacetate",
    "hydrogen",
    "disodium",
    "dipotassium",
    "tromethamine",
    "meglumine",
    # French
    "chlorhydrate",
    "bromhydrate",
    "mesilate",
    "besilate",
    "sodique",
    "potassique",
    "calcique",
    "magnesique",
    "anhydre",
    "de",
    "d",
    "du",
    "des",
    "hydrogenosuccinate",
    "hydrogenotartrate",
    "dimesilate",
    "monosodique",
    "disodique",
    "tosilate",
    "napsilate",
    "enantate",
}

_NON_ALNUM = re.compile(r"[^a-z0-9]+")
_PARENTHETICAL = re.compile(r"\([^)]*\)")


def fold_name(name: str) -> str:
    """Accent-fold and lowercase a name to space-separated alphanumeric words."""
    s = unicodedata.normalize("NFKD", name or "").encode("ascii", "ignore").decode()
    return _NON_ALNUM.sub(" ", s.lower()).strip()


def name_keys(name: str) -> list[str]:
    """The lookup keys a registry name is tried under, most specific first: the
    folded name, then the folded name with any parenthetical and every salt
    word removed (``"methylphenidate hydrochloride"`` → ``"methylphenidate"``)."""
    keys: list[str] = []
    folded = fold_name(name)
    if folded:
        keys.append(folded)
    stripped = fold_name(_PARENTHETICAL.sub(" ", name or ""))
    words = [w for w in stripped.split() if w not in _SALT_WORDS]
    bare = " ".join(words)
    if bare and bare not in keys:
        keys.append(bare)
    return keys


def gtin_check_digit(digits: str) -> str:
    """GS1 mod-10 check digit for a run of data digits (rightmost weight 3)."""
    total = 0
    for i, ch in enumerate(reversed(digits)):
        weight = 3 if i % 2 == 0 else 1
        total += int(ch) * weight
    return str((10 - total % 10) % 10)


def gtin14_from_ndc(package_ndc: str) -> str | None:
    """The GTIN-14 a US package NDC prints as: ``003`` + NDC-10 + check.
    Accepts the hyphenated openFDA form (4-4-2 / 5-3-2 / 5-4-1); ``None`` when
    the digits don't make a 10-digit NDC."""
    digits = re.sub(r"\D", "", package_ndc or "")
    if len(digits) != 10:
        return None
    body = "003" + digits
    return body + gtin_check_digit(body)


def gtin14_from_ean(code: str) -> str | None:
    """Left-pad a GTIN-8/12/13 to 14 digits after verifying its check digit;
    ``None`` for a malformed code."""
    digits = re.sub(r"\D", "", code or "")
    if len(digits) not in (8, 12, 13, 14):
        return None
    if gtin_check_digit(digits[:-1]) != digits[-1]:
        return None
    return digits.zfill(14)


# ---------------------------------------------------------------------------
# Pack-size parsing (registry package descriptions)
# ---------------------------------------------------------------------------

# openFDA units → the unit stored in `product_codes.pack_unit`.
_US_UNIT = {
    "tablet": "tablet",
    "capsule": "capsule",
    "ml": "mL",
    "patch": "patch",
    "film": "film",
    "lozenge": "lozenge",
    "troche": "lozenge",
    "packet": "sachet",
    "pouch": "sachet",
    "suppository": "suppository",
    "vial": "vial",
    "ampule": "ampule",
    "syringe": "syringe",
    "cartridge": "cartridge",
    "kit": "kit",
    "g": "g",
    "mg": "mg",
    "spray": "spray",
    "dose": "dose",
    "inhaler": "inhaler",
    "pen": "pen",
    "wafer": "wafer",
    "strip": "strip",
    "granule": "granule",
    "gum": "gum",
    "implant": "implant",
    "insert": "insert",
    "ring": "ring",
    "l": "L",
}
# Innermost levels that are containers, not contents ("1 BOTTLE in 1 CARTON"
# with no inner level): no countable pack size.
_CONTAINERS = {
    "bottle",
    "blister",
    "carton",
    "box",
    "bag",
    "container",
    "tube",
    "jar",
    "can",
    "case",
    "tray",
    "pack",
    "package",
    "cup",
    "bulk",
    "drum",
    "pail",
    "cylinder",
    "tank",
    "canister",
    "plaquette",
    "pilulier",
    "boite",
    "etui",
}

_US_LEVEL = re.compile(
    r"^\s*(\d+(?:\.\d+)?)\s+([A-Za-z][A-Za-z ,]*?)\s+in\s+(\d+)\s+([A-Za-z ,]+?)(?:\s*\(.*)?$"
)


def parse_us_package(description: str) -> tuple[float, str] | None:
    """Total count + unit from an openFDA package description.

    A description is a chain of levels, outermost first, joined by ``>``:
    ``"10 BLISTER PACK in 1 CARTON (…) > 10 TABLET in 1 BLISTER PACK"``. The
    total is the product of every level's count and the unit is the innermost
    level's — ``(100, "tablet")`` here; ``"30 mL in 1 BOTTLE"`` → ``(30, "mL")``.
    ``None`` when no level parses."""
    total = 1.0
    unit: str | None = None
    parsed_any = False
    for level in (description or "").split(">"):
        m = _US_LEVEL.match(level)
        if not m:
            continue
        count, raw_unit, per, _container = m.groups()
        total *= float(count) * float(per)
        # "TABLET, FILM COATED" / "BLISTER PACK" — the first word names the unit.
        unit = raw_unit.split(",")[0].split()[0]
        parsed_any = True
    if not parsed_any or unit is None or unit.lower() in _CONTAINERS:
        return None
    return total, _US_UNIT.get(unit.lower(), unit.lower())


# BDPM "libellé de présentation": "plaquette(s) PVC PVDC aluminium de 30
# comprimé(s)", "3 pilulier(s) polypropylène de 30 comprimé(s)", "1 flacon(s)
# polyéthylène de 5  ml". The first "de N unit" is the content per container
# (a later one describes the outer wrapping); multiply by an optional leading
# container count.
_FR_UNIT = {
    "comprime": "tablet",
    "comprimes": "tablet",
    "gelule": "capsule",
    "gelules": "capsule",
    "capsule": "capsule",
    "capsules": "capsule",
    "ml": "mL",
    "gomme": "gum",
    "gommes": "gum",
    "sachet": "sachet",
    "suppositoire": "suppository",
    "ampoule": "ampule",
    "flacon": "vial",
    "seringue": "syringe",
    "patch": "patch",
    "dispositif": "patch",
    "film": "film",
    "pastille": "lozenge",
    "dose": "dose",
    "g": "g",
    "mg": "mg",
    "stylo": "pen",
    "cartouche": "cartridge",
    "lyophilisat": "wafer",
    "recipient": "vial",
    "unidose": "dose",
    "l": "L",
}
_FR_INNER = re.compile(r"\bde\s+(\d+(?:[.,]\d+)?)\s+([a-z]+)")
_FR_LEADING = re.compile(r"^\s*(\d+)\s+[a-z]")


def parse_fr_presentation(label: str) -> tuple[float, str] | None:
    """Total count + unit from a BDPM presentation label; ``None`` when unparsed."""
    folded = fold_name(label)
    inner = _FR_INNER.search(folded)
    if inner is None:
        return None
    count = float(inner.group(1).replace(",", "."))
    unit = inner.group(2)
    if unit in _CONTAINERS:
        return None
    lead = _FR_LEADING.match(folded)
    if lead:
        count *= float(lead.group(1))
    return count, _FR_UNIT.get(unit, unit)
