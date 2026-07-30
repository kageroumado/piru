"""Render palette-L1.json to a self-contained HTML preview.

Emits real `color(display-p3 …)` values so a P3 display shows the actual
proposed colors, with the sRGB-gamut equivalent beside each for comparison.
Values are read from the JSON — nothing is hand-transcribed.
"""

import json

from colorimetry import (
    composite,
    from_xyz,
    hex_to_rgb,
    oklch,
    rgb_to_hex,
    srgb_to_p3_same_appearance,
    to_xyz,
)

with open("palette-L1.json") as _palette_file:
    P = json.load(_palette_file)
TOK = P["tokens"]
# roles come from the palette, never hardcoded — the ladder length is data
ROLES = [k.split("/")[1] for k in TOK]
CARD = {"light": "#f5f5f5", "dark": "#111111"}
PAGE = {"light": "#ffffff", "dark": "#000000"}
ALPHA = P["_meta"]["fill_alpha"]
# the app's only shipped P3 asset — the family the palette must live with
ACCENT = {"light": (0.898, 0.497, 0.591), "dark": (0.920, 0.268, 0.441)}


def p3(rgb):
    return f"color(display-p3 {rgb[0]:.4f} {rgb[1]:.4f} {rgb[2]:.4f})"


def srgb_of(rgb_p3):
    return rgb_to_hex(from_xyz(to_xyz(rgb_p3, "p3"), "srgb"))


def swatch_row(name, mode):
    e = TOK[f"semantic/{name}"][mode]
    text_p3 = tuple(e["text_p3"])
    acc_p3 = tuple(e["accent_p3"])
    card = hex_to_rgb(CARD[mode])
    card_p3 = srgb_to_p3_same_appearance(card)
    fill_p3 = composite(acc_p3, ALPHA, card_p3, "p3")
    v = e["verified_p3"]
    gain = (e["chroma"]["text_p3"] / e["chroma"]["text_srgb"] - 1) * 100
    oob = "out of sRGB" if e["text_out_of_srgb"] else "in sRGB"
    return f"""
    <tr>
      <th scope="row">{name}</th>
      <td>
        <span class="pill" style="background:{p3(fill_p3)};color:{p3(text_p3)}">
          <span class="dot" style="background:{p3(text_p3)}"></span>Caution label
        </span>
      </td>
      <td><span class="txt" style="color:{p3(text_p3)}">11pt body copy</span></td>
      <td>
        <span class="mark" style="background:{p3(acc_p3)}"></span>
        <span class="bar" style="background:{p3(acc_p3)}"></span>
      </td>
      <td class="num">{v["text_on_fill"]:.2f}</td>
      <td class="num">{v["text_on_card"]:.2f}</td>
      <td class="num">{v["accent_on_card"]:.2f}</td>
      <td class="meta">{e["text_srgb_preview"]}<br><span class="dim">+{gain:.0f}% C · {oob}</span></td>
    </tr>"""


def panel(mode):
    rows = "".join(swatch_row(n, mode) for n in ROLES)
    acc = ACCENT[mode]
    L, C, h = oklch(acc, "p3")
    return f"""
  <section class="panel {mode}" style="--card:{p3(srgb_to_p3_same_appearance(hex_to_rgb(CARD[mode])))};
                                       --page:{p3(srgb_to_p3_same_appearance(hex_to_rgb(PAGE[mode])))}">
    <header>
      <h2>{mode} mode</h2>
      <p class="dim">page {PAGE[mode]} · card {CARD[mode]} (measured)</p>
      <p class="accentline">
        <span class="mark" style="background:{p3(acc)}"></span>
        app accent · Oklch L {L:.2f} C {C:.3f} h {h:.1f}°
      </p>
    </header>
    <table>
      <thead><tr>
        <th>role</th><th>filled pill</th><th>text on card</th><th>accent marks</th>
        <th>t/fill</th><th>t/card</th><th>a/card</th><th>sRGB equiv</th>
      </tr></thead>
      <tbody>{rows}</tbody>
    </table>
  </section>"""


def gamut_strip():
    """sRGB vs P3 side by side — the whole argument for moving to P3."""
    cells = ""
    for n in ROLES:
        e = TOK[f"semantic/{n}"]["light"]
        acc_p3 = tuple(e["accent_p3"])
        # The left half must be the value *independently gated in sRGB* — not the
        # P3 value converted down, which would compare the colour against itself
        # and show no difference at all.
        srgb_hex = e["accent_srgb_gated"]
        cells += f"""
      <div class="gcell">
        <div class="gswatch"><div style="background:{srgb_hex}"></div>
                             <div style="background:{p3(acc_p3)}"></div></div>
        <div class="glabel">{n}<br><span class="dim">sRGB → P3 · +{(e["chroma"]["accent_p3"] / e["chroma"]["accent_srgb"] - 1) * 100:.0f}% chroma</span></div>
      </div>"""
    return f"""
  <section class="gamut">
    <h2>sRGB ceiling vs P3, at identical contrast</h2>
    <p class="dim">Left half of each swatch is the most saturated value sRGB allows at this
       lightness; right half is what P3 allows. Same measured contrast, more color.
       On a non-P3 display the two halves will look identical — that is expected.</p>
    <div class="grow">{cells}</div>
  </section>"""


