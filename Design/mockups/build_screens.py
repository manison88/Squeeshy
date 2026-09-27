#!/usr/bin/env python3
"""Assembles the Squish Index screen mockup into one self-contained page."""
import base64
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = "/home/user/Squeeshy/Design/mockups/fonts"


def font(name):
    data = base64.b64encode(open(f"{FONTS}/{name}.woff2", "rb").read()).decode()
    return f"url(data:font/woff2;base64,{data}) format('woff2')"


# ---------------------------------------------------------------- specimens
# Stand-ins. There are no photographs in a mockup, so every plate draws a
# silhouette in the specimen's own palette — the shapes match the six classes
# the app actually assigns.
BLOBS = {
    "round": "M50 10c22 0 33 15 33 34S72 82 50 82 17 63 17 44 28 10 50 10z",
    "oval": "M50 16c24 0 34 12 34 28S74 78 50 78 16 60 16 44 26 16 50 16z",
    "tall": "M50 6c17 0 26 12 26 26v30c0 15-9 26-26 26S24 77 24 62V32C24 18 33 6 50 6z",
    "wide": "M22 28h56c9 0 14 7 14 16s-5 16-14 16H22c-9 0-14-7-14-16s5-16 14-16z",
    "lobed": "M50 8c12 0 18 8 24 8s16 4 16 16c0 9-6 13-6 20s6 10 6 18-8 12-18 12H28c-10 0-18-4-18-12s6-11 6-18-6-11-6-20c0-12 10-16 16-16s12-8 24-8z",
    "blocky": "M26 18h48c6 0 10 4 10 10v44c0 6-4 10-10 10H26c-6 0-10-4-10-10V28c0-6 4-10 10-10z",
}

SPECIMENS = [
    dict(name="Amber blob", squish=7, form="lobed", mm=(88, 74), method="LiDAR",
         pal=["#E8A33D", "#F3D9A4", "#C8762A", "#FFFFFF"], props=[.52, .24, .16, .08]),
    dict(name="Peach bun", squish=9, form="round", mm=(61, 58), method="LiDAR",
         pal=["#F2A38C", "#FBD9CB", "#D9705A"], props=[.58, .27, .15]),
    dict(name="Grey loaf", squish=3, form="blocky", mm=(112, 66), method="Card",
         pal=["#9AA0A6", "#D6D9DC", "#6B7076"], props=[.5, .32, .18]),
    dict(name="Mint cloud", squish=8, form="wide", mm=(96, 52), method="Depth",
         pal=["#8FCDB4", "#DDF0E6", "#4E9A7C"], props=[.55, .3, .15]),
    dict(name="Plum pod", squish=5, form="oval", mm=(74, 62), method="LiDAR",
         pal=["#8A5FA8", "#C9AEDA", "#5B3A73"], props=[.6, .24, .16]),
    dict(name="Butter brick", squish=2, form="blocky", mm=(140, 78), method="Card",
         pal=["#EFD37A", "#FAF0C4", "#C9A73F"], props=[.54, .3, .16]),
    dict(name="Coral fry", squish=10, form="tall", mm=(38, 96), method="Depth",
         pal=["#EE7A6B", "#FAC7BE", "#C24B3D"], props=[.57, .26, .17]),
    dict(name="Slate egg", squish=4, form="round", mm=(52, 60), method="Card",
         pal=["#6E7A88", "#B9C2CB", "#455060"], props=[.56, .28, .16]),
    dict(name="Ochre knot", squish=7, form="lobed", mm=(66, 64), method="LiDAR",
         pal=["#D08B2E", "#F0CE96", "#9A6420"], props=[.55, .28, .17]),
    dict(name="Fog bun", squish=5, form="round", mm=(58, 55), method="Depth",
         pal=["#C7C2BA", "#EAE6E0", "#8E8880"], props=[.52, .31, .17]),
    dict(name="Rose brick", squish=7, form="blocky", mm=(104, 58), method="Card",
         pal=["#D9789A", "#F4C4D4", "#A94A6C"], props=[.53, .3, .17]),
    dict(name="Cobalt pip", squish=9, form="oval", mm=(44, 48), method="Depth",
         pal=["#4A6FA8", "#A9C0DE", "#2E4A76"], props=[.58, .26, .16]),
]

FAMILIES = {
    "Amber blob": ("Orange", "#D97C2B"), "Peach bun": ("Pink", "#C96395"),
    "Grey loaf": ("Neutral", "#9A9A9A"), "Mint cloud": ("Green", "#4E9A51"),
    "Plum pod": ("Purple", "#7A5AA8"), "Butter brick": ("Yellow", "#D9B02B"),
    "Coral fry": ("Red", "#C0392B"), "Slate egg": ("Neutral", "#9A9A9A"),
    "Ochre knot": ("Orange", "#D97C2B"), "Fog bun": ("Neutral", "#9A9A9A"),
    "Rose brick": ("Pink", "#C96395"), "Cobalt pip": ("Blue", "#3A6EA5"),
}


