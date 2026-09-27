import Foundation
import SwiftData
import SwiftUI

// MARK: - Size

/// Size is asked for, never guessed. A photo has no scale in it without a reference
/// object, so an inch figure derived from how much of the frame the squeeshy filled
/// was precision the app hadn't earned — and it was wrong often enough that people
/// would correct it every time. Three buckets are what anyone would say out loud.
enum SizeClass: String, CaseIterable, Codable, Identifiable, Comparable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    /// Rough guidance shown under the picker, so "medium" means the same thing to
    /// everyone without turning into a measurement.
    var hint: String {
        switch self {
        case .small:  return "palm sized"
        case .medium: return "two hands"
        case .large:  return "a hug"
        }
    }

    /// Ordinal, used by the field's size slider so it can sweep small to large.
    var order: Int {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .large: return 2
        }
    }

    static func < (a: SizeClass, b: SizeClass) -> Bool { a.order < b.order }

    static func closest(toOrder value: Double) -> SizeClass {
        let clamped = Int(value.rounded()).clamped(to: 0...2)
        return allCases.first { $0.order == clamped } ?? .medium
    }
}

// MARK: - Squishy

@Model
final class Squishy {
    var id: UUID = UUID()
    /// Always typed by the owner. The vision pass fills every other field but this one.
    var name: String = ""
    var speciesRaw: String = Species.round.rawValue
    /// Dominant hue in degrees, extracted on device from the cut-out.
    var hue: Double = 0
    var saturation: Double = 0.45
    var sizeRaw: String = SizeClass.medium.rawValue
    var squeeshiness: Double = 5
    /// Owning two of the same squishy merges into a count rather than a second row.
    var quantity: Int = 1
    /// Species the cloud pass named: "Axolotl", "Bear". Distinct from body plan.
    var typeName: String = ""
    var addedAt: Date = Date()
    var isSample: Bool = false
    /// Filename of the cut-out on disk. Nil for the seeded demo shelf, which uses
    /// drawn art instead.
    var photoFilename: String?

    /// Manual shelves this squishy has been put on by hand.
    @Relationship(inverse: \Shelf.items) var shelves: [Shelf]? = []

    init(name: String, species: Species, hue: Double, size: SizeClass,
         squeeshiness: Double, typeName: String, addedAt: Date = .now, isSample: Bool = false) {
        self.id = UUID()
        self.name = name
        self.speciesRaw = species.rawValue
        self.hue = hue
        self.sizeRaw = size.rawValue
        self.squeeshiness = squeeshiness
        self.typeName = typeName
        self.addedAt = addedAt
        self.isSample = isSample
    }

    var species: Species {
        get { Species(rawValue: speciesRaw) ?? .round }
        set { speciesRaw = newValue.rawValue }
    }

    var size: SizeClass {
        get { SizeClass(rawValue: sizeRaw) ?? .medium }
        set { sizeRaw = newValue.rawValue }
    }

    var color: Color { Hue.color(hue, saturation: saturation) }
    var shapeName: String { species.shapeName }
    var colorName: String { Hue.name(hue) }

    /// "Cat · Round · Medium"
    var traitLine: String {
        [typeName, shapeName, size.label].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Shelves

/// A shelf the owner made by hand. Smart shelves are computed, never stored.
@Model
final class Shelf {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var items: [Squishy]? = []
    /// Pinned shelves are listed above the smart ones. Defaulted, so existing stores
    /// migrate without a schema version.
    var isPinned: Bool = false

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
    }
}

// MARK: - Smart shelves

/// Generated from traits, never curated. These are the front door.
enum SmartShelf: String, CaseIterable, Identifiable, Sendable {
    case everything, squeeshiest, warm, cool, large, small, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything:  return "Everything"
        case .squeeshiest: return "Squeeshiest"
        case .warm:        return "Warm colours"
        case .cool:        return "Cool colours"
        case .large:       return "Large"
        case .small:       return "Small"
        case .recent:      return "Added this week"
        }
    }

    /// Which trait axis the field's slider should open on for this shelf.
    var preferredTrait: Trait {
        switch self {
        case .everything, .warm, .cool: return .colour
        case .squeeshiest:              return .squeeshiness
        // A shelf selected *by* size has only one size on it, so opening on that axis
        // would hand you a slider with nowhere to go.
        case .large, .small:            return .squeeshiness
        case .recent:                   return .colour
        }
    }

    func matches(_ s: Squishy) -> Bool {
        switch self {
        case .everything:  return true
        case .squeeshiest: return s.squeeshiness >= 8
        case .warm:        return s.hue >= 320 || s.hue <= 70
        case .cool:        return s.hue > 150 && s.hue < 290
        case .large:       return s.size == .large
        case .small:       return s.size == .small
        case .recent:      return s.addedAt > Date().addingTimeInterval(-7 * 86_400)
        }
    }
}

// MARK: - Traits

/// The three axes the field's slider can sort on.
enum Trait: String, CaseIterable, Identifiable, Sendable {
    case colour, size, squeeshiness

    var id: String { rawValue }

    var label: String {
        switch self {
        case .colour:       return "Colour"
        case .size:         return "Size"
        case .squeeshiness: return "Squeesh"
        }
    }

    func value(of s: Squishy) -> Double {
        switch self {
        case .colour:       return s.hue
        // Size is ordinal now, so the slider sweeps small to large across whatever
        // classes the shelf actually contains.
        case .size:         return Double(s.size.order)
        case .squeeshiness: return s.squeeshiness
        }
    }
}

