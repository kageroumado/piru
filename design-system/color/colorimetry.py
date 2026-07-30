"""Dependency-free colorimetry for the Piru color audit.

Everything the audit needs, with no third-party imports so results are
reproducible on any machine:

  * sRGB / Display-P3  <->  linear  <->  XYZ(D65)  <->  Oklab / Oklch
  * WCAG 2.1 contrast ratio
  * APCA-W3 0.1.9 lightness contrast (Lc)
  * alpha compositing (SwiftUI `.opacity` happens in *linear-ish* display
    space -- see `composite` for the caveat)
  * gamut containment tests + chroma reduction to fit a gamut
  * the two distinct ways to move an sRGB value to P3, which are NOT the same
    thing and are the single biggest trap in a P3 migration

Run `python3 colorimetry.py` to execute the self-tests.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence

Vec3 = tuple[float, float, float]

# --------------------------------------------------------------------------
# matrices
# --------------------------------------------------------------------------

# linear sRGB -> XYZ (D65)
M_SRGB_TO_XYZ: tuple[Vec3, Vec3, Vec3] = (
    (0.4123907992659595, 0.3575843393838780, 0.1804807884018343),
    (0.2126390058715104, 0.7151686787677559, 0.0721923153607337),
    (0.0193308187155918, 0.1191947797946259, 0.9505321522496608),
)

# linear Display-P3 -> XYZ (D65)
M_P3_TO_XYZ: tuple[Vec3, Vec3, Vec3] = (
    (0.4865709486482162, 0.2656676931690929, 0.1982172852343625),
    (0.2289745640697488, 0.6917385218365064, 0.0792869140937449),
    (0.0000000000000000, 0.0451133818589026, 1.0439443689009760),
)

# Oklab: XYZ(D65) -> LMS, then cube-root, then LMS' -> Lab
M_XYZ_TO_LMS: tuple[Vec3, Vec3, Vec3] = (
    (0.8189330101, 0.3618667424, -0.1288597137),
    (0.0329845436, 0.9293118715, 0.0361456387),
    (0.0482003018, 0.2643662691, 0.6338517070),
)
M_LMS_TO_LAB: tuple[Vec3, Vec3, Vec3] = (
    (0.2104542553, 0.7936177850, -0.0040720468),
    (1.9779984951, -2.4285922050, 0.4505937099),
    (0.0259040371, 0.7827717662, -0.8086757660),
)


def _mul(m: Sequence[Vec3], v: Vec3) -> Vec3:
    return (
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    )


def _inv(m: Sequence[Vec3]) -> tuple[Vec3, Vec3, Vec3]:
    (a, b, c), (d, e, f), (g, h, i) = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return (
        ((e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det),
        ((f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det),
        ((d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det),
    )


M_XYZ_TO_SRGB = _inv(M_SRGB_TO_XYZ)
M_XYZ_TO_P3 = _inv(M_P3_TO_XYZ)
M_LAB_TO_LMS = _inv(M_LMS_TO_LAB)
M_LMS_TO_XYZ = _inv(M_XYZ_TO_LMS)

# --------------------------------------------------------------------------
# transfer function -- sRGB and Display-P3 share it on Apple platforms
# --------------------------------------------------------------------------


def eotf(c: float) -> float:
    """Encoded value -> linear light. Sign-preserving, so extended-range
    (out-of-[0,1]) components survive the round trip intact."""
    s = -1.0 if c < 0 else 1.0
    c = abs(c)
    return s * (c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)


def oetf(c: float) -> float:
    """Linear light -> encoded value. Inverse of `eotf`."""
    s = -1.0 if c < 0 else 1.0
    c = abs(c)
    return s * (c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055)


def hex_to_rgb(h: str) -> Vec3:
    """`#RRGGBB` / `RGB` / `RRGGBBAA` -> encoded 0..1 triple (alpha dropped).

    Mirrors `Shared/Formatting/ColorHex.swift`, including its shorthand
    expansion, so audit numbers match what the app actually parses."""
    h = "".join(ch for ch in h if ch.isalnum())
    if len(h) == 3:
        h = "".join(ch * 2 for ch in h)
    if len(h) == 8:
        h = h[:6]
    if len(h) != 6:
        raise ValueError(f"bad hex: {h!r}")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def rgb_to_hex(rgb: Vec3, clip: bool = True) -> str:
    vals: Iterable[float] = (min(1.0, max(0.0, c)) for c in rgb) if clip else rgb
    return "#" + "".join(f"{round(c * 255):02X}" for c in vals)


# --------------------------------------------------------------------------
# space conversions
# --------------------------------------------------------------------------


def to_xyz(rgb: Vec3, space: str = "srgb") -> Vec3:
    lin = (eotf(rgb[0]), eotf(rgb[1]), eotf(rgb[2]))
    return _mul(M_SRGB_TO_XYZ if space == "srgb" else M_P3_TO_XYZ, lin)


def from_xyz(xyz: Vec3, space: str = "srgb") -> Vec3:
    lin = _mul(M_XYZ_TO_SRGB if space == "srgb" else M_XYZ_TO_P3, xyz)
    return (oetf(lin[0]), oetf(lin[1]), oetf(lin[2]))


def oklab(rgb: Vec3, space: str = "srgb") -> Vec3:
    lms = _mul(M_XYZ_TO_LMS, to_xyz(rgb, space))
    lms_ = tuple(math.copysign(abs(v) ** (1 / 3), v) for v in lms)
    return _mul(M_LMS_TO_LAB, lms_)  # type: ignore[arg-type]


def oklab_to_rgb(lab: Vec3, space: str = "srgb") -> Vec3:
    lms_ = _mul(M_LAB_TO_LMS, lab)
    lms = tuple(v**3 for v in lms_)
    return from_xyz(_mul(M_LMS_TO_XYZ, lms), space)  # type: ignore[arg-type]


def oklch(rgb: Vec3, space: str = "srgb") -> Vec3:
    """-> (L 0..1, C, h degrees 0..360). Hue is undefined at C~0; returns 0."""
    L, a, b = oklab(rgb, space)
    C = math.hypot(a, b)
    h = math.degrees(math.atan2(b, a)) % 360 if C > 1e-7 else 0.0
    return (L, C, h)


def oklch_to_rgb(lch: Vec3, space: str = "srgb") -> Vec3:
    L, C, h = lch
    r = math.radians(h)
    return oklab_to_rgb((L, C * math.cos(r), C * math.sin(r)), space)


# --------------------------------------------------------------------------
# gamut
# --------------------------------------------------------------------------


def in_gamut(rgb: Vec3, tol: float = 1e-4) -> bool:
    return all(-tol <= c <= 1 + tol for c in rgb)


def fit_chroma(lch: Vec3, space: str = "srgb") -> Vec3:
    """Largest chroma <= the requested one that lands inside `space`.

    Binary search holding L and h fixed -- the standard CSS Color 4 style
    gamut map. Preserves hue exactly, which naive RGB clipping does not."""
    L, C, h = lch
    if in_gamut(oklch_to_rgb(lch, space)):
        return lch
    lo, hi = 0.0, C
    for _ in range(48):
        mid = (lo + hi) / 2
        if in_gamut(oklch_to_rgb((L, mid, h), space)):
            lo = mid
        else:
            hi = mid
    return (L, lo, h)


# --------------------------------------------------------------------------
# the P3 migration trap
# --------------------------------------------------------------------------


def srgb_to_p3_same_appearance(rgb: Vec3) -> Vec3:
    """Colorimetric conversion: the color LOOKS IDENTICAL, numbers change.

    This is what you want when migrating existing colors to a P3 asset
    catalog without redesigning them."""
    return from_xyz(to_xyz(rgb, "srgb"), "p3")


def srgb_to_p3_same_numbers(rgb: Vec3) -> Vec3:
    """Reinterpretation: numbers kept, the color SHIFTS (more saturated).

    This is what you get by pasting sRGB components into a `display-p3`
    colorset -- almost always an accident. Returned for comparison so the
    audit can quantify the shift rather than hand-wave about it."""
    return rgb


def p3_shift_delta(rgb: Vec3) -> float:
    """Oklab dE between an sRGB color and the same numbers read as P3.

    Quantifies the error of a numbers-preserving 'migration'."""
    a = oklab(rgb, "srgb")
    b = oklab(rgb, "p3")
    return math.dist(a, b)


# --------------------------------------------------------------------------
# compositing
# --------------------------------------------------------------------------


def composite(fg: Vec3, alpha: float, bg: Vec3, space: str = "srgb") -> Vec3:
    """`fg.opacity(alpha)` over opaque `bg`.

    Blends in LINEAR light, which is what the GPU does. Blending the encoded
    values instead (the naive approach) skews midtones and would make every
    contrast number in this audit slightly wrong."""
    f = [eotf(c) for c in fg]
    b = [eotf(c) for c in bg]
    return tuple(oetf(f[i] * alpha + b[i] * (1 - alpha)) for i in range(3))  # type: ignore[return-value]


# --------------------------------------------------------------------------
# contrast -- WCAG 2.1
# --------------------------------------------------------------------------


def relative_luminance(rgb: Vec3, space: str = "srgb") -> float:
    """WCAG relative luminance, generalized to wide-gamut spaces.

    WCAG 2.1 defines Y with the sRGB primaries. Applying those coefficients to
    Display-P3 components is simply wrong -- P3's primaries are different
    chromaticities, so the same numbers carry different luminance. Taking CIE Y
    straight from XYZ is the correct generalization, and for sRGB input it is
    numerically identical to the WCAG formula (the sRGB->XYZ middle row *is*
    (0.2126, 0.7152, 0.0722), to rounding)."""
    return to_xyz(rgb, space)[1]


def wcag_ratio(fg: Vec3, bg: Vec3, space: str = "srgb") -> float:
    """Contrast ratio. Pass `space="p3"` when the components are P3-encoded;
    mixing spaces in one call is a bug, so both are read in the same space."""
    a, b = relative_luminance(fg, space), relative_luminance(bg, space)
    lo, hi = sorted((a, b))
    return (hi + 0.05) / (lo + 0.05)


def wcag_passes(ratio: float, pt: float, bold: bool = False) -> dict[str, bool]:
    large = pt >= 18 or (bold and pt >= 14)
    return {
        "AA": ratio >= (3.0 if large else 4.5),
        "AAA": ratio >= (4.5 if large else 7.0),
        "large_text": large,
    }


# --------------------------------------------------------------------------
# contrast -- APCA-W3 0.1.9
# --------------------------------------------------------------------------

_APCA = {
    "trc": 2.4,
    "rco": 0.2126729,
    "gco": 0.7151522,
    "bco": 0.0721750,
    "norm_bg": 0.56,
    "norm_txt": 0.57,
    "rev_txt": 0.62,
    "rev_bg": 0.65,
    "blk_thrs": 0.022,
    "blk_clmp": 1.414,
    "scale_bow": 1.14,
    "lo_bow_off": 0.027,
    "scale_wob": 1.14,
    "lo_wob_off": 0.027,
    "delta_y_min": 0.0005,
    "lo_clip": 0.1,
}


def _apca_y(rgb: Vec3) -> float:
    k = _APCA
    y = (
        k["rco"] * abs(rgb[0]) ** k["trc"]
        + k["gco"] * abs(rgb[1]) ** k["trc"]
        + k["bco"] * abs(rgb[2]) ** k["trc"]
    )
    return y + (k["blk_thrs"] - y) ** k["blk_clmp"] if y < k["blk_thrs"] else y


def apca_lc(fg: Vec3, bg: Vec3) -> float:
    """APCA lightness contrast. Sign carries polarity:
    positive = dark text on light bg, negative = light text on dark bg.

    Perceptually far better calibrated than WCAG 2.1 for thin/small UI text,
    which is most of Piru's colored copy -- hence reporting both."""
    k = _APCA
    ytxt, ybg = _apca_y(fg), _apca_y(bg)
    if abs(ybg - ytxt) < k["delta_y_min"]:
        return 0.0
    if ybg > ytxt:  # normal polarity
        sapc = (ybg ** k["norm_bg"] - ytxt ** k["norm_txt"]) * k["scale_bow"]
        out = 0.0 if sapc < k["lo_clip"] else sapc - k["lo_bow_off"]
    else:  # reverse polarity
        sapc = (ybg ** k["rev_bg"] - ytxt ** k["rev_txt"]) * k["scale_wob"]
        out = 0.0 if sapc > -k["lo_clip"] else sapc + k["lo_wob_off"]
    return out * 100


