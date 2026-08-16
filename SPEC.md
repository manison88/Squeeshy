# Squish Index — Build Spec

> Drop this in the repo root as `SPEC.md`. Paste the Kickoff block below as your first Claude Code message, then let it read this file.

---

## Kickoff prompt

```
Read SPEC.md in full before writing anything.

Build Squish Index: a native iOS app for cataloguing squishy toys. The user
photographs a toy, names it, rates how squishy it is 1–10, and the app measures
it — real millimetres, colour palette, silhouette — then files it in a
collection they can sort, filter, and browse.

Two files are already written and are the source of truth for their domains:
  - SquishyVision.swift — segmentation, measurement, duplicate detection.
    Drop it in as-is. Do not rewrite it. If something in it is wrong, tell me
    before changing it.
  - squish-index-mockups.html — the visual target. Open it and match it.

Start with Milestone 1 only. Build it, tell me how to verify it on device, and
stop. Do not run ahead to later milestones.

Ask me before adding any third-party dependency.
```

---

## 1. What this is

A specimen catalogue, not a toy box. The premise: apply museum-grade cataloguing rigour to objects that are inherently silly and soft. The tension between the two is the product.

Target user is a collector — often a kid or teen, sometimes an adult — who owns 10–200 squishies and currently has them in a bin.

**Core loop:** photograph → name → rate squish → measured & filed → browse.

## 2. Design direction — locked

Do not redesign this. It is settled. Match `squish-index-mockups.html`.

### Palette
| Token | Hex | Use |
|---|---|---|
| `putty` | `#F1F0EC` | app canvas |
| `ink` | `#14151A` | primary text, primary buttons |
| `soft` | `#74777E` | secondary text, labels |
| `line` | `#DDDBD4` | hairline rules and borders |
| `chalk` | `#FFFFFF` | raised surfaces, photo plates |

**The UI has no colour of its own.** Every colour on screen comes out of the user's photos — palette chips, the tinted durometer on the detail sheet, the colour-spread bar. Do not introduce a brand accent. Do not add gradients to chrome. If a screen looks drab with no specimens on it, that is correct; it fills with colour as the collection grows.

### Type
- **Display** — Bricolage Grotesque, weights 600/800, tight tracking (`-0.02em`). Names, headings, the big squish numeral.
- **Body** — Inter, 400/500/600. Sentences and descriptions.
- **Data** — DM Mono, 400/500. Every label, measurement, unit, and eyebrow. Uppercase, `0.16em` tracking, 10pt.

The mono/display split is load-bearing: mono says *measured*, display says *named*. Never mix them up — a toy's name is never mono, a measurement is never display except the hero squish numeral.

### Geometry
- Corner radii: 15pt cards, 19–24pt photo plates, 26pt sheet tops, 999pt pills.
- Hairlines are 1pt `line`, never shadows, except the floating CTA and the bottom sheet.
- Grid gutter 13pt, screen margin 22pt.

### The signature: the durometer
Squish level is **not** a stock slider. It is ten vertical bars. As the value rises, the filled bars *compress* — shorter, wider, more rounded — so the control physically performs the property it measures. Each bar is fractionally shorter than the one before it, giving a slight lean.

- Interactive on capture (`DragGesture`, plus tap-to-set, plus accessibility increment/decrement).
- Frozen and read-only on the detail sheet, tinted to the specimen's dominant colour.
- Always paired with the numeral. The bars give feel; the number gives precision.

Haptics: `.selection` feedback on each step change. `.impact(.soft)` at 10.

## 3. Screens

Numbered to match the mockups.

1. **Shelf / Grid** — 2-up uniform grid. Card = square photo plate, name in display, four-swatch palette strip, squish number in mono. Header shows count and average squish.
2. **Empty state** — teaches by showing a completed record, then chips listing what gets measured. Never just "no items yet."
3. **Capture / viewfinder** — full-bleed camera, corner brackets, live subject lock with distance readout, and an explicit badge naming the measurement method (LiDAR / Depth / Card). Shutter centre, Library left, Card right.
4. **Name & durometer** — photo plate, name field with display type, durometer, one plain-language sentence describing the current level.
5. **Measuring** — checklist that fills in sequence: subject isolated → palette extracted → measuring depth → checking duplicates → identifying. Scan line sweeps the photo.
6. **Specimen sheet** — photo fills the top; specs arrive as a bottom sheet with `.presentationDetents([.medium, .large])`. Name, tinted durometer, spec rows, palette proportion bar.
7. **Shelf / true scale** — every specimen rendered at actual relative size on hairline baselines, sorted small to large, mm ticks per row. This is the payoff for the measurement work and the screen people will screenshot.
8. **Stats** — squish histogram, colour spread bar, summary rows.

