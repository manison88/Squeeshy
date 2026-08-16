import SwiftUI

/// Screen 8 — stats.
///
/// The histogram is built from `DurometerBar`'s own geometry: bin *i* carries
/// the compression the durometer shows at level *i*, and its height carries the
/// count. The input control and the summary become the same object seen twice.
struct StatsView: View {
    let stats: LibraryStats

    // Wider than the sheet's 88: "Most unusual" wraps at 88 and the row grid
    // stops reading as a grid.
    private let labelColumn: CGFloat = 104

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SquishTheme.Space.lg) {
                histogram
                colourSpread
                summary
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, SquishTheme.Space.margin)
            .padding(.top, SquishTheme.Space.margin)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Histogram

    private var histogram: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
            Eyebrow("Squish distribution")

            let peak = max(stats.squishHistogram.max() ?? 0, 1)
            HStack(spacing: 0) {
                ForEach(1...10, id: \.self) { level in
                    let count = stats.squishHistogram[level - 1]
                    HistogramBar(level: level,
                                 share: Double(count) / Double(peak),
                                 count: count)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Durometer.trackHeight + 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Squish distribution")
            .accessibilityValue(histogramSpoken)
        }
    }

    private var histogramSpoken: String {
        let parts = stats.squishHistogram.enumerated()
            .filter { $0.element > 0 }
            .map { "level \($0.offset + 1): \($0.element)" }
        return parts.isEmpty ? "No specimens" : parts.joined(separator: ", ")
    }

    // MARK: Colour spread

    private var colourSpread: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
            Eyebrow("Colour spread")

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(stats.colourSpread) { entry in
                        entry.family.swatch
                            .frame(width: proxy.size.width * entry.share)
                    }
                }
            }
            .frame(height: 22)
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Colour spread")
            .accessibilityValue(colourSpoken)

            FlowRow(spacing: SquishTheme.Space.sm) {
                ForEach(stats.colourSpread) { entry in
                    HStack(spacing: SquishTheme.Space.xs) {
                        RoundedRectangle(cornerRadius: 3).fill(entry.family.swatch)
                            .frame(width: 9, height: 9)
                        MonoLabel(text: "\(entry.family.display) \(Int((entry.share * 100).rounded()))%")
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var colourSpoken: String {
        stats.colourSpread
            .map { "\($0.family.display) \(Int(($0.share * 100).rounded())) percent" }
            .joined(separator: ", ")
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 0) {
            summaryRow("Specimens", "\(stats.count)")
            HairlineRule()
            summaryRow("Avg squish", stats.averageSquish.map { String(format: "%.1f", $0) } ?? "—")
            HairlineRule()
            summaryRow("Measured", "\(stats.measuredCount) of \(stats.count)")
            if let smallest = stats.smallest, let edge = smallest.longestEdgeMM {
                HairlineRule()
                summaryRow("Smallest", "\(smallest.name) · \(Int(edge.rounded())) mm")
            }
            if let largest = stats.largest, let edge = largest.longestEdgeMM {
                HairlineRule()
                summaryRow("Largest", "\(largest.name) · \(Int(edge.rounded())) mm")
            }
            if let unusual = stats.mostUnusual, stats.count > 1 {
                HairlineRule()
                summaryRow("Most unusual", unusual.name)
            }
            if let form = stats.formCounts.first {
                HairlineRule()
                summaryRow("Common form", "\(form.form.display) · \(form.count)")
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            MonoLabel(text: label)
                .frame(width: labelColumn, alignment: .leading)
            Text(value)
                .typeStyle(.b1)
                .foregroundStyle(SquishTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

private struct HistogramBar: View {
    let level: Int
    let share: Double
    let count: Int

    var body: some View {
        let k = SquishLevel(level).k
        let width = DurometerBar.width(k: k)
        let full = DurometerBar.baseHeight(level)
        let height = max(count > 0 ? 3 : 1, full * share)
        let radius = min(3 + 10 * k, width / 2, height / 2)

        VStack(spacing: SquishTheme.Space.xs) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(count > 0 ? SquishTheme.ink : SquishTheme.soft.opacity(0.35))
                .frame(width: width, height: height)
            MonoLabel(text: "\(level)", style: .value,
                      tint: count > 0 ? SquishTheme.ink : SquishTheme.soft)
        }
    }
}
