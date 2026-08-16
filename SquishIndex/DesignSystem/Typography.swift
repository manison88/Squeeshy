import SwiftUI

/// The three-family type system. SPEC.md §2, sizes from UX-SPEC §2.1.
///
/// The mono/display split is load-bearing: mono says *measured*, display says
/// *named*. A toy's name is never mono; a measurement is never display, except
/// the hero squish numeral.
enum TypeStyle {
    /// Bricolage 44/800 — hero squish numeral.
    case d1
    /// Bricolage 26/800 — screen titles.
    case d2
    /// Bricolage 24/600 — specimen name, detail & name field.
    case d3
    /// Bricolage 17/600 — specimen name, grid card.
    case d4
    /// Inter 15/400 — sentences.
    case b1
    /// Inter 16/600 — button labels.
    case b2
    /// Inter 13/400 — secondary prose.
    case b3
    /// DM Mono 10/400 uppercase +0.16em — eyebrows, field labels, units.
    case m1
    /// DM Mono 12/500 +0.04em — bare numerals in line.
    case m2

    var size: CGFloat {
        switch self {
        case .d1: 44
        case .d2: 26
        case .d3: 24
        case .d4: 17
        case .b1: 15
        case .b2: 16
        case .b3: 13
        case .m1: 10
        case .m2: 12
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .d1: .largeTitle
        case .d2: .title
        case .d3: .title2
        case .d4: .headline
        case .b1, .b2: .body
        case .b3: .footnote
        case .m1: .caption2
        case .m2: .caption
        }
    }

    /// Tracking as a fraction of the point size.
    var trackingEm: CGFloat {
        switch self {
        case .d1, .d2, .d3, .d4: -0.02
        case .b1, .b2, .b3: 0
        case .m1: 0.16
        case .m2: 0.04
        }
    }

    var isUppercase: Bool { self == .m1 }

    var isMono: Bool { self == .m1 || self == .m2 }

    fileprivate func fontName(boldText: Bool) -> String {
        switch self {
        case .d1, .d2:
            return SquishFont.bricolageExtraBold
        case .d3, .d4:
            return boldText ? SquishFont.bricolageBold : SquishFont.bricolageSemiBold
        case .b1, .b3:
            return boldText ? SquishFont.interMedium : SquishFont.interRegular
        case .b2:
            return SquishFont.interSemiBold
        case .m1:
            return boldText ? SquishFont.dmMonoMedium : SquishFont.dmMonoRegular
        case .m2:
            return SquishFont.dmMonoMedium
        }
    }
}

/// PostScript names of the bundled faces. Registered through `UIAppFonts`.
enum SquishFont {
    static let bricolageSemiBold = "BricolageGrotesque-SemiBold"
    static let bricolageBold = "BricolageGrotesque-Bold"
    static let bricolageExtraBold = "BricolageGrotesque-ExtraBold"
    static let interRegular = "Inter-Regular"
    static let interMedium = "Inter-Medium"
    static let interSemiBold = "Inter-SemiBold"
    static let dmMonoRegular = "DMMono-Regular"
    static let dmMonoMedium = "DMMono-Medium"
}

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        content
            .font(.custom(style.fontName(boldText: legibilityWeight == .bold),
                          size: style.size,
                          relativeTo: style.relativeTo))
            .tracking(tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
            .monospacedDigit(isNumericMono: style.isMono)
    }

    /// Mono tracking degrades above `.xxLarge` — +0.16em at accessibility sizes
    /// overflows every container, and tracking is a nicety, not information.
    /// UX-SPEC §3.6.
    private var tracking: CGFloat {
        guard style.isMono, style.trackingEm > 0.08, typeSize > .xxLarge else {
            return style.size * style.trackingEm
        }
        return style.size * 0.08
    }
}

private extension View {
    @ViewBuilder
    func monospacedDigit(isNumericMono: Bool) -> some View {
        if isNumericMono { self.monospacedDigit() } else { self }
    }
}

extension View {
    /// Applies one of the nine locked type styles.
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}

extension Font {
    /// For the rare place a raw `Font` is needed rather than a view modifier.
    static func squish(_ style: TypeStyle) -> Font {
        .custom(style.fontName(boldText: false), size: style.size, relativeTo: style.relativeTo)
    }
}

// MARK: - Reserved heights

extension DynamicTypeSize {
    /// Line height for a style at the current type size, used to reserve space
    /// so layouts do not jump. Reserved heights are computed, never literal
    /// (UX-SPEC §7.1).
    func lineHeight(for style: TypeStyle) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: style.relativeTo.uiTextStyle)
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let scaled = metrics.scaledValue(for: style.size, compatibleWith: traits)
        return (scaled * 1.24).rounded()
    }

    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
