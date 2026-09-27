# Squish Index — Friends & Trading (proposal)

> Status: **proposal, needs owner sign-off.** `SPEC.md` §6 says "no accounts, no network calls
> except the one identification request" and §7 says "do not add social … in v1." This document
> is written to keep both of those true. It is proposed as **Milestone 6**, after M5, and does
> not change M1–M5.

## 1. The request

User feedback (from the target audience: a kid collector) asked for two things:

- **Friends** — see what my friends have.
- **Trading** — swap squishies with them.

## 2. The key observation

Squishies are physical. A trade already happens in person: two kids, two toys, a hand-off. The
app does not need to *run* the trade. It needs to **record** it, and move the catalogue record
along with the toy so the new owner doesn't have to re-photograph and re-measure it.

That reframes both features as one small capability — **passing a file between two phones** —
and fits the museum premise exactly: a specimen changing hands is a *transfer*, and its history
is *provenance*.

## 3. Recommendation: no server, no accounts — AirDrop a file

| | Lightest (recommended) | Heavier (not recommended) |
|---|---|---|
| Transport | Share sheet → AirDrop / Messages | CloudKit sharing, or a backend |
| Identity | A display name the kid types once ("Maya") | Apple ID / accounts |
| Friends list | Derived from who you've traded with / received shelves from | Friend requests, social graph |
| Who can reach a kid | Only someone physically nearby (AirDrop) or already in Messages | Anyone with their handle |
| Moderation, chat, COPPA surface | None — the app collects nothing | All of it |
| Rough size | ~1–2 days on top of M5 | Weeks, plus ongoing ops |

Parents keep control with settings they already use: AirDrop can be set to *Contacts Only*
or turned off in Screen Time.

## 4. What gets built

### 4.1 One file type: `.squishy`

A custom `UTType` (`com.squishindex.specimen`, exported, conforms to `public.data`) containing
JSON with the record's fields and a downscaled JPEG (long edge 1600 px, ~300 KB). Implemented
with `Transferable` + `FileRepresentation`, received with `.onOpenURL`. No dependencies.

```jsonc
{
  "format": 1,
  "kind": "specimen",            // or "shelf" (§4.3)
  "from": "Maya",                 // sender's display name
  "sentAt": "2026-09-27T15:04:00Z",
  "specimen": {
    "originID": "…",              // stable across every owner
    "name": "Amber blob", "squishLevel": 7,
    "widthMM": 62.0, "heightMM": 48.5, "measurementMethod": "lidar",
    "paletteHex": ["#E8A33D", …], "form": "…", "tags": [ … ],
    "provenance": [ { "owner": "Maya", "from": "2026-03-02", "to": "2026-09-27" } ],
    "photoJPEG": "<base64>"
  }
}
```

`featurePrint` is **not** sent; the receiver regenerates it from the photo on import so duplicate
detection works without trusting another device's archived Vision object.

### 4.2 Trading — "Transfer"

**Sender** (specimen sheet, screen 6 → action sheet → *Transfer to a friend…*):

1. Share sheet opens with the `.squishy` file.
2. On a completed share, the record is **not deleted**. It moves to a *Transferred* state:
   greyed out of Grid/Shelf/Stats counts, kept in an archive with a line
   `TRANSFERRED TO MAYA · 27 SEP 2026`. (Kids regret trades. The record of having owned it is
   part of the collection.)
3. On a cancelled share, nothing changes.

**Receiver** (file opens in the app):

1. An *Incoming specimen* card: photo plate, name, squish, `FROM MAYA`, with **Accession** and
   **Decline**.
2. Accession files it with the sender's measurements intact and the method badge preserved —
   measured on Maya's phone is still measured. Provenance gains a row.
3. If `originID` matches a record already in *Transferred*, it's a trade-back: restore that
   record instead of creating a new one.

A two-for-one swap is just each kid sending once. No handshake, no "pending trade" state, no
way for a trade to get stuck half-done.

### 4.3 Friends — "Shelf cards"

*Share my shelf* (from the Grid header) sends a `kind: "shelf"` file: every held specimen's
thumbnail (long edge 400 px), name, squish, size, palette. No full photos.

The receiver gets a **Friends** list: one row per sender name, each opening a read-only copy of
that friend's Grid and true-scale Shelf. Receiving a newer shelf from the same name replaces the
old one; the list shows `UPDATED 3 DAYS AGO`. Long-press → *Remove*.

This is the "window shopping" half of trading — kids browse each other's shelves, pick what they
want, then meet up and swap physical toys.

The friends list is **stored separately** from the catalogue (its own SwiftData model) so it can
never leak into the user's own counts, stats, or duplicate detection.

### 4.4 Model additions

```swift
// On Squishy
var originID: UUID                  // = id for things you photographed yourself
var status: String                  // "held" | "transferred"
var provenance: [ProvenanceEntry]   // Codable struct: owner, from, to
var acquiredFrom: String?           // nil = photographed yourself

@Model final class FriendShelf {
    @Attribute(.unique) var name: String
    var receivedAt: Date
    var entries: [ShelfEntry]       // Codable: name, squish, sizes, palette, thumbnail Data
}
```

Plus one `UserDefaults` string: the kid's display name, asked for the first time they transfer
or share.

## 5. What we deliberately don't build

- No accounts, sign-in, or friend requests.
- No chat, comments, likes, or feeds.
- No online "trade offers" to people you haven't met. Trades finish in person.
- No trade values, rarity scores, or "fair trade" meters — that turns friends into a market.
- No server. The app still makes exactly one kind of network request (identification).

## 6. Spec changes this would need

- `SPEC.md` §6: add "…and files the user explicitly sends through the system share sheet."
- `SPEC.md` §7: narrow "no social" to "no social feeds, accounts, or online contact."
- `SPEC.md` §5: add Milestone 6 — Transfer & Shelf cards.
- Design: two new surfaces (*Incoming specimen* card, *Friends* list). Both reuse existing
  components (`PhotoPlate`, `SpecimenCard`, `MonoLabel`, the Grid) — no new visual language.

## 7. Open questions

1. **Transferred records** — keep in an archive (proposed) or delete outright?
2. **Display name** — free text, or first name only with a character cap?
3. **Where do Friends live?** Proposed: a fourth segment is too much; put *Friends* behind a
   header button on the Grid. Needs a mockup.
4. **Messages as a route** — allow (it's in the share sheet by default) or exclude it and make
   this AirDrop-only for tighter "in person" guarantees?
