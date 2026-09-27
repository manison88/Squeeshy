import Foundation

#if DEBUG
/// Lets a debug build be launched straight onto a deep screen, so screens below the
/// front door can be opened without tapping through:
///
///     xcrun simctl launch <device> com.squeeshy.app -openShelf everything -openItem 1
enum DebugLaunch {
    private static func value(for flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var openShelf: SmartShelf? {
        value(for: "-openShelf").flatMap(SmartShelf.init(rawValue:))
    }

    /// Index into the shelf, used to land on a squeeshy's detail view.
    static var openItem: Int? {
        value(for: "-openItem").flatMap(Int.init)
    }

    /// Opens play mode straight from the item detail screen.
    static var openPlay: Bool {
        ProcessInfo.processInfo.arguments.contains("-openPlay")
    }

    /// Freezes play mode mid-gesture so the deformation can be screenshotted:
    /// `-playHold stretch` or `-playHold squash`.
    static var playHold: String? { value(for: "-playHold") }

    /// Which way the frozen grab pulls: `top`, `left`, or `corner`.
    static var playAxis: String? { value(for: "-playAxis") }

    /// Flips the theme this many seconds after launch, so a *runtime* scheme change can
    /// be screenshotted. Launching straight into light mode does not reproduce bugs that
    /// only appear when the scheme changes under a live view.
    static var flipThemeAfter: Double? {
        value(for: "-flipThemeAfter").flatMap(Double.init)
    }

    static var openRating: Bool {
        ProcessInfo.processInfo.arguments.contains("-openRating")
    }

    static var openCapture: Bool {
        ProcessInfo.processInfo.arguments.contains("-openCapture")
    }

    /// Shows the 3D viewer against the bundled stand-in mesh.
    static var openModel: Bool {
        ProcessInfo.processInfo.arguments.contains("-openModel")
    }

    /// Bulk-imports whatever is sitting in the app container's Documents/Import/.
    static var importPhotos: Bool {
        ProcessInfo.processInfo.arguments.contains("-importPhotos")
    }

    /// Puts a handful of squeeshies in an empty store so the UI tests have something to
    /// tap. Nothing else seeds any more, and a UI test cannot photograph anything.
    static var uiTestSeed: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestSeed")
    }

    /// Wipes the store and the app's own defaults before seeding, so each UI test starts
    /// from the same place. Without it a test that renames a squeeshy or pins a shelf
    /// leaves that behind and every later test sees a different app.
    static var uiTestReset: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestReset")
    }

    /// Renders all three share cards to Documents so the exported PNGs can be
    /// inspected without going through the system share sheet.
    static var renderShareCards: Bool {
        ProcessInfo.processInfo.arguments.contains("-renderShareCards")
    }

    /// Runs a synthesised photo through the real subject-lift pipeline. The simulator
    /// has no camera, so this is the only way to exercise capture without a device.
    static var captureSample: Bool {
        ProcessInfo.processInfo.arguments.contains("-captureSample")
    }

    /// Jumps straight to the review screen with a stand-in cut-out, so the layout can
    /// be checked without a camera. The lift itself is exercised by `-captureSample`.
    static var reviewSample: Bool {
        ProcessInfo.processInfo.arguments.contains("-reviewSample")
    }
}

#if canImport(UIKit)
import UIKit

/// A stand-in photo: a plush-looking subject sitting on a surface, with the kind of
/// background the lift is supposed to remove.
enum SampleShot {
    static func make() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext

            // Background: a warm surface with a soft vignette, so there is something
            // real for the mask to reject.
            let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [UIColor(red: 0.83, green: 0.78, blue: 0.71, alpha: 1).cgColor,
                                         UIColor(red: 0.62, green: 0.56, blue: 0.50, alpha: 1).cgColor] as CFArray,
                                locations: [0, 1])!
            cg.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            // Contact shadow.
            cg.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
            cg.fillEllipse(in: CGRect(x: 250, y: 830, width: 400, height: 90))

            // Body.
            let body = UIColor(red: 0.98, green: 0.62, blue: 0.76, alpha: 1)
            cg.setFillColor(body.cgColor)
            cg.fillEllipse(in: CGRect(x: 190, y: 420, width: 520, height: 470))
            cg.fillEllipse(in: CGRect(x: 215, y: 350, width: 150, height: 150))
            cg.fillEllipse(in: CGRect(x: 535, y: 350, width: 150, height: 150))

            // Belly and face, so the colour sample has something to average.
            cg.setFillColor(UIColor(white: 1, alpha: 0.30).cgColor)
            cg.fillEllipse(in: CGRect(x: 330, y: 640, width: 240, height: 190))
            cg.setFillColor(UIColor(red: 0.16, green: 0.13, blue: 0.19, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: 350, y: 590, width: 42, height: 52))
            cg.fillEllipse(in: CGRect(x: 508, y: 590, width: 42, height: 52))
        }
    }

    /// The same subject with no background at all, standing in for a successful lift.
    static func cutout() -> UIImage {
        let size = CGSize(width: 560, height: 560)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let body = UIColor(red: 0.98, green: 0.62, blue: 0.76, alpha: 1)
            cg.setFillColor(body.cgColor)
            cg.fillEllipse(in: CGRect(x: 20, y: 40, width: 130, height: 130))
            cg.fillEllipse(in: CGRect(x: 410, y: 40, width: 130, height: 130))
            cg.fillEllipse(in: CGRect(x: 30, y: 110, width: 500, height: 430))
            cg.setFillColor(UIColor(white: 1, alpha: 0.30).cgColor)
            cg.fillEllipse(in: CGRect(x: 170, y: 320, width: 220, height: 180))
            cg.setFillColor(UIColor(red: 0.16, green: 0.13, blue: 0.19, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: 195, y: 270, width: 40, height: 50))
            cg.fillEllipse(in: CGRect(x: 325, y: 270, width: 40, height: 50))
            cg.setFillColor(UIColor(red: 1, green: 0.45, blue: 0.6, alpha: 0.5).cgColor)
            cg.fillEllipse(in: CGRect(x: 140, y: 330, width: 60, height: 38))
            cg.fillEllipse(in: CGRect(x: 360, y: 330, width: 60, height: 38))
        }
    }
}
#endif
#endif
