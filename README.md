# Squish Index

A native iOS app for cataloguing squishy toys. Photograph a toy, name it, rate
how squishy it is 1–10, and the app measures it — subject mask, colour palette,
silhouette, real millimetres — then files it in a collection you can sort,
filter and browse.

`SPEC.md` is the authority on what this is. `Design/UX-SPEC.md` covers
interaction, motion, state and component decomposition. This file records what
was built and the calls made along the way.

## Opening it

```
open SquishIndex.xcodeproj
```

Requires **Xcode 16** or later (the project uses a file-system-synchronised
group, so new files in `SquishIndex/` are picked up without touching the project
file). Deployment target is **iOS 17.0**. No third-party dependencies.

Set your own team and bundle identifier in **Signing & Capabilities** before
running on device — `PRODUCT_BUNDLE_IDENTIFIER` currently reads
`com.squishindex.SquishIndex`.

## Verifying it on device

Segmentation, depth and haptics all need real hardware. The Simulator will run
the app and the library-import path, but not the camera.

1. **Empty state** — first launch shows the blank accession card. Shelf and
   Stats are disabled, not hidden. The CTA is a full-width bar, not a floating
   pill.
2. **Capture** — the badge top-right names the measurement method the device can
   actually offer (`LiDAR`, `Depth`, or `No size data`) before you press the
   shutter. Corner brackets should track a toy on a plain surface within about a
   fifth of a second.
3. **Name & durometer** — the plate shows the raw frame, then crossfades to the
   cut-out subject on white when segmentation lands. Drag across the durometer:
   the filled bars compress and widen, area conserved, with a selection tick per
   step and a soft impact at 10. Try to scroll by dragging vertically on it —
   the value must revert, silently.
4. **Filing** — tap *File specimen*. If analysis is still running you get the
   measuring checklist; otherwise it files immediately. An empty name files as
   *Unnamed specimen*; the button is never disabled.
5. **Millimetres** — photograph a toy with any bank card lying flat beside it,
   in the same plane. The sheet should report `Card` and a size within a few
   millimetres of a ruler. On a Pro device without a card, it should report
   `LiDAR` or `Depth`.
6. **Duplicates** — photograph the same toy twice. The second capture shows a
   twin card under the name field. It never blocks the save.
7. **Shelf** — with two or more measured specimens, the true-scale shelf draws
   them at real relative size and prints its own scale factor.
8. **Accessibility** — turn on VoiceOver (the durometer announces as adjustable,
   "7 of 10. Slack."), Reduce Motion (durometer interpolation and the scan sweep
   both stop; crossfades remain), and an accessibility Dynamic Type size (the
   two-up grid becomes a one-up list).

## What is in the build

| Area | State |
|---|---|
| Screens 1–8 | All built |
| Segmentation (`VNGenerateForegroundInstanceMaskRequest`) | Yes |
| Colour palette + proportions | Yes |
| Silhouette classification | Yes |
| Depth measurement (LiDAR / dual camera) | Yes |
| Reference-card measurement | Yes, automatic |
| Duplicate detection (feature prints) | Yes |
| Cloud identification (type, subject, material) | **Not wired** — see below |

### Cloud identification is deliberately absent

`SPEC.md` §4 asks for the identification call to be discussed before wiring, and
specifically says not to hardcode or commit a key. Nothing here makes a network
request; the model has `type`, `subject`, `material`, `surface` and `tags`
fields sitting empty and ready.

The approach I'd suggest when you want it: keep the key out of the repo in
`Secrets.xcconfig` (already git-ignored), surface it through a build setting into
`Info.plist`, and read it at launch. That is fine for a personal build but the
key still ships inside the app bundle, so if this ever goes to the App Store the
call needs to go through a small proxy you control instead. Tell me which and
I'll wire it — the call site is one function and the save path already treats
identification as optional, so nothing else moves.

## Calls made on the spec's open questions

Answers to `UX-SPEC.md` §9, all reversible:

- **Q1 `soft` contrast** — palette untouched. `soft` is used for text only where
  it is duplicative or large; small sole-carrier labels use `ink` at 62 %
  (4.6:1), and `soft` binds to `#5F6269` under Increase Contrast.
- **Q2 Dark Mode** — light only, via `.preferredColorScheme(.light)` and
  `UIUserInterfaceStyle`. Inverting putty and ink would be a redesign.
- **Q3 Method badge** — the badge is real. Depth and card both ship, so it names
  what the device can actually do rather than always reading `NO SIZE DATA`.
- **Q4 Average squish** — arithmetic mean, one decimal, omitted entirely at zero.
- **Q5 Sort options** — six: Recently added (default), Name A–Z, Squishiest
  first, Largest first (disabled until something is measured), Colour, Most
  unusual.
- **Q6 Tinted durometer** — the dominant colour is darkened (brightness only)
  until it clears 3:1 against chalk. The palette strip keeps the true colour.
- **Q7 Deployment / Liquid Glass** — iOS 17 floor kept, so the iOS 18 zoom
  transition is skipped rather than conditionally compiled.
  `UIDesignRequiresCompatibility` is set, and the app leans on custom chrome
  (`safeAreaInset`, custom pills) so the iOS 27 migration costs little.
- **Q8 Card borders** — the plate's hairline is the card's only boundary.
- **Q9 Empty name** — files as `Unnamed specimen`. Duplicate names are allowed to
  collide; the index is a record of what you own, not a namespace.
- **Q10 Sheet detents** — `.fraction(0.55)` and `.fraction(0.92)`, so the
  photograph the sheet is describing is never fully buried.
- **Q11 Short palettes** — only what was extracted is rendered. Nothing is padded
  with grey.
- **Q12 Header count** — reports the whole library, with a second
  `SHOWING n OF m` line when filters are active.
- **Q13 `M2` tracking** — kept as the +0.04em numeric variant.

## Deviations from `SPEC.md`, flagged

1. **Two fields added to the model.** `dominantSaturation` and
   `dominantBrightness` sit alongside `dominantHue`. Hue alone cannot separate
   white from grey from brown, and the colour filter, the colour sort and the
   uniqueness score all need that separation. Nothing else in §4's model changed.
2. **`paletteProportions` added.** Screen 6's proportion bar needs the shares,
   and recomputing them from the photo on every open would be wasteful.
3. **`SquishyVision.swift` was written, not dropped in.** The spec describes it
   as already existing; it was not in the repository. It follows the contract
   §4 sets out — the measurement ladder in order, method always recorded, no
   estimated millimetres — and is the one file to check against your original if
   you still have it.
4. **Uniqueness is a computed score, not a stored field.** It is defined against
   the rest of the collection, so it changes as the collection grows; storing it
   would make it stale on every save.

## Layout

```
SquishIndex/
  App/            entry point, model container
  Models/         SwiftData model, sorting, filtering, uniqueness, stats
  Capture/        camera session, viewfinder, capture flow, name & measure
  Vision/         SquishyVision — segmentation, palette, silhouette, millimetres
  Library/        grid, empty state, true-scale shelf, stats, filters
  Detail/         specimen sheet
  DesignSystem/   tokens, typography, durometer, shared components
  Resources/      bundled typefaces, asset catalogue
Config/Info.plist
Design/           the mockups and the UX spec (unchanged)
```

Typefaces are the three named in `SPEC.md` §2, instanced from the vendored
variable fonts into static cuts (Bricolage SemiBold/Bold/ExtraBold, Inter
Regular/Medium/SemiBold, DM Mono Regular/Medium). All three are SIL Open Font
License 1.1; the notice travels with them in
`SquishIndex/Resources/Fonts/NOTICE.md`.
