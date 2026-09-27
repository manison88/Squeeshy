// Runs the app's exact subject-lift pipeline against real photographs, outside the
// simulator, and reports what it found. AppKit rather than UIKit so it can be run
// straight from the command line:
//
//     swift Tools/liftcheck.swift TestPhotos
//
// Writes each cut-out to /tmp/lift_<name>.png with a transparent background.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

let ciContext = CIContext(options: [.useSoftwareRenderer: false])

func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
    guard mask.extent.width > 0, mask.extent.height > 0 else { return mask }
    return mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                  y: extent.height / mask.extent.height))
}

func skinMask(from request: VNGeneratePersonSegmentationRequest, matching extent: CGRect) -> CIImage? {
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

func maskStats(_ image: CIImage, extent: CGRect) -> (area: Double, cx: Double, cy: Double)? {
    let side = 48
    let scale = CGAffineTransform(scaleX: CGFloat(side)/extent.width, y: CGFloat(side)/extent.height)
    guard let cg = ciContext.createCGImage(image.transformed(by: scale),
                                           from: CGRect(x: 0, y: 0, width: side, height: side)) else { return nil }
    var raw = [UInt8](repeating: 0, count: side*side*4)
    guard let ctx = CGContext(data: &raw, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: side*4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
    var n = 0; var sx = 0.0; var sy = 0.0
    for y in 0..<side { for x in 0..<side where raw[(y*side+x)*4] > 128 {
        n += 1; sx += Double(x); sy += Double(y) } }
    guard n > 0 else { return nil }
    return (Double(n)/Double(side*side), sx/Double(n)/Double(side), sy/Double(n)/Double(side))
}

func cropToSubject(_ cg: CGImage, margin: CGFloat = 0.04) -> (CGImage, Double)? {
    let side = 96
    var raw = [UInt8](repeating: 0, count: side*side*4)
    guard let ctx = CGContext(data: &raw, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: side*4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
    var minX = side, minY = side, maxX = -1, maxY = -1
    for y in 0..<side { for x in 0..<side where raw[(y*side+x)*4+3] > 40 {
        minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y) } }
    guard maxX > minX, maxY > minY else { return nil }
    let coverage = Double((maxX-minX)*(maxY-minY))/Double(side*side)
    guard coverage > 0.02, coverage < 0.985 else { return nil }
    let w = CGFloat(cg.width), h = CGFloat(cg.height), pad = margin*max(w,h)
    // Top-down, matching the scan and cropping(to:). See SubjectLift.cropToSubject.
    let rect = CGRect(x: CGFloat(minX)/CGFloat(side)*w - pad,
                      y: CGFloat(minY)/CGFloat(side)*h - pad,
                      width: CGFloat(maxX-minX+1)/CGFloat(side)*w + pad*2,
                      height: CGFloat(maxY-minY+1)/CGFloat(side)*h + pad*2)
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard let cropped = cg.cropping(to: rect) else { return nil }
    return (cropped, coverage)
}

func lift(_ url: URL) -> (CGImage, String)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }

    let foreground = VNGenerateForegroundInstanceMaskRequest()
    let person = VNGeneratePersonSegmentationRequest()
    person.qualityLevel = .accurate
    person.outputPixelFormat = kCVPixelFormatType_OneComponent8

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    do { try handler.perform([foreground, person]) }
    catch { print("  perform failed: \(error)"); return nil }

    guard let result = foreground.results?.first, !result.allInstances.isEmpty else {
        print("  no foreground instances"); return nil
    }

    let source = CIImage(cgImage: cgImage)
    let notPerson = skinMask(from: person, matching: source.extent)
    print("  instances: \(result.allInstances.count)  person detected: \(notPerson != nil)")

    // Score every instance by what survives the hand being cut out of it.
    var best: Int?
    var bestScore = 0.0
    var bestSubtract = true
    var log: [String] = []
    for instance in result.allInstances {
        guard let buffer = try? result.generateScaledMaskForImage(forInstances: IndexSet(integer: instance),
                                                                  from: handler) else { continue }
        var mask = scaled(CIImage(cvPixelBuffer: buffer), to: source.extent)
        let rawStats = maskStats(mask, extent: source.extent)
        if let notPerson {
            let cut = CIFilter.multiplyCompositing()
            cut.inputImage = mask; cut.backgroundImage = notPerson
            mask = cut.outputImage ?? mask
        }
        var stats = maskStats(mask, extent: source.extent)
        var subtracted = true
        // When the person mask claims nearly everything, it is wrong far more often
        // than the instance is genuinely a hand. Fall back to the raw instance.
        let remaining = (stats?.area ?? 0) / max(rawStats?.area ?? 1, 0.0001)
        if remaining < 0.08 {
            stats = rawStats
            subtracted = false
            mask = scaled(CIImage(cvPixelBuffer: buffer), to: source.extent)
        }
        guard let stats else {
            log.append(String(format: "    inst %d: nothing at all", instance))
            continue
        }
        if !subtracted {
            log.append(String(format: "    inst %d: person mask ignored (claimed everything)", instance))
        }
        let dx = stats.cx - 0.5, dy = stats.cy - 0.5
        let off = min(1, (dx*dx+dy*dy).squareRoot()/0.707)
        let score = stats.area * (1 - off*0.75)
        log.append(String(format: "    inst %d: area %.3f -> %.3f  score %.3f",
                          instance, rawStats?.area ?? 0, stats.area, score))
        if score > bestScore { bestScore = score; best = instance; bestSubtract = subtracted }
    }
    log.forEach { print($0) }
    guard let best else { print("  everything was skin"); return nil }

    guard let buffer = try? result.generateScaledMaskForImage(forInstances: IndexSet(integer: best),
                                                              from: handler) else { return nil }
    var mask = scaled(CIImage(cvPixelBuffer: buffer), to: source.extent)
    if bestSubtract, let notPerson {
        let cut = CIFilter.multiplyCompositing()
        cut.inputImage = mask; cut.backgroundImage = notPerson
        mask = cut.outputImage ?? mask
    }
    let erode = CIFilter.morphologyMinimum()
    erode.inputImage = mask
    erode.radius = Float(max(1, min(source.extent.width, source.extent.height)*0.0025))
    let feather = CIFilter.gaussianBlur()
    feather.inputImage = erode.outputImage
    feather.radius = Float(max(0.8, min(source.extent.width, source.extent.height)*0.0018))
    guard let refined = feather.outputImage?.cropped(to: source.extent) else { return nil }

    let blend = CIFilter.blendWithMask()
    blend.inputImage = source
    blend.backgroundImage = CIImage.empty()
    blend.maskImage = refined
    guard let out = blend.outputImage,
          let cg = ciContext.createCGImage(out, from: source.extent) else { return nil }
    guard let (cropped, coverage) = cropToSubject(cg) else {
        print("  rejected: coverage guard"); return nil
    }
    return (cropped, String(format: "chose inst %d, coverage %.2f", best, coverage))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "TestPhotos"
let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
    .filter { ["jpg","jpeg","png","heic"].contains($0.lowercased().split(separator: ".").last.map(String.init) ?? "") }
    .sorted()

if files.isEmpty { print("No images in \(dir)/") }
for f in files {
    print("\(f):")
    if let (cg, note) = lift(URL(fileURLWithPath: dir + "/" + f)) {
        print("  OK  \(note)  \(cg.width)x\(cg.height)")
        let out = "/tmp/lift_" + f.replacingOccurrences(of: ".", with: "_") + ".png"
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: out))
        print("  wrote \(out)")
    } else {
        print("  FAILED")
    }
}
