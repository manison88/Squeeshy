#!/usr/bin/env python3
"""Five minimal directions for Squish Index, two screens each."""
import base64
import os

HERE = os.path.dirname(os.path.abspath(__file__))
VENDOR = "/home/user/Squeeshy/Design/mockups/fonts"


def face(path):
    data = base64.b64encode(open(path, "rb").read()).decode()
    return f"url(data:font/woff2;base64,{data}) format('woff2')"


FONTS = {
    "__INTER__": face(f"{VENDOR}/inter-400600.woff2"),
    "__MONO__": face(f"{VENDOR}/dmmono-400.woff2"),
    "__MONO5__": face(f"{VENDOR}/dmmono-500.woff2"),
    "__ARCHIVO__": face(f"{HERE}/archivo.woff2"),
    "__SERIF__": face(f"{HERE}/newsreader.woff2"),
}

# ---------------------------------------------------------------- specimens
# Geometric object studies. No faces, no highlights, no cartoon: a catalogue
# plate records the form, not a personality.
SHAPES = {
    "disc": '<circle cx="50" cy="50" r="38"/>',
    "ovoid": '<ellipse cx="50" cy="50" rx="31" ry="40"/>',
    "bun": '<rect x="13" y="23" width="74" height="54" rx="27"/>',
    "block": '<rect x="21" y="25" width="58" height="50" rx="9"/>',
    "loaf": '<rect x="8" y="33" width="84" height="34" rx="17"/>',
    "drop": '<path d="M50 11c14 17 27 27 27 41a27 27 0 1 1-54 0c0-14 13-24 27-41z"/>',
    "pip": '<circle cx="50" cy="52" r="25"/>',
    "knot": ('<path d="M38 14h24a8 8 0 0 1 8 8v8h8a8 8 0 0 1 8 8v24a8 8 0 0 1-8 8h-8v8'
             'a8 8 0 0 1-8 8H38a8 8 0 0 1-8-8v-8h-8a8 8 0 0 1-8-8V38a8 8 0 0 1 8-8h8v-8'
             'a8 8 0 0 1 8-8z"/>'),
}

S = [
    dict(name="Ochre bun", shape="bun", hex="#C08A3E", squish=7, mm=(88, 64), colour="Ochre"),
    dict(name="Clay ovoid", shape="ovoid", hex="#AE6350", squish=9, mm=(61, 78), colour="Clay"),
    dict(name="Sage disc", shape="disc", hex="#7C8F72", squish=4, mm=(74, 74), colour="Sage"),
    dict(name="Slate block", shape="block", hex="#5E6B78", squish=2, mm=(112, 66), colour="Slate"),
    dict(name="Plum drop", shape="drop", hex="#6E5570", squish=8, mm=(52, 70), colour="Plum"),
    dict(name="Sand loaf", shape="loaf", hex="#BFAE8E", squish=5, mm=(140, 58), colour="Sand"),
    dict(name="Cobalt pip", shape="pip", hex="#3E5A72", squish=10, mm=(44, 44), colour="Cobalt"),
    dict(name="Oxblood knot", shape="knot", hex="#8C4340", squish=6, mm=(96, 92), colour="Oxblood"),
]

TERMS = {1: "Rigid", 2: "Firm", 3: "Dense", 4: "Resilient", 5: "Even",
         6: "Soft", 7: "Slack", 8: "Deep", 9: "Slow rise", 10: "Barely holds shape"}

HERO = S[0]


def art(spec, fill=None, stroke=None, width=1.5):
    body = SHAPES[spec["shape"]]
    if stroke:
        attrs = f'fill="none" stroke="{stroke}" stroke-width="{width}"'
    else:
        attrs = f'fill="{fill or spec["hex"]}"'
    return (f'<svg viewBox="0 0 100 100" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" '
            f'aria-hidden="true" {attrs}>{body}</svg>')


def pad(n):
    return f"{n:02d}"


