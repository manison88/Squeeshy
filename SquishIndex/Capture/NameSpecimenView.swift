import SwiftData
import SwiftUI

/// Screens 4 and 5 — name & durometer, then measuring.
///
/// The durometer never scrolls. Its drag is positional and starts on
/// touch-down, so putting it inside a scroll view would let a user set a value
/// while trying to scroll. Layout solves that for free: the durometer block
/// lives in a bottom safe-area inset. UX-SPEC §4.4.
@MainActor
struct NameSpecimenView: View {
    @Bindable var flow: CaptureFlow
    let library: [Squishy]
    let onCancel: () -> Void
    let onFiled: (Squishy) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var nameFocused: Bool
    @State private var showRetakeOptions = false
    @State private var showDiscardConfirmation = false
    @State private var filedToken = 0

    var body: some View {
        NavigationStack {
            content
                .background(SquishTheme.putty)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            flow.hasEdits ? (showDiscardConfirmation = true) : onCancel()
                        }
                        .typeStyle(.b1)
                        .foregroundStyle(SquishTheme.soft)
                    }
                }
                .confirmationDialog("Discard this photo?",
                                    isPresented: $showDiscardConfirmation,
                                    titleVisibility: .visible) {
                    Button("Discard photo", role: .destructive, action: onCancel)
                    Button("Keep editing", role: .cancel) {}
                }
                .confirmationDialog("Replace the photo?",
                                    isPresented: $showRetakeOptions,
                                    titleVisibility: .visible) {
                    Button("Retake photo") { flow.reset() }
                    Button("Cancel", role: .cancel) {}
                }
        }
        .sensoryFeedback(.success, trigger: filedToken)
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .measuring:
            MeasuringView(flow: flow)
        default:
            namingBody
        }
    }

    // MARK: Screen 4

    private var namingBody: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    plate(side: plateSide(in: proxy.size))
                        .padding(.top, SquishTheme.Space.gutter)

                    Button("Retake") { showRetakeOptions = true }
                        .typeStyle(.m1)
                        .foregroundStyle(SquishTheme.soft)
                        .frame(height: 44)
                        .padding(.top, SquishTheme.Space.xs)

                    NameField(text: $flow.name, isFocused: $nameFocused)
                        .padding(.top, SquishTheme.Space.margin)

                    if let duplicate = flow.visibleDuplicate,
                       let twin = library.first(where: { $0.id == duplicate.id }) {
                        DuplicateCard(twin: twin,
                                      score: duplicate.score,
                                      current: flow.plateImage) {
                            flow.duplicateDismissed = true
                        }
                        .padding(.top, SquishTheme.Space.margin)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, SquishTheme.Space.margin)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(SquishTheme.Motion.settle, value: flow.visibleDuplicate)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { durometerBlock }
    }

    private func plate(side: CGFloat) -> some View {
        PhotoPlate(state: plateState,
                   cornerRadius: SquishTheme.Radius.plateLarge)
            .frame(width: side, height: side)
            .overlay(alignment: .bottom) {
                if !flow.subjectIsolated, flow.analysisFinished {
                    MonoLabel(text: "Subject not isolated")
                        .padding(.bottom, SquishTheme.Space.sm)
                }
            }
            .animation(reduceMotion ? nil : SquishTheme.Motion.reveal, value: flow.analysisFinished)
    }

    private var plateState: PlateState {
        if let image = flow.plateImage { return .filled(image) }
        return .pending
    }

    private func plateSide(in size: CGSize) -> CGFloat {
        max(200, min(260, size.height - 140))
    }

    private var durometerBlock: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(alignment: .lastTextBaseline, spacing: SquishTheme.Space.gutter) {
                Eyebrow("Squish level")
                Spacer()
                HeroNumeral(value: flow.level)
            }
            .frame(height: 44)
            .padding(.top, SquishTheme.Space.margin)

            Durometer(level: $flow.level)
                .padding(.top, SquishTheme.Space.gutter)

            levelSentence
                .padding(.top, SquishTheme.Space.gutter)

            PrimaryPill(title: "File specimen") { file() }
                .padding(.top, SquishTheme.Space.margin)
        }
        .padding(.horizontal, SquishTheme.Space.margin)
        .padding(.bottom, SquishTheme.Space.gutter)
        .background(SquishTheme.putty)
    }

    /// Reserved at two lines (four at accessibility sizes) so the footer does
    /// not jump on every drag step.
    private var levelSentence: some View {
        let level = SquishLevel(flow.level)
        let term = Text(level.term + ".")
            .font(.custom(SquishFont.interSemiBold, size: TypeStyle.b1.size, relativeTo: .body))
            .foregroundColor(SquishTheme.ink)
        let behaviour = Text(" " + level.behaviour)
            .font(.squish(.b1))
            .foregroundColor(SquishTheme.soft)
        return (term + behaviour)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: typeSize.lineHeight(for: .b1) * (typeSize.isAccessibilitySize ? 4 : 2),
                   alignment: .topLeading)
            .id(flow.level)
            .transition(.opacity)
            .animation(SquishTheme.Motion.readout, value: flow.level)
    }

    private func file() {
        Task {
            if let specimen = await flow.requestFiling(into: modelContext) {
                filedToken += 1
                onFiled(specimen)
            }
        }
    }
}