def longest(spec):
    return max(spec["mm"])


COUNT = len(SPECIMENS)
AVERAGE = sum(s["squish"] for s in SPECIMENS) / COUNT
HEADLINE = f"{COUNT} specimens &middot; avg squish {AVERAGE:.1f}"

TERMS = [
    ("Rigid", "A thumb leaves no impression."),
    ("Firm", "Gives at the surface, returns instantly."),
    ("Dense", "Compresses under steady pressure and springs straight back."),
    ("Resilient", "Presses in about a third of the way and recovers at once."),
    ("Even", "Compresses about halfway. Returns without delay."),
    ("Soft", "Folds around a thumb and recovers in about a second."),
    ("Slack", "Squashes nearly flat under light pressure. Comes back slowly."),
    ("Deep", "Collapses almost completely and rises again over a few seconds."),
    ("Slow rise", "Holds the print of a thumb for five to ten seconds."),
    ("Barely holds shape", "Flows in the hand and re-forms on its own."),
]


# ------------------------------------------------------------- geometry
# UX-SPEC §5.1, exactly. The mockup and the SwiftUI run the same formulas.
def h_base(i):
    return 88 - (i - 1) * (22 / 9)


def w_of(k):
    return 12 + 14 * k


def h_of(i, k):
    return h_base(i) * (12 / w_of(k))


def r_of(i, k):
    return min(3 + 10 * k, w_of(k) / 2, h_of(i, k) / 2)


def durometer(level, tint="var(--ink)", track=340):
    slot = track / 10
    k = (level - 1) / 9
    bars = []
    for i in range(1, 11):
        filled = i <= level
        kk = k if filled else 0
        bars.append(
            f'<span class="dslot" style="width:{slot:.2f}px">'
            f'<b style="width:{w_of(kk):.2f}px;height:{h_of(i, kk):.2f}px;'
            f'border-radius:{r_of(i, kk):.2f}px;'
            f'background:{tint if filled else "#74777E"}"></b></span>'
        )
    return f'<div class="duro" style="width:{track}px">{"".join(bars)}</div>'


def photo(spec, scale=1.0):
    pal = spec["pal"]
    eyes = ""
    if spec["form"] in ("round", "oval", "lobed"):
        eyes = ('<circle cx="39" cy="42" r="3.4" fill="#14151A" opacity=".55"/>'
                '<circle cx="61" cy="42" r="3.4" fill="#14151A" opacity=".55"/>')
    return (
        f'<svg viewBox="0 0 100 100" width="100%" height="100%" aria-hidden="true">'
        f'<path d="{BLOBS[spec["form"]]}" fill="{pal[0]}"/>'
        f'<ellipse cx="38" cy="30" rx="11" ry="7" fill="#fff" opacity=".38"/>'
        f'{eyes}</svg>'
    )


def swatches(spec):
    return '<span class="pal">' + "".join(
        f'<i style="background:{c}"></i>' for c in spec["pal"]
    ) + "</span>"


def pad(n):
    return f"{n:02d}"


# ------------------------------------------------------------- screens
def grid_card(spec):
    return (
        '<div class="card">'
        f'<div class="plate">{photo(spec)}</div>'
        f'<div class="cardname D4">{spec["name"]}</div>'
        f'<div class="meta">{swatches(spec)}<span class="M2 ink">{pad(spec["squish"])}</span></div>'
        '</div>'
    )


def screen_grid():
    cards = "".join(grid_card(s) for s in SPECIMENS[:4])
    return f'''
<div class="device"><div class="screen">
  <div class="safe-t"></div>
  <div class="mx" style="padding-top:13px">
    <div class="D2">Squish Index</div>
    <div class="M1 dim stat">{HEADLINE}</div>
  </div>
  <div class="mx band">
    <div class="seg">
      <button aria-selected="true">Grid</button>
      <button aria-selected="false">Shelf</button>
      <button aria-selected="false">Stats</button>
    </div>
    <div class="chiprow">
      <span class="chip">Recent {CARET}</span>
      <span class="chip">Filter</span>
    </div>
  </div>
  <div class="rule"></div>
  <div class="mx grid">{cards}</div>
  <button class="cta corner"><span class="M1">Capture</span></button>
  <div class="safe-b"></div>
</div></div>'''


