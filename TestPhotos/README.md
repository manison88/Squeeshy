# Test photos

Drop real squeeshy photos in here — ideally the awkward ones: held in a hand, on a
messy shelf, low contrast against skin, bad light.

Then run the checker from the project root:

```bash
swift Tools/liftcheck.swift TestPhotos
```

It runs the exact pipeline the app uses and writes each cut-out to `/tmp/lift_*.png`
with a transparent background, plus a report of what it found and what it rejected.
