import Foundation
import SwiftData
import SwiftUI

/// One accession record. SPEC.md §4.
@Model
final class Squishy {
    @Attribute(.unique) var id: UUID
    var name: String
    var squishLevel: Int
    var addedAt: Date

    /// External storage is required — inlining image blobs bloats the store.
    @Attribute(.externalStorage) var photo: Data
    /// Archived `VNFeaturePrintObservation`, for duplicate detection.
    var featurePrint: Data

    var widthMM: Double?
    var heightMM: Double?
    var measurementMethod: String
    var confidence: Double

    var dominantHue: Double
    /// Saturation and brightness are stored alongside hue because hue alone
    /// cannot separate white from grey from brown — and the colour shelf sorts
    /// on the family, not the angle. (Extends SPEC.md §4's model; see README.)
    var dominantSaturation: Double
    var dominantBrightness: Double
    var paletteHex: [String]
    var paletteProportions: [Double]
    var form: String

    var type: String?
    var subject: String?
    var material: String?
    var surface: String?
    var tags: [String]

    // Friends & trading (Milestone 6). All optional so existing stores migrate
    // without a schema version: an absent value means "photographed here,
    // held, open to trade". Design/FRIENDS-AND-TRADING.md §5.

    /// Stable across every owner. `nil` for things photographed on this device,
    /// whose lineage is their own `id`.
    var originID: UUID?
    /// `nil` while held; `"TRADED"` once it has gone to a friend.
    var tradeStatus: String?
    var tradedTo: String?
    var tradedAt: Date?
    /// Whose shelf it came from, when it arrived by trade.
    var acquiredFrom: String?
    /// `true` hides the Request button on friends' copies of this shelf.
    var keepFlag: Bool?
    /// JSON-encoded `[ProvenanceEntry]` — earlier owners, oldest first.
    var provenanceData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        squishLevel: Int,
        addedAt: Date = .now,
        photo: Data,
        featurePrint: Data,
        widthMM: Double? = nil,
        heightMM: Double? = nil,
        measurementMethod: String = MeasurementMethod.none.rawValue,
        confidence: Double = 0,
        dominantHue: Double = 0,
        dominantSaturation: Double = 0,
        dominantBrightness: Double = 0,
        paletteHex: [String] = [],
        paletteProportions: [Double] = [],
        form: String = SpecimenForm.irregular.rawValue,
        type: String? = nil,
        subject: String? = nil,
        material: String? = nil,
        surface: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.squishLevel = squishLevel
        self.addedAt = addedAt
        self.photo = photo
        self.featurePrint = featurePrint
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.measurementMethod = measurementMethod
        self.confidence = confidence
        self.dominantHue = dominantHue
        self.dominantSaturation = dominantSaturation
        self.dominantBrightness = dominantBrightness
        self.paletteHex = paletteHex
        self.paletteProportions = paletteProportions
        self.form = form
        self.type = type
        self.subject = subject
        self.material = material
        self.surface = surface
        self.tags = tags
    }
}

// MARK: - Derived reads

extension Squishy {
    static let unnamed = "Unnamed specimen"

    var image: UIImage? { UIImage(data: photo) }

    var squish: SquishLevel { SquishLevel(squishLevel) }

    var method: MeasurementMethod {
        MeasurementMethod(rawValue: measurementMethod) ?? .none
    }

    var silhouette: SpecimenForm {
        SpecimenForm(rawValue: form) ?? .irregular
    }

    var colorFamily: ColorFamily {
        ColorFamily.classify(hue: dominantHue,
                             saturation: dominantSaturation,
                             brightness: dominantBrightness)
    }

    var dominantColor: Color {
        paletteHex.first.flatMap { Color(hexString: $0) } ?? SquishTheme.soft
    }

    /// Longest measured edge, in millimetres. `nil` when size was not captured
    /// — never estimated from an unreferenced photo. SPEC.md §7.
    var longestEdgeMM: Double? {
        guard let widthMM, let heightMM else { return widthMM ?? heightMM }
        return max(widthMM, heightMM)
    }

    var hasSize: Bool { longestEdgeMM != nil }

