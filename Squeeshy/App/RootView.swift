import SwiftUI
import SwiftData

/// One screen. There is nowhere else to go in this app — a tab bar with a single
/// destination in it is just a strip of dead pixels — so the camera sits in the
/// Collections header with the other controls and the list runs clear to the bottom.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FriendsStore.self) private var friendsStore
    @Query private var squishies: [Squishy]

    @State private var showCapture = false
    @State private var showImport = false
    @State private var collectionsPath = NavigationPath()
    /// Survives launches, and is applied to the whole app below.
    @AppStorage("appTheme") private var themeRaw = AppTheme.dark.rawValue

    /// Pairs the header camera button with the capture screen so the sheet grows out
    /// of the button rather than sliding up from nowhere.
    @Namespace private var captureTransition

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .dark }

    var body: some View {
        ZStack {
            // Matches AdaptiveBackground's ground in both schemes; it only shows for
            // the instant before a screen paints over it, and a hardcoded near-black
            // here flashed against a light app.
            AdaptiveBackground(tint: .fallback)

            Group {
                #if DEBUG
                if DebugLaunch.openModel {
                    ModelViewerPreviewHarness()
                } else {
                    collections
                }
                #else
                collections
                #endif
            }
            .transition(.opacity)
        }
        .task {
            // Nothing is seeded any more; this clears whatever a previous build seeded,
            // so the shelves describe a real collection rather than eighteen drawn ones.
            SeedData.removeSamples(context)
            #if DEBUG
            if DebugLaunch.uiTestReset { SeedData.resetForUITests(context) }
            if DebugLaunch.uiTestSeed { SeedData.installUITestFixtures(context) }
            if DebugLaunch.openCapture || DebugLaunch.captureSample || DebugLaunch.reviewSample {
                showCapture = true
            }
            if DebugLaunch.importPhotos { showImport = true }
            if DebugLaunch.renderShareCards { dumpShareCards() }
            if let after = DebugLaunch.flipThemeAfter {
                DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                    themeRaw = theme == .dark ? AppTheme.light.rawValue : AppTheme.dark.rawValue
                }
            }
            #endif
        }
        // Friends: sign in, publish the shelf whenever what friends can see changes,
        // and catch up whenever the app comes back to the front.
        .task { await friendsStore.start() }
        .onChange(of: shelfSignature) { friendsStore.schedulePublish() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await friendsStore.refresh() } }
        }
        .alert(shareBackTitle,
               isPresented: Binding(get: { friendsStore.pendingShareBack != nil },
                                    set: { if !$0 { friendsStore.pendingShareBack = nil } })) {
            Button("Share mine") {
                friendsStore.pendingShareBack = nil
                Task {
                    // Let the alert finish dismissing, or the sharing sheet has
                    // nothing to present from and silently fails.
                    try? await Task.sleep(for: .seconds(0.5))
                    if let share = try? await friendsStore.shareForInvite() {
                        CloudSharing.present(share: share, container: friendsStore.container,
                                             title: "\(friendsStore.displayName)'s squeeshies")
                    }
                }
            }
            Button("Not now", role: .cancel) { friendsStore.pendingShareBack = nil }
        } message: {
            Text("Friends see each other's squeeshies. Share yours back so \(friendsStore.pendingShareBack?.name ?? "they") can see what you have.")
        }
        .sheet(isPresented: $showCapture) {
            CaptureView()
                .navigationTransition(.zoom(sourceID: "capture", in: captureTransition))
        }
        #if DEBUG
        // A second .sheet on the same view is silently ignored by SwiftUI, so the
        // importer uses a cover instead — which suits a blocking operation anyway.
        .fullScreenCover(isPresented: $showImport) { ImportOverlay() }
        #endif
        // Applied once, at the root, so sheets and covers inherit it too.
        .preferredColorScheme(theme.colorScheme)
    }

    /// Changes whenever anything a friend could see changes.
    private var shelfSignature: [String] {
        squishies.map { "\($0.lineageID)|\($0.shelfRevision)|\($0.quantity)" }
    }

    private var shareBackTitle: String {
        "You can see \(friendsStore.pendingShareBack?.name ?? "your friend")'s squeeshies"
    }

    private var collections: some View {
        CollectionsView(path: $collectionsPath,
                        theme: $themeRaw,
                        captureTransition: captureTransition,
                        onCapture: { showCapture = true })
    }

    private var shelfTint: Tint {
        Tint.sampled(from: squishies.map(\.hue))
    }

    #if DEBUG
    /// Writes the three share cards into Documents for inspection.
    private func dumpShareCards() {
        guard let first = squishies.first else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let scopes: [(String, ShareScope)] = [
            ("card-single.png", .single(first)),
            ("card-shelf.png", .shelf(title: "Warm colours",
                                      items: squishies.filter { SmartShelf.warm.matches($0) })),
            ("card-everything.png", .everything(items: squishies))
        ]
        for (name, scope) in scopes {
            if let url = ShareRenderer.png(for: scope) {
                let dest = docs.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
            }
        }
    }
    #endif
}