def screen_empty():
    chips = "".join(f'<span class="chip inert">{c}</span>' for c in
                    ["Subject mask", "Colour palette", "Silhouette",
                     "Real millimetres", "Duplicate check"])
    return f'''
<div class="device"><div class="screen">
  <div class="safe-t"></div>
  <div class="mx" style="padding-top:13px">
    <div class="D2">Squish Index</div>
    <div class="M1 dim stat">0 specimens</div>
  </div>
  <div class="mx band">
    <div class="seg">
      <button aria-selected="true">Grid</button>
      <button aria-selected="false" disabled>Shelf</button>
      <button aria-selected="false" disabled>Stats</button>
    </div>
    <div class="chiprow">
      <span class="chip off">Recent {CARET}</span>
      <span class="chip off">Filter</span>
    </div>
  </div>
  <div class="mx" style="padding-top:34px">
    <div class="M1 dim">Specimen record &middot; blank</div>
    <div class="blank-plate"></div>
    <div class="fields">
      <div class="frow"><span class="M1 flabel dim">Name</span><span class="dashbar"></span></div>
      <div class="frow"><span class="M1 flabel dim">Squish</span><span class="M1 faint">--</span></div>
      <div class="frow"><span class="M1 flabel dim">Palette</span>
        <span class="pal"><i class="hollow"></i><i class="hollow"></i><i class="hollow"></i><i class="hollow"></i></span></div>
      <div class="frow"><span class="M1 flabel dim">Width</span><span class="M1 faint">-- mm</span></div>
      <div class="frow"><span class="M1 flabel dim">Form</span><span class="M1 faint">&mdash;&mdash;</span></div>
    </div>
    <p class="B1" style="margin-top:22px;max-width:300px">Photograph a squishy and the
      index fills this card in. Everything below the name is measured on your phone.</p>
    <div class="chipwrap">{chips}</div>
  </div>
  <button class="cta bar"><span class="B2">Photograph the first one</span></button>
  <div class="safe-b"></div>
</div></div>'''


def screen_capture():
    return '''
<div class="device dark"><div class="screen">
  <div class="vf">
    <div class="vf-grain"></div>
    <div class="vf-sub">''' + photo(SPECIMENS[0]) + '''</div>
  </div>
  <div class="safe-t"></div>
  <div class="mx vf-top">
    <span class="icon-btn">&#215;</span>
    <span class="badge M1">LiDAR</span>
  </div>
  <div class="brack"><i></i><i></i><i></i><i></i></div>
  <div class="readout M1">Subject locked &middot; LiDAR</div>
  <div class="vf-bottom">
    <span class="vfbtn">&#9634;</span>
    <span class="shutter"></span>
    <span class="vfbtn ghost"></span>
  </div>
  <div class="safe-b"></div>
</div></div>'''


def screen_name():
    term, behaviour = TERMS[6]
    return f'''
<div class="device"><div class="screen">
  <div class="safe-t"></div>
  <div class="mx navbar"><span class="B1 dim">Cancel</span></div>
  <div class="mx" style="text-align:center">
    <div class="big-plate">{photo(SPECIMENS[0])}</div>
    <div class="M1 dim" style="height:44px;line-height:44px">Retake</div>
  </div>
  <div class="mx" style="padding-top:9px">
    <div class="D3">Amber blob</div>
    <div class="field-rule"></div>
  </div>
  <div class="spacer"></div>
  <div class="inset">
    <div class="rule"></div>
    <div class="mx">
      <div class="inset-head">
        <span class="M1 dim">Squish level</span>
        <span class="D1" id="duroNum">7</span>
      </div>
      <div class="duro-wrap" id="duroWrap" role="slider" tabindex="0"
           aria-label="Squish level" aria-valuemin="1" aria-valuemax="10"
           aria-valuenow="7" aria-valuetext="7 of 10. Slack.">
        {durometer(7)}
      </div>
      <p class="B1 sentence" id="duroSentence"><b>{term}.</b> <span class="dim">{behaviour}</span></p>
      <button class="pill"><span class="B2">File specimen</span></button>
    </div>
  </div>
  <div class="safe-b"></div>
</div></div>'''


def screen_measuring():
    rows = []
    stages = [("Subject isolated", True), ("Palette extracted", True),
              ("Measuring size", True), ("Checking duplicates", False),
              ("Filing specimen", False)]
    for label, done in stages:
        box = '<i class="box done"></i>' if done else '<i class="box"></i>'
        tone = "ink" if done else "dim"
        rows.append(f'<div class="check">{box}<span class="M1 {tone}">{label}</span></div>')
    return f'''
<div class="device"><div class="screen">
  <div class="safe-t"></div>
  <div class="mx navbar"><span class="B1 dim">Cancel</span></div>
  <div class="mx" style="text-align:center">
    <div class="big-plate scanning">{photo(SPECIMENS[0])}<span class="scanline"></span></div>
  </div>
  <div class="mx" style="padding-top:34px">{"".join(rows)}</div>
  <div class="spacer"></div>
  <div class="safe-b"></div>
</div></div>'''