HTML = f"""<meta charset="utf-8">
<title>Piru semantic palette — Display P3</title>
<style>
  :root {{
    --ink:#1a1a1c; --dim:#6b6b70; --line:#e2e2e4; --bg:#fbfbfc; --panelbg:#fff;
    --mono:ui-monospace,SFMono-Regular,Menlo,monospace;
  }}
  @media (prefers-color-scheme:dark) {{
    :root {{ --ink:#ececed; --dim:#9a9aa0; --line:#2c2c2f; --bg:#131315; --panelbg:#1a1a1c; }}
  }}
  :root[data-theme="dark"] {{ --ink:#ececed; --dim:#9a9aa0; --line:#2c2c2f; --bg:#131315; --panelbg:#1a1a1c; }}
  :root[data-theme="light"] {{ --ink:#1a1a1c; --dim:#6b6b70; --line:#e2e2e4; --bg:#fbfbfc; --panelbg:#fff; }}
  body {{ background:var(--bg); color:var(--ink); font:14px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;
         margin:0; padding:32px; }}
  h1 {{ font-size:20px; margin:0 0 4px; font-weight:600; }}
  h2 {{ font-size:15px; margin:0 0 2px; font-weight:600; text-transform:lowercase; }}
  .dim {{ color:var(--dim); font-size:12px; }}
  .wrap {{ max-width:1180px; margin:0 auto; }}
  .panel {{ background:var(--panelbg); border:1px solid var(--line); border-radius:14px;
            padding:20px; margin:20px 0; overflow-x:auto; }}
  header {{ margin-bottom:14px; }}
  .accentline {{ display:flex; align-items:center; gap:8px; font-size:12px; color:var(--dim); margin:6px 0 0; }}
  table {{ border-collapse:collapse; width:100%; font-size:13px; }}
  th,td {{ text-align:left; padding:9px 10px; border-bottom:1px solid var(--line); vertical-align:middle; }}
  thead th {{ font-size:11px; text-transform:uppercase; letter-spacing:.04em; color:var(--dim); font-weight:600; }}
  tbody th {{ font-weight:600; font-size:13px; }}
  .num {{ font-family:var(--mono); font-size:12px; text-align:right; }}
  .meta {{ font-family:var(--mono); font-size:11px; color:var(--dim); }}
  /* the sample cells sit on the measured card colour, not the page */
  td:nth-child(2),td:nth-child(3),td:nth-child(4) {{ background:var(--card); }}
  .pill {{ display:inline-flex; align-items:center; gap:6px; padding:4px 11px; border-radius:999px;
           font-size:12px; font-weight:600; white-space:nowrap; }}
  .dot {{ width:7px; height:7px; border-radius:50%; display:inline-block; }}
  .txt {{ font-size:11px; font-weight:500; }}
  .mark {{ width:12px; height:12px; border-radius:50%; display:inline-block; vertical-align:middle; }}
  .bar {{ display:inline-block; width:54px; height:7px; border-radius:4px; margin-left:8px; vertical-align:middle; }}
  .gamut {{ background:var(--panelbg); border:1px solid var(--line); border-radius:14px; padding:20px; margin:20px 0; }}
  .grow {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:14px; margin-top:14px; }}
  .gswatch {{ display:flex; height:56px; border-radius:9px; overflow:hidden; }}
  .gswatch div {{ flex:1; }}
  .glabel {{ font-size:12px; margin-top:6px; font-weight:600; }}
  .foot {{ color:var(--dim); font-size:12px; margin-top:24px; }}
</style>
<div class="wrap">
  <h1>Piru semantic palette — Display P3</h1>
  <p class="dim">Generated from <span style="font-family:var(--mono)">palette-L1.json</span>.
     Samples sit on the <em>measured</em> card colors, not on white.
     Ratios are WCAG, computed in P3. <strong>View on a P3 display in Safari</strong> —
     Chrome and non-P3 screens will show the sRGB-clamped approximation.</p>
  {panel("light")}
  {panel("dark")}
  {gamut_strip()}
  <p class="foot">t/fill = text on its own filled pill · t/card = text on the bare card ·
     a/card = accent mark on the card. Gates: text ≥ 4.5:1, accent ≥ 3:1.
     Fill is accent at {ALPHA:.2f} alpha — never authored separately.
     Icons inside a pill use <em>text</em>, never <em>accent</em>.</p>
</div>"""

with open("palette-preview.html", "w") as _out:
    _out.write(HTML)
print("wrote palette-preview.html")
