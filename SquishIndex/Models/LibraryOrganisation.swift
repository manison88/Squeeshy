import Foundation

// MARK: - Sorting

enum SortOption: String, CaseIterable, Identifiable {
    case recent
    case nameAZ
    case squishiest
    case largest
    case colour
    case unusual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recently added"
        case .nameAZ: "Name A–Z"
        case .squishiest: "Squishiest first"
        case .largest: "Largest first"
        case .colour: "Colour"
        case .unusual: "Most unusual"
        }
    }

    /// The chip renders the current sort in mono, so it needs a short form.
    var chipTitle: String {
        switch self {
        case .recent: "Recent"
        case .nameAZ: "A–Z"
        case .squishiest: "Squishiest"
        case .largest: "Largest"
        case .colour: "Colour"
        case .unusual: "Unusual"
        }
    }

    /// Sorting by size is meaningless until something has been measured.
    func isEnabled(for specimens: [Squishy]) -> Bool {
        guard self == .largest else { return true }
        return specimens.contains { $0.hasSize }
    }
}

// MARK: - Filtering

struct LibraryFilter: Equatable {
    var colours: Set<ColorFamily> = []
    var forms: Set<SpecimenForm> = []
    var squishRange: ClosedRange<Int> = 1...10
    var measuredOnly = false

    var isActive: Bool {
        !colours.isEmpty || !forms.isEmpty || squishRange != 1...10 || measuredOnly
    }

    /// The chip's count badge. Colour is never the only indicator of state
    /// (SPEC.md §3), so the number is what actually carries it.
    var activeCount: Int {
        var n = colours.count + forms.count
        if squishRange != 1...10 { n += 1 }
        if measuredOnly { n += 1 }
        return n
    }

    func matches(_ specimen: Squishy) -> Bool {
        if !colours.isEmpty, !colours.contains(specimen.colorFamily) { return false }
        if !forms.isEmpty, !forms.contains(specimen.silhouette) { return false }
        if !squishRange.contains(specimen.squishLevel) { return false }
        if measuredOnly, !specimen.hasSize { return false }
        return true
    }

    static let none = LibraryFilter()
}

// MARK: - Organising the collection

enum LibraryOrganiser {

    static func organise(_ specimens: [Squishy],
                         sort: SortOption,
                         filter: LibraryFilter) -> [Squishy] {
        let filtered = specimens.filter(filter.matches)
        let scores = uniquenessScores(for: specimens)

        switch sort {
        case .recent:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        case .nameAZ:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .squishiest:
            return filtered.sorted {
                if $0.squishLevel != $1.squishLevel { return $0.squishLevel > $1.squishLevel }
                return $0.addedAt > $1.addedAt
            }
        case .largest:
            // Unmeasured specimens sink to the bottom rather than being
            // silently assigned a size.
            return filtered.sorted {
                switch ($0.longestEdgeMM, $1.longestEdgeMM) {
                case let (a?, b?): return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return $0.addedAt > $1.addedAt
                }
            }
        case .colour:
            return filtered.sorted {
                if $0.colorFamily == $1.colorFamily { return $0.dominantHue < $1.dominantHue }
                return familyOrder($0.colorFamily) < familyOrder($1.colorFamily)
            }
        case .unusual:
            return filtered.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
        }
    }

    /// Spectrum order, with neutrals last — a colour shelf reads as a spectrum
    /// or it reads as nothing.
    private static func familyOrder(_ family: ColorFamily) -> Int {
        let order: [ColorFamily] = [.red, .orange, .yellow, .green, .teal, .blue,
                                    .purple, .pink, .brown, .neutral]
        return order.firstIndex(of: family) ?? order.count
    }

    // MARK: Uniqueness

