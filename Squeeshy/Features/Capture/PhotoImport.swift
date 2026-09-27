import SwiftUI
import SwiftData
import UIKit

extension UIImage {
    /// True when the image has an alpha channel carrying actual transparency, which
    /// means it is already a cut-out rather than a photograph.
    var hasTransparency: Bool {
        guard let cg = cgImage else { return false }
        switch cg.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            break
        default:
            return false
        }
        // Sample the corners: a cut-out is transparent at its edges, a photo is not.
        let side = 16
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &raw, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let corners = [0, side - 1, side * (side - 1), side * side - 1]
        return corners.contains { raw[$0 * 4 + 3] < 30 }
    }
}

#if DEBUG
/// Bulk-imports real photographs through the exact capture pipeline, so the app can
/// be filled with actual squeeshies without shooting each one by hand.
///
/// Drop images into the app container's `Documents/Import/` and launch with
/// `-importPhotos`. Each one is lifted off its background, its traits read from the
/// pixels, and saved as a real record. Anything the lift rejects is reported rather
/// than silently skipped, because a failed import is the interesting case.
enum PhotoImport {

    struct Report {
        var imported: [String] = []
        var rejected: [String] = []
    }

    static var importDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Import", isDirectory: true)
    }

    static func pendingFiles() -> [URL] {
        let allowed = ["jpg", "jpeg", "png", "heic", "heif"]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: importDirectory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @MainActor
    static func run(into context: ModelContext) async -> Report {
        var report = Report()

        for url in pendingFiles() {
            let name = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                report.rejected.append("\(name): unreadable")
                continue
            }

            // An image that already carries transparency has been cut out elsewhere,
            // so it is taken as-is. That is how real squeeshies get into the app in
            // the simulator, where Vision's segmentation models refuse to load at all
            // ("Could not create inference context") — the lift runs on device and on
            // macOS, but never here.
            let cutout: UIImage
            if image.hasTransparency {
                cutout = image
            } else if let lifted = await SubjectLift.cutout(from: image) {
                cutout = lifted
            } else {
                report.rejected.append("\(name): no subject found")
                continue
            }

            let traits = SubjectLift.traits(from: cutout)
            let squishy = Squishy(name: name,
                                  species: traits.species,
                                  hue: traits.hue,
                                  size: .medium,
                                  squeeshiness: 7,
                                  typeName: "")
            squishy.saturation = traits.saturation
            squishy.photoFilename = PhotoStore.save(cutout)
            context.insert(squishy)
            report.imported.append("\(name): \(Hue.name(traits.hue)), \(traits.species.shapeName)")
        }

        try? context.save()
        return report
    }
}

/// Shown while a bulk import runs, and afterwards so the outcome is visible rather
/// than something you have to go digging in the log for.
struct ImportOverlay: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var report: PhotoImport.Report?
    @State private var running = true

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: .fallback)
            VStack(alignment: .leading, spacing: 16) {
                MetaLabel(text: running ? "isolating squeeshies" : "import finished")
                    .padding(.top, 24)

                if running {
                    HStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("\(PhotoImport.pendingFiles().count) photos")
                            .font(.display(20, .bold))
                            .foregroundStyle(Color.ink)
                    }
                } else if let report {
                    Text("\(report.imported.count) in, \(report.rejected.count) rejected")
                        .font(.display(24, .heavy))
                        .foregroundStyle(Color.ink)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(report.imported, id: \.self) { line in
                                Label(line, systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.ink2)
                            }
                            ForEach(report.rejected, id: \.self) { line in
                                Label(line, systemImage: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.55))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    Button("Done") { dismiss() }
                        .buttonStyle(SheetButton(filled: true, tint: Tint.fallback.primary))
                        .padding(.bottom, 20)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .task {
            report = await PhotoImport.run(into: context)
            running = false
        }
    }
}
#endif
