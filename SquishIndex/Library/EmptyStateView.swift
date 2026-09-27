import SwiftUI

/// Screen 2 — the empty state.
///
/// It teaches by showing a blank accession card with its fields labelled: the
/// app showing its own schema. A stock photograph of a squishy would be a lie
/// about the catalogue's contents; a wireframe with real field names is honest
/// and teaches better. UX-SPEC §4.2.
struct EmptyStateView: View {
    let onCapture: () -> Void

    private let labelColumn: CGFloat = 88

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Specimen record · blank")
                    .padding(.top, SquishTheme.Space.lg)

                blankPlate
                    .padding(.top, SquishTheme.Space.gutter)

                fieldRows
                    .padding(.top, SquishTheme.Space.margin)

                Text("Photograph a squishy and the index fills this card in. Everything below the name is measured on your phone.")
                    .typeStyle(.b1)
                    .foregroundStyle(SquishTheme.ink)
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding(.top, SquishTheme.Space.margin)

                descriptorChips
                    .padding(.top, SquishTheme.Space.margin)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SquishTheme.Space.margin)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            FloatingCTA(title: "Photograph the first one",
                        systemImage: "camera",
                        isBarMode: true,
                        action: onCapture)
                .padding(SquishTheme.Space.margin)
        }
    }

    private var blankPlate: some View {
        PhotoPlate(state: .empty, cornerRadius: SquishTheme.Radius.plateLarge)
            .frame(width: 240, height: 240)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    /// Same label column and row height as the specimen sheet — the empty state
    /// is literally showing the record the user is about to fill.
    private var fieldRows: some View {
        VStack(spacing: 0) {
            row("Name") {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SquishTheme.line)
                    .frame(width: 120, height: 3)
            }
            HairlineRule()
            row("Squish") { MonoLabel(text: "--", tint: SquishTheme.line) }
            HairlineRule()
            row("Palette") {
                HStack(spacing: SquishTheme.Space.xxs) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline)
                            .frame(width: 13, height: 13)
                    }
                }
            }
            HairlineRule()
            row("Width") { MonoLabel(text: "-- mm", tint: SquishTheme.line) }
            HairlineRule()
            row("Form") { MonoLabel(text: "——", tint: SquishTheme.line) }
        }
        // Five rows of dashes read one at a time is noise, so the block speaks
        // once.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blank specimen record. Fields: name, squish, palette, width, form.")
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            MonoLabel(text: label)
                .frame(width: labelColumn, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(height: 32)
    }

    /// Only capabilities this build actually has. Advertising one it does not
    /// would contradict "do not fake measurements" in spirit.
    private var descriptorChips: some View {
        FlowRow(spacing: SquishTheme.Space.sm) {
            ForEach(["Subject mask", "Colour palette", "Silhouette", "Real millimetres", "Duplicate check"], id: \.self) {
                Chip(title: $0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Measured automatically: subject mask, colour palette, silhouette, real millimetres, duplicate check.")
    }
}

/// Chips wrap to additional rows rather than shrinking. UX-SPEC §7.2.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
