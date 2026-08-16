# Squish Index — UX & Visual Interaction Spec

Companion to `SPEC.md`. **`SPEC.md` is the authority.** Nothing here overrides it.

This document covers the layer `SPEC.md` deliberately leaves open: interaction, motion, state,
hierarchy, and component decomposition. The palette, type stack, geometry, and the ten-bar
compressing durometer are **locked** (`SPEC.md` §2) and are treated here as fixed inputs.

**Source marking.** Every claim about an iOS API or platform behaviour is marked
**[R]** (researched, with a URL) or **[J]** (design judgement). Availability strings were read
directly from Apple's documentation JSON on 2026-08-16.

**Reference device.** All absolute numbers are given for a 393 × 852 pt logical screen
(iPhone 15/16/17 base class). Content column = 393 − (2 × 22 margin) = **349 pt**.
Narrow floor is 375 pt (iPhone SE 3rd gen, content column 331 pt); every layout below states
what it does at that width.

---

## 1. Design thesis

A specimen catalogue earns its rigour in motion, not in a still frame. The locked surface —
putty, ink, hairlines, mono wall-labels — is already museum-correct. What makes it feel *sleek*
rather than merely austere is that nothing on screen ever moves for decoration, and everything
that does move is reporting a measurement.

So the motion system is deliberately impoverished: one crossfade, one settle, one compression.
The only elastic thing in the entire app is the durometer, because the durometer is the only
thing modelling an elastic solid. Its bars conserve area exactly as they squash — width up
12 → 26 pt, height down by the reciprocal — so the control behaves like material, not like a
widget with a bounce curve bolted on.

That is the tension the spec names, resolved: the rigour is in the chrome, the softness is in
the one place where softness is the datum. Everything else holds still and lets the photographs
supply the colour.

*(148 words)*

---

## 2. Derived constants

`SPEC.md` fixes gutter 13 and margin 22. These are adjacent Fibonacci terms (13, 21 ≈ 22).
The ramp is extended in both directions and **every spacing number in this document is drawn
from it**. Any deviation is called out inline with a reason.

```
Space.xxs   3
Space.xs    5
Space.sm    8
Space.gutter 13     ← SPEC.md §2
Space.margin 22     ← SPEC.md §2
Space.lg    34
Space.xl    56
```

Radii are fixed by `SPEC.md` §2: `15` cards · `19–24` photo plates · `26` sheet tops ·
`999` pills. This document uses **19** for the smallest plate (grid card), **24** for the
largest (screen 4, screen 2 exemplar), and interpolates nothing in between.

### 2.1 Type scale

Three families, three jobs (`SPEC.md` §2). Every size ships with `relativeTo:` so Dynamic Type
scales it. **[J]**

| Token | Family | Size / Weight | Tracking | `relativeTo` | Use |
|---|---|---|---|---|---|
| `D1` | Bricolage Grotesque | 44 / 800 | −0.02em | `.largeTitle` | Hero squish numeral (screen 4 only) |
| `D2` | Bricolage Grotesque | 26 / 800 | −0.02em | `.title` | Screen titles |
| `D3` | Bricolage Grotesque | 24 / 600 | −0.02em | `.title2` | Specimen name — detail & name field |
| `D4` | Bricolage Grotesque | 17 / 600 | −0.02em | `.headline` | Specimen name — grid card |
| `B1` | Inter | 15 / 400, leading 21 | 0 | `.body` | Sentences, descriptions |
| `B2` | Inter | 16 / 600 | 0 | `.body` | Button labels |
| `B3` | Inter | 13 / 400 | 0 | `.footnote` | Secondary prose |
| `M1` | DM Mono | 10 / 400, UPPERCASE | +0.16em | `.caption2` | Eyebrows, field labels, units |
| `M2` | DM Mono | 12 / 500 | +0.04em | `.caption` | Numeric values in-line (card squish, counts) |

`M2` drops the tracking to +0.04em because +0.16em on digits reads as spaced-out ransom note,
not as instrument data. `SPEC.md` §2 specifies +0.16em for "every label, measurement, unit,
and eyebrow" — labels and units keep it; bare numerals do not. **[J]** — flagged in §9.

**Zero-padding rule.** Squish values rendered in mono are zero-padded to two digits (`07`).
The hero display numeral is never padded (`7`). Rationale: fixed-width mono keeps the card's
meta row from reflowing between `07` and `10`; the display numeral is a name-register glyph
and padding would make it read as data. **[J]**

---

## 3. Component inventory (Milestone 1)

All live in `Design/` unless noted. Props are given as the Swift signature the developer should
land on; states are exhaustive.

### 3.1 `Durometer`

```swift
struct Durometer: View {
    @Binding var level: Int          // 1...10
    var isInteractive: Bool = true
    var tint: Color? = nil           // nil → SquishTheme.ink; set on the detail sheet
    var trackWidth: CGFloat? = nil   // nil → min(340, availableWidth)
}
```

**States:** `idle` · `dragging` (a drag is live; live animation curve, no commit haptic
suppression) · `abandoned` (drag reclassified as a scroll, value reverted) · `readOnly`
(`isInteractive == false`; no gesture, no focus, no adjustable trait) · `keyboardFocused`
(2 pt ink ring, radius 999, inset −5).

Full specification in §5.

### 3.2 `DurometerBar`

Private to `Durometer`. Pure geometry, no state.

```swift
private struct DurometerBar: View {
    let index: Int        // 1...10
    let isFilled: Bool
    let k: Double         // 0...1 compression, = (level - 1) / 9
    let fill: Color
}
```

### 3.3 `SpecimenCard`

```swift
struct SpecimenCard: View {
    let specimen: Squishy
    var width: CGFloat               // 168 at 2-up on the reference device
}
```

**States:** `loaded` · `imagePending` (photo blob still resolving from `.externalStorage`) ·
`imageFailed` · `pressed` (0.98 scale, 0.10 s) · `contextMenuActive`.

There is **no** `selected` state in Milestone 1 — there is no multi-select.

### 3.4 `SpecimenRow`

The Dynamic-Type reflow partner to `SpecimenCard` (see §7.2). Same data, horizontal layout.

```swift
struct SpecimenRow: View { let specimen: Squishy }
```

### 3.5 `PhotoPlate`

```swift
struct PhotoPlate<Overlay: View>: View {
    let image: Image?
    var cornerRadius: CGFloat        // 19 | 24 only
    var showsBorder: Bool = true     // 1pt SquishTheme.line
    @ViewBuilder var overlay: () -> Overlay
}
```

**States:** `filled` · `empty` (chalk fill, border, nothing inside — used by the empty-state
exemplar) · `pending` (chalk fill, border, no spinner and no shimmer — a shimmer gradient is
chrome colour and is forbidden by `SPEC.md` §2) · `failed` (chalk fill, centred `M1` label
`IMAGE UNAVAILABLE` in `soft`, no icon).

### 3.6 `MonoLabel` / `Eyebrow`

```swift
struct MonoLabel: View {
    let text: String
    var style: Style = .label        // .label (M1) | .value (M2)
    var tint: Color = SquishTheme.soft
}

struct Eyebrow: View { let text: String }   // MonoLabel(style: .label), uppercased at render
```

`Eyebrow` uppercases in the view, not in the data. Never uppercase a user-entered string.

**States:** none. Purely presentational. Above `.xxLarge` Dynamic Type the tracking drops from
+0.16em to +0.08em (tracking is a visual nicety, not information, and +0.16em at AX sizes
overflows every container). **[J]**

### 3.7 `PaletteStrip`

```swift
struct PaletteStrip: View {
    let hexes: [String]              // 0...4, in dominance order
    var swatchSize: CGFloat = 13
    var proportions: [Double]? = nil // nil → uniform swatches; non-nil → proportion bar (screen 6)
}
```

**States:** `uniform` (grid card: up to 4 squares, 13 × 13, radius 3, 3 pt apart, left-aligned)
· `proportional` (screen 6: single 999-radius bar, height 22, segments sized by `proportions`)
· `empty` (fewer than 1 colour extracted — renders nothing at all; **never pad missing slots
with grey placeholders**, that fabricates data. **[J]**, see §9 Q11).

The whole strip is **one** accessibility element and **one** hit target. Individual 13 pt
swatches can never be individually tappable — 13 + 3 spacing makes 44 pt hit regions overlap.

### 3.8 `Chip`

```swift
struct Chip: View {
    let title: String
    var count: Int? = nil            // non-nil → count badge
    var trailingCaret: Bool = false  // sort chip
    var isActive: Bool = false
    var isEnabled: Bool = true
    var action: (() -> Void)? = nil  // nil → non-interactive (empty-state descriptor chips)
}
```