# ---------------------------------------------------------------- durometer
# Area-conserving compression, UX-SPEC §5.1 — kept literally in Ledger,
# reinterpreted in the other four.
def bars(level, height=64, slot=17, w0=7, w1=15, fill="#0B0B0C", empty="#C9C9C6", radius=0):
    out = []
    k = (level - 1) / 9
    for i in range(1, 11):
        on = i <= level
        kk = k if on else 0
        base = height - (i - 1) * (height * 0.25 / 9)
        w = w0 + (w1 - w0) * kk
        h = base * (w0 / w)
        r = min(radius * (0.3 + kk), w / 2) if radius else 0
        out.append(f'<span class="b" style="width:{slot}px;height:{height}px">'
                   f'<i style="width:{w:.1f}px;height:{h:.1f}px;border-radius:{r:.1f}px;'
                   f'background:{fill if on else empty}"></i></span>')
    return f'<span class="bars">{"".join(out)}</span>'


# ================================================================ 1 · LEDGER
def ledger():
    cards = ""
    for spec in S[:6]:
        cards += f'''
        <div class="c">
          <div class="pl">{art(spec)}</div>
          <div class="nm">{spec["name"]}</div>
          <div class="mt"><span>{spec["colour"]}</span><span>{pad(spec["squish"])}</span></div>
        </div>'''
    rows = "".join(
        f'<div class="r"><span>{a}</span><span>{b}</span></div>'
        for a, b in [("Form", "Bun"), ("Colour", "Ochre &middot; #C08A3E"),
                     ("Size", "88 &times; 64 mm"), ("Method", "LiDAR"),
                     ("Squish", f'07 &middot; {TERMS[7]}'), ("Filed", "16.08.2026")])
    return f'''
<div class="dev v1"><div class="scr">
  <div class="st"></div>
  <header>
    <span class="ey">Squish Index</span>
    <h2>Collection</h2>
    <span class="ey n">8 specimens / mean 6.4</span>
  </header>
  <nav><span class="on">Index</span><span>Scale</span><span>Analysis</span></nav>
  <div class="grid">{cards}</div>
  <div class="foot">New specimen</div>
</div></div>

<div class="dev v1"><div class="scr">
  <div class="st"></div>
  <header class="tight"><span class="ey">Specimen 001</span><h2>Ochre bun</h2></header>
  <div class="hero">{art(HERO)}</div>
  <div class="rows">{rows}</div>
  <div class="duro">
    <span class="ey">Squish</span>
    {bars(7)}
    <span class="num">7</span>
  </div>
  <div class="sent">{TERMS[7]}. Squashes nearly flat under light pressure.</div>
  <div class="pal">
    <span class="ey">Palette</span>
    <span class="sw"><i style="background:#C08A3E"></i><i style="background:#E0C79A"></i>
      <i style="background:#8E6224"></i><i style="background:#FFFFFF"></i></span>
  </div>
  <div class="foot">New specimen</div>
</div></div>'''


# ============================================================ 2 · INSTRUMENT
def instrument():
    rows = ""
    for i, spec in enumerate(S):
        rows += f'''
        <div class="row">
          <span class="ix">{i + 1:03d}</span>
          <span class="th">{art(spec, stroke=spec["hex"], width=2.5)}</span>
          <span class="nm">{spec["name"]}</span>
          <span class="mm">{spec["mm"][0]}&times;{spec["mm"][1]}</span>
          <span class="sq">{pad(spec["squish"])}</span>
        </div>'''
    meter = "".join(
        f'<i class="{"on" if i <= 7 else ""}"></i>' for i in range(1, 11))
    counts = [0] * 10
    for spec in S:
        counts[spec["squish"] - 1] += 1
    top = max(counts)
    spark = "".join(
        f'<i style="height:{2 + 12 * (c / top):.0f}px;opacity:{1 if c else .35}"></i>'
        for c in counts)
    return f'''
<div class="dev v2"><div class="scr">
  <div class="st"></div>
  <header>
    <span class="ey">Squish Index / Collection</span>
    <div class="readout"><span class="big">08</span><span class="unit">specimens</span>
      <span class="big r">6.4</span><span class="unit">mean squish</span></div>
  </header>
  <div class="hd"><span>Idx</span><span></span><span>Specimen</span><span>mm</span><span>Sq</span></div>
  <div class="list">{rows}</div>
  <div class="summary">
    <span><b>08</b> measured</span><span><b>44</b> mm smallest</span><span><b>140</b> mm largest</span>
  </div>
  <div class="foot">
    <span class="ey">Distribution</span>
    <span class="spark">{spark}</span>
    <span class="cap-btn">Capture</span>
  </div>
</div></div>

<div class="dev v2"><div class="scr">
  <div class="st"></div>
  <div class="frame">{art(HERO, stroke=HERO["hex"], width=2)}
    <span class="cross v"></span><span class="cross h"></span>
    <span class="dim w">88.0 mm</span><span class="dim h2">64.0 mm</span>
  </div>
  <div class="panel">
    <div class="ttl">Ochre bun</div>
    <div class="meter"><span class="ey">Squish</span><span class="m">{meter}</span><span class="v">07</span></div>
    <div class="kv"><span>Form</span><b>Bun</b><span>Colour</span><b>Ochre</b>
      <span>Method</span><b>LiDAR 90%</b><span>Filed</span><b>16.08.26</b></div>
    <div class="note">{TERMS[7]}. Squashes nearly flat under light pressure.</div>
  </div>
  <div class="foot">
    <span class="ey">Palette</span>
    <span class="sw"><i style="background:#C08A3E"></i><i style="background:#E0C79A"></i>
      <i style="background:#8E6224"></i></span>
    <span class="cap-btn">Retake</span>
  </div>
</div></div>'''


