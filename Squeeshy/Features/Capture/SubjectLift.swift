import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// What the on-device pass can honestly work out from one photo.
///
/// Colour and body plan are pixels and geometry. Size is not: a photo carries no
/// scale without a reference object, so it is asked for rather than guessed. The
/// species name is not either, which is why it is left to the cloud pass.
struct ExtractedTraits {
    var hue: Double
    var saturation: Double
    var species: Species
}

enum SubjectLift {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Cuts the squeeshy off its background using Vision's foreground instance mask,
    /// the same machinery as press-and-hold-to-lift in Photos.
    ///
    /// Returns nil when nothing subject-like is found, which is the honest answer for
    /// a photo of an empty sofa — the caller offers a retake rather than saving a
    /// rectangle of carpet.
    static func cutout(from original: UIImage) async -> UIImage? {
        // Everything downstream — Vision's masks, the Core Image composite, the crop —
        // has to agree on one coordinate space. A photo straight off the camera keeps
        // its rotation in EXIF rather than in the pixels, so the mask comes back in a
        // different orientation to the buffer it is meant to cut, lands nowhere near
        // the subject, and the coverage guard throws the whole thing away. Redrawing
        // upright once at the top removes the entire class of bug.
        let image = original.uprighted()
        guard let cgImage = image.cgImage else { return nil }

        let foreground = VNGenerateForegroundInstanceMaskRequest()

        // Almost every squeeshy photo is taken holding the thing up, so the hand is
        // in frame, it is central, and it is usually bigger than the squeeshy. Left
        // alone the lift saves a picture of a hand. Segmenting the person separately
        // lets the hand and arm be cut back out of whatever the foreground pass found.
        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .accurate
        person.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        do {
            try handler.perform([foreground, person])
        } catch {
            return nil
        }

        guard let result = foreground.results?.first, !result.allInstances.isEmpty else { return nil }

        let source = CIImage(cgImage: cgImage)
        let notPerson = skinMask(from: person, matching: source.extent)

        do {
            // Vision usually separates the squeeshy and the hand into different
            // instances, which means the hand can simply be *discarded* rather than
            // subtracted. That matters: subtracting everywhere eats fingers out of
            // the squeeshy wherever they overlap it, and a bitten cut-out looks worse
            // than a slightly generous one.
            let pick = primaryInstance(in: result, handler: handler,
                                       notPerson: notPerson, extent: source.extent)

            // Take the mask on its own rather than the pre-masked image, so the edge
            // can be cleaned up before it is applied. Straight out of Vision the
            // silhouette carries a pixel or two of background colour all the way
            // round, which on a dark glass card reads as a dirty halo.
            let maskBuffer = try result.generateScaledMaskForImage(forInstances: pick.instances,
                                                                   from: handler)
            var mask = scaled(CIImage(cvPixelBuffer: maskBuffer), to: source.extent)

            // Only when hand and squeeshy came back fused into one instance is the
            // person mask subtracted, and then the holes fingers leave get filled
            // back in.
            if pick.needsSubtraction, let notPerson {
                let cut = CIFilter.multiplyCompositing()
                cut.inputImage = mask
                cut.backgroundImage = notPerson
                mask = cut.outputImage ?? mask
                mask = fillEnclosedHoles(in: mask, extent: source.extent)
            }

            // Pull the silhouette in slightly to drop the fringe, then soften the
            // remaining edge so it doesn't look die-cut against the glass.
            let erode = CIFilter.morphologyMinimum()
            erode.inputImage = mask
            erode.radius = Float(max(1, min(source.extent.width, source.extent.height) * 0.0025))
            let feather = CIFilter.gaussianBlur()
            feather.inputImage = erode.outputImage
            feather.radius = Float(max(0.8, min(source.extent.width, source.extent.height) * 0.0018))

            guard let refined = feather.outputImage?.cropped(to: source.extent) else { return nil }

            let blend = CIFilter.blendWithMask()
            blend.inputImage = source
            blend.backgroundImage = CIImage.empty()
            blend.maskImage = refined

            guard let output = blend.outputImage,
                  let cg = ciContext.createCGImage(output, from: source.extent) else { return nil }

            let lifted = UIImage(cgImage: cg, scale: image.scale, orientation: .up)
            return cropToSubject(lifted)
        } catch {
            return nil
        }
    }