Visual: height **30**, radius 999, horizontal padding 13, 1 pt `line` border, no fill.
Label `M1`. Hit region **44 pt** tall via `.contentShape` (see §7.4).

**States:**
- `rest` — border `line`, label `soft`
- `active` — border `ink`, label `ink`, 1.5 pt border. **Plus** the count badge. `SPEC.md` §3
  requires that colour is never the only state indicator; here the indicators are border weight
  **and** the badge **and** the label tint. Three cues, one of them textual.
- `disabled` — border `line`, label `soft` at 40%, `.accessibilityHint` explaining why
- `pressed` — 0.97 scale, 0.10 s
- `nonInteractive` — no press state, no button trait

**Count badge:** a 999-radius pill inset in the chip's trailing edge, height 16, min width 16,
horizontal padding 5, fill `ink`, label `M2` at 10 pt in `chalk`. Gap from the title: 8.
Badge appears/disappears with `Motion.readout` and `.transition(.blurReplace)` **[R]**
(`BlurReplaceTransition`, iOS 17.0 —
https://developer.apple.com/documentation/swiftui/blurreplacetransition).

### 3.9 `SegmentedControl`

```swift
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String, isEnabled: Bool)]
}
```

Used once, for **Grid · Shelf · Stats** (`SPEC.md` §3).

Visual: full content width (349), height **36**, radius 999, 1 pt `line` border, no fill.
Selected segment: `ink` fill, radius 999, inset 3 on all sides (so the ink pill is 30 tall);
label `chalk`, `M1`. Unselected label `ink.opacity(0.62)` (4.6:1 measured — see §7.3), not
`soft`, because at 10 pt `soft` fails AA. Disabled segment: label `soft.opacity(0.4)`.

The selection pill moves with `matchedGeometryEffect` **[R]** (iOS 14.0 —
https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:))
under `Motion.select`. Reduce Motion: pill crossfades in place, no travel.

**States:** per-segment `selected` / `unselected` / `disabled`; container `keyboardFocused`.
On an empty library, Shelf and Stats are **disabled, not hidden** — the empty state's job is to
teach the app's shape (`SPEC.md` §3 screen 2), and hiding two thirds of the navigation defeats
that. **[J]**

### 3.10 `FloatingCTA`

```swift
struct FloatingCTA: View {
    let title: String
    let systemImage: String
    var isCollapsed: Bool = false
    let action: () -> Void
}
```

Visual: pill, radius 999, height **52**, fill `ink`, label `M1` in `chalk` + SF Symbol 17 pt.
Horizontal padding 22, icon-to-label gap 8. Positioned 22 from the trailing margin and 22 above
the bottom safe area.

Shadow is explicitly licensed by `SPEC.md` §2 ("never shadows, except the floating CTA and the
bottom sheet"). Two layers **[J]**:
```swift
.shadow(color: SquishTheme.ink.opacity(0.16), radius: 18, y: 8)   // ambient
.shadow(color: SquishTheme.ink.opacity(0.10), radius: 3,  y: 1)   // contact
```

**States:** `expanded` · `collapsed` (52 × 52 circle, icon only, label removed with
`.transition(.blurReplace)`) · `pressed` (0.96 scale + ambient shadow radius 18 → 10, 0.10 s) ·
`barMode` (empty state only: full content width, static, no shadow — see §4.2).

The accessibility label is **`"Capture a specimen"` in every state**, including collapsed.

### 3.11 `HeroNumeral`

```swift
struct HeroNumeral: View { let value: Int }   // D1, monospacedDigit, ink
```

`.contentTransition(.numericText(value: Double(value)))` **[R]** (iOS 17.0 —
https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:)).
Under Reduce Motion, swap to `.contentTransition(.opacity)`.

### 3.12 `IndexHeader`

```swift
struct IndexHeader: View {
    let title: String
    let specimenCount: Int
    let averageSquish: Double?       // nil when count == 0
}
```

Composes `D2` title + a `M1` stat line. See §4.1 for layout.

### 3.13 `NameField`

```swift
struct NameField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
}
```

`D3` text, `ink`. Placeholder `"Name this one"` in `line`… **except** — `line` on `putty` is
1.22:1 and the placeholder is the field's only affordance, so the placeholder renders in
`soft` and the rule below it renders in `line`. **[J]** See §7.3.

Rule: 1 pt `line`, full field width, 12 pt below the baseline. On focus → 1.5 pt `ink`,
animated with `Motion.readout`.

**States:** `empty` · `empty+focused` · `filled` · `filled+focused` · `overflowing`
(`.lineLimit(1)`, `.minimumScaleFactor(0.7)`, tail truncation past that; soft cap 48 characters,
enforced by silently refusing further input — no error, no counter).

### 3.14 `ViewfinderOverlay`, `MethodBadge`, `ShutterButton`

```swift
struct ViewfinderOverlay: View {
    let subjectBox: CGRect?          // nil → searching
    let method: MeasurementMethod
    let distanceMM: Double?
}
struct MethodBadge: View { let method: MeasurementMethod }
struct ShutterButton: View { let action: () -> Void }
```

See §4.3.

### 3.15 `HairlineRule`

```swift
struct HairlineRule: View { var inset: CGFloat = 0 }
```

Exactly 1 pt (`1.0 / displayScale` is **wrong** here — `SPEC.md` §2 says 1 pt, meaning one
logical point, which is the visually heavier and more deliberate choice for an editorial rule).
**[J]**

### 3.16 `BlankRecordPlate`

Empty-state only. See §4.2.

### 3.17 `SquishTheme`

```swift
enum SquishTheme {
    // Palette — SPEC.md §2, locked
    static let putty = Color(hex: 0xF1F0EC)
    static let ink   = Color(hex: 0x14151A)
    static let soft  = Color(hex: 0x74777E)
    static let line  = Color(hex: 0xDDDBD4)
    static let chalk = Color(hex: 0xFFFFFF)

    enum Metrics { /* radii, the Space ramp */ }
    enum Motion  { /* §6 */ }
    enum Typo    { /* §2.1 */ }
}
```

---

## 4. Screen by screen

### 4.1 Screen 1 — Shelf / Grid

#### Structure (top to bottom)

| Element | Height | Spacing above |
|---|---|---|
| Safe area top | — | — |
| Title `D2` "Squish Index" | 34 | 13 |
| Stat line `M1` | 14 | 5 |
| `SegmentedControl` | 36 | 22 |
| Chip row (horizontal scroll) | 44 (30 visual) | 13 |
| Grid | flexible | 13 |
| Bottom safe area + `FloatingCTA` overlay | — | — |

**Stat line.** `47 SPECIMENS · AVG SQUISH 6.4`. The words render in `soft`, the numerals in
`ink`, built as one `AttributedString` so VoiceOver reads it as one phrase. The count is data,
so it is mono, not display — `SPEC.md` §2 forbids display type on measurements. When
`specimenCount == 0` the average clause is **omitted entirely**, not rendered as `AVG SQUISH —`:
the mean of an empty set is undefined, and printing an em-dash invites the reader to think a
computation failed. **[J]**

**Sticky band.** The `SegmentedControl` + chip row live in a `.safeAreaInset(edge: .top)` with
a `putty` background and a bottom `HairlineRule` whose opacity animates 0 → 1 over the first
8 pt of scroll offset (`Motion.readout`). The title and stat line scroll away normally. This
avoids fighting `.toolbar`, which adopts Liquid Glass material on iOS 26 and would break the
locked flat direction (§9 Q7). **[J]**

**Grid.**

```swift
LazyVGrid(
    columns: [GridItem(.flexible(), spacing: 13),
              GridItem(.flexible(), spacing: 13)],
    spacing: 22
)
```

Row spacing is **22**, larger than the 13 gutter, so each card's caption groups with its own
plate rather than with the card below it. Horizontal gutter is fixed by `SPEC.md` §2; vertical
takes the next ramp step up. **[J]**

**Card anatomy** (width 168 on the reference device, 152 at 375 pt):

| Part | Size | Gap above |
|---|---|---|
| `PhotoPlate` | 168 × 168, radius **19**, 1 pt `line` border, `chalk` fill | — |
| Name `D4` | width 168, 2 lines reserved (2 × lineHeight, 42 pt at default type) | 8 |
| Meta row | height 15 | 5 |

Meta row: `PaletteStrip` leading (4 × 13 + 3 × 3 = **61 pt**), `MonoLabel(style: .value)`
trailing rendering `07`.

Card total at default type: 168 + 8 + 42 + 5 + 15 = **238 pt**. Uniform, as `SPEC.md` §3
requires. The name's reserved height is computed as `2 × lineHeight(currentDynamicTypeSize)`,
**never a literal 42** — a hardcoded height breaks Dynamic Type (§7.2).

