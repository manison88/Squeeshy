import SwiftUI
import SwiftData

@main
struct SqueeshyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            // The app now carries a CloudKit entitlement for friends and trading,
            // and SwiftData would otherwise start mirroring the whole collection into
            // iCloud on its own — rows without their cut-outs, which live on disk.
            // The collection stays on this device; only the shared shelf zone that
            // FriendsStore manages goes to iCloud.
            container = try ModelContainer(for: Squishy.self, Shelf.self,
                                           configurations: ModelConfiguration(cloudKitDatabase: .none))
        } catch {
            fatalError("Could not open the collection: \(error)")
        }
        FriendsStore.shared.attach(container)
        #if DEBUG
        if FriendsSelfTest.isRequested {
            let container = container
            Task { @MainActor in await FriendsSelfTest.run(container: container) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // No scheme forced here: RootView applies the stored theme, and a
            // hardcoded .dark at the scene root sits outside it and wins.
            RootView()
                .environment(FriendsStore.shared)
        }
        .modelContainer(container)
    }
}
