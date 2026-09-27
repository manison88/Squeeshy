import SwiftUI

// MARK: - Adaptive palette
//
// Squeeshy has no palette of its own. Every screen samples the collection it is
// showing and tints itself from those squeeshies, so a pink shelf makes a pink app.

struct Tint: Equatable {
    var primary: Color
    var secondary: Color

    static let fallback = Tint(
        primary: Color(hue: 0.94, saturation: 0.42, brightness: 1.0),
        secondary: Color(hue: 0.56, saturation: 0.38, brightness: 1.0)
    )

    /// Derives a two-stop tint from whatever is on the shelf.
    ///
    /// The primary is the shelf's *most common* hue, not its average: averaging a
    /// mixed shelf lands on a colour nothing in it actually is. The secondary is an
    /// analogous neighbour rather than the furthest hue, because complementary pairs
    /// go muddy where they meet and the background is mostly meeting.
    static func sampled(from hues: [Double]) -> Tint {
        guard !hues.isEmpty else { return .fallback }
        let ranked = rankedHues(hues)
        let dominant = ranked.first ?? 0
        // Prefer the shelf's second most common colour, so the gradient is made of
        // two things it actually contains. Fall back to a near neighbour when the
        // runner-up is far enough round the wheel to go muddy against the primary.
        let runnerUp = ranked.dropFirst().first
        let secondary: Double
        if let r = runnerUp, Hue.distance(r, dominant) <= 90 {
            secondary = r
        } else {
            secondary = dominant + 26
        }
        return Tint(primary: pastel(dominant), secondary: pastel(secondary))
    }

    /// Buckets hues into twelve 30-degree bins and returns each bin's circular mean,
    /// most populated first, so tints always come from colours the shelf really has.
    private static func rankedHues(_ hues: [Double]) -> [Double] {
        var bins: [Int: [Double]] = [:]
        for h in hues {
            let bin = Int(Hue.wrap(h) / 30) % 12
            bins[bin, default: []].append(Hue.wrap(h))
        }
        // Sorted by count then bin index, so the same shelf always resolves the same
        // way instead of flickering between equally populated bins.
        return bins
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map { Hue.circularMean(of: $0.value) }
    }

    /// Tint for a single known hue — one squeeshy, or a fresh capture. Going through
    /// `sampled` here would bucket the pair and could pick the wrong end of it.
    static func single(_ hue: Double) -> Tint {
        Tint(primary: pastel(hue), secondary: pastel(hue + 28))
    }

    private static func pastel(_ degrees: Double) -> Color {
        Color(hue: Hue.wrap(degrees) / 360, saturation: 0.40, brightness: 1.0)
    }
}

enum Hue {
    static func wrap(_ d: Double) -> Double {
        let m = d.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    /// Shortest angular distance between two hues, 0...180.
    static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(wrap(a) - wrap(b))
        return d > 180 ? 360 - d : d
    }

    /// Mean of angles, done on the unit circle so 350 and 10 average to 0, not 180.
    static func circularMean(of hues: [Double]) -> Double {
        guard !hues.isEmpty else { return 0 }
        var x = 0.0, y = 0.0
        for h in hues {
            let r = h * .pi / 180
            x += cos(r); y += sin(r)
        }
        return wrap(atan2(y / Double(hues.count), x / Double(hues.count)) * 180 / .pi)
    }

    static func color(_ degrees: Double, saturation: Double = 0.45, brightness: Double = 1.0) -> Color {
        Color(hue: wrap(degrees) / 360, saturation: saturation, brightness: brightness)
    }

    /// Human name for a hue, used in slider legends.
    static func name(_ degrees: Double) -> String {
        switch wrap(degrees) {
        case ..<14:   return "Coral"
        case ..<34:   return "Apricot"
        case ..<58:   return "Butter"
        case ..<100:  return "Leaf"
        case ..<145:  return "Mint"
        case ..<185:  return "Sea"
        case ..<220:  return "Sky"
        case ..<258:  return "Periwinkle"
        case ..<300:  return "Lilac"
        default:      return "Blush"
        }
    }
}

