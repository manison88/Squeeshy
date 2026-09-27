# Squish Index — Friends & Trading (proposal)

> Status: **proposal, needs owner sign-off.** This changes two locked rules in `SPEC.md`
> (§6 "no accounts, no network calls except identification"; §7 "no social in v1") — see §8.
> Proposed as **Milestone 6**, after M5. Nothing in M1–M5 changes.

## 1. The request

From the target audience (a kid collector):

1. **Friend each other** — a lasting connection, not a one-off send.
2. **See what each other has** — a friend's shelf, always current, from anywhere.
3. **Request trades** — pick their squishy, offer one of yours, they say yes or no.

Friends are usually **not in the same place**, so none of this can depend on being nearby.

## 2. Why this needs a backend, and why CloudKit is the lightest one

"Always current" and "request" mean the data has to live somewhere both phones can reach at
any time. That rules out passing files around. The options:

| | **CloudKit sharing (recommended)** | Own backend (Firebase, Supabase…) |
|---|---|---|
| Server to run | None — Apple hosts it | Yes |
| Sign-in | None in-app; uses the iCloud account already on the phone | Build accounts, passwords, recovery |
| Where a kid's data lives | Their own iCloud; friends get read access Apple enforces | Our database — we become the data holder for children (COPPA) |
| Cost | Free at this scale | Monthly bill + maintenance |
| Finding strangers | Impossible — no search, no directory | Has to be designed out |
| Push notifications | Built in (`CKDatabaseSubscription`) | Build it |
| Rough size | ~1.5–2 weeks on top of M5 | Several weeks, then ongoing |

Kids under 13 on a Family Sharing Apple Account have iCloud, so this works for them.

## 3. How it works — one idea: *my shelf is a shared folder*

Each kid's app keeps a small **public copy of their shelf** in a CloudKit zone in their own
iCloud: one record per squishy they hold, carrying a **thumbnail** (400 px), name, squish,
size, palette. Full-resolution photos stay on the device.

**Friending = sharing that zone.** The zone is shared read-only with each friend (a
zone-wide `CKShare`, iOS 15+). When both kids have accepted each other's invite, each can see
the other's shelf, and it updates live.

**Trade requests live in the requester's own zone.** No one ever writes into someone else's
iCloud. That keeps the permissions simple: every share is read-only.

```
Maya's iCloud                         Zoe's iCloud
┌─ Shelf zone (shared → Zoe) ─┐      ┌─ Shelf zone (shared → Maya) ─┐
│ Specimen × n  (thumbnails)  │      │ Specimen × n                 │
│ TradeRequest → Zoe          │ ───▶ │                              │
│                             │ ◀─── │ TradeReply → Maya  (yes/no)  │
└─────────────────────────────┘      └──────────────────────────────┘
      each app subscribes to its shared database → push on change
```

One consequence: every friend of Maya could technically read a request Maya sent to Zoe. The
app only shows each friend the requests addressed to them. If that isn't private enough, the
fix is a separate zone per friend, which is more code; see §9 Q6.

## 4. The flows

### 4.1 Friending

1. *Friends* → **Add a friend** → the system sharing UI (`UICloudSharingController`) sends a
   private invite link, most often through Messages.
