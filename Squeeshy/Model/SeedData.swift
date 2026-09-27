import Foundation
import SwiftData

/// The demo shelf. Nothing installs it any more — the library is whatever has actually
/// been photographed, so shelves reflect a real collection instead of eighteen drawn
/// stand-ins. What remains here is the clean-up for devices that were seeded before.
enum SeedData {

    /// Removes anything left over from when the demo shelf was installed on first
    /// launch: the sample squeeshies, and the two starter shelves *if they are still
    /// empty*. A starter shelf someone has actually filled is theirs now and stays.
    static func removeSamples(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Squishy>(predicate: #Predicate { $0.isSample })
        let samples = (try? context.fetch(descriptor)) ?? []
        guard !samples.isEmpty else { return }

        for s in samples {
            PhotoStore.delete(s.photoFilename)
            context.delete(s)
        }

        let seededNames: Set<String> = ["Favourites", "On my bed"]
        let shelves = (try? context.fetch(FetchDescriptor<Shelf>())) ?? []
        for shelf in shelves where seededNames.contains(shelf.name) && (shelf.items ?? []).isEmpty {
            context.delete(shelf)
        }

        try? context.save()
    }

    #if DEBUG
    /// Empties the store and the defaults the app owns, so a UI test run is repeatable.
    static func resetForUITests(_ context: ModelContext) {
        for s in (try? context.fetch(FetchDescriptor<Squishy>())) ?? [] {
            PhotoStore.delete(s.photoFilename)
            context.delete(s)
        }
        for shelf in (try? context.fetch(FetchDescriptor<Shelf>())) ?? [] {
            context.delete(shelf)
        }
        try? context.save()
        for key in ["pinnedSmartShelves", "appTheme", "bgStyle", "glowStrength", "playGain"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Test fixtures, not a demo shelf. Only `-uiTestSeed` calls this.
    static func installUITestFixtures(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Squishy>())) ?? 0
        guard existing == 0 else { return }

        let rows: [(String, Species, Double, SizeClass, Double)] = [
            ("Mochi", .round, 337, .medium, 9.4),
            ("Kai",   .axo,   203, .large,  8.1),
            ("Toast", .loaf,  42,  .small,  6.5)
        ]
        for (i, r) in rows.enumerated() {
            let s = Squishy(name: r.0, species: r.1, hue: r.2, size: r.3,
                            squeeshiness: r.4, typeName: "",
                            addedAt: Date().addingTimeInterval(-Double(i) * 86_400))
            context.insert(s)
        }
        context.insert(Shelf(name: "Test shelf"))
        try? context.save()
    }
    #endif
}