// MARK: - Ink

/// Ink resolves against whichever scheme the view is rendering in, so every call site
/// stays `Color.ink` and nothing has to know which mode it is in.
///
/// Light is not a straight inversion. Pure black on white is harsher than white on
/// near-black, so the darkest ink is a very dark plum that keeps the app's colour cast,
/// and the fainter grades carry more weight than their dark-mode twins — a 30% white
/// disappears on black far less readily than a 30% black does on white.
extension Color {
    private static func ink(_ darkAlpha: Double, _ lightAlpha: Double) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: darkAlpha)
                : UIColor(red: 0.09, green: 0.07, blue: 0.13, alpha: lightAlpha)
        })
    }

    static let ink = ink(1.0, 1.0)
    /// For text and glyphs sitting *on* an `ink` fill. It has to invert with the scheme:
    /// a selected pill filled with `ink` is white in dark mode and near-black in light,
    /// so a hardcoded dark label turns the pill into a black blob in light mode.
    static let onInk = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.043, green: 0.043, blue: 0.055, alpha: 1)
            : UIColor(white: 1, alpha: 1)
    })
    static let ink2 = ink(0.58, 0.62)
    static let ink3 = ink(0.30, 0.42)
    static let hairline = ink(0.16, 0.20)
}

// MARK: - Tap targets

/// The button style everything in Squeeshy uses.
///
/// It exists for one reason: `.buttonStyle(.plain)` hit-tests the label's *subviews*, and
/// a `Spacer` is not a subview — it is layout-only, and it takes no touches. Every row in
/// the app is `icon · labels · Spacer · chevron`, so the wide gap the `Spacer` opens in
/// the middle was dead. A tap landing there did nothing, a tap two centimetres left on a
/// word worked, and the difference is invisible, which is why it read as the app dropping
/// taps at random rather than as a dead zone.
///
/// A `.glassEffect` background does not rescue it: the glass draws, but it does not
/// register as content to hit-test against. Fixed `.frame`s and `.padding` *do* take
/// touches across their whole area — that was measured, not assumed, so this is narrower
/// than it first looked.
///
/// Deliberately no press styling: interactive glass already responds to a touch, and a
/// second effect layered on top double-counts.
///
/// Guarded by `HitTargetTests`, which taps seven points across a shelf row.
struct TapStyle: ButtonStyle {
    /// Match the corner radius of the control's own background where it has one, so the
    /// hit region does not spill past a rounded card into its neighbour.
    var cornerRadius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect(cornerRadius: cornerRadius))
    }
}

extension ButtonStyle where Self == TapStyle {
    /// Whole-rectangle hit target. The default for every button in the app.
    static var tap: TapStyle { TapStyle() }

    /// Same, rounded to a card's own radius.
    static func tap(_ cornerRadius: CGFloat) -> TapStyle { TapStyle(cornerRadius: cornerRadius) }
}

// MARK: - Scheme identity

/// Rebuilds a view when the colour scheme changes.
///
/// `glassEffect(.regular.interactive())` is UIKit-backed, and in a list of repeated glass
/// rows exactly one row would keep the previous scheme's material after a light/dark
/// switch — a dark card with white text sitting in an otherwise light list. Which row it
/// picked was arbitrary. Re-identifying the view forces fresh glass.
///
/// Worth applying to any *repeated* interactive-glass row. One-off buttons on screens that
/// get rebuilt by navigation have not shown the problem.
private struct SchemeIdentity: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.id(scheme) }
}

extension View {
    func rebuildsOnSchemeChange() -> some View { modifier(SchemeIdentity()) }
}

// MARK: - Environment

private struct TintKey: EnvironmentKey {
    static let defaultValue = Tint.fallback
}

extension EnvironmentValues {
    var tint2: Tint {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }
}

// MARK: - The ground the whole app sits on

