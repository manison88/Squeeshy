import SwiftData
import SwiftUI

@main
struct SquishIndexApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            // The app has a CloudKit entitlement for friends and trading, and
            // SwiftData would otherwise mirror the whole catalogue into iCloud
            // on its own — which this model can't support (unique `id`,
            // non-optional fields) and the design doesn't want: the catalogue
            // stays on device; only the shared shelf goes to CloudKit.
            container = try ModelContainer(for: Squishy.self,
                                           configurations: ModelConfiguration(cloudKitDatabase: .none))
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
