import SwiftData
import SwiftUI

@main
struct SquishIndexApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Squishy.self)
        } catch {
            // A store that will not open is not recoverable in-app, and a
            // silent in-memory fallback would quietly lose a collection.
            fatalError("Could not open the specimen index: \(error)")
        }
        FriendsStore.shared.attach(container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // The locked palette has no dark variant, and inverting putty
                // and ink would be a redesign. v1 is light-only, deliberately.
                // UX-SPEC §9 Q2.
                .preferredColorScheme(.light)
                .tint(SquishTheme.ink)
                .environment(FriendsStore.shared)
        }
        .modelContainer(container)
    }
}