// MARK: - Trait domain
//
// The slider is scoped to the shelf it is sitting on. A pinks shelf gets a band
// covering only the pinks it actually holds, a 5-8 inch shelf gets a 5-8 ruler.
// Sweeping a range the collection doesn't occupy would just be dead travel.

struct TraitDomain: Equatable {
    var trait: Trait
    /// For colour these are degrees and `upper` may exceed 360 when the set wraps
    /// through red, e.g. 337...373. Callers wrap when they need a real hue.
    var lower: Double
    var upper: Double
    /// True when every item on the shelf shares one value on this axis. The domain is
    /// still padded so the track renders, but there is genuinely nothing to sort by,
    /// and saying "drag to stir" over dead travel would be a lie.
    var isSingleValued: Bool = false

    var span: Double { max(upper - lower, 0.0001) }

    func position(of value: Double) -> Double {
        if trait == .colour {
            // Bring the hue into the same revolution as the domain before comparing.
            var v = Hue.wrap(value)
            if v < lower - 0.0001 { v += 360 }
            return (v - lower) / span
        }
        return (value - lower) / span
    }

    func value(at position: Double) -> Double {
        lower + position.clamped(to: 0...1) * span
    }

    /// How well an item matches the current slider position, 0...1. The tolerance is
    /// a slice of the shelf's own span, so a tight shelf stays selective and a wide
    /// one doesn't require pixel precision.
    func match(_ value: Double, sliderValue: Double) -> Double {
        // Size has only three steps, so a proportional tolerance would either select
        // everything or nothing. Half a step keeps one class lit at a time.
        if trait == .size {
            return pow(max(0, 1 - abs(value - sliderValue) / 0.62), 0.75)
        }
        let tolerance = max(span * 0.28, trait == .colour ? 8 : 0.5)
        let distance: Double
        if trait == .colour {
            distance = Hue.distance(value, sliderValue)
        } else {
            distance = abs(value - sliderValue)
        }
        return pow(max(0, 1 - distance / tolerance), 0.75)
    }

    func legend(at position: Double) -> String {
        let v = value(at: position)
        switch trait {
        case .colour:       return "\(Hue.name(v)) · \(Int(Hue.wrap(v)))°"
        case .size:         return SizeClass.closest(toOrder: v).label
        case .squeeshiness: return String(format: "%.1f / 10", v)
        }
    }

    /// The two end captions under the track.
    var endLabels: (String, String) {
        switch trait {
        case .colour:
            return (Hue.name(lower), Hue.name(upper))
        case .size:
            return (SizeClass.closest(toOrder: lower).label,
                    SizeClass.closest(toOrder: upper).label)
        case .squeeshiness:
            return (String(format: "%.1f", lower), String(format: "%.1f", upper))
        }
    }

    /// Tick positions to draw under the track, as 0...1 fractions.
    var ticks: [Double] {
        switch trait {
        case .colour:
            let count = max(2, min(9, Int(span / 12)))
            return (0...count).map { Double($0) / Double(count) }
        case .size:
            // One tick per size class present, so the track reads as steps.
            let steps = max(1, Int(span.rounded()))
            return (0...steps).map { Double($0) / Double(steps) }
        case .squeeshiness:
            let steps = max(2, min(10, Int(span.rounded(.up))))
            return (0...steps).map { Double($0) / Double(steps) }
        }
    }

    /// Builds the domain from what is actually on the shelf.
    static func compute(_ trait: Trait, items: [Squishy]) -> TraitDomain {
        let values = items.map { trait.value(of: $0) }
        guard !values.isEmpty else { return TraitDomain(trait: trait, lower: 0, upper: 1) }

        if trait == .colour {
            let (lo, hi) = smallestArc(values.map(Hue.wrap))
            // Give a single-hue shelf a little room either side so the band isn't a dot.
            if hi - lo < 12 {
                let mid = (lo + hi) / 2
                return TraitDomain(trait: trait, lower: mid - 14, upper: mid + 14,
                                   isSingleValued: hi - lo < 0.5)
            }
            return TraitDomain(trait: trait, lower: lo, upper: hi)
        }

        let lo = values.min()!, hi = values.max()!

        // Size classes are discrete: the domain is exactly the classes present, so the
        // ends of the track are real sizes rather than half-steps into nothing.
        if trait == .size {
            return hi - lo < 0.5
                ? TraitDomain(trait: trait, lower: lo - 0.5, upper: hi + 0.5, isSingleValued: true)
                : TraitDomain(trait: trait, lower: lo, upper: hi)
        }

        if hi - lo < 0.4 {
            return TraitDomain(trait: trait, lower: lo - 0.5, upper: hi + 0.5,
                               isSingleValued: hi - lo < 0.05)
        }
        // A hair of padding so the extreme items aren't pinned to the very ends.
        let pad = (hi - lo) * 0.06
        return TraitDomain(trait: trait, lower: lo - pad, upper: hi + pad)
    }

    /// Smallest arc containing every hue. Finding the widest gap between adjacent
    /// hues and cutting there is what makes a pinks shelf read 337...373 rather
    /// than 13...337 the long way round.
    private static func smallestArc(_ hues: [Double]) -> (Double, Double) {
        let sorted = hues.sorted()
        guard sorted.count > 1 else { return (sorted[0], sorted[0]) }
        var gapIndex = 0
        var widest = -1.0
        for i in 0..<sorted.count {
            let next = i == sorted.count - 1 ? sorted[0] + 360 : sorted[i + 1]
            let gap = next - sorted[i]
            if gap > widest { widest = gap; gapIndex = i }
        }
        let lower = sorted[(gapIndex + 1) % sorted.count]
        var upper = sorted[gapIndex]
        if upper < lower { upper += 360 }
        return (lower, upper)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