    /// How far a specimen sits from the rest of the collection, 0…1.
    ///
    /// Four axes, each normalised, then averaged with the mean distance to
    /// every other specimen: hue (circular), squish, size, and how rare its
    /// silhouette is in the collection. A one-specimen library has no spread to
    /// measure, so everything scores 0 — the honest answer, not 1.
    static func uniquenessScores(for specimens: [Squishy]) -> [UUID: Double] {
        guard specimens.count > 1 else {
            return Dictionary(uniqueKeysWithValues: specimens.map { ($0.id, 0.0) })
        }

        let sizes = specimens.compactMap(\.longestEdgeMM)
        let sizeSpan = max((sizes.max() ?? 0) - (sizes.min() ?? 0), 1)

        var formCounts: [SpecimenForm: Int] = [:]
        for specimen in specimens { formCounts[specimen.silhouette, default: 0] += 1 }

        var scores: [UUID: Double] = [:]
        for specimen in specimens {
            var total = 0.0
            for other in specimens where other.id != specimen.id {
                total += distance(specimen, other, sizeSpan: sizeSpan)
            }
            let mean = total / Double(specimens.count - 1)
            let formRarity = 1 - Double(formCounts[specimen.silhouette] ?? 1) / Double(specimens.count)
            scores[specimen.id] = min(1, mean * 0.75 + formRarity * 0.25)
        }
        return scores
    }

    private static func distance(_ a: Squishy, _ b: Squishy, sizeSpan: Double) -> Double {
        var axes: [Double] = []

        // Hue is circular: 350° and 10° are 20° apart, not 340°.
        let rawHue = abs(a.dominantHue - b.dominantHue).truncatingRemainder(dividingBy: 360)
        let hueGap = min(rawHue, 360 - rawHue) / 180
        // A grey toy has no meaningful hue, so chroma weights the hue axis.
        let chroma = min(a.dominantSaturation, b.dominantSaturation)
        axes.append(hueGap * chroma + abs(a.dominantBrightness - b.dominantBrightness) * (1 - chroma))

        axes.append(Double(abs(a.squishLevel - b.squishLevel)) / 9)

        if let sizeA = a.longestEdgeMM, let sizeB = b.longestEdgeMM {
            axes.append(min(1, abs(sizeA - sizeB) / sizeSpan))
        }

        return axes.reduce(0, +) / Double(axes.count)
    }
}

// MARK: - Stats

struct ColourShare: Identifiable {
    let family: ColorFamily
    let share: Double
    var id: ColorFamily { family }
}

struct FormCount: Identifiable {
    let form: SpecimenForm
    let count: Int
    var id: SpecimenForm { form }
}

struct LibraryStats {
    let count: Int
    let averageSquish: Double?
    /// Ten bins, indexed 0…9 for levels 1…10.
    let squishHistogram: [Int]
    let colourSpread: [ColourShare]
    let measuredCount: Int
    let smallest: Squishy?
    let largest: Squishy?
    let mostUnusual: Squishy?
    let formCounts: [FormCount]

    init(specimens: [Squishy]) {
        count = specimens.count
        averageSquish = specimens.isEmpty
            ? nil
            : Double(specimens.reduce(0) { $0 + $1.squishLevel }) / Double(specimens.count)

        var bins = Array(repeating: 0, count: 10)
        for specimen in specimens {
            let index = min(9, max(0, specimen.squishLevel - 1))
            bins[index] += 1
        }
        squishHistogram = bins

        var families: [ColorFamily: Int] = [:]
        for specimen in specimens { families[specimen.colorFamily, default: 0] += 1 }
        let total = max(specimens.count, 1)
        colourSpread = families
            .map { ColourShare(family: $0.key, share: Double($0.value) / Double(total)) }
            .sorted { $0.share > $1.share }

        measuredCount = specimens.filter(\.hasSize).count

        let measured = specimens.filter(\.hasSize)
        smallest = measured.min { ($0.longestEdgeMM ?? 0) < ($1.longestEdgeMM ?? 0) }
        largest = measured.max { ($0.longestEdgeMM ?? 0) < ($1.longestEdgeMM ?? 0) }

        let scores = LibraryOrganiser.uniquenessScores(for: specimens)
        mostUnusual = specimens.max { (scores[$0.id] ?? 0) < (scores[$1.id] ?? 0) }

        var forms: [SpecimenForm: Int] = [:]
        for specimen in specimens { forms[specimen.silhouette, default: 0] += 1 }
        formCounts = forms.map { FormCount(form: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}
