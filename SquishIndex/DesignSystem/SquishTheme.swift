import SwiftUI

/// The locked design surface. SPEC.md §2.
///
/// The UI has no colour of its own: every colour on screen comes out of the
/// user's photographs. Nothing may be added to this enum that is not traceable
/// to the spec table.
enum SquishTheme {

    // MARK: Palette — SPEC.md §2, locked

    /// App canvas.
    static let putty = Color(hex: 0xF1F0EC)
    /// Primary text, primary buttons.
    static let ink = Color(hex: 0x14151A)
    /// Secondary text, labels. Carries a higher-contrast variant when the user
    /// has asked for one (UX-SPEC §7.3 rule 2) — same role, not a new token.
    static let soft = Color(uiColor: UIColor { trait in
        trait.accessibilityContrast == .high
            ? UIColor(hex: 0x5F6269)   // 5.36:1 on putty
            : UIColor(hex: 0x74777E)   // 3.93:1 on putty
    })
    /// Hairline rules and borders. Decorative only — never the sole carrier of
    /// information, and never used for text (1.22:1 on putty).
    static let line = Color(hex: 0xDDDBD4)
    /// Raised surfaces, photo plates.
    static let chalk = Color(hex: 0xFFFFFF)

    /// Small text that is the *only* carrier of its information and cannot use
    /// `soft` without failing AA. UX-SPEC §7.3 rule 1 — 4.6:1 on putty.
    static let quietInk = Color(hex: 0x14151A).opacity(0.62)

    // MARK: Geometry — SPEC.md §2

    enum Radius {
        static let card: CGFloat = 15
        static let plate: CGFloat = 19
        static let plateLarge: CGFloat = 24
        static let sheet: CGFloat = 26
        static let pill: CGFloat = 999
    }

    /// The Fibonacci ramp derived from the locked gutter (13) and margin (22).
    /// UX-SPEC §2. Every spacing number in the app comes from here.
    enum Space {
        static let xxs: CGFloat = 3
        static let xs: CGFloat = 5
        static let sm: CGFloat = 8
        static let gutter: CGFloat = 13
        static let margin: CGFloat = 22
        static let lg: CGFloat = 34
        static let xl: CGFloat = 56
    }

    static let hairline: CGFloat = 1

    // MARK: Motion — UX-SPEC §6

    enum Motion {
        static let readout = Animation.smooth(duration: 0.18)
        static let select = Animation.smooth(duration: 0.22)
        static let settle = Animation.smooth(duration: 0.32)
        static let surface = Animation.smooth(duration: 0.32)
        static let reveal = Animation.smooth(duration: 0.42)
        static let dismiss = Animation.smooth(duration: 0.24)
    }

    // MARK: The two sanctioned shadows — SPEC.md §2

    enum Shadow {
        static let ambient = (color: Color(hex: 0x14151A).opacity(0.16), radius: CGFloat(18), y: CGFloat(8))
        static let contact = (color: Color(hex: 0x14151A).opacity(0.10), radius: CGFloat(3), y: CGFloat(1))
    }
}

// MARK: - Hex initialisers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Parses `#RRGGBB` / `RRGGBB`. Returns `nil` for anything else rather than
    /// silently substituting a colour — a wrong swatch is fabricated data.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
