import Observation
import SwiftData
import SwiftUI

/// Drives capture → name → measure → filed.
///
/// Analysis starts the instant the shutter closes and runs while the user is
/// naming the specimen, so the measuring checklist is usually a formality. A
/// save is never blocked: if analysis fails outright the specimen still files,
/// with the photograph, the name and the squish level the user gave it.
@MainActor
@Observable
final class CaptureFlow {

    enum Step: Equatable {
        case viewfinder
        case naming
        case measuring
    }

    struct DuplicateMatch: Equatable {
        let id: UUID
        let score: Double
    }

    var step: Step = .viewfinder
    var name = ""
    /// The midpoint is the honest prior, and it is the control's most legible
    /// state. UX-SPEC §4.4.
    var level = SquishLevel.default.value

    private(set) var rawImage: UIImage?
    private(set) var analysis: SquishyVision.Analysis?
    private(set) var completedStages: Set<SquishyVision.Stage> = []
    private(set) var analysisFinished = false
    private(set) var subjectIsolated = true
    private(set) var duplicate: DuplicateMatch?
    var duplicateDismissed = false

    /// Feature prints of everything already filed, snapshotted on the main
    /// actor before the background pass starts.
    var libraryPrints: [(id: UUID, print: Data)] = []

    private var analysisTask: Task<Void, Never>?

    var hasEdits: Bool { rawImage != nil }

    var plateImage: UIImage? { analysis?.plateImage ?? rawImage }

    var visibleDuplicate: DuplicateMatch? { duplicateDismissed ? nil : duplicate }

    // MARK: Flow

    func begin(with sample: SquishyVision.Sample) {
        rawImage = UIImage(cgImage: sample.image)
        step = .naming
        startAnalysis(sample)
    }

    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        step = .viewfinder
        name = ""
        level = SquishLevel.default.value
        rawImage = nil
        analysis = nil
        completedStages = []
        analysisFinished = false
        subjectIsolated = true
        duplicate = nil
        duplicateDismissed = false
    }

    private func startAnalysis(_ sample: SquishyVision.Sample) {
        analysisTask?.cancel()
        completedStages = []
        analysisFinished = false
        let prints = libraryPrints

        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = SquishyVision.analyze(sample) { stage in
                Task { @MainActor [weak self] in
                    self?.completedStages.insert(stage)
                }
            }
            let match = Self.bestMatch(for: result.featurePrint, in: prints)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.analysis = result
                self.subjectIsolated = result.subjectIsolated
                self.duplicate = match
                self.completedStages = Set(SquishyVision.Stage.allCases)
                self.analysisFinished = true
            }
        }
    }

    /// Never auto-rejects a capture — the twin card is advisory. SPEC.md §4.
    nonisolated private static func bestMatch(for print: Data,
                                  in library: [(id: UUID, print: Data)]) -> DuplicateMatch? {
        guard !print.isEmpty else { return nil }
        var best: DuplicateMatch?
        for entry in library {
            let score = SquishyVision.similarity(print, entry.print)
            if score > 0.62, score > (best?.score ?? 0) {
                best = DuplicateMatch(id: entry.id, score: score)
            }
        }
        return best
    }

    // MARK: Filing

    /// Called when the user taps *File specimen*. If the background pass is
    /// still running we show the checklist rather than a spinner, and file the
    /// moment it lands.
    func requestFiling(into context: ModelContext) async -> Squishy? {
        if !analysisFinished {
            step = .measuring
            while !analysisFinished, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        return file(into: context)
    }

    private func file(into context: ModelContext) -> Squishy? {
        guard let image = plateImage,
              let data = image.jpegData(compressionQuality: 0.86) else { return nil }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let specimen = Squishy(
            name: trimmed.isEmpty ? Squishy.unnamed : trimmed,
            squishLevel: level,
            photo: data,
            featurePrint: analysis?.featurePrint ?? Data(),
            widthMM: analysis?.widthMM,
            heightMM: analysis?.heightMM,
            measurementMethod: (analysis?.method ?? .none).rawValue,
            confidence: analysis?.confidence ?? 0,
            dominantHue: analysis?.dominant.hue ?? 0,
            dominantSaturation: analysis?.dominant.saturation ?? 0,
            dominantBrightness: analysis?.dominant.brightness ?? 0,
            paletteHex: analysis?.palette.map(\.hex) ?? [],
            paletteProportions: analysis?.palette.map(\.share) ?? [],
            form: (analysis?.form ?? .irregular).rawValue
        )
        context.insert(specimen)
        try? context.save()
        return specimen
    }
}