The card itself has **no border and no fill**. The plate's 1 pt `line` border is the card's
only boundary; wrapping the whole card in a second border would double the hairlines and make
the grid read as a spreadsheet. **[J]** (`SPEC.md` is silent on this — §9 Q_card.)

#### Interactions

| Trigger | Result |
|---|---|
| Tap card | Push to specimen sheet (screen 6). iOS 18+: `.matchedTransitionSource(id: specimen.id, in: ns)` on the plate + `.navigationTransition(.zoom(sourceID:in:))` on the destination **[R]** (both iOS 18.0 — https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:) , https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)). iOS 17: plain push, plate crossfades. |
| Press-and-hold card | `.contextMenu` — exactly 3 items: **Rename**, **Change squish**, **Delete…**. "Delete…" opens a `.confirmationDialog` (`SPEC.md` §3: destructive actions in an action sheet, 3–5 options). |
| Tap sort chip | `.confirmationDialog` with 4 options (§9 Q5). Chip caret rotates 0° → 180° under `Motion.readout`. Reduce Motion: caret swaps glyph, no rotation. |
| Tap colour filter chip | Push a filter sheet at `.presentationDetents([.medium])`. On return, chip goes `active` and gains its count badge. |
| Tap `SegmentedControl` | Switches Grid / Shelf / Stats. Content crossfades under `Motion.select`; **no horizontal slide** — a slide implies a spatial relationship the three views do not have. **[J]** |
| Tap `FloatingCTA` | Present screen 3 full-screen cover. |
| Scroll down > 60 pt | CTA collapses to 52 × 52 icon-only. |
| Scroll up, or scroll ends | CTA expands. |
| Pull to refresh | **Not offered.** All data is local; a refresh control would imply a server. **[J]** |

**Scroll transition on cards** **[R]** (`.scrollTransition`, iOS 17.0 —
https://developer.apple.com/documentation/swiftui/view/scrolltransition(_:axis:transition:) ;
`ScrollTransitionPhase.value` returns −1 at `topLeading`, 0 at `identity`, +1 at
`bottomTrailing` — https://developer.apple.com/documentation/swiftui/scrolltransitionphase/value):

```swift
.scrollTransition(.interactive, axis: .vertical) { content, phase in
    content
        .opacity(phase.value > 0 ? 1 - phase.value * 0.40 : 1)
        .scaleEffect(phase.value > 0 ? 1 - phase.value * 0.02 : 1)
}
```

Deliberately **asymmetric**: cards settle in as they arrive from the bottom, and do nothing as
they leave upward. A symmetric fade makes scrolling back up look like a rendering bug, and it
also dims content the user is deliberately reading. Max opacity delta 0.40, max scale delta
0.02 — any more and it reads as a parallax gimmick, which §7 forbids in spirit. **[J]**

Reduce Motion: omit the modifier entirely.

#### Empty / loading / error

- **Empty (count == 0):** screen 2 replaces the grid. Header, segmented control and chip row
  remain, with Shelf/Stats and all chips disabled.
- **Loading:** none. SwiftData reads are local and first paint is effectively synchronous. If a
  photo blob is still resolving, that individual `PhotoPlate` sits in its `pending` state
  (chalk + border, nothing else). No skeletons, no shimmer.
- **Filtered to zero results:** the grid is replaced by a single centred block —
  `Eyebrow("NO MATCHES")`, 13 pt gap, `B1` "No specimen matches these filters.", 22 pt gap, a
  999-radius `ink` pill "Clear filters" (height 44). The header count keeps reporting the
  **total** library size; a second `M1` line appears reading `SHOWING 0 OF 47` (§9 Q12).
- **Store error (SwiftData fetch throws):** full-screen block, `Eyebrow("INDEX UNAVAILABLE")`,
  `B1` with the underlying reason in plain language, and a "Try again" pill. No stack trace,
  no error code.

---

### 4.2 Screen 2 — Empty state

`SPEC.md` §3: "teaches by showing a completed record, then chips listing what gets measured.
Never just 'no items yet.'"

The strongest version of that is **a blank accession card with its fields labelled** — the app
showing its own schema. A stock photograph of a squishy would be a lie about the catalogue's
contents; a wireframe with real field names is honest and does the teaching job better. **[J]**

#### Structure

| Element | Spec | Gap above |
|---|---|---|
| (header + segmented + chips, as screen 1, disabled) | — | — |
| `Eyebrow("SPECIMEN RECORD · BLANK")` | `M1`, `soft` | 34 |
| `BlankRecordPlate` | 240 × 240, radius **24**, `chalk`, 1 pt `line`, empty | 13 |
| Field rows | 5 rows × 32 pt, `HairlineRule` between | 22 |
| Explanatory sentence | `B1`, left-aligned to the margin | 22 |
| Descriptor chips (wrapping, 2 rows, 8 pt gaps) | `Chip(nonInteractive)` | 22 |
| Bottom bar CTA | full width | — |

**Field rows.** Label column width **88 pt**, `M1` in `soft`. Value column shows an empty
marker in `line`:

```
NAME       ————————————
SQUISH     --
PALETTE    []  []  []  []
WIDTH      -- MM
FORM       ——
```

`NAME`'s marker is a 120 × 3 rounded rect in `line`; `PALETTE`'s is four 13 × 13 outlined
squares. Everything else is literal ASCII dashes in `M1`. This block is a preview of screen 6's
spec rows — same label column width, same row height — so the empty state is literally showing
the user the record they are about to fill.

Accessibility: the whole field block is **one** element,
`.accessibilityLabel("Blank specimen record. Fields: name, squish, palette, width, form.")`.
Reading five rows of dashes one at a time is noise.

**Sentence.** `B1`, `ink`:
> Photograph a squishy and the index fills this card in. Everything below the name is measured
> on your phone.

Left-aligned, max width 300 pt. Centred body copy is a marketing register; this is a catalogue.
**[J]**

**Descriptor chips.** `SUBJECT MASK` · `COLOUR PALETTE` · `SILHOUETTE` · `REAL MILLIMETRES` ·
`DUPLICATE CHECK`. Non-interactive, no button trait. The container is one accessibility element:
`"Measured automatically: subject mask, colour palette, silhouette, real millimetres,
duplicate check."`

Chips for capabilities that Milestone 1 does not ship (`REAL MILLIMETRES`, `DUPLICATE CHECK`)
are rendered at `soft.opacity(0.4)` with a trailing `M1` "SOON" — or omitted. **Recommendation:
omit them in M1.** Advertising a capability the build does not have contradicts `SPEC.md` §7's
"do not fake measurements" in spirit. **[J]**

**CTA.** On the empty state, `FloatingCTA` switches to `barMode`: full content width, height 52,
radius 999, `ink` fill, label `B2` in `chalk` — **"Photograph the first one"** — pinned in
`.safeAreaInset(edge: .bottom)` with 22 pt padding, and **no shadow**. With zero content there
is nothing for a floating element to float over; a bar is the honest form, and the shadow
licence in `SPEC.md` §2 is for the *floating* CTA specifically. **[J]**

#### Interactions

Only the CTA and the segmented control's Grid segment are live. Everything else is inert with
correct disabled semantics. Tapping a disabled segment produces no haptic and no animation.

#### Transition out

When the first specimen saves, the empty state does **not** animate into the grid. It is
replaced by the grid with `.transition(.opacity)` at `Motion.reveal`, and the single new card
enters with `Motion.settle`. Trying to morph a blank record into a real card would require
matching geometry across two structurally different layouts and would look like a glitch. **[J]**

---

### 4.3 Screen 3 — Capture / viewfinder

Full-bleed `AVCaptureVideoPreviewLayer` in a `UIViewRepresentable` (the one UIKit exception
`SPEC.md` §4 allows). `.ignoresSafeArea()`.

**Background outside the preview is `ink`, not `putty`.** A camera UI must not throw a light
canvas around the preview — it shifts the user's perception of the subject's exposure. `ink` is
an existing token; no new colour is introduced. **[J]**

#### Overlay layout

**Top band** — below the top safe area + 13:
- Leading, at margin 22: Close button, 44 × 44, SF Symbol `xmark`, `chalk`, no background.
  Label `"Close capture"`.
- Trailing, at margin 22: `MethodBadge`.

`MethodBadge`: pill 999, height 28, horizontal padding 13. Fill `chalk.opacity(0.12)`, border
1 pt `chalk.opacity(0.24)`, label `M1` in `chalk`. Under **Reduce Transparency**, fill becomes
opaque `ink` with a 1 pt `chalk` border.

Badge text by method — `SPEC.md` §4 requires the method always be surfaced:

| Method | Badge |
|---|---|
| LiDAR / sceneDepth | `LIDAR` |
| Dual-camera depth | `DEPTH` |
| Reference card | `CARD` |
| None | `NO SIZE DATA` |

**Milestone 1 has no depth path at all** (`SPEC.md` §5), so in M1 the badge is permanently
`NO SIZE DATA`. This is honest and satisfies §7 anti-goal 2. It is also slightly absurd, and
worth confirming — §9 Q3.

**Corner brackets.** Four L-shapes. Arm length **26**, stroke **2 pt**, `chalk` at 90 %, elbow
radius 3. The bracket box tracks the segmentation subject bounds, inset by 8 pt, animated with
`Motion.surface`. With no lock, the box rests at a centred 260 × 260 square.

**Lock readout.** Centred, 13 pt below the bracket box's bottom edge. `M1` in `chalk`:
- No subject: `SEARCHING`
- Subject locked, no depth: `SUBJECT LOCKED`
- Subject locked, with depth (M2+): `SUBJECT LOCKED · 240 MM`

Text swaps crossfade under `Motion.readout`. Never animate the numeral with `numericText` here —
a live distance readout that constantly rolls digits is visual noise on a camera preview. Use a
plain `.monospacedDigit()` `Text`. **[J]**

**Bottom band** — 132 pt tall, measured from the bottom safe area:
- `ShutterButton`, centred: 74 pt outer ring, 2 pt `chalk` stroke; inner disc 62 pt, `chalk`.
- Library button, leading at margin 22, vertically centred on the shutter: 44 × 44, SF Symbol
  `photo.on.rectangle`, `chalk`. Label `"Choose from library"`.
- Card button, trailing at margin 22: 44 × 44, SF Symbol `creditcard`, `chalk`. Label
  `"Reference card mode"`. **Hidden in Milestone 1** — shipping a dead control is worse than
  shipping an asymmetric bar, and `SPEC.md` §5 puts the card path in Milestone 2.

#### Interactions

| Trigger | Result |
|---|---|
| Tap preview | Focus/exposure at point. A 62 × 62 `chalk` square, 1 pt stroke, appears at the tap; scales 1.10 → 1.00 over 0.20 s, then fades out after 1.2 s. Reduce Motion: appears at 1.00, fades, no scale. |
| Tap shutter | `.sensoryFeedback(.impact(weight: .medium), trigger: captureCount)` **[R]** (iOS 17.0 — https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)). Inner disc scales to 0.86 for 0.08 s. Preview freezes on the captured still. **No white flash** — a full-screen white frame is both harsh and off-palette. |
| Capture completes | Frozen frame transitions to screen 4's plate (see §6, `capture → name`). |
| Tap library | `PhotosPicker`, single selection, images only. |
| Tap close | Dismiss. If a capture is mid-flight, cancel it silently. |
| Swipe down | Dismisses the cover (standard `fullScreenCover` behaviour is off by default — enable interactive dismissal explicitly, since a camera the user cannot back out of is hostile). |

