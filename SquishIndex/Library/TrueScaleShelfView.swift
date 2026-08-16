import SwiftUI

/// Screen 7 — the true-scale shelf.
///
/// Every measured specimen at its actual relative size, smallest first, on
/// hairline baselines with millimetre ticks. This is the payoff for the
/// measurement work, so it prints its own scale factor: that is what makes it a
/// plate in a catalogue rather than a picture.
struct TrueScaleShelfView: View {
    let specimens: [Squishy]

    private var measured: [Squishy] {
        specimens.filter(\.hasSize).sorted { ($0.longestEdgeMM ?? 0) < ($1.longestEdgeMM ?? 0) }
    }

    private var unmeasured: [Squishy] {
        specimens.filter { !$0.hasSize }
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = proxy.size.width - SquishTheme.Space.margin * 2
            let largest = measured.compactMap(\.longestEdgeMM).max() ?? 1
            let pointsPerMM = contentWidth / max(largest, 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if measured.isEmpty {
                        emptyNotice
                    } else {
                        MonoLabel(text: String(format: "1 pt = %.2f mm", 1 / pointsPerMM))
                            .padding(.top, SquishTheme.Space.gutter)

                        ForEach(measured) { specimen in
                            row(specimen, pointsPerMM: pointsPerMM, contentWidth: contentWidth)
                        }
                        .padding(.top, SquishTheme.Space.margin)
                    }

                    if !unmeasured.isEmpty {
                        HairlineRule().padding(.vertical, SquishTheme.Space.margin)
                        Eyebrow("Not measured · \(unmeasured.count)")
                        Text("These filed without a size. Photograph them again with a card beside them, or on a device with depth.")
                            .typeStyle(.b3)
                            .foregroundStyle(SquishTheme.soft)
                            .padding(.top, SquishTheme.Space.sm)
                    }

                    Color.clear.frame(height: 96)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SquishTheme.Space.margin)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ specimen: Squishy, pointsPerMM: CGFloat, contentWidth: CGFloat) -> some View {
        let widthMM = specimen.widthMM ?? specimen.longestEdgeMM ?? 0
        let heightMM = specimen.heightMM ?? specimen.longestEdgeMM ?? 0
        let width = max(12, CGFloat(widthMM) * pointsPerMM)
        let height = max(12, CGFloat(heightMM) * pointsPerMM)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: SquishTheme.Space.gutter) {
                if let image = specimen.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: width, height: height)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(specimen.name)
                        .typeStyle(.d4)
                        .foregroundStyle(SquishTheme.ink)
                        .lineLimit(1)
                    MonoLabel(text: String(format: "%.0f × %.0f mm · %@",
                                           widthMM, heightMM, specimen.method.badgeText),
                              style: .value)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, SquishTheme.Space.sm)

            TickRule(widthMM: Double(contentWidth / pointsPerMM), pointsPerMM: pointsPerMM)
        }
        .padding(.bottom, SquishTheme.Space.margin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(specimen.name). \(Int(widthMM.rounded())) by \(Int(heightMM.rounded())) millimetres.")
    }

    private var emptyNotice: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
            Eyebrow("Nothing measured yet")
            Text("The shelf draws specimens at their real relative size, so it needs at least one measurement. Lay any bank card flat beside the toy when you photograph it.")
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.ink)
                .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(.top, SquishTheme.Space.lg)
    }
}

/// The baseline: 5 pt ticks every 10 mm, 9 pt every 50 mm.
private struct TickRule: View {
    let widthMM: Double
    let pointsPerMM: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(path, with: .color(SquishTheme.line), lineWidth: 1)

            var mm = 0.0
            while mm <= widthMM {
                let x = CGFloat(mm) * pointsPerMM
                guard x <= size.width else { break }
                let isMajor = mm.truncatingRemainder(dividingBy: 50) == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: isMajor ? 9 : 5))
                context.stroke(tick, with: .color(SquishTheme.line), lineWidth: 1)
                mm += 10
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
