import SwiftUI

/// The grid card. Its plate's hairline is the card's only boundary — wrapping
/// the whole card in a second border would double the hairlines and make the
/// grid read as a spreadsheet. UX-SPEC §4.1.
struct SpecimenCard: View {
    let specimen: Squishy
    let width: CGFloat

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoPlate(image: specimen.image)
                .frame(width: width, height: width)

            Text(specimen.name)
                .typeStyle(.d4)
                .foregroundStyle(SquishTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .topLeading)
                // Reserved, never literal: a hardcoded height breaks Dynamic
                // Type. UX-SPEC §7.1.
                .frame(height: typeSize.lineHeight(for: .d4) * 2, alignment: .topLeading)
                .padding(.top, SquishTheme.Space.sm)

            HStack(spacing: 0) {
                PaletteStrip(hexes: specimen.paletteHex)
                Spacer(minLength: SquishTheme.Space.sm)
                MonoLabel(text: specimen.squish.padded, style: .value, tint: SquishTheme.ink)
            }
            .frame(height: 15)
            .padding(.top, SquishTheme.Space.xs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(specimen.spokenSummary)
        .accessibilityAddTraits(.isButton)
    }
}

/// The Dynamic-Type reflow partner. At accessibility sizes the two-up grid
/// becomes a one-up list, because the two layouts are structurally different
/// rather than the same layout at two tightnesses. UX-SPEC §7.2.
struct SpecimenRow: View {
    let specimen: Squishy

    var body: some View {
        HStack(alignment: .top, spacing: SquishTheme.Space.gutter) {
            PhotoPlate(image: specimen.image)
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: SquishTheme.Space.xs) {
                Text(specimen.name)
                    .typeStyle(.d4)
                    .foregroundStyle(SquishTheme.ink)
                    .lineLimit(3)
                PaletteStrip(hexes: specimen.paletteHex)
                MonoLabel(text: specimen.squish.padded, style: .value, tint: SquishTheme.ink)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(specimen.spokenSummary)
        .accessibilityAddTraits(.isButton)
    }
}
