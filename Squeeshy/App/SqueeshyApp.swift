import SwiftUI
import SwiftData

@main
struct SqueeshyApp: App {
    var body: some Scene {
        WindowGroup {
            // No scheme forced here: RootView applies the stored theme, and a
            // hardcoded .dark at the scene root sits outside it and wins.
            RootView()
        }
        .modelContainer(for: [Squishy.self, Shelf.self])
    }
}