# ================================================================= 3 · PLATE
def plate():
    tiles = "".join(
        f'<div class="t"><div class="im">{art(spec)}</div>'
        f'<div class="lb">{spec["name"]}<span>{pad(spec["squish"])}</span></div></div>'
        for spec in S)
    ticks = "".join(f'<i class="{"on" if i <= 7 else ""}"></i>' for i in range(1, 11))
    return f'''
<div class="dev v3"><div class="scr">
  <div class="st"></div>
  <h2>The collection</h2>
  <p class="sub">Eight specimens, measured on device.</p>
  <div class="tiles">{tiles}</div>
</div></div>

<div class="dev v3"><div class="scr">
  <div class="bleed">{art(HERO)}</div>
  <div class="cap">
    <h3>Ochre bun</h3>
    <p class="dsc">Bun, 88 &times; 64 millimetres. Measured with LiDAR.</p>
    <div class="scale"><span class="lbl">Squish</span><span class="rule">{ticks}</span><span class="fig">7</span></div>
    <p class="dsc q">{TERMS[7]}. Squashes nearly flat under light pressure, and comes back slowly.</p>
  </div>
</div></div>'''


# ============================================================== 4 · REGISTER
def register():
    rows = ""
    for i, spec in enumerate(S):
        cells = "".join(f'<i class="{"on" if n <= spec["squish"] else ""}"></i>' for n in range(1, 11))
        rows += f'''
        <tr>
          <td class="ix">{i + 1:03d}</td>
          <td class="th"><span style="background:{spec["hex"]}"></span></td>
          <td class="nm">{spec["name"]}</td>
          <td class="cl">{spec["colour"]}</td>
          <td class="sz">{spec["mm"][0]}&times;{spec["mm"][1]}</td>
          <td class="bar"><span class="cells">{cells}</span></td>
          <td class="sq">{pad(spec["squish"])}</td>
        </tr>'''
    detail = "".join(
        f'<tr><td>{a}</td><td>{b}</td></tr>'
        for a, b in [("Form", "Bun"), ("Colour", "Ochre"), ("Palette", "4 extracted"),
                     ("Width", "88.0 mm"), ("Height", "64.0 mm"),
                     ("Method", "LiDAR"), ("Confidence", "0.90"),
                     ("Duplicate", "None above 0.62"), ("Filed", "2026-08-16 09:41")])
    cells7 = "".join(f'<i class="{"on" if n <= 7 else ""}"></i>' for n in range(1, 11))
    return f'''
<div class="dev v4"><div class="scr">
  <div class="st"></div>
  <header><h2>Register</h2><span class="ey">8 rows &middot; mean squish 6.4</span></header>
  <div class="tools"><span class="on">All</span><span>Measured</span><span>By colour</span><span>By size</span></div>
  <table class="tbl">
    <thead><tr><th>#</th><th></th><th>Specimen</th><th>Colour</th><th>mm</th><th>Squish</th><th></th></tr></thead>
    <tbody>{rows}</tbody>
  </table>
  <div class="foot"><span>8 rows</span><span>8 measured</span><span>mean squish 6.4</span></div>
</div></div>

<div class="dev v4"><div class="scr">
  <div class="st"></div>
  <header><h2>Ochre bun</h2><span class="ey">Specimen 001</span></header>
  <div class="pv">{art(HERO)}</div>
  <div class="sqline"><span class="ey">Squish</span><span class="cells lg">{cells7}</span><span class="val">07</span>
    <span class="term">{TERMS[7]}</span></div>
  <table class="tbl kv"><tbody>{detail}</tbody></table>
  <div class="foot"><span>Specimen 001 of 008</span><span>Ochre</span><span>07 slack</span></div>
</div></div>'''


