import UIKit

/// Cut-outs live on disk, not in the database. SwiftData rows stay small and the
/// files are the natural thing to hand to R2 once the Cloudflare layer lands.
enum PhotoStore {

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cutouts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Writes a PNG so the alpha from subject lifting survives, and returns the
    /// filename to store on the model.
    @discardableResult
    static func save(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let filename = "\(UUID().uuidString).png"
        do {
            try data.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        return UIImage(contentsOfFile: url(for: filename).path)
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}

// MARK: - In-memory cache
//
// The field redraws every frame and the collections list scrolls; decoding a PNG on
// each pass would be visible. Cutouts are small and few, so they are simply kept.

@Observable
final class CutoutCache {
    static let shared = CutoutCache()
    @ObservationIgnored private var images: [String: UIImage] = [:]

    func image(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        if let cached = images[filename] { return cached }
        guard let loaded = PhotoStore.load(filename) else { return nil }
        images[filename] = loaded
        return loaded
    }

    func forget(_ filename: String?) {
        guard let filename else { return }
        images.removeValue(forKey: filename)
    }
}
