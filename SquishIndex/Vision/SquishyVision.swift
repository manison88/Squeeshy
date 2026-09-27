import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import simd
import UIKit
import Vision

/// Everything the app measures on device: subject segmentation, colour palette,
/// silhouette, real millimetres, and the feature print used for duplicate
/// detection. SPEC.md §4.
///
/// Nothing in here guesses. If the measurement ladder runs out of rungs the
/// result carries `.none` and no dimensions — an unreferenced photograph cannot
/// yield millimetres and the app never pretends otherwise (SPEC.md §7).
enum SquishyVision {

    // MARK: Input / output

    struct Sample {
        /// Already rotated to `.up`.
        let image: CGImage
        /// Already rotated to match `image`.
        var depth: AVDepthData?
        /// Horizontal field of view of the capturing format, in degrees.
        var fieldOfViewDegrees: Double?
        /// Whether the capturing device was a LiDAR-equipped rear camera.
        var isLiDAR: Bool = false
    }

    struct PaletteEntry {
        let hex: String
        let share: Double
        let hsb: HSB
    }

    struct HSB {
        /// Degrees, 0…360.
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    struct Analysis {
        /// Subject cut out and laid on chalk, cropped square. This is what gets
        /// stored and shown on every plate.
        let plateImage: UIImage
        let subjectIsolated: Bool
        let palette: [PaletteEntry]
        let dominant: HSB
        let form: SpecimenForm
        let widthMM: Double?
        let heightMM: Double?
        let method: MeasurementMethod
        let confidence: Double
        let featurePrint: Data
    }

