// Settles which coordinate space CGImage.cropping(to:) uses, using an image whose
// opaque region is written byte by byte so there is no drawing step to reason about.
//
//     swift Tools/cropcheck.swift
//
// The subject is deliberately off-centre: a centred one hides the bug, because the
// wrong flip and the right one agree when minY == side-1-maxY.
import AppKit
import CoreGraphics

let W = 400, H = 800

/// Opaque red across rows `rows`, transparent elsewhere. Row 0 is the first row in
/// memory; whether that is the top of the picture is exactly what we are testing.
func makeImage(rows: Range<Int>) -> CGImage {
    var raw = [UInt8](repeating: 0, count: W * H * 4)
    for y in rows {
        for x in 120..<280 {
            let o = (y * W + x) * 4
            raw[o] = 230; raw[o + 1] = 60; raw[o + 2] = 60; raw[o + 3] = 255
        }
    }
    let ctx = CGContext(data: &raw, width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func write(_ cg: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: "/tmp/cropcheck_\(name).png")
    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: url)
    print("    wrote \(url.path)  \(cg.width)x\(cg.height)")
}

/// The scan from SubjectLift.cropToSubject, unchanged.
func scan(_ cg: CGImage, side: Int = 96) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
    var raw = [UInt8](repeating: 0, count: side * side * 4)
    let ctx = CGContext(data: &raw, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
    var minX = side, minY = side, maxX = -1, maxY = -1
    for y in 0..<side {
        for x in 0..<side where raw[(y * side + x) * 4 + 3] > 40 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return (minX, minY, maxX, maxY)
}

/// What fraction of the crop is actually opaque. The correct crop is nearly all
/// subject; a crop offset by the wrong flip is mostly empty.
func opaqueFraction(_ cg: CGImage) -> Double {
    let side = 64
    var raw = [UInt8](repeating: 0, count: side * side * 4)
    let ctx = CGContext(data: &raw, width: side, height: side, bitsPerComponent: 8,
                        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
    var n = 0
    for i in 0..<(side * side) where raw[i * 4 + 3] > 40 { n += 1 }
    return Double(n) / Double(side * side)
}

// Subject in memory rows 80..<240 of 800 — well into the first third.
let image = makeImage(rows: 80..<240)
print("Subject written to memory rows 80..<240 of \(H).")
print("Open the file below: if the red block sits at the TOP, memory row 0 is the top.")
write(image, "source")

let b = scan(image)
let side = 96
let w = CGFloat(W), h = CGFloat(H)
let pad = 0.04 * max(w, h)
print("\nScan of the 96x96 thumbnail: minY=\(b.minY) maxY=\(b.maxY)")
print("  (rows 80..<240 of 800 scale to roughly \(80 * side / H)..\(240 * side / H))")

func crop(y: CGFloat, label: String) {
    let rect = CGRect(x: CGFloat(b.minX) / CGFloat(side) * w - pad,
                      y: y,
                      width: CGFloat(b.maxX - b.minX + 1) / CGFloat(side) * w + pad * 2,
                      height: CGFloat(b.maxY - b.minY + 1) / CGFloat(side) * h + pad * 2)
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard let out = image.cropping(to: rect) else { print("  \(label): crop failed"); return }
    print(String(format: "  %@  rect.y=%.0f  ->  %.0f%% of the crop is subject",
                 label, rect.origin.y, opaqueFraction(out) * 100))
    write(out, label)
}

print("\nCurrent code uses the bottom-up flip:")
crop(y: CGFloat(side - 1 - b.maxY) / CGFloat(side) * h - pad, label: "flipped")
print("Top-down uses minY directly:")
crop(y: CGFloat(b.minY) / CGFloat(side) * h - pad, label: "topdown")