/// How much of the collection's colour the ground carries.
///
/// The original poured three big pools of the shelf's hue over near-black, which on a
/// warm shelf stopped reading as "dark with colour in it" and started reading as brown.
enum BackgroundStyle: String, CaseIterable {
    /// Pure white and pure black. No tint anywhere.
    case pure
    /// Off-white and near-black. Same idea, less glare, and black that is not a hole.
    case paper
    /// Paper, with just enough hue to notice when you move between shelves.
    case whisper
    /// Paper, with the colour pushed out to the corners so the middle stays clean.
    case corners
    /// The original.
    case pools

    func ground(dark: Bool) -> Color {
        switch self {
        case .pure:
            return dark ? .black : .white
        default:
            return dark ? Color(red: 0.043, green: 0.043, blue: 0.055)
                        : Color(red: 0.973, green: 0.973, blue: 0.980)
        }
    }

    /// Opacities for the three pools, and how wide they spread.
    func pools(dark: Bool) -> (opacities: (Double, Double, Double), radius: Double) {
        switch self {
        case .pure, .paper: return ((0, 0, 0), 0)
        case .whisper:      return (dark ? (0.10, 0.07, 0.06) : (0.11, 0.08, 0.06), 1.0)
        case .corners:      return (dark ? (0.20, 0.16, 0.13) : (0.22, 0.17, 0.13), 0.55)
        case .pools:        return (dark ? (0.26, 0.19, 0.16) : (0.30, 0.22, 0.18), 1.0)
        }
    }
}

struct AdaptiveBackground: View {
    var tint: Tint
    @Environment(\.colorScheme) private var scheme

    /// Read from UserDefaults so the styles can be compared on device without a
    /// rebuild; falls back to the shipping choice.
    private var style: BackgroundStyle {
        BackgroundStyle(rawValue: UserDefaults.standard.string(forKey: "bgStyle") ?? "")
            ?? .paper
    }

    var body: some View {
        let dark = scheme == .dark
        let (opacities, radius) = style.pools(dark: dark)

        ZStack {
            style.ground(dark: dark)
            if radius > 0 {
                // Three soft pools of the collection's own colour. These animate
                // whenever the tint changes, so moving between shelves reads as the
                // room changing colour rather than a screen swap.
                RadialGradient(colors: [tint.primary.opacity(opacities.0), .clear],
                               center: .init(x: 0.16, y: 0.02),
                               startRadius: 0, endRadius: 420 * radius)
                RadialGradient(colors: [tint.secondary.opacity(opacities.1), .clear],
                               center: .init(x: 0.95, y: 0.26),
                               startRadius: 0, endRadius: 380 * radius)
                RadialGradient(colors: [tint.primary.opacity(opacities.2), .clear],
                               center: .init(x: 0.5, y: 1.04),
                               startRadius: 0, endRadius: 460 * radius)
            }
        }
        .ignoresSafeArea()
        .animation(Motion.tintShift, value: tint)
    }
}

// MARK: - Theme choice

/// Dark, light, or follow the phone. One setting, cycled by one button.
enum AppTheme: String, CaseIterable {
    case auto, light, dark

    var next: AppTheme {
        switch self {
        case .dark:  return .light
        case .light: return .auto
        case .auto:  return .dark
        }
    }

    /// nil hands the decision back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }

    var symbol: String {
        switch self {
        case .auto:  return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark:  return "moon.fill"
        }
    }

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }
}

/// The one control. Tapping cycles dark to light to auto and back; the icon is the
/// only thing that says which you are in, so it changes with a bit of movement.
struct ThemeToggle: View {
    @Binding var theme: AppTheme

    var body: some View {
        Button {
            withAnimation(Motion.tap) { theme = theme.next }
        } label: {
            Image(systemName: theme.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 38, height: 38)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.tap)
        .accessibilityIdentifier("themeToggle")
        .accessibilityLabel("Appearance: \(theme.label)")
    }
}

// MARK: - Type

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Small uppercase monospaced label used for every piece of metadata in the app.
struct MetaLabel: View {
    var text: String
    var color: Color = .ink2
    var body: some View {
        Text(text.uppercased())
            .font(.mono(10))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}