def screen_sheet():
    spec = SPECIMENS[0]
    seg = "".join(
        f'<span style="width:{p * 100:.1f}%;background:{c}"></span>'
        for c, p in zip(spec["pal"], spec["props"])
    )
    rows = [("Squish", "7 of 10 &middot; Slack"), ("Form", "Lobed"), ("Colour", "Orange"),
            ("Size", "88 &times; 74 mm"), ("Method", "LiDAR &middot; 90% confidence"),
            ("Filed", "16 Aug 2026 at 09:41")]
    row_html = "".join(
        f'<div class="srow"><span class="M1 flabel dim">{a}</span><span class="B1">{b}</span></div>'
        for a, b in rows)
    return f'''
<div class="device"><div class="screen">
  <div class="sheet-photo">{photo(spec)}</div>
  <div class="safe-t"></div>
  <div class="mx"><span class="round-btn">&#8249;</span></div>
  <div class="sheet">
    <span class="grabber"></span>
    <div class="mx" style="padding-top:13px">
      <div class="D3">Amber blob</div>
      <div class="sheet-duro">
        {durometer(7, tint="#B5761F", track=220)}
        <span class="D1">7</span>
      </div>
      <p class="B1 dim" style="margin-top:13px"><b class="ink">Slack.</b> Squashes nearly flat
        under light pressure. Comes back slowly.</p>
      <div class="specs">{row_html}</div>
      <div class="M1 dim" style="margin-top:22px">Palette</div>
      <div class="propbar">{seg}</div>
    </div>
  </div>
</div></div>'''


def screen_true_scale():
    ordered = sorted(SPECIMENS, key=longest)
    largest = longest(ordered[-1])
    pt_per_mm = 349 / largest
    rows = []
    tick = 10 * pt_per_mm
    for spec in ordered[:5]:
        w = spec["mm"][0] * pt_per_mm
        h = spec["mm"][1] * pt_per_mm
        rows.append(f'''
      <div class="ts-row">
        <div class="ts-art" style="width:{w:.1f}px;height:{h:.1f}px">{photo(spec)}</div>
        <div class="ts-meta">
          <div class="D4">{spec["name"]}</div>
          <div class="M2 dim">{spec["mm"][0]} &times; {spec["mm"][1]} mm &middot; {spec["method"]}</div>
        </div>
      </div>
      <div class="ticks" style="--tick:{tick:.2f}px"></div>''')
    return f'''
<div class="device"><div class="screen">
  <div class="safe-t"></div>
  <div class="mx" style="padding-top:13px">
    <div class="D2">Squish Index</div>
    <div class="M1 dim stat">{HEADLINE}</div>
  </div>
  <div class="mx band">
    <div class="seg">
      <button aria-selected="false">Grid</button>
      <button aria-selected="true">Shelf</button>
      <button aria-selected="false">Stats</button>
    </div>
    <div class="chiprow"><span class="chip">Largest {CARET}</span><span class="chip">Filter</span></div>
  </div>
  <div class="rule"></div>
  <div class="mx" style="padding-top:13px">
    <div class="M1 dim">1 pt = {1 / pt_per_mm:.2f} mm</div>
    <div class="ts">{"".join(rows)}</div>
  </div>
  <div class="safe-b"></div>
</div></div>'''