    /// What VoiceOver reads for a card: *"Amber blob. Squish 7 of 10, slack.
    /// Four colours."*
    var spokenSummary: String {
        var parts = ["\(name).", "Squish \(squishLevel) of 10, \(squish.term.lowercased())."]
        if let edge = longestEdgeMM {
            parts.append("\(Int(edge.rounded())) millimetres.")
        }
        if !paletteHex.isEmpty {
            parts.append("\(paletteHex.count) colours.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Friends & trading

/// One earlier owner of a specimen. The current owner is never listed: their
/// tenure is `addedAt` to now.
struct ProvenanceEntry: Codable, Hashable {
    var owner: String
    var from: Date
    var to: Date
}

extension Squishy {
    static let tradedStatus = "TRADED"

    /// The identity that follows a toy from shelf to shelf.
    var lineageID: UUID { originID ?? id }

    var isTraded: Bool { tradeStatus == Self.tradedStatus }

    var isKeeping: Bool {
        get { keepFlag ?? false }
        set { keepFlag = newValue ? true : nil }
    }

    var provenance: [ProvenanceEntry] {
        get {
            guard let provenanceData else { return [] }
            return (try? JSONDecoder().decode([ProvenanceEntry].self, from: provenanceData)) ?? []
        }
        set { provenanceData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    /// Changes whenever anything a friend can see changes, so the shelf only
    /// re-uploads what moved.
    var shelfRevision: String {
        [name, String(squishLevel), isKeeping ? "K" : "O", String(photo.count),
         widthMM.map { String(format: "%.1f", $0) } ?? "-",
         heightMM.map { String(format: "%.1f", $0) } ?? "-",
         paletteHex.joined(separator: ",")].joined(separator: "|")
    }
}

// MARK: - Measurement method

/// The measurement ladder. SPEC.md §4 — always surfaced to the user, never
/// silently downgraded.
enum MeasurementMethod: String, CaseIterable, Codable {
    case lidar = "LIDAR"
    case depth = "DEPTH"
    case card = "CARD"
    case none = "NONE"

    var badgeText: String {
        switch self {
        case .lidar: "LiDAR"
        case .depth: "Depth"
        case .card: "Card"
        case .none: "No size data"
        }
    }

    /// Plain language for the specimen sheet.
    var explanation: String {
        switch self {
        case .lidar: "Measured with the LiDAR scanner."
        case .depth: "Measured from dual-camera depth."
        case .card: "Measured against a reference card."
        case .none: "Size wasn't captured for this one."
        }
    }

    var capturesSize: Bool { self != .none }
}

// MARK: - Silhouette

/// Shape, read off the segmentation mask. Deliberately coarse: these are
/// classes a person would agree with at a glance, not a taxonomy.
enum SpecimenForm: String, CaseIterable, Codable {
    case round = "ROUND"
    case oval = "OVAL"
    case tall = "TALL"
    case wide = "WIDE"
    case blocky = "BLOCKY"
    case lobed = "LOBED"
    case irregular = "IRREGULAR"

    var display: String {
        switch self {
        case .round: "Round"
        case .oval: "Oval"
        case .tall: "Tall"
        case .wide: "Wide"
        case .blocky: "Blocky"
        case .lobed: "Lobed"
        case .irregular: "Irregular"
        }
    }
}

// MARK: - Colour family

/// The colour axis the library sorts and filters on. Derived from the dominant
/// swatch, never asserted by the user.
enum ColorFamily: String, CaseIterable, Codable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, brown, neutral

    var id: String { rawValue }

    var display: String { rawValue.capitalized }

    /// Representative swatch, used only where a family needs a mark of its own
    /// (the stats colour spread already uses real specimen colours).
    var swatch: Color {
        switch self {
        case .red: Color(hex: 0xC0392B)
        case .orange: Color(hex: 0xD97C2B)
        case .yellow: Color(hex: 0xD9B02B)
        case .green: Color(hex: 0x4E9A51)
        case .teal: Color(hex: 0x2E9296)
        case .blue: Color(hex: 0x3A6EA5)
        case .purple: Color(hex: 0x7A5AA8)
        case .pink: Color(hex: 0xC96395)
        case .brown: Color(hex: 0x8A6A4F)
        case .neutral: Color(hex: 0x9A9A9A)
        }
    }

    /// `hue` in degrees 0…360, `saturation` and `brightness` 0…1.
    static func classify(hue: Double, saturation: Double, brightness: Double) -> ColorFamily {
        if brightness < 0.14 || saturation < 0.14 { return .neutral }
        let h = hue.truncatingRemainder(dividingBy: 360)
        let hueValue = h < 0 ? h + 360 : h
        // Dark, low-chroma warms read as brown rather than as dull orange.
        if (hueValue < 45 || hueValue >= 330), brightness < 0.55, saturation < 0.6 { return .brown }
        switch hueValue {
        case 0..<12, 348..<360: return .red
        case 12..<44: return .orange
        case 44..<70: return .yellow
        case 70..<160: return .green
        case 160..<195: return .teal
        case 195..<255: return .blue
        case 255..<300: return .purple
        default: return .pink
        }
    }
}