    /// Matches a Vision mask to the photo; masks come back at their own scale.
    private static func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        guard mask.extent.width > 0, mask.extent.height > 0 else { return mask }
        return mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                      y: extent.height / mask.extent.height))
    }

    /// An inverted, slightly grown person mask: white everywhere that is *not* skin.
    ///
    /// Grown before inverting because segmentation stops a pixel or two short of the
    /// real edge of a finger, and the leftover rim of knuckle around a held squeeshy
    /// is more noticeable than losing a sliver of the squeeshy itself.
    private static func skinMask(from request: VNGeneratePersonSegmentationRequest,
                                 matching extent: CGRect) -> CIImage? {
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        let person = scaled(CIImage(cvPixelBuffer: buffer), to: extent)

        let grow = CIFilter.morphologyMaximum()
        grow.inputImage = person
        grow.radius = Float(max(2, min(extent.width, extent.height) * 0.006))

        let soften = CIFilter.gaussianBlur()
        soften.inputImage = grow.outputImage
        soften.radius = Float(max(1, min(extent.width, extent.height) * 0.003))

        let invert = CIFilter.colorInvert()
        invert.inputImage = soften.outputImage?.cropped(to: extent)
        return invert.outputImage?.cropped(to: extent)
    }

    struct InstancePick {
        var instances: IndexSet
        /// True when no hand-free instance existed, so the person has to be cut out
        /// of the chosen one instead of simply skipping it.
        var needsSubtraction: Bool
    }

    /// Picks the one instance the photo is actually of.
    ///
    /// Instances that are mostly skin are thrown away outright — that is the hand,
    /// and it is usually its own instance. Whatever is left is scored on area and how
    /// central it is, untouched, so fingers overlapping the squeeshy don't get carved
    /// out of it. Only if every instance is mostly skin does the caller fall back to
    /// subtraction.
    private static func primaryInstance(in result: VNInstanceMaskObservation,
                                        handler: VNImageRequestHandler,
                                        notPerson: CIImage?,
                                        extent: CGRect) -> InstancePick {
        let instances = result.allInstances
        guard instances.count > 1 || notPerson != nil else {
            return InstancePick(instances: instances, needsSubtraction: false)
        }

        var best: Int?
        var bestScore = 0.0
        var fallback: Int?
        var fallbackScore = 0.0

        for instance in instances {
            let single = IndexSet(integer: instance)
            guard let buffer = try? result.generateScaledMaskForImage(forInstances: single,
                                                                      from: handler) else { continue }
            let mask = scaled(CIImage(cvPixelBuffer: buffer), to: extent)
            guard let stats = maskStats(mask, extent: extent) else { continue }

            // Distance of the centre of mass from the frame centre, normalised so 0
            // is dead centre and 1 is a corner.
            let dx = stats.centreX - 0.5, dy = stats.centreY - 0.5
            let offCentre = min(1, (dx * dx + dy * dy).squareRoot() / 0.707)
            let score = stats.area * (1 - offCentre * 0.75)

            // How much of this instance is skin.
            var skinFraction = 0.0
            if let notPerson {
                let cut = CIFilter.multiplyCompositing()
                cut.inputImage = mask
                cut.backgroundImage = notPerson
                if let cutOut = cut.outputImage,
                   let remaining = maskStats(cutOut, extent: extent) {
                    skinFraction = 1 - (remaining.area / max(stats.area, 0.0001))
                } else {
                    skinFraction = 1
                }
            }

            // Measured against real photos: when person segmentation claims almost
            // the entire instance, it is nearly always wrong rather than the instance
            // actually being a hand. A pale bread squeeshy held in a palm reads as
            // 100% skin and gets deleted outright. Vision's foreground pass had
            // already excluded the hand in every one of those cases, so the safe
            // reading of "all skin" is "ignore the person mask", not "give up".
            if skinFraction > 0.92 {
                if score > bestScore { bestScore = score; best = instance }
            } else if skinFraction < 0.55 {
                if score > bestScore { bestScore = score; best = instance }
            } else if score > fallbackScore {
                // Genuinely part hand, part something else. Worth subtracting.
                fallbackScore = score; fallback = instance
            }
        }

        if let best {
            return InstancePick(instances: IndexSet(integer: best), needsSubtraction: false)
        }
        if let fallback {
            // Hand and squeeshy fused into one blob; cut the person out of it.
            return InstancePick(instances: IndexSet(integer: fallback), needsSubtraction: true)
        }
        return InstancePick(instances: instances, needsSubtraction: notPerson != nil)
    }

    /// Puts back any hole the hand punched through the middle of the squeeshy.
    ///
    /// A finger crossing in front leaves an enclosed gap; a finger gripping the rim
    /// leaves a notch open to the outside. Flooding inward from the border separates
    /// the two, so enclosed gaps get filled and genuine silhouette edges are left
    /// alone. Worked at low resolution and composited back as a soft additive layer,
    /// so the original mask keeps its crisp outline.
    private static func fillEnclosedHoles(in mask: CIImage, extent: CGRect) -> CIImage {
        let side = 192
        let scale = CGAffineTransform(scaleX: CGFloat(side) / extent.width,
                                      y: CGFloat(side) / extent.height)
        guard let cg = ciContext.createCGImage(mask.transformed(by: scale),
                                               from: CGRect(x: 0, y: 0, width: side, height: side)) else { return mask }

        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &raw, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return mask }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Flood the background inward from every border pixel.
        var outside = [Bool](repeating: false, count: side * side)
        var stack: [Int] = []
        func isBackground(_ i: Int) -> Bool { raw[i * 4] < 110 }

        for x in 0..<side {
            for y in [0, side - 1] {
                let i = y * side + x
                if isBackground(i) && !outside[i] { outside[i] = true; stack.append(i) }
            }
        }
        for y in 0..<side {
            for x in [0, side - 1] {
                let i = y * side + x
                if isBackground(i) && !outside[i] { outside[i] = true; stack.append(i) }
            }
        }
        while let i = stack.popLast() {
            let x = i % side, y = i / side
            if x > 0 { let n = i - 1; if isBackground(n) && !outside[n] { outside[n] = true; stack.append(n) } }
            if x < side - 1 { let n = i + 1; if isBackground(n) && !outside[n] { outside[n] = true; stack.append(n) } }
            if y > 0 { let n = i - side; if isBackground(n) && !outside[n] { outside[n] = true; stack.append(n) } }
            if y < side - 1 { let n = i + side; if isBackground(n) && !outside[n] { outside[n] = true; stack.append(n) } }
        }

        // Anything dark that the flood never reached is enclosed: a finger hole.
        var holes = [UInt8](repeating: 0, count: side * side * 4)
        var found = false
        for i in 0..<(side * side) where isBackground(i) && !outside[i] {
            found = true
            holes[i * 4] = 255; holes[i * 4 + 1] = 255; holes[i * 4 + 2] = 255; holes[i * 4 + 3] = 255
        }
        guard found else { return mask }

        guard let holeCG = CGContext(data: &holes, width: side, height: side,
                                     bitsPerComponent: 8, bytesPerRow: side * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else { return mask }

        let holeImage = CIImage(cgImage: holeCG)
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(side),
                                               y: extent.height / CGFloat(side)))
        let soften = CIFilter.gaussianBlur()
        soften.inputImage = holeImage
        soften.radius = Float(max(2, min(extent.width, extent.height) * 0.004))

        // Lighten keeps whichever is brighter, so the crisp original outline survives
        // and only the interior gains coverage.
        let merge = CIFilter.lightenBlendMode()
        merge.inputImage = soften.outputImage?.cropped(to: extent)
        merge.backgroundImage = mask
        return merge.outputImage?.cropped(to: extent) ?? mask
    }

    /// Coverage and centre of mass of a mask, read from a small downscale.
    private static func maskStats(_ image: CIImage, extent: CGRect) -> (area: Double, centreX: Double, centreY: Double)? {
        let side = 48
        let scale = CGAffineTransform(scaleX: CGFloat(side) / extent.width,
                                      y: CGFloat(side) / extent.height)
        guard let cg = ciContext.createCGImage(image.transformed(by: scale),
                                               from: CGRect(x: 0, y: 0, width: side, height: side)) else { return nil }

        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &raw, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var count = 0, sumX = 0.0, sumY = 0.0
        for y in 0..<side {
            for x in 0..<side {
                // The mask is greyscale, so any channel carries the value.
                if raw[(y * side + x) * 4] > 128 {
                    count += 1; sumX += Double(x); sumY += Double(y)
                }
            }
        }
        guard count > 0 else { return nil }
        let n = Double(count)
        return (n / Double(side * side), sumX / n / Double(side), sumY / n / Double(side))
    }

    /// Trims the transparent margin so every cut-out fills its card the same amount,
    /// whether the squeeshy was shot close up or from across the room. Without this,
    /// a shelf of cards looks randomly zoomed.
    private static func cropToSubject(_ image: UIImage, margin: CGFloat = 0.04) -> UIImage? {
        guard let cg = image.cgImage else { return nil }

        let side = 96
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &raw, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where raw[(y * side + x) * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return nil }

        // Reject masks that found almost nothing, or that swallowed the whole frame:
        // both mean the lift failed and the caller should offer a retake.
        let coverage = Double((maxX - minX) * (maxY - minY)) / Double(side * side)
        guard coverage > 0.02, coverage < 0.985 else { return nil }

        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let pad = margin * max(w, h)
        // Both the scan above and `cropping(to:)` measure y downwards from the top, so
        // minY goes in as-is. Flipping it to `side - 1 - maxY` put the crop the same
        // distance below the subject as the subject sat below the top edge, which
        // sliced the top off anything not vertically centred — and left anything that
        // *was* centred looking perfect, which is why the test photos never caught it.
        let rect = CGRect(x: CGFloat(minX) / CGFloat(side) * w - pad,
                          y: CGFloat(minY) / CGFloat(side) * h - pad,
                          width: CGFloat(maxX - minX + 1) / CGFloat(side) * w + pad * 2,
                          height: CGFloat(maxY - minY + 1) / CGFloat(side) * h + pad * 2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))

        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    /// Reads traits off the cut-out. Transparent pixels are skipped, so the colour is
    /// the squeeshy's rather than an average with its background.
    static func traits(from cutout: UIImage) -> ExtractedTraits {
        let (hue, saturation) = dominantHue(sampleOpaquePixels(cutout))
        let aspect = cutout.size.height > 0 ? cutout.size.width / cutout.size.height : 1
        return ExtractedTraits(hue: hue,
                               saturation: saturation,
                               species: bodyPlan(aspect: aspect, coverage: coverageRatio(cutout)))
    }

    // MARK: Colour

    /// Averages hue on the unit circle, weighted by saturation, so a mostly-white
    /// plush with pink ears reads pink rather than washing out to grey.
    private static func dominantHue(_ samples: [(h: Double, s: Double, b: Double)]) -> (Double, Double) {
        guard !samples.isEmpty else { return (330, 0.4) }

        var x = 0.0, y = 0.0, weightTotal = 0.0, satTotal = 0.0
        for p in samples {
            // Very dark or very desaturated pixels carry almost no hue information.
            let weight = p.s * p.b
            let radians = p.h * 2 * .pi
            x += cos(radians) * weight
            y += sin(radians) * weight
            weightTotal += weight
            satTotal += p.s
        }

        let meanSat = satTotal / Double(samples.count)
        guard weightTotal > 0.0001 else { return (0, min(0.2, meanSat)) }

        let degrees = Hue.wrap(atan2(y, x) * 180 / .pi)
        // Clamped so a near-grey squeeshy stays grey instead of being pushed into a
        // colour the eye cannot see in the photo.
        return (degrees, min(0.62, max(0.10, meanSat)))
    }

    private static func sampleOpaquePixels(_ image: UIImage) -> [(h: Double, s: Double, b: Double)] {
        guard let cg = image.cgImage else { return [] }

        // Downscale hard before reading pixels: 64x64 is plenty for a dominant hue
        // and keeps this well under a frame even on older phones.
        let side = 64
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &raw, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var out: [(Double, Double, Double)] = []
        out.reserveCapacity(side * side / 2)
        for i in stride(from: 0, to: raw.count, by: 4) {
            let a = Double(raw[i + 3]) / 255
            guard a > 0.6 else { continue }
            // Premultiplied: undo it before converting, or dark edges skew the hue.
            let r = Double(raw[i]) / 255 / a
            let g = Double(raw[i + 1]) / 255 / a
            let b = Double(raw[i + 2]) / 255 / a
            out.append(rgbToHSB(min(r, 1), min(g, 1), min(b, 1)))
        }
        return out
    }

    private static func rgbToHSB(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        var h = 0.0
        if delta > 0.0001 {
            if maxV == r      { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == g { h = (b - r) / delta + 2 }
            else              { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    // MARK: Shape

    /// How much of the bounding box the subject actually fills. A star fills far less
    /// of its box than a loaf does, which is most of what separates them.
    private static func coverageRatio(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0.8 }
        let side = 48
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &raw, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0.8 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var opaque = 0
        for i in stride(from: 3, to: raw.count, by: 4) where raw[i] > 150 { opaque += 1 }
        return Double(opaque) / Double(side * side)
    }

    /// Maps silhouette geometry onto one of the eight body plans. This is a guess and
    /// the app treats it as one: the shape chip on the detail view corrects it in a tap.
    ///
    /// The thresholds are calibrated against real cut-outs, not ideal shapes. A solid
    /// blob measures around 0.45–0.55 rather than the 0.79 a perfect ellipse would,
    /// because the crop adds a margin and the feathered edge falls below the alpha
    /// cut-off. Tuned for synthetic shapes, this called five of six real squeeshies a
    /// star. When in doubt it now says round, which is what most of them are.
    private static func bodyPlan(aspect: Double, coverage: Double) -> Species {
        if coverage < 0.24 { return .star }
        if aspect > 1.5    { return .wide }
        if aspect < 0.62   { return .loaf }
        return .round
    }

}

// MARK: - Naming

/// The cloud pass that turns a cut-out into "Axolotl". Behind a protocol so the app
/// works offline today and gains the network later without the capture flow changing.
protocol SpeciesNaming: Sendable {
    func typeName(for cutout: UIImage) async -> String?
}

/// Offline placeholder. Returns nothing rather than inventing a species, so the
/// review screen shows an honest "Tap to set" instead of a confident wrong answer.
struct OfflineNaming: SpeciesNaming {
    func typeName(for cutout: UIImage) async -> String? { nil }
}

extension UIImage {
    /// Redraws into an upright buffer, folding EXIF rotation into the pixels.
    ///
    /// Cheap when the photo is already upright, and the only reliable way to keep
    /// Vision, Core Image and CoreGraphics in the same coordinate space.
    func uprighted() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
