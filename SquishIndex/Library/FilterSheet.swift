import SwiftData
import SwiftUI

/// Filtering by what the app measured: colour family, silhouette, squish range,
/// and whether a real size was captured. Only values that actually occur in the
/// library are offered — an empty filter is a dead end.
struct FilterSheet: View {
    @Binding var filter: LibraryFilter
    let specimens: [Squishy]

    @Environment(\.dismiss) private var dismiss

    private var presentColours: [ColorFamily] {
        let present = Set(specimens.map(\.colorFamily))
        return ColorFamily.allCases.filter(present.contains)
    }

    private var presentForms: [SpecimenForm] {
        let present = Set(specimens.map(\.silhouette))
        return SpecimenForm.allCases.filter(present.contains)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SquishTheme.Space.lg) {
                    section("Colour") {
                        FlowRow(spacing: SquishTheme.Space.sm) {
                            ForEach(presentColours) { family in
                                Chip(title: family.display,
                                     isActive: filter.colours.contains(family)) {
                                    toggle(family)
                                }
                            }
                        }
                    }

                    section("Form") {
                        FlowRow(spacing: SquishTheme.Space.sm) {
                            ForEach(presentForms, id: \.self) { form in
                                Chip(title: form.display,
                                     isActive: filter.forms.contains(form)) {
                                    toggle(form)
                                }
                            }
                        }
                    }

                    section("Squish \(filter.squishRange.lowerBound)–\(filter.squishRange.upperBound)") {
                        SquishRangePicker(range: $filter.squishRange)
                    }

                    section("Measurement") {
                        Chip(title: "Measured only",
                             isActive: filter.measuredOnly) {
                            filter.measuredOnly.toggle()
                        }
                    }
                }
                .padding(SquishTheme.Space.margin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SquishTheme.putty)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { filter = .none }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(SquishTheme.Radius.sheet)
        .presentationDragIndicator(.visible)
        .tint(SquishTheme.ink)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
            Eyebrow(title)
            content()
        }
    }

    private func toggle(_ family: ColorFamily) {
        if filter.colours.contains(family) { filter.colours.remove(family) }
        else { filter.colours.insert(family) }
    }

    private func toggle(_ form: SpecimenForm) {
        if filter.forms.contains(form) { filter.forms.remove(form) }
        else { filter.forms.insert(form) }
    }
}

/// Ten boxes; a tap moves whichever end of the range is nearer. Two ends, one
/// row, no system slider.
private struct SquishRangePicker: View {
    @Binding var range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: SquishTheme.Space.xxs) {
            ForEach(1...10, id: \.self) { level in
                let included = range.contains(level)
                Button {
                    move(to: level)
                } label: {
                    Text("\(level)")
                        .typeStyle(.m2)
                        .foregroundStyle(included ? SquishTheme.chalk : SquishTheme.quietInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(included ? SquishTheme.ink : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(included ? Color.clear : SquishTheme.line,
                                              lineWidth: SquishTheme.hairline)
                        )
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Squish \(level)")
                .accessibilityValue(included ? "Included" : "Excluded")
            }
        }
        .animation(SquishTheme.Motion.select, value: range)
    }

    private func move(to level: Int) {
        let lower = range.lowerBound
        let upper = range.upperBound
        if level < lower {
            range = level...upper
        } else if level > upper {
            range = lower...level
        } else if abs(level - lower) <= abs(level - upper) {
            range = level...upper
        } else {
            range = lower...level
        }
    }
}

// MARK: - Small edits

struct RenameSheet: View {
    @Bindable var specimen: Squishy
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focused: Bool
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SquishTheme.Space.margin) {
                NameField(text: $draft, isFocused: $focused)
                Spacer()
                PrimaryPill(title: "Save name") {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    specimen.name = trimmed.isEmpty ? Squishy.unnamed : trimmed
                    try? modelContext.save()
                    dismiss()
                }
            }
            .padding(SquishTheme.Space.margin)
            .background(SquishTheme.putty)
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(240)])
        .presentationCornerRadius(SquishTheme.Radius.sheet)
        .tint(SquishTheme.ink)
        .onAppear {
            draft = specimen.name == Squishy.unnamed ? "" : specimen.name
            focused = true
        }
    }
}

struct AdjustSquishSheet: View {
    @Bindable var specimen: Squishy
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var level = 5

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
                HStack(alignment: .lastTextBaseline) {
                    Eyebrow("Squish level")
                    Spacer()
                    HeroNumeral(value: level)
                }
                Durometer(level: $level)
                Text(SquishLevel(level).sentence)
                    .typeStyle(.b1)
                    .foregroundStyle(SquishTheme.soft)
                Spacer()
                PrimaryPill(title: "Save squish") {
                    specimen.squishLevel = level
                    try? modelContext.save()
                    dismiss()
                }
            }
            .padding(SquishTheme.Space.margin)
            .background(SquishTheme.putty)
            .navigationTitle(specimen.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(360)])
        .presentationCornerRadius(SquishTheme.Radius.sheet)
        .tint(SquishTheme.ink)
        .onAppear { level = specimen.squishLevel }
    }
}