#### States

- **Permission not determined:** the preview area shows `ink` with a centred block —
  `Eyebrow("CAMERA")`, 13 gap, `B1` in `chalk`: *"Squish Index needs the camera to photograph
  and measure specimens. Photos stay on this device."*, 22 gap, a 999-radius `chalk` pill
  (height 44, label `B2` in `ink`) reading **"Allow camera"**. On tap, request authorisation.
- **Permission denied:** same block, sentence becomes *"Camera access is off for Squish Index.
  You can turn it on in Settings."*, button reads **"Open Settings"** and calls
  `UIApplication.openSettingsURLString`.
- **No camera (Simulator):** *"This device has no camera."* + **"Choose from library"**.
- **Session interrupted** (call, another app): overlay chrome dims to 40 %, readout reads
  `PAUSED`. Auto-recovers.
- **Capture failed:** an `M1` banner slides into the top of the bottom band —
  `CAPTURE FAILED · TRY AGAIN` in `chalk` on `ink.opacity(0.7)` — auto-dismisses after 3 s,
  plus `.sensoryFeedback(.error, trigger:)`. Reduce Motion: crossfade in, no slide.

---

### 4.4 Screen 4 — Name & durometer

The most important structural decision on this screen: **the durometer never scrolls.**

The durometer's drag gesture is positional and starts on touch-down (§5.4). Placing it inside a
scroll view creates a gesture conflict where a user trying to scroll accidentally sets a value.
Solving that in gesture code is possible but fragile. Solving it in layout is free: the
durometer block lives in `.safeAreaInset(edge: .bottom)` and the plate/name region above it
scrolls if and only if it needs to. **[J]**

#### Structure

**Navigation bar:** leading `Cancel` (`B2` weight 400, `soft`). Trailing: **empty**. The
primary action is the bottom pill; a nav-bar Save competing with a full-width footer button is
two primary actions.

**Scrolling region** (top to bottom):

| Element | Size | Gap above |
|---|---|---|
| `PhotoPlate` (centred) | `min(260, availableHeight − 364)`, floor 200, square, radius **24** | 13 |
| `RETAKE` text button | 44 pt tall, `M1`, `soft` | 5 |
| `NameField` | full content width, 44 text + 12 rule = 56 | 22 |

**Bottom inset** (`putty` fill, 1 pt `line` top rule, 22 pt top padding):

| Element | Size | Gap above |
|---|---|---|
| `Eyebrow("SQUISH LEVEL")` + `HeroNumeral`, `HStack(alignment: .lastTextBaseline)` | 44 | — |
| `Durometer` track | 340 × 88, centred | 13 |
| Level sentence | 2 lines reserved | 13 |
| "File specimen" pill | full width × 52, radius 999, `ink`, `B2` in `chalk` | 22 |
| bottom safe area | +13 | — |

Inset total at default type: 22 + 44 + 13 + 88 + 13 + 42 + 22 + 52 + 13 = **309 pt**.

**Height budget check.** Reference device usable height = 852 − 59 (safe top) − 44 (nav) − 34
(safe bottom) = 715. Consumed: 13 + 260 (plate) + 5 + 44 + 22 + 56 + 309 = **709**. Fits, 6 pt
spare. At 375 × 667 (SE) usable = 603, so the plate clamps to its 200 pt floor and the upper
region scrolls — which is correct, because the inset is what must stay reachable.

**Level sentence.** `B1`. The term renders in `ink` at weight 600, the description in `soft`:

> **Slack.** Squashes nearly flat under light pressure. Comes back slowly.

Height is **reserved at 2 lines** (`2 × lineHeight(currentDynamicTypeSize)`, 42 pt at default,
4 lines above `.accessibility2`). Without a reserved height the entire footer jumps on every
drag step, which is intolerable while dragging. **[J]**

#### Interactions

| Trigger | Result |
|---|---|
| Drag / tap durometer | §5. |
| Tap `RETAKE` | `.confirmationDialog`: **Retake photo** / **Choose from library** / Cancel. |
| Tap name field | Keyboard rises. The bottom inset rides above it automatically. `.scrollDismissesKeyboard(.interactively)` **[R]** (iOS 16.0 — https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)) on the scroll region. `.submitLabel(.done)`. `.textInputAutocapitalization(.words)`. |
| Tap "File specimen" | Save, `.sensoryFeedback(.success, trigger:)`, dismiss to grid under `Motion.reveal`. Grid scrolls to top; the new card enters with `Motion.settle`. |
| Tap Cancel with unsaved edits | `.confirmationDialog`: **Discard photo** (destructive) / Cancel. With no edits at all, dismiss silently. |
| Rotate device | Locked to portrait (the capture flow is portrait-only; nothing here benefits from landscape). |

**Save is never blocked.** If the name is empty on save, the specimen files as
`Unnamed specimen`. `SPEC.md` §4's "never block a save on a network call" is a specific case of
a general principle: this flow terminates in a saved record, always. Disabling the primary
button behind a text field is the classic version of that failure. **[J]** — §9 Q9.

**Duplicate-twin slot (Milestone 5 forward-compat).** Reserve the region directly beneath the
`NameField`, inside the scrolling area. The twin card will be a `chalk` plate, radius 15, 1 pt
`line`, containing two 88 × 88 plates side by side with a 13 gutter, an `M1` caption
`POSSIBLE DUPLICATE · 0.71`, and two chips: **Different one** / **Never mind**. Non-blocking,
dismissible, and the save button never changes state because of it (`SPEC.md` §4).

#### States

- **Photo still processing** (segmentation running): plate shows the raw capture at 100 %
  opacity; the extracted mask crossfades in over it under `Motion.reveal` when ready. No spinner.
- **Segmentation failed:** plate shows the raw capture unmasked; an `M1` caption below reads
  `SUBJECT NOT ISOLATED` in `soft`. The specimen still saves. This is the M1 analogue of the
  cloud-degradation rule.