Screens 1, 7, 8 share one segmented control: **Grid · Shelf · Stats**.

### Controls
- Sorting lives behind a chip with a trailing caret, not a row of four chips.
- Colour filter chip carries a **count badge** when filters are active. Colour alone must never be the only indicator of state.
- Destructive actions go in an action sheet, capped at 3–5 options.

## 4. Architecture

**Platform:** iOS 17+, SwiftUI, SwiftData. No UIKit except where `AVCaptureVideoPreviewLayer` requires a representable.

```
SquishIndex/
  App/                 entry point, root navigation
  Models/              SwiftData models
  Capture/             camera session, viewfinder, capture flow
  Vision/              SquishyVision.swift  ← already written, drop in
  Library/             grid, true-scale shelf, stats
  Detail/              specimen sheet
  Design/              tokens, typography, Durometer, shared components
  Services/            Identification (Claude API), persistence helpers
```

### Model

```swift
@Model final class Squishy {
    @Attribute(.unique) var id: UUID
    var name: String
    var squishLevel: Int
    var addedAt: Date

    @Attribute(.externalStorage) var photo: Data
    var featurePrint: Data          // archived VNFeaturePrintObservation

    var widthMM: Double?
    var heightMM: Double?
    var measurementMethod: String
    var confidence: Double

    var dominantHue: Double
    var paletteHex: [String]
    var form: String

    var type: String?
    var subject: String?
    var material: String?
    var surface: String?
    var tags: [String]
}
```

`.externalStorage` on `photo` is required — inlining image blobs bloats the store badly.

### Measurement ladder

Try in order, record which one succeeded, and always surface the method to the user:

1. **LiDAR / sceneDepth** — best accuracy.
2. **Dual-camera `AVDepthData`** — good.
3. **Reference card** — user lays any ID-1 card (credit card, licence) flat beside the toy. Universal fallback.
4. **None** — record proportion and palette only, and say plainly that size wasn't captured.

All of this is implemented in `SquishyVision.swift`. Wire it up; don't reimplement it.

### On-device vs cloud

| On device (Vision) | Cloud (Claude API) |
|---|---|
| Subject segmentation | Type, subject, material |
| Real dimensions | Surface finish |
| Colour palette | Tags, one-line note |
| Duplicate detection | — |

**The cloud call must degrade gracefully.** If identification fails or the user is offline, the specimen still saves with full measurements. Never block a save on a network call. Never show a spinner that can't be escaped.

Model: `claude-sonnet-4-6`. Prompt and JSON contract are in `SquishyVision.swift`'s companion — ask me for the API key handling approach before wiring it; do not hardcode a key or commit one.

### Duplicate detection

On capture, compare the new feature print against the library. If a match scores above 0.62, show a non-blocking card on the result screen: the suspected twin, side by side, with "Different one" and "Never mind" actions. Never auto-reject a capture.

## 5. Milestones

Build these in order. Stop after each and report.

1. **Capture → segment → save → grid.** Camera, name, durometer, `VNGenerateForegroundInstanceMaskRequest`, palette extraction, SwiftData persistence, screens 1/2/3/4. No depth yet, no cloud. Proves the mask works on real toys.
2. **Measurement.** Depth path, card fallback, method badge in the viewfinder, size rows on the detail sheet. Screens 5/6.
3. **True-scale shelf.** Screen 7. Depends on 2 being trustworthy.
4. **Identification.** Claude API call, tags, material. Graceful degradation.
5. **Duplicates and stats.** Feature prints, the twin card, screen 8.

## 6. Constraints

- No third-party dependencies without asking. Swift Charts is fine.
- No analytics, no accounts, no network calls except the one identification request.
- Accessibility is not optional: the durometer needs a proper `accessibilityValue` and adjustable trait; every icon-only button needs a label; Dynamic Type must not break the grid.
- Respect Reduce Motion — the scan sweep and durometer animation both need to no-op.
- Photos stay on device.

## 7. Anti-goals

Say no to these if they come up:

- **Do not make it cute.** No pastel chrome, no rounded playful fonts, no emoji, no mascot, no bouncy spring on everything. The restraint is the design.
- **Do not fake measurements.** If depth and card both fail, say size wasn't captured. Never estimate millimetres from an unreferenced photo and present them as measured.
- **Do not gate the app on the cloud.** Offline capture must work end to end.
- **Do not add social, sharing feeds, or gamification** in v1.
- **Do not use a stock `Slider` for squish.** The durometer is the product's signature.