// MARK: - Screen 5

/// The plate stays exactly where screen 4 left it, so moving from naming to
/// measuring moves nothing. Only the checklist arrives.
@MainActor
struct MeasuringView: View {
    let flow: CaptureFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PhotoPlate(state: flow.plateImage.map(PlateState.filled) ?? .pending,
                       cornerRadius: SquishTheme.Radius.plateLarge)
                .frame(width: 260, height: 260)
                .overlay { scanSweep }
                .padding(.top, SquishTheme.Space.gutter)

            VStack(spacing: 0) {
                ForEach(SquishyVision.Stage.allCases) { stage in
                    if stage != .isolating { HairlineRule() }
                    ChecklistRow(stage: stage, isDone: flow.completedStages.contains(stage))
                }
            }
            .padding(.top, SquishTheme.Space.lg)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SquishTheme.Space.margin)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Measuring this specimen")
    }

    @ViewBuilder
    private var scanSweep: some View {
        // Reduce Motion drops the sweep entirely and lets the checklist carry
        // progress. SPEC.md §6.
        if reduceMotion {
            RoundedRectangle(cornerRadius: SquishTheme.Radius.plateLarge, style: .continuous)
                .strokeBorder(SquishTheme.chalk, lineWidth: SquishTheme.hairline)
                .padding(SquishTheme.Space.sm)
        } else {
            ScanLine()
        }
    }
}

private struct ScanLine: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(SquishTheme.chalk.opacity(0.55))
                .frame(height: 2)
                .offset(y: (offset + 1) / 2 * proxy.size.height)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        offset = 1
                    }
                }
        }
        .accessibilityHidden(true)
    }
}

private struct ChecklistRow: View {
    let stage: SquishyVision.Stage
    let isDone: Bool

    var body: some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            Group {
                if isDone {
                    RoundedRectangle(cornerRadius: 2).fill(SquishTheme.ink)
                        .transition(.blurReplace)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline)
                }
            }
            .frame(width: 13, height: 13)

            MonoLabel(text: stage.label, tint: isDone ? SquishTheme.ink : SquishTheme.soft)
            Spacer()
        }
        .frame(height: 44)
        .animation(SquishTheme.Motion.readout, value: isDone)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : "Pending")
    }
}

// MARK: - Duplicate twin card

/// Advisory, never blocking: the save button does not change state because of
/// it. SPEC.md §4.
struct DuplicateCard: View {
    let twin: Squishy
    let score: Double
    let current: UIImage?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
            MonoLabel(text: String(format: "Possible duplicate · %.2f", score))

            HStack(spacing: SquishTheme.Space.gutter) {
                PhotoPlate(image: current).frame(width: 88, height: 88)
                PhotoPlate(image: twin.image).frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: SquishTheme.Space.xs) {
                    Text(twin.name).typeStyle(.d4).foregroundStyle(SquishTheme.ink).lineLimit(2)
                    MonoLabel(text: "Already filed")
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: SquishTheme.Space.sm) {
                Chip(title: "Different one", action: onDismiss)
                Chip(title: "Never mind", action: onDismiss)
            }
        }
        .padding(SquishTheme.Space.gutter)
        .background(SquishTheme.chalk, in: RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SquishTheme.Radius.card, style: .continuous)
                .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline)
        )
    }
}
