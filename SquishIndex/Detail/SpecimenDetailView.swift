import SwiftData
import SwiftUI

/// Screen 6 — the specimen sheet.
///
/// The photograph fills the top edge to edge and the specs arrive as a sheet
/// over it. Background interaction stays enabled up through the medium detent,
/// which is the single thing that makes this read as an object under glass
/// rather than a form.
struct SpecimenDetailView: View {
    @Bindable var specimen: Squishy

    @State private var showSpecs = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            SquishTheme.ink.ignoresSafeArea()

            if let image = specimen.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .horizontal)
                    .accessibilityLabel("Photograph of \(specimen.name)")
            }

            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SquishTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(SquishTheme.chalk.opacity(0.9), in: Circle())
            }
            .padding(.leading, SquishTheme.Space.margin)
            .accessibilityLabel("Back to the index")
        }
        .background(SquishTheme.putty)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSpecs) {
            SpecimenSpecs(specimen: specimen)
                // `.large` would bury the photograph the sheet is describing,
                // so the top detent stops just short of it. UX-SPEC §9 Q10.
                .presentationDetents([.fraction(0.55), .fraction(0.92)])
                .presentationCornerRadius(SquishTheme.Radius.sheet)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.55)))
                .interactiveDismissDisabled()
        }
    }
}

private struct SpecimenSpecs: View {
    @Bindable var specimen: Squishy

    private let labelColumn: CGFloat = 88

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SquishTheme.Space.margin) {
                Text(specimen.name)
                    .typeStyle(.d3)
                    .foregroundStyle(SquishTheme.ink)

                HStack(alignment: .bottom, spacing: SquishTheme.Space.gutter) {
                    Durometer(level: .constant(specimen.squishLevel),
                              isInteractive: false,
                              tint: tint,
                              trackWidth: 220)
                    Spacer(minLength: 0)
                    HeroNumeral(value: specimen.squishLevel)
                }

                Text(specimen.squish.sentence)
                    .typeStyle(.b1)
                    .foregroundStyle(SquishTheme.soft)

                specRows

                if !specimen.paletteHex.isEmpty {
                    VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
                        Eyebrow("Palette")
                        PaletteStrip(hexes: specimen.paletteHex,
                                     proportions: proportions)
                    }
                }
            }
            .padding(SquishTheme.Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SquishTheme.putty)
        .scrollIndicators(.hidden)
    }

    private var proportions: [Double]? {
        guard specimen.paletteProportions.count == specimen.paletteHex.count,
              !specimen.paletteProportions.isEmpty else { return nil }
        return specimen.paletteProportions
    }

    /// A pale specimen would otherwise make the frozen durometer invisible, so
    /// the tint is darkened until it clears 3:1 against chalk. The palette strip
    /// keeps the true, unmodified colour. UX-SPEC §4.5.
    private var tint: Color {
        specimen.dominantColor.darkenedForContrast(against: .white, ratio: 3)
    }

    @ViewBuilder
    private var specRows: some View {
        VStack(spacing: 0) {
            row("Squish", "\(specimen.squishLevel) of 10 · \(specimen.squish.term)")
            HairlineRule()
            row("Form", specimen.silhouette.display)
            HairlineRule()
            row("Colour", specimen.colorFamily.display)
            HairlineRule()
            if let width = specimen.widthMM, let height = specimen.heightMM {
                row("Size", String(format: "%.0f × %.0f mm", width, height))
                HairlineRule()
                row("Method", methodLine)
                HairlineRule()
            } else {
                // Never estimate millimetres from an unreferenced photo and
                // present them as measured. SPEC.md §7.
                row("Size", "Not captured")
                HairlineRule()
                row("Method", specimen.method.explanation)
                HairlineRule()
            }
            row("Filed", specimen.addedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var methodLine: String {
        let confidence = Int((specimen.confidence * 100).rounded())
        return "\(specimen.method.badgeText) · \(confidence)% confidence"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: SquishTheme.Space.gutter) {
            MonoLabel(text: label)
                .frame(width: labelColumn, alignment: .leading)
                .padding(.top, 3)
            Text(value)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Contrast

extension Color {
    /// Darkens a colour until it reaches the given contrast ratio against a
    /// background, leaving hue and saturation alone.
    func darkenedForContrast(against background: Color, ratio: Double) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation,
                                   brightness: &brightness, alpha: &alpha) else { return self }

        var candidate = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var guardRail = 0
        while candidate.contrastRatio(against: UIColor(background)) < ratio, guardRail < 40 {
            brightness = max(0, brightness - 0.025)
            candidate = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
            guardRail += 1
        }
        return Color(uiColor: candidate)
    }
}

extension UIColor {
    func contrastRatio(against other: UIColor) -> Double {
        let a = relativeLuminance + 0.05
        let b = other.relativeLuminance + 0.05
        return max(a, b) / min(a, b)
    }

    var relativeLuminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}
