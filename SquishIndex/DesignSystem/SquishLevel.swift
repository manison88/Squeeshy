import Foundation

/// The ten squish levels, each a material term plus how it behaves under a
/// thumb. UX-SPEC §5.9.
///
/// Register: sentence case, no exclamation marks, no anthropomorphism, no
/// adjectives of delight. Every sentence names a *yield* and a *recovery time*
/// — the two axes a real durometer measures.
struct SquishLevel: Hashable {
    let value: Int

    init(_ value: Int) {
        self.value = min(10, max(1, value))
    }

    static let range = 1...10
    static let `default` = SquishLevel(5)

    var term: String {
        switch value {
        case 1: "Rigid"
        case 2: "Firm"
        case 3: "Dense"
        case 4: "Resilient"
        case 5: "Even"
        case 6: "Soft"
        case 7: "Slack"
        case 8: "Deep"
        case 9: "Slow rise"
        default: "Barely holds shape"
        }
    }

    var behaviour: String {
        switch value {
        case 1: "A thumb leaves no impression."
        case 2: "Gives at the surface, returns instantly."
        case 3: "Compresses under steady pressure and springs straight back."
        case 4: "Presses in about a third of the way and recovers at once."
        case 5: "Compresses about halfway. Returns without delay."
        case 6: "Folds around a thumb and recovers in about a second."
        case 7: "Squashes nearly flat under light pressure. Comes back slowly."
        case 8: "Collapses almost completely and rises again over a few seconds."
        case 9: "Holds the print of a thumb for five to ten seconds."
        default: "Flows in the hand and re-forms on its own."
        }
    }

    /// What screen 4 renders under the durometer.
    var sentence: String { "\(term). \(behaviour)" }

    /// What VoiceOver announces on every adjustable swipe — short form only.
    var spokenValue: String { "\(value) of 10. \(term)." }

    /// Mono renders squish zero-padded so meta rows do not reflow between
    /// `07` and `10`. The display numeral is never padded. UX-SPEC §2.1.
    var padded: String { String(format: "%02d", value) }

    /// Compression factor driving the durometer geometry: 0 at level 1, 1 at 10.
    var k: Double { Double(value - 1) / 9.0 }
}