def screen_stats():
    bins = [0] * 10
    for spec in SPECIMENS:
        bins[spec["squish"] - 1] += 1
    peak = max(bins)
    bars = []
    for level in range(1, 11):
        count = bins[level - 1]
        k = (level - 1) / 9
        w = w_of(k)
        height = max(4, h_base(level) * (count / peak))
        r = min(3 + 10 * k, w / 2, height / 2)
        tone = "var(--ink)" if count else "rgba(116,119,126,.35)"
        bars.append(
            f'<span class="hslot"><b style="width:{w:.1f}px;height:{height:.1f}px;'
            f'border-radius:{r:.1f}px;background:{tone}"></b>'
            f'<em class="M2 {"ink" if count else "dim"}">{level}</em></span>')

    tally = {}
    for spec in SPECIMENS:
        name, hexv = FAMILIES[spec["name"]]
        tally.setdefault(name, [hexv, 0])[1] += 1
    spread = sorted(((n, v[0], v[1] / COUNT) for n, v in tally.items()),
                    key=lambda row: -row[2])
    bar = "".join(f'<span style="width:{p * 100}%;background:{c}"></span>' for _, c, p in spread)
    legend = "".join(
        f'<span class="legend"><i style="background:{c}"></i>'
        f'<span class="M1 dim">{n} {int(p * 100)}%</span></span>' for n, c, p in spread)
    small = min(SPECIMENS, key=longest)
    big = max(SPECIMENS, key=longest)
    forms = {}
    for spec in SPECIMENS:
        forms[spec["form"]] = forms.get(spec["form"], 0) + 1
    common = max(forms.items(), key=lambda row: row[1])
    rows = [("Specimens", str(COUNT)), ("Avg squish", f"{AVERAGE:.1f}"),
            ("Measured", f"{COUNT} of {COUNT}"),
            ("Smallest", f'{small["name"]} &middot; {longest(small)} mm'),
            ("Largest", f'{big["name"]} &middot; {longest(big)} mm'),
            ("Most unusual", "Coral fry"),
            ("Common form", f"{common[0].capitalize()} &middot; {common[1]}")]
    row_html = "".join(
        f'<div class="srow"><span class="M1 flabel wide dim">{a}</span><span class="B1">{b}</span></div>'
        for a, b in rows)
    return f'''
<div class="device"><div class="screen">
  <div class="safe-t"></div>
  <div class="mx" style="padding-top:13px">
    <div class="D2">Squish Index</div>
    <div class="M1 dim stat">{HEADLINE}</div>
  </div>
  <div class="mx band">
    <div class="seg">
      <button aria-selected="false">Grid</button>
      <button aria-selected="false">Shelf</button>
      <button aria-selected="true">Stats</button>
    </div>
    <div class="chiprow"><span class="chip">Recent {CARET}</span><span class="chip">Filter</span></div>
  </div>
  <div class="rule"></div>
  <div class="mx" style="padding-top:22px">
    <div class="M1 dim">Squish distribution</div>
    <div class="hist">{"".join(bars)}</div>
    <div class="M1 dim" style="margin-top:34px">Colour spread</div>
    <div class="propbar">{bar}</div>
    <div class="legends">{legend}</div>
    <div class="specs" style="margin-top:34px">{row_html}</div>
  </div>
  <div class="safe-b"></div>
</div></div>'''


CARET = ('<svg width="9" height="6" viewBox="0 0 9 6" aria-hidden="true">'
         '<path d="M1 1l3.5 3.5L8 1" stroke="currentColor" stroke-width="1.5" '
         'fill="none" stroke-linecap="round"/></svg>')

SLOTS = [
    ("01", "Shelf / grid", "Two-up, uniform. The plate&rsquo;s hairline is the card&rsquo;s only boundary.", screen_grid),
    ("02", "Empty state", "A blank accession card with its fields labelled &mdash; the app showing its own schema.", screen_empty),
    ("03", "Capture", "The badge names the method the device can actually offer, before the shutter.", screen_capture),
    ("04", "Name &amp; durometer", "Live &mdash; drag the bars. Area is conserved as they compress.", screen_name),
    ("05", "Measuring", "The plate does not move from screen 4. Only the checklist arrives.", screen_measuring),
    ("06", "Specimen sheet", "Tinted durometer, frozen. The tint is darkened until it clears 3:1.", screen_sheet),
    ("07", "True scale", "Real relative size, smallest first. The sheet prints its own scale factor.", screen_true_scale),
    ("08", "Stats", "The histogram is the durometer&rsquo;s own bar geometry, counts driving height.", screen_stats),
]


def build():
    slots = []
    for num, name, note, fn in SLOTS:
        slots.append(f'''
    <figure class="slot">
      <figcaption class="cap">
        <span class="M1 num">{num}</span>
        <span class="M1 name">{name}</span>
        <span class="B3 note">{note}</span>
      </figcaption>
      {fn()}
    </figure>''')

    return TEMPLATE.replace("__SLOTS__", "".join(slots)) \
                   .replace("__BRIC__", font("bric-600800")) \
                   .replace("__INTER__", font("inter-400600")) \
                   .replace("__MONO400__", font("dmmono-400")) \
                   .replace("__MONO500__", font("dmmono-500")) \
                   .replace("__SENTENCES__", json.dumps(TERMS))


TEMPLATE = open(f"{HERE}/template.html").read()

if __name__ == "__main__":
    out = "/home/user/Squeeshy/Design/mockups/screens.html"
    open(out, "w").write(build())
    print(out, os.path.getsize(out))
