# Squeeshy

An iOS app for cataloguing a squishy collection. Photograph a squeeshy, the app reads
its colour, type, shape and size, you name it and rate its squeeshiness on a liquid
glass scale, and it files itself onto every shelf it belongs on.

**Xcode 26.2 · iOS 26 · SwiftUI · SwiftData**

## Signing

The team lives in `project.yml`, not in Xcode's Signing & Capabilities editor.
`xcodegen generate` rewrites the whole project, so anything set through the UI is
discarded on the next regeneration — which looks exactly like Xcode forgetting the
team, and produces an unsigned archive and *"Use the Signing & Capabilities editor to
assign a team to the targets and build a new archive"* in Organizer.

Signing is disabled **only** for the simulator SDK, where it is pointless and where
the embedded GLTFKit2 framework would otherwise fail to sign:

```yaml
DEVELOPMENT_TEAM: H483GY2MQ4
"CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]": NO
```

To change team, edit `project.yml` and re-run `xcodegen generate`.

## Interactive glass keeps the old scheme's material

After a light/dark switch, exactly *one* row in the shelf list kept the previous scheme's
glass &mdash; a dark card with white text in an otherwise light list. Which row it picked
was arbitrary, and it reproduces reliably by changing the scheme under a live view
(`xcrun simctl ui <device> appearance light` with the app's theme set to auto).
`glassEffect(.regular.interactive())` is UIKit-backed and does not always pick the change
up. `.rebuildsOnSchemeChange()` re-identifies the view and forces fresh glass; apply it to
any *repeated* interactive-glass row.

Note that `-appTheme` cannot be used to reproduce this: launch arguments land in
UserDefaults' argument domain, which outranks the user domain, so the app's own write is
silently ignored and the theme appears stuck.

## Writing an unchanged value still invalidates the view

`FanSimulation` used to integrate and write `offset` every frame even when settled, and
`SquishSpring` did the same with `amount`. Writing an *unchanged* value to an
`@Observable` property still notifies, so the detail screen re-rendered sixty times a
second with nothing moving &mdash; a stray simulator process sat at 38% CPU for six
minutes with no input. Both now return early once at rest, and the display link is
stopped when everything has settled and woken on the next interaction.

## UI tests must reset the store

Two tests rename a squeeshy and pin a shelf, both of which persist. Launched without
`-uiTestReset` they poisoned every test that ran after them &mdash; eight of nine failed
while each passed in isolation. `setUp` passes `-uiTestReset -uiTestSeed`.

## SquishSpring does not drive a view on its own

`SquishSpring` is `@Observable`, but a view that reads only `spring.amount` renders once
and never again. The hero on the detail screen *appears* to animate because the fan strip
re-reads its own simulation sixty times a second and drags the spring along with it. Any
screen without something else changing per frame &mdash; play mode, for instance &mdash;
must read `driver.frame` to stay in step. That is what `DisplayLinkDriver.frame` is for.

A related trap when verifying this: a bounding box barely changes when a near-square
shape is squashed along a diagonal, so measuring a bbox will tell you nothing is
happening when it is. Deform along a single axis when checking.

## Gestures on the hero squeeshy

The hero on the detail screen is a `Button`, not an image with `.onTapGesture`. A raw
tap gesture there never received a touch at all &mdash; not from a tap, a press, or a
synthesised tap on its exact centre &mdash; while every `Button` on the same screen was
tappable. The squeeze rides along as a `.simultaneousGesture`. If a tap ever stops
opening play mode, check that this is still a Button before suspecting anything else.

## iPad

The app ships for both families. On regular width it is a `NavigationSplitView` &mdash;
shelves in a sidebar, the field filling the detail column &mdash; and on the phone it
stays a single `NavigationStack`. `CollectionsView.isWide` is the switch, and it keys
off the horizontal size class rather than the idiom, so a narrow Stage Manager column
correctly gets the phone layout.

Two things that only show up on a big screen:

- Field bubble sizes are derived from the field's short side, not fixed points, or six
  squeeshies sit marooned in the middle of a 13-inch display. They are clamped at both
  ends so a Split View column stays legible and a full screen does not produce beach
  balls.
- Anything that is the *root* of the detail column must be passed `showsBack: false`.
  There is nothing behind it, so its back chevron would do nothing.

## A coordinate convention worth remembering

`CGContext` bitmap data and `CGImage.cropping(to:)` both measure y **downwards from
the top**. They do not disagree, and no flip belongs between them. `SubjectLift`
had one, which cropped every subject the same distance below itself as it sat below
the top edge — invisible on a vertically centred squeeshy, and a straight slice
through anything else. `swift Tools/cropcheck.swift` demonstrates it from scratch if
the question ever comes up again.

## App icon

`Squeeshy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is generated,
not hand-drawn — `python3 Tools/makeicon.py` redraws it from the app's own palette
(AdaptiveBackground's ground, Tint.fallback's pink and cyan). Edit the script, not
the PNG. It writes RGB with no alpha, because the App Store rejects an icon that
carries an alpha channel.

Two build settings make it count, and both have to be there:
`ASSETCATALOG_COMPILER_APPICON_NAME` so actool emits the sizes, and a real
`Squeeshy/Info.plist` (generated by xcodegen's `info:` block) carrying a top-level
`CFBundleIconName`. actool only ever writes that key nested inside `CFBundleIcons`,
and `INFOPLIST_KEY_CFBundleIconName` resolves as a build setting but is dropped by
the plist generator — the file is the only place validation reliably finds it.

## Running it

```bash
xcodegen generate          # regenerate the project after adding files
open Squeeshy.xcodeproj
```

`Squeeshy.xcodeproj` is generated from `project.yml` and is not in git. Run
`xcodegen generate` after every pull: a project generated before a pull doesn't list
files the pull added, and the build fails with "Cannot find … in scope". Open only
`Squeeshy.xcodeproj`; an old copy such as `Squeeshy 2.xcodeproj` is out of date.

Or from the command line:

```bash
xcodebuild -project Squeeshy.xcodeproj -scheme Squeeshy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Debug builds accept launch arguments that open a deep screen directly, which saves
tapping through while iterating:

```bash
xcrun simctl launch <device> com.squeeshy.app -openShelf cool -openItem 3 -openRating
```

`-openShelf` takes any `SmartShelf` raw value: `everything`, `squeeshiest`, `warm`,
`cool`, `extraLarge`, `pocket`, `recent`. Also available: `-openStats`, `-openCapture`,
`-captureSample` (runs a synthesised photo through the real lift pipeline) and
`-reviewSample` (jumps to the capture review screen with a stand-in cut-out).

## The three screens

**Collections** — smart shelves generated from traits, then shelves made by hand.
Search sits in the header rather than the tab bar.

**Field** — what a shelf opens into. A force simulation, not a layout: every squeeshy
is pulled toward the centre in proportion to how well it matches the slider, pushed to
the rim when it doesn't, and they collide off each other on the way. Dragging the
slider stirs the field.

**Detail** — a hero you can grab and squash, and a fan of the rest of the shelf you
can throw. Whatever lands at centre becomes the hero, live, even mid-throw.

## The slider is scoped to its shelf

The trait control is bounded by what the shelf actually holds, not by a global scale.
A pinks shelf gets a band covering only its own arc — including when that arc wraps
through red, which `TraitDomain.smallestArc` resolves by cutting at the widest gap
between adjacent hues rather than taking the long way round. A Small-to-Medium shelf
gets a two-step size ruler. Legends come from the real minimum and maximum, so no part
of the travel is dead.

When a shelf has only one value on an axis — every squeeshy on the Large shelf is
large — the domain reports `isSingleValued`, the slider dims and stops responding, and
the caption says so rather than inviting you to stir something that cannot move. Those
shelves also open on a different axis for the same reason.

## Capture, and why photos don't look like photos

A rectangular snapshot with a carpet behind it would wreck every card in the app, so
nothing is ever stored as a rectangle. Capture runs:

1. **Subject lift** — `VNGenerateForegroundInstanceMaskRequest`, the model behind
   press-and-hold-to-lift in Photos. It returns per-object masks, not a crop.
2. **Remove the hand** — almost every squeeshy photo is taken holding the thing up, so
   the hand is in frame, central, and usually *bigger than the squeeshy*. Left alone
   the lift saves a picture of a hand. `VNGeneratePersonSegmentationRequest` runs
   alongside, and its mask is grown slightly (segmentation stops short of the real
   edge of a finger) then inverted and multiplied out of the foreground.
3. **Pick one object** — instances are scored on *what survives the hand being
   removed*, combined with how central they are. Area alone picks the sofa; area
   after subtraction picks the squeeshy, because a hand scores near zero once it has
   been cut out of itself.
3. **Clean the edge** — the raw mask carries a pixel or two of background all the way
   round, which reads as a dirty halo on dark glass. The mask is eroded by ~0.25% of
   the short side and then feathered, so the edge is neither fringed nor die-cut.
5. **Composite to transparency** — `CIBlendWithMask` over an empty background, stored
   as PNG so the alpha survives.
6. **Crop to the subject** — trimmed to the alpha bounding box plus a 4% margin, so
   every cut-out fills its card the same amount however close the photo was taken.
   Without this a shelf looks randomly zoomed.
7. **Refuse bad lifts** — coverage under 2% (found a speck) or over 98.5% (mask
   swallowed the frame) is treated as a failure, and the user gets a retake rather
   than a saved rectangle of carpet.

Traits come off the cut-out, not the photo: hue is averaged on the unit circle
weighted by saturation and skipping transparent pixels, so a cream plush with pink
ears reads pink instead of washing out to grey. Body plan comes from the silhouette's
aspect and how much of its box it fills.

**Size is asked for, not guessed.** A photo carries no scale without a reference
object in frame, so an inch figure derived from how much of the frame the squeeshy
filled was precision the app hadn't earned — and wrong often enough that it would be
corrected every time. It is now three buckets (`SizeClass`), picked on the review
screen with no default selected, and saving is blocked until it is answered. Small /
Medium / Large carry hints — palm sized, two hands, a hug — so the words mean the same
thing to everyone without becoming a measurement.

## What is actually simulated

SwiftUI animations interpolate between two values; they cannot report how fast
something is travelling right now. Three things need that, so they run their own
integrator on a `CADisplayLink` (`Spring1D` in `Design/Motion.swift`):

| | |
|---|---|
| **Glass scale** | The bead chases your finger on a spring rather than sticking to it, so it lags, overshoots and stretches along its direction of travel. A droplet trails behind and merges back through an alpha-threshold metaball filter. |
| **Bubble field** | Radial attraction weighted by match, pairwise collision resolution, velocity damping. Diameter is itself a spring, so growth overshoots. |
| **Fan** | Momentum, then a spring into the nearest detent, with the hero tracking whatever is nearest centre throughout. |

Everything else uses the springs in `Motion` — nothing in the app eases.

## Colour

The app has no palette of its own. `Tint.sampled(from:)` buckets a shelf's hues into
twelve bins, takes the most populated as the primary and the runner-up as the
secondary, falling back to a near neighbour when the two are far enough apart to go
muddy. A pink shelf makes a pink app.

## Built

- Collections, field and detail screens, all three wired together
- Capture: viewfinder, subject lift, trait extraction, live rating, naming, save
- Duplicate detection with the "I own two" merge into `quantity`
- Stats: squeeshiness histogram, colour ring, growth timeline, trait rarity
- The glass scale, used both for squeeshiness and as the shelf trait control
- Shelf-scoped trait domains for colour, size and squeeshiness
- SwiftData model, smart shelves, hand-made shelves, an 18-item demo collection
- Cut-outs stored on disk with an in-memory cache, falling back to drawn art
- Hand-made shelves: named on creation, grid picker for contents, rename, delete
- Share cards at three scopes, rendered to PNG through the system share sheet
- Inline trait chips with editors
- Liquid Glass throughout, adaptive tint, staggered entrances

## Share cards

`ShareCard` renders off-screen at 900x1200 via `ImageRenderer`, so it has to hold up
with no scroll view, no safe area and no interaction — everything in it is fixed size.
Three scopes share one renderer: a single squeeshy gets a portrait with its score, a
shelf or the whole collection gets a grid whose column count follows the item count,
so six squeeshies fill the card as convincingly as sixty. Four columns is the widest
layout that still fits a name under each one, so it is held onto as long as the tiles
stay a reasonable size. Every card is tinted from what it contains.

Render them without going through the share sheet:

```bash
xcrun simctl launch <device> com.squeeshy.app -renderShareCards
# then read them out of the app container's Documents/
```

## 3D models

Squeeshies can become real rotatable meshes, generated from the same cut-out the app
already makes. Nothing runs on the phone &mdash; these models want a GPU &mdash; but
generation is asynchronous, so capture stays one photo and six seconds and the mesh
swaps in when it arrives.

```bash
pip3 install gradio_client
python3 Tools/make3d.py Pictures/IMG_1617.heic.png     # writes .glb + turntable .mp4
```

That calls the public TRELLIS Space on Hugging Face, which is **free**: about 35
seconds per squeeshy, returning a ~1MB GLB. Anonymous callers get only a couple of
minutes of GPU per day; a free token raises it a lot:

```bash
export HF_TOKEN=hf_xxxx      # https://huggingface.co/settings/tokens
```

This is a prototyping path, not production. The Space is a shared community demo, and
TRELLIS itself is licensed for research. Shipping means self-hosting
[Hunyuan3D 2.0](https://github.com/Tencent-Hunyuan/Hunyuan3D-2) (Apache 2.0) or paying
an API such as Meshy, which also exports USDZ.

`ModelViewer` renders the result: GLTFKit2 imports the GLB, SceneKit draws it on a
transparent background with three lights and a slow idle turn, and drag orbits it.
`-openModel` shows it against a bundled stand-in mesh so the viewer can be worked on
without spending quota.

## Friends and trading

Design and mockups: `Design/FRIENDS-AND-TRADING.md` and `Design/friends-trading.html`.
Code: `Squeeshy/Features/Friends/`.

- **Friends** — invite through iCloud (usually by Messages). Each person's squeeshies
  are a CloudKit zone in *their own* iCloud, shared read-only with the friends they
  invite. Friends see a small cut-out and the traits, never the full photo. Invite-only,
  mutual, removable; no search, usernames or chat. Entry points: the people button in
  the Collections header (phone) and the Friends section under the shelves (both).
- **Trade requests** — open a friend's squeeshy, offer one or more of yours, add an
  optional preset line. They accept or decline; each of you ticks *handed over* once the
  real toys have swapped (in person or by post); then each device files the swap.
- **Trade table** — two phones side by side, MultipeerConnectivity, no internet. Each
  puts squeeshies in and votes ✓ / ✗. Both ✓ on the same table trades instantly.
  Changing the table clears both votes, so a yes never carries over to a different
  squeeshy, and the swap is only filed once both phones hold each other's squeeshies.
  Two yeses play the portal swap: glowing portals open under both seats, the
  squeeshies sink in, arcs of light cross the table, and they rise out of the other
  portal. The celebration (confetti in the traded squeeshies' colours) waits for it
  to land, however fast the phones finished. After a no the portals start to pull,
  glitch grey and throw the squeeshies back up, where they dissolve; each phone then
  empties its own side (unless its owner already put something new in), and the
  cleared board says who said no until something new goes on. The table is locked
  from two yeses until the swap is filed, and during a no.
  A seat with several squeeshies shows them as a cluster with a count; tap it to see
  them all, and take your own off from there.

A squeeshy you trade away leaves the collection the same way Delete removes it
(shelves, cut-out, row), or loses one from `quantity` if you own more than one. The
record of it moves to **Trades → Traded away**. One that arrives keeps its traits and
cut-out and says where it came from under the hero ("from Mia · Oct 2026"). *Keep —
not for trading* in the detail menu lets friends see it but not ask for it.

### The collection stays local

The CloudKit entitlement would, on its own, make SwiftData start mirroring every row
into iCloud — rows without their cut-outs, which are files. `SqueeshyApp` opens the
container with `ModelConfiguration(cloudKitDatabase: .none)` for that reason. Only the
shelf zone `FriendsStore` manages goes to iCloud.

### Finished trades are filed only on a friends screen

Filing a trade deletes what was given away, and the field and detail screens hold
snapshots of their squeeshies; reading a deleted model from one of those crashes. So
`FriendsStore` files finished trades only while a friends screen is showing
(`.filesReadyTrades()`), and until then counts them in the badge on the people button.

### Setup

The capabilities live in `project.yml` (entitlements block and `info.properties`), so
`xcodegen generate` keeps them. Once, in the developer portal / Xcode:

1. Create the iCloud container `iCloud.com.squeeshy.app` (Signing & Capabilities →
   iCloud → +) if it doesn't exist. Then `xcodegen generate` again — the capability
   comes from `project.yml`, not from the editor.
2. Test friends on **two devices with two different iCloud accounts**; a share can't be
   accepted by the account that owns it. The trade table needs two real devices too.
3. Before App Store: run one invite and one trade on a development build so every
   record type exists (`Profile`, `Specimen`, `TradeRequest`, `TradeReply`), then in the
   CloudKit Console deploy the schema to Production. No indexes are needed — the app
   never queries, it reads zones whole.

### Testing without a second phone (Debug builds)

Real iCloud friends never start in the Simulator: signing is off for the simulator
SDK, so the build has no iCloud entitlement, and touching CloudKit without one raises
an exception. `FriendsStore` checks `targetEnvironment(simulator)` and says so instead.
The trade table's discovery works in the Simulator, but a table needs a second device.


The Friends screen has a yellow debug panel. *Simulate iCloud friends* swaps iCloud for
a pretend friend, Mia, who shares a collection, answers requests (accept / decline /
ignore), hands over, and can sit at a trade table as the other phone. Launch with
`-SimulateFriends YES` to start with it on, or `-FriendsSelfTest YES` to run every
friends flow — requests, declines, cancels, the open-request limit, double-promising,
and the trade-table protocol — and print `[SelfTest] PASS/FAIL` lines to the console.

## Not built yet

- **Item management** — no way to delete a squeeshy, adjust a merged duplicate's
  count, or set the type locally now that cloud naming is deferred.
- **First-run intro** — the three-card intro and a visible "clear the samples"
  affordance.
- **Cloud naming** — `SpeciesNaming` is a protocol with an offline stub. Wiring a
  vision model to it fills in "Axolotl" without changing the capture flow.
- **Sign in with Apple** and the three-card intro before the demo shelf.
- **Cloudflare** — Workers API, D1 for the collection, R2 for photos. The model layer
  is local-only today; cut-outs are already files, which is what R2 wants.
- **Share cards** at all three scopes.

## Known gaps

- **Fingers gripping the front are kept, not removed.** Vision's foreground pass
  returns hand and squeeshy as a single instance in real photos, so there is nothing
  to discard, and subtracting the person mask does more harm than good (see below).
  Putting the squeeshy down beats every algorithmic fix, which is why the capture
  screen asks for that first.

## Vision does not run in the simulator

`VNGenerateForegroundInstanceMaskRequest` and `VNGeneratePersonSegmentationRequest`
both fail in the iOS Simulator with:

```
Error Domain=com.apple.Vision Code=9 "Could not create inference context"
```

The identical pipeline succeeds on macOS and will succeed on a device. **Capture
cannot be tested in the simulator at all** — every photo comes back rejected, and it
looks exactly like a bad lift.

The way round it, and how the app gets real squeeshies in it today:

```bash
swift Tools/liftcheck.swift Pictures          # cut them out natively, to /tmp/lift_*.png
# copy the PNGs into the app container's Documents/Import/, naming each file
# whatever the squeeshy should be called, then:
xcrun simctl launch <device> com.squeeshy.app -importPhotos
```

`PhotoImport` notices an image that already carries transparency and takes it as-is
rather than trying to lift it again. Traits are still read from the pixels, because
colour and geometry need no ML. A bulk import also skips the demo shelf, so six real
squeeshies do not end up buried in eighteen drawn ones.

## What the real photos taught us

Six real photographs in `Pictures/`, run through `swift Tools/liftcheck.swift Pictures`:

| Photo | Subject | Result |
|---|---|---|
| IMG_1617, IMG_1623 | tomato, on a surface | perfect |
| IMG_1622 | glitter cube, on a surface | perfect |
| IMG_1605 | butter block, held | clean, hand excluded |
| IMG_1606 | bread loaf, held | clean after the fix below |
| IMG_1607 | green pig, gripped | isolated, but gripping fingers kept |

Two things only real photos could have shown:

**Vision returns one instance, not several.** The plan to discard a separate "hand"
instance never fires, because hand and object come back fused or the hand is simply
absent from the foreground.

**Person segmentation destroys pale objects.** A golden bread loaf in a palm reads as
100% skin, so subtracting the person deleted the whole subject and the capture failed
outright. The rule now is: if the person mask claims more than 92% of an instance it
is wrong rather than right, and gets ignored. That took the failure rate from 2 of 6
to 0 of 6.

**Shape thresholds were calibrated on ideal shapes, not photographs.** A perfect
ellipse fills 79% of its bounding box; a real cut-out measures 45–55%, because the
crop adds a margin and the feathered edge falls below the alpha cut-off. The old
thresholds called five of six real squeeshies a star. They are now set from measured
values and bias toward round, which is what most squeeshies are.
- Changing `sizeInches` to `SizeClass` is a breaking model change. Existing installs
  need a delete-and-reinstall; there are no real users yet, so no migration was
  written.
