#!/usr/bin/env python3
"""Assemble a self-contained mockup page from its parts.

The output must be a single file: viewable offline, and publishable as an
artifact where a strict CSP blocks every external host. So the typefaces are
inlined as base64 data URIs rather than linked.

    python3 Design/mockups/build.py                     # -> squish-index-mockups.html
    python3 Design/mockups/build.py durometer-options   # -> durometer-options.html

Inputs   Design/mockups/{fonts/*.woff2, tokens.css, <name>.body.html}
Output   <name>.html at the repo root (per SPEC.md kickoff)
"""

import base64
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent

# page slug -> (body file, <title>)
PAGES = {
    "squish-index-mockups": ("body.html", "Squish Index"),
    "durometer-options": ("durometer-options.body.html", "Three Durometers"),
}

# (file, css family name, font-weight descriptor)
FONTS = [
    ("bric-600800.woff2", "Bricolage Grotesque", "600 800"),
    ("inter-400600.woff2", "Inter", "400 600"),
    ("dmmono-400.woff2", "DM Mono", "400"),
    ("dmmono-500.woff2", "DM Mono", "500"),
]


def font_face_css() -> str:
    rules = []
    for filename, family, weight in FONTS:
        path = HERE / "fonts" / filename
        if not path.exists():
            sys.exit(f"missing font: {path}")
        b64 = base64.b64encode(path.read_bytes()).decode("ascii")
        rules.append(
            f"@font-face{{font-family:'{family}';font-style:normal;"
            f"font-weight:{weight};font-display:block;"
            f"src:url(data:font/woff2;base64,{b64}) format('woff2');}}"
        )
    return "\n".join(rules)


def build(slug: str, faces: str) -> None:
    body_name, title = PAGES[slug]
    tokens = (HERE / "tokens.css").read_text()
    body = (HERE / body_name).read_text()

    html = (
        f"<title>{title}</title>\n"
        "<style>\n" + faces + "\n\n" + tokens + "\n</style>\n" + body
    )
    out = ROOT / f"{slug}.html"
    out.write_text(html)
    print(f"wrote {out.relative_to(ROOT)}  ({len(html.encode()) / 1024:.0f} KB)")


def main() -> None:
    slugs = sys.argv[1:] or ["squish-index-mockups"]
    unknown = [s for s in slugs if s not in PAGES]
    if unknown:
        sys.exit(f"unknown page(s): {', '.join(unknown)}\nknown: {', '.join(PAGES)}")
    faces = font_face_css()  # encode once, reuse across pages
    for slug in slugs:
        build(slug, faces)


if __name__ == "__main__":
    main()
