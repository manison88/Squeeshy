import SwiftUI

// MARK: - Scope
//
// Three things worth sharing: one squeeshy, one shelf, or the lot. Same renderer,
// three layouts, each tinted from whatever it contains.

enum ShareScope: Identifiable {
    case single(Squishy)
    case shelf(title: String, items: [Squishy])
    case everything(items: [Squishy])

    var id: String {
        switch self {
        case let .single(s):        return "single-\(s.id)"
        case let .shelf(title, _):  return "shelf-\(title)"
        case .everything:           return "everything"
        }
    }

    var items: [Squishy] {
        switch self {
        case let .single(s):     return [s]
        case let .shelf(_, i):   return i
        case let .everything(i): return i
        }
    }

    var filename: String {
        switch self {
        case let .single(s):       return "\(s.name).png"
        case let .shelf(title, _): return "\(title).png"
        case .everything:          return "My squeeshies.png"
        }
    }
}

// MARK: - The card

/// Rendered off-screen to a PNG, so it has to hold up at 3x with no scroll view, no
/// safe area and no interaction. Everything here is deliberately fixed-size.
struct ShareCard: View {
    var scope: ShareScope

    private var items: [Squishy] { scope.items }
    private var tint: Tint { Tint.sampled(from: items.map(\.hue)) }
    private var average: Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.squeeshiness).reduce(0, +) / Double(items.count)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: tint)
            switch scope {
            case let .single(squishy): singleCard(squishy)
            case let .shelf(title, _): gridCard(title: title)
            case .everything:          gridCard(title: "My squeeshies")
            }
        }
        .frame(width: 900, height: 1200)
        .background(Color(red: 0.031, green: 0.027, blue: 0.051))
    }

    // MARK: One squeeshy

    private func singleCard(_ squishy: Squishy) -> some View {
        VStack(spacing: 0) {
            Spacer()

            SquishyImage(squishy: squishy)
                .frame(width: 460, height: 460)
                .shadow(color: squishy.color.opacity(0.5), radius: 70, y: 30)

            Text(squishy.name)
                .font(.system(size: 84, weight: .heavy))
                .kerning(-3)
                .foregroundStyle(Color.ink)
                .padding(.top, 46)

            Text(squishy.traitLine.uppercased())
                .font(.system(size: 21, weight: .regular, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Color.ink2)
                .padding(.top, 16)

            HStack(spacing: 16) {
                Text(String(format: "%.1f", squishy.squeeshiness))
                    .font(.system(size: 62, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.05, green: 0.04, blue: 0.08))
                    .padding(.horizontal, 34)
                    .padding(.vertical, 12)
                    .background(tint.primary, in: .capsule)
                Text("squeeshiness")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.ink2)
            }
            .padding(.top, 44)

            if squishy.quantity > 1 {
                Text("×\(squishy.quantity) in the collection")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 20)
            }

            Spacer()
            wordmark
        }
        .padding(60)
    }

    // MARK: A shelf, or everything

    private func gridCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 66, weight: .heavy))
                .kerning(-2.4)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            Text("\(items.count) squeeshies · average \(String(format: "%.1f", average))".uppercased())
                .font(.system(size: 20, weight: .regular, design: .monospaced))
                .tracking(2.6)
                .foregroundStyle(Color.ink2)
                .padding(.top, 14)

            Spacer(minLength: 30)

            // Column count follows the collection size, so six squeeshies fill the
            // card as convincingly as sixty.
            let columns = gridColumns
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns),
                      spacing: 20) {
                ForEach(items.prefix(48)) { squishy in
                    VStack(spacing: 8) {
                        SquishyImage(squishy: squishy)
                            .frame(height: tileSize)
                        if columns <= 4 {
                            Text(squishy.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.ink2)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if items.count > 48 {
                Text("+ \(items.count - 48) more")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 24)
            }

            Spacer(minLength: 30)
            wordmark
        }
        .padding(60)
    }

    /// Four columns is the widest layout that still fits a name under each squeeshy,
    /// so it is held onto as long as the tiles stay a reasonable size.
    private var gridColumns: Int {
        switch items.count {
        case ..<5:  return 2
        case ..<10: return 3
        case ..<21: return 4
        case ..<37: return 5
        default:    return 6
        }
    }

    private var tileSize: CGFloat {
        switch gridColumns {
        case 2: return 260
        case 3: return 190
        case 4: return 150
        case 5: return 118
        default: return 96
        }
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(colors: [tint.primary, tint.secondary],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
            Text("Squeeshy")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.ink2)
            Spacer()
        }
    }
}

// MARK: - Rendering and presenting

enum ShareRenderer {
    /// ImageRenderer runs on the main actor and is fast enough at this size that the
    /// share sheet can be presented straight afterwards without a spinner.
    @MainActor
    static func png(for scope: ShareScope) -> URL? {
        let renderer = ImageRenderer(content: ShareCard(scope: scope))
        renderer.scale = 2
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }

        // Written under a sanitised name so the share sheet shows something readable
        // rather than a UUID.
        let safe = scope.filename.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// UIActivityViewController, because a PNG belongs wherever the owner already posts.
struct ShareSheet: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Attaches a share flow to any view: render on demand, then present.
struct SharePresenter: ViewModifier {
    @Binding var scope: ShareScope?
    @State private var url: URL?

    func body(content: Content) -> some View {
        content
            .onChange(of: scope?.id) { _, _ in
                guard let scope else { url = nil; return }
                url = ShareRenderer.png(for: scope)
            }
            .sheet(item: Binding(get: { url.map(ShareURL.init) },
                                 set: { if $0 == nil { url = nil; scope = nil } })) { wrapper in
                ShareSheet(url: wrapper.url)
            }
    }
}

private struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension View {
    func shareCard(_ scope: Binding<ShareScope?>) -> some View {
        modifier(SharePresenter(scope: scope))
    }
}