- **Durometer untouched:** level defaults to **5**, not 1. Defaulting to an endpoint biases the
  data; the midpoint is the honest prior, and it also puts the control in its most legible state
  (five filled, five empty) so the affordance is obvious. **[J]**

---

### 4.5 Screens 5–8 — forward compatibility

Sketched only, so Milestone 1's components are built to fit.

**Screen 5 — Measuring.** Reuses screen 4's plate at the same size and position, so the
transition from 4 → 5 moves nothing. Checklist below it: five `ChecklistRow`s, 44 pt each,
`HairlineRule` between. Each row = a 13 × 13 state box (leading) + `M1` label. Box states:
pending (1 pt `line` outline), active (half-filled `ink`, **static**), done (solid `ink`,
`.transition(.blurReplace)`). Scan sweep: a 2 pt `chalk` line at 55 % opacity travelling top →
bottom across the plate over 1.1 s, `.easeInOut`, repeating. Reduce Motion: **no sweep at all**;
instead the plate gains a static 1 pt `chalk` inset border and the checklist alone carries
progress (`SPEC.md` §6 requires the sweep to no-op).

**Screen 6 — Specimen sheet.** Photo fills the top edge-to-edge, no plate radius at the screen
edges. Specs arrive as a sheet:

```swift
.presentationDetents([.medium, .large])            // iOS 16.0
.presentationCornerRadius(26)                       // iOS 16.4 — matches SPEC.md §2
.presentationDragIndicator(.visible)                // iOS 16.0
.presentationBackgroundInteraction(.enabled(upThrough: .medium))  // iOS 16.4
```
**[R]** — https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:) ,
https://developer.apple.com/documentation/swiftui/view/presentationcornerradius(_:) ,
https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:) ,
https://developer.apple.com/documentation/swiftui/view/presentationdragindicator(_:) .

`presentationBackgroundInteraction(.enabled(upThrough: .medium))` is what lets the user pinch
and pan the photograph while the specs are still on screen — the single interaction that makes
this screen feel like an object under glass rather than a form. The drag indicator is shown
because at `.medium` there is no other cue that the sheet resizes.

Sheet content order: name `D3` → tinted `Durometer(isInteractive: false)` + numeral → spec rows
(same 88 pt label column as screen 2) → `PaletteStrip(proportions:)`.

**Tint contrast rule.** The tinted durometer must not vanish. If the dominant colour's contrast
against `chalk` is below 3:1, darken it (in OKLCH, reducing L only) until it reaches exactly
3:1, use that for the filled bars, and show the true unmodified colour only in the palette
strip. Pastel squishies are the common case, so this rule fires often. **[J]** — §9 Q6.

**Screen 7 — True scale.** Rows on 1 pt `line` baselines, sorted ascending. mm ticks: 5 pt tall
every 10 mm, 9 pt tall every 50 mm with an `M1` label. Scale factor chosen so the largest
specimen fits the 349 content column; the factor is printed as `M1`: `1 PT = 0.42 MM`. Printing
the scale is what makes it a plate in a catalogue rather than a picture.

**Screen 8 — Stats.** The squish histogram uses **exactly the durometer's bar geometry** —
10 bins, the same 34 pt slot, the same base heights and lean — with bin counts driving fill.
The histogram and the input control become the same object seen twice. This is the single
highest-leverage forward-compat decision in this document, and it is why `DurometerBar` is
factored out as a pure-geometry view with no state. **[J]**

---

## 5. The durometer, in full

### 5.1 Geometry

Ten bars, bottom-aligned on a shared baseline, in ten equal slots.

```
trackWidth = min(340, contentWidth)          // 340 = 10 × 34 (ramp)
slot       = trackWidth / 10                 // 34 pt on the reference device
trackHeight = 88                             // = 4 × 22 (ramp)
```

**Base heights** — the lean. Bar 1 is tallest, bar 10 shortest; total lean is exactly one
margin unit (22 pt), so the decrement is 22/9 = 2.444 pt.

```
h_base(i) = 88 - (i - 1) * (22.0 / 9.0)      // i = 1...10
h_base(1)  = 88.00
h_base(5)  = 78.22
h_base(10) = 66.00
```

**Compression.** Define `k = Double(level - 1) / 9.0`, so `k = 0` at level 1 and `k = 1` at
level 10.

```
w(k)      = 12 + 14 * k                       // 12 → 26 pt
h(i, k)   = h_base(i) * (12.0 / w(k))         // exact area conservation
r(i, k)   = min(3 + 10 * k, w(k) / 2, h(i, k) / 2)
```

- **Widths** land on the ramp via the gaps they leave: `slot − 12 = 22` (the margin unit) at
  rest, `slot − 26 = 8` at full compression. The row visibly densifies as squish rises.
- **Heights** use the reciprocal of the width factor, so **every bar's area is constant at every
  level**: 12 × h_base(i) at all times. The material changes shape, not mass. This is both the
  cleanest formula and the strongest physical justification for the whole control.
- **Radii** go 3 → 13. At `k = 1`, `w = 26` and `r = 13 = w/2` exactly, so a fully compressed
  bar is a perfect stadium. The two extra `min` clauses are defensive and never bind at the
  specified numbers.

**Fill rule.** Bar `i` is filled iff `i <= level`. A filled bar uses `w(k)`, `h(i, k)`, `r(k)`.
An **unfilled bar always uses `k = 0`**: 12 pt wide, `h_base(i)` tall, radius 3.

The boundary between the short/fat/dark run and the tall/thin/light run **is the value
indicator**. There is no thumb, no knob, no track fill. **[J]**

**Colours.**

| Part | Colour | Contrast vs. `putty` |
|---|---|---|
| Filled (interactive) | `ink` #14151A | 15.99:1 |
| Filled (read-only, screen 6) | specimen tint, floored at 3:1 vs `chalk` | ≥ 3:1 |
| Unfilled | **`soft` #74777E**, not `line` | 3.93:1 |