def apca_min_lc(pt: float, weight: int = 400) -> float:
    """Minimum |Lc| the APCA readability tables ask for at a given size.

    Condensed from the APCA font-size lookup: the full table is 2-D over
    size x weight. These are the practical floors this audit enforces --
    conservative, and documented as such rather than presented as spec."""
    if pt >= 24 or (pt >= 18 and weight >= 600):
        return 60.0
    if pt >= 16:
        return 75.0
    return 90.0  # <16pt body/caption text -- most of Piru's colored labels


def verdict(fg: Vec3, bg: Vec3, pt: float, weight: int = 400) -> dict:
    ratio = wcag_ratio(fg, bg)
    lc = apca_lc(fg, bg)
    need = apca_min_lc(pt, weight)
    w = wcag_passes(ratio, pt, weight >= 600)
    return {
        "wcag_ratio": round(ratio, 2),
        "wcag_AA": w["AA"],
        "wcag_AAA": w["AAA"],
        "apca_lc": round(lc, 1),
        "apca_min": need,
        "apca_passes": abs(lc) >= need,
        "verdict": "PASS" if (w["AA"] and abs(lc) >= need) else "FAIL",
    }


# --------------------------------------------------------------------------
# self-tests
# --------------------------------------------------------------------------


def _test() -> None:
    def close(a, b, eps=2e-3, what=""):
        assert abs(a - b) < eps, f"{what}: {a} != {b}"

    # Oklab reference values (Ottosson).
    # White lands ~1e-4 off neutral: the published XYZ->LMS and sRGB->XYZ
    # matrices are each rounded, so D65 white does not chain to exactly
    # (1, 0, 0). That residue is ~20x below the Oklab JND (~0.002), so the
    # tolerance here is 5e-4 rather than pretending at exactness.
    L, a, b = oklab(hex_to_rgb("#FFFFFF"))
    close(L, 1.0, 1e-3, "white L")
    close(a, 0, 5e-4, "white a")
    close(b, 0, 5e-4, "white b")
    L, C, h = oklch(hex_to_rgb("#FF0000"))
    close(L, 0.6279, 1e-3, "red L")
    close(C, 0.2577, 1e-3, "red C")
    close(h, 29.23, 0.1, "red h")
    L, C, h = oklch(hex_to_rgb("#0000FF"))
    close(L, 0.4520, 1e-3, "blue L")
    close(h, 264.05, 0.2, "blue h")

    # round trips
    for hx in ("#FF0000", "#00FF00", "#3A7BD5", "#856300", "#111113"):
        rgb = hex_to_rgb(hx)
        assert rgb_to_hex(oklch_to_rgb(oklch(rgb))) == hx, f"oklch round trip {hx}"
        assert rgb_to_hex(from_xyz(to_xyz(rgb))) == hx, f"xyz round trip {hx}"

    # WCAG anchors
    close(wcag_ratio(hex_to_rgb("#000"), hex_to_rgb("#FFF")), 21.0, 1e-6, "wcag bw")
    close(wcag_ratio(hex_to_rgb("#777"), hex_to_rgb("#FFF")), 4.48, 1e-2, "wcag gray")

    # APCA anchors (APCA-W3 0.1.9 published pairs)
    close(apca_lc(hex_to_rgb("#000"), hex_to_rgb("#FFF")), 106.04, 0.1, "apca b-on-w")
    close(apca_lc(hex_to_rgb("#FFF"), hex_to_rgb("#000")), -107.88, 0.1, "apca w-on-b")
    close(apca_lc(hex_to_rgb("#888"), hex_to_rgb("#FFF")), 63.06, 0.5, "apca gray-on-w")
    assert apca_lc(hex_to_rgb("#FFF"), hex_to_rgb("#FFF")) == 0.0, "apca identical"

    # compositing: alpha 1 and 0 are identity
    bg, fg = hex_to_rgb("#FFFFFF"), hex_to_rgb("#FF0000")
    assert rgb_to_hex(composite(fg, 1.0, bg)) == "#FF0000"
    assert rgb_to_hex(composite(fg, 0.0, bg)) == "#FFFFFF"

    # gamut: P3-only color is outside sRGB, fit_chroma pulls it in at same hue
    p3_green = (0.0, 1.0, 0.0)
    as_srgb = from_xyz(to_xyz(p3_green, "p3"), "srgb")
    assert not in_gamut(as_srgb), "p3 green should exceed sRGB"
    lch = oklch(p3_green, "p3")
    fitted = fit_chroma(lch, "srgb")
    assert in_gamut(oklch_to_rgb(fitted, "srgb")), "fitted should be in sRGB"
    close(fitted[2], lch[2], 1e-6, "fit preserves hue")
    assert fitted[1] < lch[1], "fit reduces chroma"

    # the migration trap is real and measurable
    assert p3_shift_delta(hex_to_rgb("#FF0000")) > 0.02, "p3 reinterpretation should shift red"
    same = srgb_to_p3_same_appearance(hex_to_rgb("#FF0000"))
    close(
        math.dist(oklab(same, "p3"), oklab(hex_to_rgb("#FF0000"), "srgb")),
        0.0,
        1e-6,
        "colorimetric",
    )

    print("all colorimetry self-tests passed")


if __name__ == "__main__":
    _test()
