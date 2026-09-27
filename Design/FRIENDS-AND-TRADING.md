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

Squishies are physical. A trade already happens outside the app: a hand-off at school, or a
toy dropped in the post to a cousin. The app does not need to *run* the trade. It needs to **record** it, and move the catalogue record
along with the toy so the new owner doesn't have to re-photograph and re-measure it.

That reframes both features as one small capability — **passing a file between two devices** —
and fits the museum premise exactly: a specimen changing hands is a *transfer*, and its history
is *provenance*.

## 3. Recommendation: no server, no accounts — send a file through Messages or AirDrop

Friends must be able to share **when they are not together**. The system share sheet already
does this: a `.squishy` file sent in iMessage arrives on the friend's iPhone or iPad wherever
they are, and tapping it opens Squish Index. AirDrop is the same button for when they *are*
together. The app ships one feature and gets both for free.

| | Lightest (recommended) | Heavier (not recommended) |
|---|---|---|
| Transport | Share sheet → Messages (remote) / AirDrop (nearby) | CloudKit sharing, or a backend |
| Identity | A display name the kid types once ("Maya") | Apple ID / accounts |
| Friends list | Derived from who you've traded with / received shelves from | Friend requests, social graph |
| Who can reach a kid | Only people she already messages, or someone nearby on AirDrop | Anyone with their handle |
| Moderation, chat, COPPA surface | None — the app collects nothing | All of it |
| Rough size | ~1–2 days on top of M5 | Weeks, plus ongoing ops |

Parents keep control with settings they already use: Screen Time *Communication Limits*
decide who a kid can message, and AirDrop can be set to *Contacts Only* or turned off. The app
adds no new way to contact a child.

Messages, Mail and Files also appear in the share sheet, so a friend without iMessage can still
receive the file by email. (Only Squish Index on iPhone/iPad can open it; there is no Android
or web viewer in this proposal.)

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

**Trading at a distance.** Nothing above assumes the two kids are together. The sender sends the
transfer when the toy actually leaves their hands (posted, or handed to a parent to pass on), and
the receiver can open the file and tap Accession whenever it arrives, days later if need be. The
message thread in Messages is where they agree the swap; the app doesn't need its own.

A two-for-one swap is just each kid sending once. No handshake, no "pending trade" state, no
way for a trade to get stuck half-done.

### 4.3 Friends — "Shelf cards"

*Share my shelf* (from the Grid header) sends a `kind: "shelf"` file: every held specimen's
thumbnail (long edge 400 px), name, squish, size, palette. No full photos.

The receiver gets a **Friends** list: one row per sender name, each opening a read-only copy of
that friend's Grid and true-scale Shelf. Receiving a newer shelf from the same name replaces the
old one; the list shows `UPDATED 3 DAYS AGO`. Long-press → *Remove*.

This is the "window shopping" half of trading — kids browse each other's shelves, pick what they
want, then swap the physical toys in person or by post. Shelf cards are sent the same way as
transfers, so a friend in another city can keep their shelf current with one tap.

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
- No in-app "trade offers" or inbox. Kids agree trades in Messages, with people they already
  know; the app only carries the record once the toy moves.
- No trade values, rarity scores, or "fair trade" meters — that turns friends into a market.
- No server. The app still makes exactly one kind of network request (identification).

## 6. Spec changes this would need

- `SPEC.md` §6: add "…and files the user explicitly sends through the system share sheet."
- `SPEC.md` §7: narrow "no social" to "no social feeds, accounts, or in-app messaging."
- `SPEC.md` §5: add Milestone 6 — Transfer & Shelf cards.
- Design: two new surfaces (*Incoming specimen* card, *Friends* list). Both reuse existing
  components (`PhotoPlate`, `SpecimenCard`, `MonoLabel`, the Grid) — no new visual language.

## 7. Open questions

1. **Transferred records** — keep in an archive (proposed) or delete outright?
2. **Display name** — free text, or first name only with a character cap?
3. **Where do Friends live?** Proposed: a fourth segment is too much; put *Friends* behind a
   header button on the Grid. Needs a mockup.
4. ~~Messages as a route~~ — **resolved: yes.** Remote sharing is a requirement, and Messages
   is how it's met.

## 8. If Messages turns out not to be enough

If a kid has no iMessage (e.g. an iPad without an Apple ID for Messages), email from the share
sheet still works. Only if that proves inadequate, the next step up is **CloudKit with share
codes**: the app uploads a shelf card to its public CloudKit database and shows a 6-character
code the kid reads to a friend over the phone. That adds network calls, an iCloud-account
requirement, expiry and abuse handling — roughly a week more — so it stays out unless real use
shows the share-sheet route failing.