2. The friend taps the link → Squish Index opens → *"Maya wants to be friends"* → **Accept**.
3. Accepting also sends Maya an invite back, so friendship is always **mutual**. Until both
   sides accept, nothing is visible. *To verify in a prototype:* whether Zoe's app can add
   Maya to its own share automatically (using the owner identity on Maya's share), or whether
   Zoe must tap through a one-screen "Send your invite back" step. Either is acceptable.
4. **Remove friend** revokes the share immediately; their shelf disappears from your app and
   yours from theirs.

Invites are private (`publicPermission = .none`): a forwarded link doesn't let anyone else in.

### 4.2 Seeing a friend's shelf

The Friends list shows one row per friend: name, count, `UPDATED 2 H AGO`. Tapping opens
their shelf in the **existing Grid and true-scale Shelf views** in a read-only mode. Nothing
new is designed here. The only addition is a **Request trade** button on each of their
specimens.

Optional per-specimen flag on your own shelf: **Open to trade** / **Keeping**. Kept items still
show but can't be requested. This cuts down on "no" replies.

### 4.3 Requesting a trade

1. On Zoe's specimen → **Request trade** → pick **one or more of your own** squishies to offer.
2. Review card: *your Amber blob ↔ her Mochi cat* → **Send request**.
3. Zoe gets a push: *"Maya wants to trade."* The request card shows both sides with
   **Accept** / **No thanks**. She can't counter-offer; to counter, she sends her own request.
4. **Requests carry no free text.** Only the items plus, optionally, one preset line
   ("I have a double!", "Swap at school?"). No chat means nothing to moderate.
5. Requests expire after 14 days. Each kid can have up to 5 open outgoing requests.

### 4.4 Completing a trade

The toys still have to physically change hands, in person or by post. So an accepted trade
sits in **Trades → In progress** until each side taps **I've handed mine over**.

When both have tapped:

- Each app **accessions** the incoming squishy with the sender's measurements intact
  (measured on Maya's phone is still measured) and a provenance line
  `FROM MAYA · 27 SEP 2026`. The full photo travels once, as a `CKAsset` attached for this step
  only, then is deleted from the cloud. The receiver regenerates the Vision feature print from
  it, so duplicate detection keeps working.
- The outgoing squishy moves to a **Traded** archive rather than being deleted: greyed out,
  out of counts and stats, `TRADED TO ZOE`. Kids regret trades, and having owned it is part of
  the collection.
- If a squishy comes back (same `originID`), the archived record is restored.

## 5. Model additions

```swift
// On Squishy
var originID: UUID                  // stable across every owner
var status: String                  // "held" | "traded"
var openToTrade: Bool
var provenance: [ProvenanceEntry]   // Codable: owner, from, to

// Local mirrors of CloudKit state
@Model final class Friend       { var name: String; var shareURL: URL; var lastSeen: Date }
@Model final class FriendItem   { /* thumbnail, name, squish, size, palette, openToTrade */ }
@Model final class TradeRequest { var id: UUID; var from: String; var to: String
                                  var offered: [UUID]; var wanted: [UUID]
                                  var state: String   // sent|accepted|declined|done|expired
                                  var handedOverBy: [String]; var createdAt: Date }
```

Friends' items are stored **separately** from the user's own catalogue, so they never leak into
the user's counts, stats or duplicate detection.

**Sync engine:** `CKSyncEngine` (iOS 17, which matches the deployment floor). SwiftData's built-in
CloudKit sync only covers the private database and can't share, so the shelf zone is mirrored
by hand: about one file of code, with no dependencies.

## 6. Offline and no-iCloud behaviour

- The catalogue keeps working fully offline and without iCloud. `SPEC.md` §7's "don't gate
  the app on the cloud" still holds.
- No iCloud account → the Friends tab explains that friends need iCloud, and nothing else changes.
- Requests and handovers made offline queue up and sync later (`CKSyncEngine` handles this).

## 7. Safety model

- **No discovery.** No search, usernames, or directory. You can only friend someone whose invite
  link you received, which in practice means someone already in your Messages. Parents control
  that with Screen Time *Communication Limits*.
- **No chat.** Only items and preset lines.
- **Mutual and revocable.** Both sides must accept; either side can remove the other instantly.
- **We hold no children's data.** Everything lives in the families' own iCloud accounts. The
  developer can't see or read shelves.

## 8. Spec changes this would need

- `SPEC.md` §6: add "…and CloudKit sync of the user's shared shelf, friends and trades."
  Also "Photos stay on device" → "full-resolution photos stay on device; friends see thumbnails."
- `SPEC.md` §7: narrow "no social" to "no feeds, discovery, chat or gamification."
- `SPEC.md` §5: add **Milestone 6 — Friends & trading**, split as 6a *friends + shelf viewing*
  and 6b *trade requests*. 6a alone is useful and ships first.
- Design: new surfaces are the *Friends* list, the *Request trade* picker, the request card and
  *Trades* list. They are built from existing components (`SpecimenCard`, `PhotoPlate`,
  `MonoLabel`, Grid), with no new visual language. Mockups needed.

## 9. Open questions

1. **Where do Friends and Trades live?** A fourth segment beside Grid · Shelf · Stats, or a
   header button on the Grid? Needs a mockup.
2. **Preset lines** in requests — allow a short fixed list, or items only?
3. **"Open to trade" default** — should new squishies default to open or keeping?
4. **Parent approval** — should accepting a friend or a trade need a parent's OK? It adds
   friction. Recommend no for v1, since the friend list is already limited by Communication
   Limits.
5. **Display name** — first name only with a character cap, or the iCloud name?
6. **Request privacy** — is it acceptable that Maya's other friends could technically fetch a
   request she sent to Zoe (§3), or should requests go in per-friend zones?
