#!/usr/bin/env python3
"""Assemble squish-index-mockups.html from its parts.

The mockups must be a single self-contained file: viewable offline, and
publishable as an artifact where a strict CSP blocks every external host.
So the typefaces are inlined as base64 data URIs rather than linked.

    python3 Design/mockups/build.py

Inputs   Design/mockups/{fonts/*.woff2, tokens.css, body.html}
Output   squish-index-mockups.html  (repo root, per SPEC.md kickoff)
"""

import base64
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = ROOT / "squish-index-mockups.html"

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


def main() -> None:
    tokens = (HERE / "tokens.css").read_text()
    body = (HERE / "body.html").read_text()

    html = (
        "<title>Squish Index</title>\n"
        "<style>\n" + font_face_css() + "\n\n" + tokens + "\n</style>\n" + body
    )
    OUT.write_text(html)
    kb = len(html.encode()) / 1024
    print(f"wrote {OUT.relative_to(ROOT)}  ({kb:.0f} KB)")


if __name__ == "__main__":
    main()
