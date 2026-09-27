# Bundled typefaces

The three typefaces named in `SPEC.md` §2 are vendored here as latin-subset
`woff2` files so `squish-index-mockups.html` renders identically offline and
under an artifact CSP that blocks external hosts.

| File | Family | Weights | Licence |
|---|---|---|---|
| `bric-600800.woff2` | Bricolage Grotesque | 600–800 (variable) | SIL Open Font License 1.1 |
| `inter-400600.woff2` | Inter | 400–600 (variable) | SIL Open Font License 1.1 |
| `dmmono-400.woff2` | DM Mono | 400 | SIL Open Font License 1.1 |
| `dmmono-500.woff2` | DM Mono | 500 | SIL Open Font License 1.1 |

All three are licensed under the SIL Open Font License, Version 1.1, which
permits bundling and redistribution — including embedding in an iOS app —
provided the fonts are not sold on their own and this notice travels with them.
Full licence text: <https://openfontlicense.org/>

Upstream sources:

- Bricolage Grotesque — <https://github.com/ateliertriay/bricolage>
- Inter — <https://github.com/rsms/inter>
- DM Mono — <https://github.com/googlefonts/dm-mono>

Subsets were retrieved from the Google Fonts CSS API (latin range,
`U+0000-00FF`). When these are added to the iOS target, use the full `.ttf`
from the upstream repositories rather than these web subsets, and list each
family under `UIAppFonts` in `Info.plist`.
