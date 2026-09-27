import SwiftUI
import SwiftData

/// One screen. There is nowhere else to go in this app — a tab bar with a single
/// destination in it is just a strip of dead pixels — so the camera sits in the
/// Collections header with the other controls and the list runs clear to the bottom.
struct RootView: View {
    @Environment(\.modelContext) private var context
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