    enum Stage: Int, CaseIterable, Identifiable {
        case isolating, palette, measuring, duplicates, filing

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .isolating: "Subject isolated"
            case .palette: "Palette extracted"
            case .measuring: "Measuring size"
            case .duplicates: "Checking duplicates"
            case .filing: "Filing specimen"
            }
        }
    }

    enum Failure: Error {
        case noSubject
        case renderFailed
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// Working resolution for pixel statistics. Full resolution buys nothing
    /// for palette or silhouette, and costs a great deal of time.
    private static let analysisEdge = 512

    // MARK: Entry point

    /// Runs the whole on-device pipeline. Synchronous and thread-confined —
    /// call it off the main actor.
    static func analyze(_ sample: Sample, progress: (Stage) -> Void = { _ in }) -> Analysis {
        let full = CIImage(cgImage: sample.image)
        let fullSize = CGSize(width: sample.image.width, height: sample.image.height)

        // 1 — Subject
        let mask = foregroundMask(for: sample.image)
        let maskField = mask.flatMap { downsampledMask($0, to: analysisSize(for: fullSize)) }
        progress(.isolating)

        let size = analysisSize(for: fullSize)
        let subject = maskField.flatMap { SubjectField(mask: $0, width: size.width, height: size.height) }

        // 2 — Palette
        let pixels = bitmap(from: sample.image, size: size)
        let palette = pixels.map { extractPalette(from: $0, size: size, subject: subject) } ?? []
        let dominant = palette.first?.hsb ?? HSB(hue: 0, saturation: 0, brightness: 0.5)
        progress(.palette)

        // 3 — Silhouette
        let form = subject.map(classifyForm) ?? .irregular

        // 4 — Millimetres
        let measurement = measure(sample: sample, subject: subject, fullSize: fullSize)
        progress(.measuring)

        // 5 — The stored plate
        let plate = plateImage(full: full,
                               fullSize: fullSize,
                               mask: mask,
                               subject: subject)

        // 6 — Feature print, taken on the plate so the background cannot carry
        //     the match.
        let print = featurePrint(for: plate) ?? Data()
        progress(.duplicates)
        progress(.filing)

        return Analysis(
            plateImage: plate,
            subjectIsolated: mask != nil,
            palette: palette,
            dominant: dominant,
            form: form,
            widthMM: measurement.widthMM,
            heightMM: measurement.heightMM,
            method: measurement.method,
            confidence: measurement.confidence,
            featurePrint: print
        )
    }

    // MARK: 1 — Segmentation

    /// `VNGenerateForegroundInstanceMaskRequest`, iOS 17. Returns a
    /// full-resolution single-channel mask, or `nil` when there is no subject —
    /// which is a legitimate outcome, not an error: the specimen still files.
    private static func foregroundMask(for image: CGImage) -> CVPixelBuffer? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            return try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        } catch {
            return nil
        }
    }

    /// The mask resampled to analysis resolution as 0…1 coverage.
    private static func downsampledMask(_ buffer: CVPixelBuffer, to size: (width: Int, height: Int)) -> [Float]? {
        let source = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        guard let cg = context.createCGImage(source, from: source.extent),
              let bytes = bitmap(from: cg, size: size) else { return nil }
        return (0..<(size.width * size.height)).map { Float(bytes[$0 * 4]) / 255 }
    }

    /// Mask statistics in analysis-space pixels. Origin is top-left.
    struct SubjectField {
        let mask: [Float]
        let width: Int
        let height: Int
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        let area: Int
        let perimeter: Int

        init?(mask: [Float], width: Int, height: Int) {
            var minX = width, minY = height, maxX = -1, maxY = -1
            var area = 0
            var perimeter = 0
            for y in 0..<height {
                for x in 0..<width where mask[y * width + x] > 0.5 {
                    area += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    let isEdge = x == 0 || y == 0 || x == width - 1 || y == height - 1
                        || mask[y * width + x - 1] <= 0.5
                        || mask[y * width + x + 1] <= 0.5
                        || mask[(y - 1) * width + x] <= 0.5
                        || mask[(y + 1) * width + x] <= 0.5
                    if isEdge { perimeter += 1 }
                }
            }
            // Under about a fiftieth of the frame there is no subject worth
            // measuring; treat it as a miss rather than measuring noise.
            guard maxX >= 0, area > (width * height) / 400 else { return nil }
            self.mask = mask
            self.width = width
            self.height = height
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
            self.area = area
            self.perimeter = max(perimeter, 1)
        }

        var boxWidth: Int { maxX - minX + 1 }
        var boxHeight: Int { maxY - minY + 1 }

        func contains(x: Int, y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return mask[y * width + x] > 0.5
        }

        /// Normalised, origin top-left.
        var normalisedBox: CGRect {
            CGRect(x: CGFloat(minX) / CGFloat(width),
                   y: CGFloat(minY) / CGFloat(height),
                   width: CGFloat(boxWidth) / CGFloat(width),
                   height: CGFloat(boxHeight) / CGFloat(height))
        }
    }

    // MARK: 2 — Palette

    /// Greedy seeding then one Lloyd pass, over the masked pixels only. Returns
    /// at most four entries in dominance order, and pads nothing: a monochrome
    /// toy gets one swatch, not one swatch and three greys.
    private static func extractPalette(from bytes: [UInt8],
                                       size: (width: Int, height: Int),
                                       subject: SubjectField?) -> [PaletteEntry] {
        var samples: [(r: Double, g: Double, b: Double)] = []
        samples.reserveCapacity(4096)
        let stride = max(1, (size.width * size.height) / 20_000)
        var index = 0
        for y in 0..<size.height {
            for x in 0..<size.width {
                defer { index += 1 }
                guard index % stride == 0 else { continue }
                if let subject, !subject.contains(x: x, y: y) { continue }
                let offset = (y * size.width + x) * 4
                samples.append((Double(bytes[offset]) / 255,
                                Double(bytes[offset + 1]) / 255,
                                Double(bytes[offset + 2]) / 255))
            }
        }
        guard samples.count > 16 else { return [] }

        // Seeds: the most-populated coarse bins, kept apart so near-identical
        // shades do not take two slots.
        var bins: [Int: Int] = [:]
        for sample in samples {
            bins[binKey(sample), default: 0] += 1
        }
        var seeds: [(r: Double, g: Double, b: Double)] = []
        for (key, _) in bins.sorted(by: { $0.value > $1.value }) {
            let candidate = binCentre(key)
            if seeds.allSatisfy({ colourDistance($0, candidate) > 0.22 }) {
                seeds.append(candidate)
            }
            if seeds.count == 6 { break }
        }
        guard !seeds.isEmpty else { return [] }

        var clusters = Array(repeating: (r: 0.0, g: 0.0, b: 0.0, n: 0), count: seeds.count)
        for sample in samples {
            var best = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for (i, seed) in seeds.enumerated() {
                let d = colourDistance(seed, sample)
                if d < bestDistance { bestDistance = d; best = i }
            }
            clusters[best].r += sample.r
            clusters[best].g += sample.g
            clusters[best].b += sample.b
            clusters[best].n += 1
        }

        let total = Double(samples.count)
        return clusters
            .filter { $0.n > 0 }
            .map { cluster -> PaletteEntry in
                let n = Double(cluster.n)
                let rgb = (r: cluster.r / n, g: cluster.g / n, b: cluster.b / n)
                return PaletteEntry(hex: hexString(rgb), share: n / total, hsb: hsb(rgb))
            }
            .sorted { $0.share > $1.share }
            // A colour holding less than a twentieth of the subject is a
            // highlight or a shadow, not part of the toy's palette.
            .filter { $0.share >= 0.05 }
            .prefix(4)
            .map { $0 }
    }

    private static func binKey(_ c: (r: Double, g: Double, b: Double)) -> Int {
        let r = Int(c.r * 7.99), g = Int(c.g * 7.99), b = Int(c.b * 7.99)
        return (r << 6) | (g << 3) | b
    }

    private static func binCentre(_ key: Int) -> (r: Double, g: Double, b: Double) {
        (r: (Double((key >> 6) & 7) + 0.5) / 8,
         g: (Double((key >> 3) & 7) + 0.5) / 8,
         b: (Double(key & 7) + 0.5) / 8)
    }

    private static func colourDistance(_ a: (r: Double, g: Double, b: Double),
                                       _ b: (r: Double, g: Double, b: Double)) -> Double {
        // Weighted so the distance tracks perception more closely than raw RGB.
        let dr = (a.r - b.r) * 0.30
        let dg = (a.g - b.g) * 0.59
        let db = (a.b - b.b) * 0.11
        return (dr * dr + dg * dg + db * db).squareRoot() * 3
    }

    private static func hexString(_ c: (r: Double, g: Double, b: Double)) -> String {
        String(format: "#%02X%02X%02X",
               Int((c.r * 255).rounded()),
               Int((c.g * 255).rounded()),
               Int((c.b * 255).rounded()))
    }

    static func hsb(_ c: (r: Double, g: Double, b: Double)) -> HSB {
        let maxV = max(c.r, c.g, c.b)
        let minV = min(c.r, c.g, c.b)
        let delta = maxV - minV
        var hue = 0.0
        if delta > 0.0001 {
            if maxV == c.r {
                hue = 60 * (((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxV == c.g {
                hue = 60 * (((c.b - c.r) / delta) + 2)
            } else {
                hue = 60 * (((c.r - c.g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return HSB(hue: hue, saturation: maxV <= 0 ? 0 : delta / maxV, brightness: maxV)
    }

    // MARK: 3 — Silhouette

    private static func classifyForm(_ subject: SubjectField) -> SpecimenForm {
        let w = Double(subject.boxWidth)
        let h = Double(subject.boxHeight)
        let aspect = w / max(h, 1)
        let extent = Double(subject.area) / max(w * h, 1)
        let perimeter = Double(subject.perimeter)
        // 1.0 for a perfect disc, lower as the outline gets more involved.
        let circularity = min(1, 4 * Double.pi * Double(subject.area) / (perimeter * perimeter))

        if aspect > 1.45 { return .wide }
        if aspect < 0.69 { return .tall }
        if circularity < 0.52 || extent < 0.55 { return .lobed }
        if extent > 0.88 && circularity < 0.82 { return .blocky }
        if circularity > 0.80 && aspect > 0.86 && aspect < 1.16 { return .round }
        if extent > 0.62 { return .oval }
        return .irregular
    }

    // MARK: 4 — The measurement ladder

    private struct Measurement {
        var widthMM: Double?
        var heightMM: Double?
        var method: MeasurementMethod
        var confidence: Double

        static let unmeasured = Measurement(widthMM: nil, heightMM: nil, method: .none, confidence: 0)
    }

    private static func measure(sample: Sample,
                                subject: SubjectField?,
                                fullSize: CGSize) -> Measurement {
        guard let subject else { return .unmeasured }

        // Rung 1 & 2 — depth.
        if let depth = sample.depth,
           let mmPerPixel = millimetresPerPixelFromDepth(depth,
                                                         subject: subject,
                                                         fullSize: fullSize,
                                                         fovDegrees: sample.fieldOfViewDegrees) {
            let scale = fullSize.width / CGFloat(subject.width)
            return Measurement(
                widthMM: Double(CGFloat(subject.boxWidth) * scale) * mmPerPixel.value,
                heightMM: Double(CGFloat(subject.boxHeight) * scale) * mmPerPixel.value,
                method: sample.isLiDAR ? .lidar : .depth,
                confidence: mmPerPixel.confidence
            )
        }

        // Rung 3 — a card of known size lying in the same plane.
        if let card = referenceCard(in: sample.image, avoiding: subject.normalisedBox) {
            let scale = fullSize.width / CGFloat(subject.width)
            return Measurement(
                widthMM: Double(CGFloat(subject.boxWidth) * scale) * card.millimetresPerPixel,
                heightMM: Double(CGFloat(subject.boxHeight) * scale) * card.millimetresPerPixel,
                method: .card,
                confidence: card.confidence
            )
        }

        // Rung 4 — say so.
        return .unmeasured
    }

    private static func millimetresPerPixelFromDepth(_ depth: AVDepthData,
                                                     subject: SubjectField,
                                                     fullSize: CGSize,
                                                     fovDegrees: Double?) -> (value: Double, confidence: Double)? {
        let converted = depth.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depth
            : depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }

        let mapWidth = CVPixelBufferGetWidth(map)
        let mapHeight = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        // Median over the subject only — the background is metres away and
        // would drag a mean into nonsense.
        var depths: [Float] = []
        depths.reserveCapacity(1024)
        let box = subject.normalisedBox
        let step = max(1, min(mapWidth, mapHeight) / 48)
        var y = Int(box.minY * CGFloat(mapHeight))
        while y < Int(box.maxY * CGFloat(mapHeight)), y < mapHeight {
            var x = Int(box.minX * CGFloat(mapWidth))
            while x < Int(box.maxX * CGFloat(mapWidth)), x < mapWidth {
                defer { x += step }
                let sx = Int(Double(x) / Double(mapWidth) * Double(subject.width))
                let sy = Int(Double(y) / Double(mapHeight) * Double(subject.height))
                guard subject.contains(x: sx, y: sy) else { continue }
                let pointer = base.advanced(by: y * rowBytes + x * MemoryLayout<Float>.size)
                let value = pointer.assumingMemoryBound(to: Float.self).pointee
                if value.isFinite, value > 0.05, value < 8 { depths.append(value) }
            }
            y += step
        }
        guard depths.count >= 8 else { return nil }
        depths.sort()
        let metres = Double(depths[depths.count / 2])

        // Intrinsics are exact when the capture carried them; field of view is
        // the documented fallback.
        if let calibration = converted.cameraCalibrationData {
            let matrix = calibration.intrinsicMatrix
            let reference = calibration.intrinsicMatrixReferenceDimensions
            let fx = Double(matrix.columns.0.x) * (fullSize.width / reference.width)
            guard fx > 0 else { return nil }
            return (metres * 1000 / fx, accuracyConfidence(converted))
        }

        guard let fovDegrees, fovDegrees > 0 else { return nil }
        let widthAtSubject = 2 * metres * tan(fovDegrees * Double.pi / 360)
        return (widthAtSubject * 1000 / Double(fullSize.width), accuracyConfidence(converted) * 0.9)
    }

    private static func accuracyConfidence(_ depth: AVDepthData) -> Double {
        // Relative depth has no trustworthy absolute scale; the number still
        // ships, but the sheet reports how sure it is.
        depth.depthDataAccuracy == .absolute ? 0.9 : 0.45
    }

    private struct ReferenceCard {
        let millimetresPerPixel: Double
        let confidence: Double
    }

    /// Any ID-1 card — credit card, licence — is 85.60 × 53.98 mm.
    private static func referenceCard(in image: CGImage, avoiding subjectBox: CGRect) -> ReferenceCard? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.72
        request.minimumConfidence = 0.7
        request.minimumSize = 0.06
        request.maximumObservations = 8
        request.quadratureTolerance = 22

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty else { return nil }

        let width = Double(image.width)
        let height = Double(image.height)

        let candidates = observations.filter { observation in
            // Vision's origin is bottom-left; the subject box is top-left.
            let flipped = CGRect(x: observation.boundingBox.minX,
                                 y: 1 - observation.boundingBox.maxY,
                                 width: observation.boundingBox.width,
                                 height: observation.boundingBox.height)
            return flipped.intersection(subjectBox).isNull
                || flipped.intersection(subjectBox).area < flipped.area * 0.3
        }
        guard let card = candidates.max(by: { $0.confidence < $1.confidence }) else { return nil }

        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: p.y * height) }
        let corners = [point(card.topLeft), point(card.topRight),
                       point(card.bottomRight), point(card.bottomLeft)]
        var edges: [Double] = []
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            edges.append(Double(hypot(b.x - a.x, b.y - a.y)))
        }
        edges.sort()
        // The two long edges, averaged — perspective makes them differ.
        let longEdge = (edges[2] + edges[3]) / 2
        guard longEdge > 24 else { return nil }
        return ReferenceCard(millimetresPerPixel: 85.60 / longEdge,
                             confidence: Double(card.confidence) * 0.9)
    }

    // MARK: 5 — The stored plate

    /// Subject on chalk, cropped square around the subject with a little air.
    /// Falls back to a centre crop of the raw frame when there is no mask —
    /// the specimen still files.
    private static func plateImage(full: CIImage,
                                   fullSize: CGSize,
                                   mask: CVPixelBuffer?,
                                   subject: SubjectField?) -> UIImage {
        var composed = full
        if let mask {
            let maskImage = CIImage(cvPixelBuffer: mask, options: [.colorSpace: NSNull()])
                .transformed(by: CGAffineTransform(scaleX: full.extent.width / CGFloat(CVPixelBufferGetWidth(mask)),
                                                   y: full.extent.height / CGFloat(CVPixelBufferGetHeight(mask))))
            let blend = CIFilter.blendWithMask()
            blend.inputImage = full
            blend.backgroundImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: full.extent)
            blend.maskImage = maskImage
            composed = blend.outputImage ?? full
        }

        // Crop square around the subject, 10 % air, clamped to the frame.
        var crop = CGRect(origin: .zero, size: fullSize)
        if let subject {
            let scaleX = fullSize.width / CGFloat(subject.width)
            let scaleY = fullSize.height / CGFloat(subject.height)
            let boxWidth = CGFloat(subject.boxWidth) * scaleX
            let boxHeight = CGFloat(subject.boxHeight) * scaleY
            let side = min(max(boxWidth, boxHeight) * 1.20, min(fullSize.width, fullSize.height))
            let centreX = (CGFloat(subject.minX) + CGFloat(subject.boxWidth) / 2) * scaleX
            // Core Image's origin is bottom-left; the mask's is top-left.
            let centreY = fullSize.height - (CGFloat(subject.minY) + CGFloat(subject.boxHeight) / 2) * scaleY
            crop = CGRect(x: centreX - side / 2, y: centreY - side / 2, width: side, height: side)
            crop.origin.x = min(max(0, crop.origin.x), fullSize.width - side)
            crop.origin.y = min(max(0, crop.origin.y), fullSize.height - side)
        } else {
            let side = min(fullSize.width, fullSize.height)
            crop = CGRect(x: (fullSize.width - side) / 2, y: (fullSize.height - side) / 2,
                          width: side, height: side)
        }

        let cropped = composed.cropped(to: crop)
        let target: CGFloat = 1200
        let scale = min(1, target / max(crop.width, crop.height))
        let scaled = cropped
            .transformed(by: CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cg = context.createCGImage(scaled, from: CGRect(origin: .zero,
                                                                  size: CGSize(width: crop.width * scale,
                                                                               height: crop.height * scale))) else {
            return UIImage(ciImage: full)
        }
        return UIImage(cgImage: cg)
    }

    // MARK: 6 — Feature prints and duplicates

    static func featurePrint(for image: UIImage) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNFeaturePrintObservation else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    /// 0…1, where 1 is the same photograph. The Vision distance is unbounded in
    /// principle; in practice two shots of the same toy land under 0.8 and two
    /// different toys land well above it, so the map is linear over 0…2.
    static func similarity(_ a: Data, _ b: Data) -> Double {
        guard let left = unarchive(a), let right = unarchive(b) else { return 0 }
        var distance = Float.greatestFiniteMagnitude
        guard (try? left.computeDistance(&distance, to: right)) != nil else { return 0 }
        return max(0, min(1, 1 - Double(distance) / 2))
    }

    private static func unarchive(_ data: Data) -> VNFeaturePrintObservation? {
        guard !data.isEmpty else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    // MARK: Pixel helpers

    private static func analysisSize(for size: CGSize) -> (width: Int, height: Int) {
        let longest = max(size.width, size.height)
        let scale = min(1, CGFloat(analysisEdge) / longest)
        return (max(1, Int(size.width * scale)), max(1, Int(size.height * scale)))
    }

    /// Rows run top-down, origin top-left — the same convention the mask,
    /// the depth map and Core Graphics all use. Every pixel index in this file
    /// is in that space.
    private static func bitmap(from image: CGImage, size: (width: Int, height: Int)) -> [UInt8]? {
        let count = size.width * size.height * 4
        let data = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 8)
        defer { data.deallocate() }
        data.initializeMemory(as: UInt8.self, repeating: 0, count: count)

        guard let ctx = CGContext(data: data,
                                  width: size.width,
                                  height: size.height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: size.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return [UInt8](UnsafeRawBufferPointer(start: data, count: count))
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