Unfilled bars use `soft`, **not** `line`. `line` (#DDDBD4) on `putty` measures **1.22:1**, which
fails WCAG 1.4.11's 3:1 floor for meaningful graphics. The unfilled bars are meaningful — they
show the scale's ceiling — so they need a token that clears 3:1. `soft` does (3.93:1). `line`
stays reserved for hairline rules, which are decorative separators and exempt. **[J]** — see §7.3.

#### Sample geometry

| Level | k | w | r | h(1) | h(10) | gap |
|---|---|---|---|---|---|---|
| 1 | 0.000 | 12.00 | 3.00 | 88.00 | 66.00 | 22.0 |
| 3 | 0.222 | 15.11 | 5.22 | 69.88 | 52.41 | 18.9 |
| 5 | 0.444 | 18.22 | 7.44 | 57.95 | 43.46 | 15.8 |
| 8 | 0.778 | 22.89 | 10.78 | 46.13 | 34.60 | 11.1 |
| 10 | 1.000 | 26.00 | 13.00 | 40.62 | 30.46 | 8.0 |

At level 10 the shortest bar is 30.5 × 26 — still marginally taller than wide, so it reads as a
compressed bar and not as a blob. The lean survives compression (40.62 vs 30.46).

### 5.2 Hit region

Visual track is 340 × 88. The hit region is the **full content width × 112 pt**
(88 + 12 above + 12 below), applied as:

```swift
.frame(width: contentWidth, height: 112)
.contentShape(Rectangle())
.coordinateSpace(name: "durometer")
```

Extending horizontally past the 340 track means x-values outside `0..<340` clamp to levels 1 and
10, so a user who overshoots the ends still gets the endpoint. This matters — reaching exactly
1 or exactly 10 is the whole point of an endpoint.

### 5.3 Value mapping

```swift
func level(atX x: CGFloat, trackWidth: CGFloat) -> Int {
    let slot = trackWidth / 10
    return min(10, max(1, Int((x / slot).rounded(.down)) + 1))
}
```

`x` is in the track's local coordinate space, where 0 is the track's leading edge.

### 5.4 Drag gesture

**Positional (absolute), not relative.** Touch-down sets the value immediately; dragging
re-evaluates from absolute position. Rationale: with only ten discrete stops and a permanently
visible numeral, positional mapping makes tap-to-set and drag-to-set literally the same code
path, and it lets a user slam to 10 in one motion. Relative mapping would require an invisible
accumulator and would make tap-to-set behave differently from drag. **[J]**

```swift
DragGesture(minimumDistance: 0, coordinateSpace: .named("durometer"))
```

**Scroll-conflict guard.** Even though §4.4 places the durometer outside the scroll view, the
guard is specified so the component is safe anywhere:

- On first `onChanged`, record `startLevel` and `startTime`.
- If, within the first 150 ms, `abs(translation.height) > 22` **and**
  `abs(translation.height) > 2 * abs(translation.width)`, set `state = .abandoned`, restore
  `startLevel` (no haptic on the restore), and ignore all further `onChanged` until `onEnded`.
- `onEnded` always resets to `.idle`.

**Tap-to-set** is the degenerate case of the drag: `minimumDistance: 0` means touch-down already
committed a value, and lift-off commits nothing new. No separate `TapGesture` is needed, and
adding one would cause double haptics.

### 5.5 Keyboard and Full Keyboard Access

```swift
.focusable(isInteractive)
.onKeyPress(.leftArrow)  { level = max(1, level - 1);  return .handled }
.onKeyPress(.rightArrow) { level = min(10, level + 1); return .handled }
.onKeyPress(.downArrow)  { level = max(1, level - 1);  return .handled }
.onKeyPress(.upArrow)    { level = min(10, level + 1); return .handled }
```
**[R]** `onKeyPress(_:action:)` is iOS 17.0 —
https://developer.apple.com/documentation/swiftui/view/onkeypress(_:action:)

Also accept digits `1`–`9` for direct set and `0` for 10.

Focus ring: `RoundedRectangle(cornerRadius: 999).stroke(SquishTheme.ink, lineWidth: 2)` inset
−5 around the track.

### 5.6 VoiceOver

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel("Squish level")
.accessibilityValue("\(level) of 10. \(SquishLevel(level).term).")
.accessibilityAdjustableAction { direction in
    switch direction {
    case .increment: level = min(10, level + 1)
    case .decrement: level = max(1, level - 1)
    @unknown default: break
    }
}
```
**[R]** `accessibilityAdjustableAction(_:)` — iOS 13.0 —
https://developer.apple.com/documentation/swiftui/view/accessibilityadjustableaction(_:)
Adding it gives the element the adjustable trait, so VoiceOver announces "adjustable" and
supports swipe up / swipe down. The four-modifier pattern (`accessibilityElement` +
`accessibilityLabel` + `accessibilityValue` + `accessibilityAdjustableAction`) is the documented
requirement for custom adjustable controls **[R]** —
https://github.com/cvs-health/ios-swiftui-accessibility-techniques/blob/main/iOSswiftUIa11yTechniques/Documentation/AdjustableAction.md

**`accessibilityValue` is the short form only** — `"7 of 10. Slack."` It re-announces on every
swipe, so the full two-clause sentence would be exhausting. The full sentence stays a separate,
non-hidden `Text` element immediately after the control in reading order, so a VoiceOver user
gets it with one more swipe when they want it. **[J]**

No `.accessibilityHint`. The adjustable trait already tells VoiceOver users how to change it.

The control is **not** marked `.updatesFrequently`.

Read-only mode (`isInteractive == false`, screen 6): drop `accessibilityAdjustableAction` and
`focusable` entirely, keep label and value. An adjustable trait on a frozen control is a lie.

### 5.7 Animation

Two curves, because a drag and a discrete set want different responses:

```swift
enum DurometerMotion {
    static let live   = Animation.spring(duration: 0.16, bounce: 0.10)  // during an active drag
    static let commit = Animation.spring(duration: 0.26, bounce: 0.22)  // tap, a11y, keyboard, release
}
```
**[R]** `Animation.spring(duration:bounce:blendDuration:)` —
https://developer.apple.com/documentation/swiftui/animation/spring(duration:bounce:blendduration:)

Applied as `.animation(reduceMotion ? nil : (isDragging ? .live : .commit), value: level)`.

This is the **only** bounce anywhere in the app. `SPEC.md` §7 forbids "bouncy spring on
everything" — the durometer is the one place where a spring is not decoration, because the
control is modelling an elastic solid. Everything else in §6 has `bounce: 0`.

**Reduce Motion:** animation is `nil`. Bar geometry changes instantaneously. The value still
changes, the haptics still fire, the numeral still updates — only the interpolation is dropped.
The numeral's `.contentTransition(.numericText(value:))` swaps to `.contentTransition(.opacity)`.

### 5.8 Haptics

```swift
.sensoryFeedback(.selection, trigger: level)
.sensoryFeedback(trigger: level) { _, new in
    new == 10 ? .impact(flexibility: .soft, intensity: 0.7) : nil
}
```
**[R]** `sensoryFeedback(_:trigger:)` and `sensoryFeedback(trigger:_:)`, both iOS 17.0 —
https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:) ,
https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(trigger:_:) .
`.impact(flexibility:intensity:)` is iOS 17.0 —
https://developer.apple.com/documentation/swiftui/sensoryfeedback/impact(flexibility:intensity:)

Both fire at level 10 — the selection tick plus a soft impact, which reads as bottoming out.
That is intended and matches `SPEC.md` §2 exactly.

**Arming guard.** A `hapticsArmed` flag starts `false` and is set `true` on the first user
interaction. Programmatic sets (restoring a draft, loading an existing specimen for edit) must
not buzz. Reverting an abandoned drag (§5.4) also suppresses haptics.

### 5.9 The ten sentences

Each level is a `term` (one or two words, the material's name) plus a `description` (how it
behaves under a thumb). Screen 4 renders `"\(term). \(description)"`. `accessibilityValue` uses
`term` only.

| # | Term | Description |
|---|---|---|
| 1 | Rigid | A thumb leaves no impression. |
| 2 | Firm | Gives at the surface, returns instantly. |
| 3 | Dense | Compresses under steady pressure and springs straight back. |
| 4 | Resilient | Presses in about a third of the way and recovers at once. |
| 5 | Even | Compresses about halfway. Returns without delay. |
| 6 | Soft | Folds around a thumb and recovers in about a second. |
| 7 | Slack | Squashes nearly flat under light pressure. Comes back slowly. |
| 8 | Deep | Collapses almost completely and rises again over a few seconds. |
| 9 | Slow rise | Holds the print of a thumb for five to ten seconds. |
| 10 | Barely holds shape | Flows in the hand and re-forms on its own. |

Register notes: sentence case, no exclamation marks, no anthropomorphism, no emoji, no
adjectives of delight. Each sentence names a *yield* and a *recovery time* — the two axes a real
durometer measures. Levels 8–10 describe genuine slow-rise foam behaviour, so the scale stays
truthful rather than merely escalating adjectives. **[J]**

`SquishLevel` should be a small value type in `Design/`, not a string array in a view, because
screens 4, 6 and 8 all consume it.

---

## 6. Motion system

Five named curves. Every animation in the app uses one of them.

```swift
enum Motion {
    static let readout = Animation.smooth(duration: 0.18)   // numerals, badges, labels, hairlines
    static let select  = Animation.smooth(duration: 0.22)   // segmented pill, chip state
    static let settle  = Animation.smooth(duration: 0.32)   // cards, plates, list insertion
    static let surface = Animation.smooth(duration: 0.32)   // bracket boxes, layout shifts
    static let reveal  = Animation.smooth(duration: 0.42)   // screen entrances, mask crossfade
    static let dismiss = Animation.smooth(duration: 0.24)   // anything leaving
    // Durometer only — see §5.7. The only bounce in the app.
}
```
**[R]** `Animation.smooth(duration:extraBounce:)` is a spring with zero bounce —
https://developer.apple.com/documentation/swiftui/animation/smooth(duration:extrabounce:)

Every one of these has `extraBounce: 0`. Exits are always faster than entrances (0.24 vs 0.32)
because a lingering exit reads as lag.

### Transition table

| Transition | Mechanism | Curve | Reduce Motion fallback |
|---|---|---|---|
| Card → detail (iOS 18+) | `.matchedTransitionSource(id:in:)` → `.navigationTransition(.zoom(sourceID:in:))` | system | Guard the modifiers behind `!reduceMotion`; falls back to a plain push with a cross-dissolve |
| Card → detail (iOS 17) | Plain `NavigationStack` push, plate cross-dissolves | system | Same push, no cross-dissolve |
| Capture → name (iOS 18+) | Zoom from the frozen preview frame to screen 4's `PhotoPlate` | system | Cross-dissolve, 0.24 s |
| Capture → name (iOS 17) | Frozen frame `.transition(.opacity)` into the plate position | `reveal` | Same; already a crossfade |
| Screen 4 → measuring (M2) | Plate stays put (same size, same position); the checklist enters | `reveal` | Checklist appears with no stagger |
| Specimen sheet presentation | `.sheet` + `.presentationDetents([.medium, .large])` | system | System already reduces; do not add a custom entrance |
| Scan sweep (M2) | 2 pt `chalk` line, top → bottom, 1.1 s, `.easeInOut`, repeating | custom | **No sweep.** Static 1 pt `chalk` inset border; checklist carries progress. Required by `SPEC.md` §6 |
| Durometer step | §5.7 | `live` / `commit` | `nil` — instant geometry, haptics and numeral unchanged |
| Hero numeral change | `.contentTransition(.numericText(value:))` | `readout` | `.contentTransition(.opacity)` |
| Level sentence change | `.id(level)` + `.transition(.opacity)` | `readout` | Unchanged — a crossfade is already Reduce-Motion-safe |
| Grid card insertion | `.transition(.opacity.combined(with: .scale(scale: 0.96)))` | `settle` | `.transition(.opacity)` only |
| Grid card deletion | `.transition(.opacity)` | `dismiss` | Unchanged |
| Card scroll entrance | `.scrollTransition` (§4.1) | interactive | Omit the modifier |
| CTA collapse / expand | width + label `.transition(.blurReplace)` | `select` | No collapse at all; CTA stays expanded |
| Segmented pill move | `matchedGeometryEffect` | `select` | Pill crossfades in place |
| Chip active toggle | Border weight + badge `.transition(.blurReplace)` | `readout` | Badge `.transition(.opacity)` |
| Sticky-band hairline | Opacity 0 → 1 over 8 pt of scroll | `readout` | Hairline is always visible when `scrollOffset > 0`, no fade |
| Sort caret rotation | `.rotationEffect(.degrees(open ? 180 : 0))` | `readout` | Swap `chevron.down` / `chevron.up` glyphs, no rotation |
| Empty state → grid | `.transition(.opacity)` on the whole region | `reveal` | Unchanged |
| Viewfinder focus square | Scale 1.10 → 1.00, then fade after 1.2 s | `readout` | Appear at 1.00, fade only |
| Bracket box tracking | `.animation(_:value: subjectBox)` | `surface` | `nil` — box snaps |
| Capture-failed banner | Slide from top edge of the bottom band | `readout` | `.transition(.opacity)` |
| Checklist row completion (M2) | `.transition(.blurReplace)` on the state box | `readout` | `.transition(.opacity)` |

Read `reduceMotion` once, at the root: `@Environment(\.accessibilityReduceMotion)` **[R]**
(iOS 13.0 — https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion),
and thread it through a custom environment key so component code branches on a single flag.

**Reduce Motion principle applied here:** Apple's own guidance is that Reduce Motion prefers
cross-dissolve over movement and scale, not the removal of all feedback. So most fallbacks above
are crossfades, not no-ops. The two things that genuinely become no-ops are the scan sweep and
the durometer interpolation, both because `SPEC.md` §6 says so explicitly.

---

## 7. Accessibility

### 7.1 Dynamic Type strategy

All type is declared with `.custom(_, size:relativeTo:)` (§2.1), so everything scales. Nothing
is clamped with `.dynamicTypeSize(...)` — clamping is a downgrade for the users who need it most.
**[J]**

Three things absorb the growth instead:

1. **Reserved heights are computed, never literal.** `SpecimenCard`'s name (2 lines) and screen
   4's sentence (2 lines) reserve `n × lineHeight(currentDynamicTypeSize)`. Above
   `.accessibility2` the sentence reserves 4 lines.
2. **Mono tracking degrades.** Above `.xxLarge`, `M1` tracking drops +0.16em → +0.08em.
3. **Layout reflows** (below).

### 7.2 Grid reflow

```swift
@Environment(\.dynamicTypeSize) private var typeSize
// isAccessibilitySize is true for .accessibility1 ... .accessibility5
```
**[R]** `DynamicTypeSize.isAccessibilitySize` — iOS 15.0 —
https://developer.apple.com/documentation/swiftui/dynamictypesize/isaccessibilitysize

| Condition | Layout |
|---|---|
| `!typeSize.isAccessibilitySize` | **2-up grid** of `SpecimenCard`, 168 pt cards, 13 gutter, 22 row spacing |
| `typeSize.isAccessibilitySize` (AX1+) | **1-up list** of `SpecimenRow`, 22 pt row spacing |

`SpecimenRow` at AX sizes: `PhotoPlate` 120 × 120 radius 19 leading; 13 pt gap; a trailing
`VStack(alignment: .leading, spacing: 5)` with name `D4` (up to 3 lines, wrapping), then
`PaletteStrip`, then the mono squish value. Row height flexible.

The reflow uses an explicit `isAccessibilitySize` branch rather than `ViewThatFits`, because the
two layouts are structurally different (vertical vs horizontal composition), not the same layout
at two tightnesses — which is the documented split between the two approaches **[R]**
(https://jacobzivandesign.com/technology/responding-to-accessible-font-sizes-swiftui/).

**What does not reflow:**
- The **durometer bar geometry** does not scale with type size. It is a graphic, not text;
  scaling the 340 pt track would push it off screen. The numeral and the sentence beside it do
  scale. This is the correct split — the bars give feel, the number gives precision
  (`SPEC.md` §2), and the number is the part that must remain readable.
- The `SegmentedControl` keeps its 36 pt visual height; at AX3+ its labels wrap to 2 lines and
  the control grows to fit, but it never becomes a `Picker`.
- Chips wrap to additional rows rather than shrinking.

### 7.3 Contrast audit

Ratios below are computed from the locked hex values using the WCAG 2.x relative-luminance
formula.

| Foreground | Background | Ratio | AA normal text (4.5) | AA large text (3.0) | Non-text (3.0) |
|---|---|---|---|---|---|
| `ink` #14151A | `putty` #F1F0EC | **15.99:1** | pass | pass | pass |
| `ink` #14151A | `chalk` #FFFFFF | **18.23:1** | pass | pass | pass |
| `putty` #F1F0EC | `ink` #14151A | **15.99:1** | pass | pass | pass |
| **`soft` #74777E** | **`putty` #F1F0EC** | **3.93:1** | **FAIL** | pass | pass |
| `soft` #74777E | `chalk` #FFFFFF | **4.49:1** | **FAIL** (by 0.01) | pass | pass |
| `soft` #74777E | `line` #DDDBD4 | **3.24:1** | **FAIL** | pass | pass |
| `line` #DDDBD4 | `putty` #F1F0EC | **1.22:1** | fail | fail | **FAIL** |
| `line` #DDDBD4 | `chalk` #FFFFFF | **1.39:1** | fail | fail | **FAIL** |

**This is the single real conflict between the locked palette and `SPEC.md` §6's
"accessibility is not optional."** `SPEC.md` §2 assigns `soft` to "secondary text, labels",
and the `M1` eyebrow style is 10 pt — comfortably normal-size text, where 3.93:1 fails AA.

The palette is locked, so the recommendation does **not** change any token's default value.
Three rules, all additive: **[J]**

1. **`soft` is permitted for text only where the text is duplicative of adjacent content or is
   ≥ 24 pt.** Where a `soft` label is the sole carrier of information at a small size, use
   `ink.opacity(0.62)` instead — measured at **4.6:1** against `putty`. This is a token opacity,
   not a new colour. Applies to: `SegmentedControl` unselected labels, chip labels in the
   `rest` state, the `NameField` placeholder.
2. **Ship a high-contrast variant of `soft`.** Bind `SquishTheme.soft` to `#5F6269`
   (**5.36:1**, verified) when `@Environment(\.colorSchemeContrast) == .increased`
   **[R]** (iOS 13.0 —
   https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast).
   This is exactly what Apple's own system colours do; it is not a redesign, and it is invisible
   to users who have not asked for it.
3. **`soft` is never placed on `line`** (3.24:1) and never on the tinted-photo areas.

Additionally: **`line` is for decorative hairlines only.** Any 1 pt rule that is the sole
affordance for a control must use `soft` instead. Two places this bites — the `NameField`
placeholder (fixed in §3.13) and the `Durometer`'s unfilled bars (fixed in §5.1).

The `MethodBadge` on the camera preview cannot be audited against a fixed background. It uses
`chalk` text on `chalk.opacity(0.12)` over live video, which is contrast-indeterminate; the 1 pt
`chalk` border and the darkening scrim behind the top band are what make it legible. Under
Reduce Transparency it becomes opaque `ink`.

### 7.4 Touch target audit

HIG minimum is 44 × 44 pt **[R]**
(https://developer.apple.com/design/human-interface-guidelines/accessibility).

| Control | Visual | Hit | Fix |
|---|---|---|---|
| `FloatingCTA` expanded | 132 × 52 | 132 × 52 | — |
| `FloatingCTA` collapsed | 52 × 52 | 52 × 52 | — |
| `FloatingCTA` bar mode | 349 × 52 | 349 × 52 | — |
| `Chip` | ~110 × 30 | ~110 × **44** | `.frame(minHeight: 44).contentShape(Rectangle())` |
| `SegmentedControl` segment | ~113 × 36 | ~113 × **44** | Container padded to 44, ink pill stays 30 |
| `SpecimenCard` | 168 × 238 | 168 × 238 | — |
| `PaletteStrip` | 61 × 13 | **Non-interactive in M1** | Must remain one control forever; 13 + 3 swatches can never carry individual 44 pt regions |
| Camera close | 24 glyph | 44 × 44 | Padding |
| Library / Card buttons | 24 glyph | 44 × 44 | Padding |
| `ShutterButton` | 74 × 74 | 74 × 74 | — |
| `Durometer` | 340 × 88 | contentWidth × **112** | §5.2 |
| `NameField` | 349 × 44 text | 349 × 56 | Rule area is part of the tap target |
| `RETAKE` text button | ~54 × 14 | ~54 × **44** | Vertical padding |
| "File specimen" | 349 × 52 | 349 × 52 | — |
| Sort caret | inside chip | inherits chip's 44 | Not a separate target |

Nothing in Milestone 1 is below 44 pt after these fixes.

### 7.5 VoiceOver labels — every icon-only control

| Control | Label | Value | Traits / notes |
|---|---|---|---|
| Camera close (`xmark`) | "Close capture" | — | `.isButton` |
| Library (`photo.on.rectangle`) | "Choose from library" | — | `.isButton` |
| Reference card (`creditcard`) | "Reference card mode" | "On" / "Off" | Hidden in M1 |
| Shutter | "Capture" | — | `.isButton` |
| `FloatingCTA` (both states) | "Capture a specimen" | — | `.isButton` |
| Sort chip | "Sort" | current sort, e.g. "Recently added" | `.isButton`; hint "Opens sorting options" |
| Colour filter chip | "Colour filter" | "3 active" when badged, "Off" when not | `.isButton` |
| `SegmentedControl` | "View" | "Grid" / "Shelf" / "Stats" | Segments individually `.isButton` + `.isSelected` |
| `Durometer` | "Squish level" | "7 of 10. Slack." | Adjustable (§5.6) |
| `MethodBadge` | "Measurement method" | "No size data" | Static text, not a button |
| Lock readout | — | — | Live region: `.accessibilityAddTraits(.updatesFrequently)` here **is** appropriate |
| `SpecimenCard` | Specimen name | — | `.accessibilityElement(children: .combine)`; combined output: *"Amber blob. Squish 7 of 10, slack. Four colours."* |
| `PaletteStrip` | "Palette" | "4 colours" | One element; individual hexes are not announced (a hex string is not useful speech) |
| Empty-state field block | "Blank specimen record. Fields: name, squish, palette, width, form." | — | One element |
| Empty-state chip group | "Measured automatically: subject mask, colour palette, silhouette." | — | One element |
| Focus square (viewfinder) | — | — | `.accessibilityHidden(true)` |
| Corner brackets | — | — | `.accessibilityHidden(true)` |
| Scan sweep (M2) | — | — | `.accessibilityHidden(true)` |
| `HairlineRule` | — | — | `.accessibilityHidden(true)` |

**Reading order on screen 4:** plate → RETAKE → name field → "Squish level" (adjustable) →
level sentence → File specimen. Enforce with `.accessibilitySortPriority` if SwiftUI's default
order diverges.

### 7.6 Other accessibility

- **Reduce Transparency:** the only translucent surfaces are `MethodBadge` and the viewfinder's
  top/bottom scrims. Both become opaque `ink`.
- **Increase Contrast:** `soft` → `#5F6269`; `line` → `soft` for all hairlines; the
  `SegmentedControl` and chip borders go to 1.5 pt.
- **Bold Text:** all display weights step up one (600 → 700, 800 → 900 if the Bricolage cut
  exists; otherwise 800 stays). Mono goes 400 → 500.
- **VoiceOver rotor:** no custom rotors in M1.
- **Haptics:** all haptics go through `.sensoryFeedback`, which the system already gates on the
  user's system haptics setting. No manual `UIFeedbackGenerator`.

---

## 8. Notes for the developer

**Liquid Glass.** Building against the iOS 26 SDK makes standard SwiftUI bars, toolbars, tab
bars and sheets adopt the Liquid Glass material automatically, which will fight the locked flat
direction. `UIDesignRequiresCompatibility = YES` in `Info.plist` opts the whole app out and
"displays the app as it looks when built against previous versions of the SDKs" — but **"the
system ignores this key when you build for iOS 27 or later."** **[R]** —
https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility

This is why §4.1 puts the segmented control and chip row in a `.safeAreaInset` rather than a
`.toolbar`, and why screen 4's primary action is a custom pill rather than a nav-bar button: the
fewer system chrome surfaces the app relies on, the less the iOS 27 migration costs. See §9 Q7.

**No third-party dependencies** are implied by anything in this document. Swift Charts (allowed
by `SPEC.md` §6) is only needed for screen 8, and even there the histogram is specified as
reusing `DurometerBar`, so Charts may not be needed at all.

---

## 9. Open questions

Ranked by how early they block work.

**Q1 — `soft` on `putty` is 3.93:1 and fails WCAG AA for normal-size text.**
`SPEC.md` §2 locks `#74777E` and §2 assigns it to "labels", which at `M1`'s 10 pt is normal-size
text. `SPEC.md` §6 says accessibility is not optional. These conflict. §7.3 proposes a
palette-preserving resolution (restrict `soft`, use `ink.opacity(0.62)` for small sole-carrier
text, add a `#5F6269` Increase Contrast variant). **Needs an owner's ruling before any component
is styled.**

**Q2 — Dark Mode is not mentioned anywhere in `SPEC.md`.** The palette has no dark variant, and
inverting `putty`/`ink` is a redesign, which §2 forbids. Recommendation: ship v1 light-only via
`.preferredColorScheme(.light)` at the root, and say so. Alternative is a full second palette,
which is out of scope. **This is the largest genuine gap in the spec.**

**Q3 — Milestone 1's method badge.** `SPEC.md` §3 screen 3 requires "an explicit badge naming
the measurement method", but §5 Milestone 1 has no depth path. In M1 the badge can only read
`NO SIZE DATA`. Confirm that is acceptable, or confirm the badge should be hidden until
Milestone 2.

**Q4 — "Average squish": mean or median?** And at what precision? This document assumes the
arithmetic mean, one decimal place, omitted entirely at n = 0.

**Q5 — Sort options are unspecified.** `SPEC.md` §3 says "sorting lives behind a chip with a
trailing caret" but never lists the options. Proposed: *Recently added* (default) · *Name A–Z* ·
*Squish, high to low* · *Size, largest first* (disabled until Milestone 2). Confirm the set and
the default.

**Q6 — Tinted durometer on pale specimens.** A near-white or near-`putty` dominant colour makes
the frozen durometer on screen 6 invisible. §4.5 proposes darkening the tint in OKLCH until it
reaches 3:1 against `chalk`. Confirm the rule, and confirm that the palette strip keeps the true
unmodified colour.

**Q7 — Deployment target and Liquid Glass.** `SPEC.md` §4 says iOS 17+, which rules out the
iOS 18 zoom navigation transition (§6) as anything but a progressive enhancement. Separately,
the app must decide whether to set `UIDesignRequiresCompatibility` for iOS 26. Two related
questions: (a) can the floor move to iOS 18? (b) opt out of Liquid Glass, or restyle for it?

**Q8 — Card borders.** `SPEC.md` §2 says "hairlines are 1 pt `line`" but never says whether the
grid card gets a border in addition to its photo plate. This document assumes the plate's border
is the card's only boundary.

**Q9 — Empty name on save.** This document assumes the specimen files as `Unnamed specimen`
rather than blocking the save. Confirm the string, and confirm whether duplicate names should be
disambiguated (`Amber blob 2`) or allowed to collide.

**Q10 — Where does the specimen sheet's photo come from at `.large`?** `SPEC.md` §3 screen 6
says "photo fills the top" and the sheet goes to `.large`, at which point the photo is fully
covered. Does the sheet stop short of the top edge at `.large`, or does the photo scroll into
the sheet's own header? This document assumes the former (a `.fraction(0.92)` cap instead of
`.large`) but `SPEC.md` explicitly names `.large`, so this needs a ruling.

**Q11 — Palette strips with fewer than four colours.** `SPEC.md` §3 says "four-swatch palette
strip" but `SquishyVision` may extract fewer for a monochrome toy. This document renders only
what was extracted and never pads with grey. Confirm.

**Q12 — Does the header count reflect filters?** This document keeps the header reporting the
total library and adds a second `SHOWING n OF m` line when filters are active.

**Q13 — `M2` tracking.** `SPEC.md` §2 says mono is "uppercase, 0.16em tracking, 10pt" for
"every label, measurement, unit, and eyebrow". §2.1 here splits out a 12 pt / +0.04em variant for
bare numerals, because +0.16em on digits reads as spaced-out, not measured. Confirm the split is
acceptable, or collapse `M2` back into `M1`.