# ================================================================ 5 · OBJECT
def object_():
    tiles = "".join(
        f'<div class="o"><div class="a">{art(spec)}</div>'
        f'<div class="l">{spec["name"]}<span>{pad(spec["squish"])}</span></div></div>'
        for spec in S[:6])
    strokes = "".join(f'<i class="{"on" if i <= 7 else ""}"></i>' for i in range(1, 11))
    return f'''
<div class="dev v5"><div class="scr">
  <div class="st"></div>
  <h2>Eight</h2>
  <p class="sub">specimens, measured</p>
  <div class="objs">{tiles}</div>
</div></div>

<div class="dev v5"><div class="scr">
  <div class="st"></div>
  <div class="art">{art(HERO)}</div>
  <h3>Ochre bun</h3>
  <div class="fig"><span class="n">7</span><span class="strokes">{strokes}</span></div>
  <p class="term">{TERMS[7]}</p>
  <div class="facts"><span>88 &times; 64 mm</span><span>LiDAR</span><span>Ochre</span></div>
</div></div>'''


VARIATIONS = [
    ("01", "Ledger", "Paper, not glass",
     "Square corners everywhere, a hairline grid, and type doing all the work. The durometer keeps "
     "its compressing bars but loses every radius, so it reads as a printed bar chart in a field book.",
     "Archivo + DM Mono &middot; White #FFFFFF, ink #0B0B0C, rule #E3E3E0",
     ledger),
    ("02", "Instrument", "A measuring device that happens to hold toys",
     "Near-black, mono-led, everything a readout. Specimens are drawn as contours rather than filled "
     "shapes &mdash; a caliper's view of an object. Squish becomes a ten-segment meter with a numeric field.",
     "DM Mono + Archivo &middot; Black #0A0B0D, signal #E8E9EA, dim #6B7078",
     instrument),
    ("03", "Plate", "The photograph is the interface",
     "Chrome recedes to almost nothing: full-bleed images, one serif line for the name, a caption set "
     "like a museum label. Squish is a single fine rule with a marker on it, and the numeral is set in the serif.",
     "Newsreader + DM Mono &middot; White #FFFFFF, ink #16171A, rule #EAEAE7",
     plate),
    ("04", "Register", "A collection is a table",
     "Dense rows instead of cards, tabular figures, eight specimens on screen at once. Squish is a ten-cell "
     "micro-bar inline in the row, so the whole collection's distribution is legible in one column.",
     "Archivo + DM Mono &middot; Cool white #FCFCFD, ink #101114, rule #E6E8EB",
     register),
    ("05", "Object", "One thing at a time",
     "Space is the only structure &mdash; no rules, no borders, no chrome. Large light type, four specimens to a "
     "screen, and a squish figure set at display size with ten hairline strokes beside it.",
     "Inter Light + DM Mono &middot; Cool grey #EFF0EF, graphite #23262A",
     object_),
]


def build():
    sections = []
    for num, name, position, body, spec, fn in VARIATIONS:
        sections.append(f'''
  <section class="var">
    <div class="brief">
      <span class="num">{num}</span>
      <h2>{name}</h2>
      <p class="position">{position}</p>
      <p class="body">{body}</p>
      <p class="spec">{spec}</p>
    </div>
    <div class="devs">{fn()}</div>
  </section>''')
    html = open(f"{HERE}/variations_template.html").read()
    html = html.replace("__SECTIONS__", "".join(sections))
    for key, value in FONTS.items():
        html = html.replace(key, value)
    return html


if __name__ == "__main__":
    out = "/home/user/Squeeshy/Design/mockups/variations.html"
    open(out, "w").write(build())
    print(out, os.path.getsize(out))
