import SwiftUI

// MARK: - Mono labels

/// Data type. Uppercase eyebrows and field labels (`M1`), or bare in-line
/// numerals (`M2`). UX-SPEC §3.6.
struct MonoLabel: View {
    enum Style { case label, value }

    let text: String
    var style: Style = .label
    var tint: Color = SquishTheme.soft

    var body: some View {
        Text(text)
            .typeStyle(style == .label ? .m1 : .m2)
            .foregroundStyle(tint)
    }
}

/// Uppercased at render, never in the data — a user-entered string is never
/// uppercased.
struct Eyebrow: View {
    let text: String
    var tint: Color = SquishTheme.soft

    init(_ text: String, tint: Color = SquishTheme.soft) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        MonoLabel(text: text, style: .label, tint: tint)
    }
}

/// Exactly 1 pt — one logical point, the deliberate editorial weight, not a
/// device pixel. UX-SPEC §3.15.
struct HairlineRule: View {
    var inset: CGFloat = 0
    var color: Color = SquishTheme.line

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: SquishTheme.hairline)
            .padding(.horizontal, inset)
            .accessibilityHidden(true)
    }
}

// MARK: - Chip

struct Chip: View {
    let title: String
    var count: Int?
    var trailingCaret: Bool = false
    var isCaretUp: Bool = false
    var isActive: Bool = false
    var isEnabled: Bool = true
    var accessibilityLabelText: String?
    var accessibilityValueText: String?
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(ChipButtonStyle())
                .disabled(!isEnabled)
                .accessibilityLabel(accessibilityLabelText ?? title)
                .accessibilityValue(accessibilityValueText ?? "")
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        HStack(spacing: SquishTheme.Space.sm) {
            Text(title)
                .typeStyle(.m1)
                .foregroundStyle(labelTint)
            if let count {
                Text("\(count)")
                    .typeStyle(.m2)
                    .foregroundStyle(SquishTheme.chalk)
                    .padding(.horizontal, SquishTheme.Space.xs)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(SquishTheme.ink, in: Capsule())
                    .transition(.blurReplace)
            }
            if trailingCaret {
                Image(systemName: caretSymbol)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(labelTint)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isCaretUp ? 180 : 0)))
            }
        }
        .padding(.horizontal, SquishTheme.Space.gutter)
        .frame(height: 30)
        .overlay(
            Capsule()
                .strokeBorder(borderTint, lineWidth: isActive ? 1.5 : SquishTheme.hairline)
        )
        // Visual 30, hit region 44. UX-SPEC §7.4.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(SquishTheme.Motion.readout, value: count)
        .animation(SquishTheme.Motion.readout, value: isActive)
    }

    private var caretSymbol: String {
        guard reduceMotion else { return "chevron.down" }
        return isCaretUp ? "chevron.up" : "chevron.down"
    }

    private var labelTint: Color {
        guard isEnabled else { return SquishTheme.soft.opacity(0.4) }
        // `soft` at 10 pt fails AA as a sole carrier, so the rest state uses a
        // token opacity of ink instead. UX-SPEC §7.3 rule 1.
        return isActive ? SquishTheme.ink : SquishTheme.quietInk
    }

    private var borderTint: Color {
        guard isEnabled else { return SquishTheme.line }
        return isActive ? SquishTheme.ink : SquishTheme.line
    }
}

private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

// MARK: - Segmented control

/// Used once, for Grid · Shelf · Stats. SPEC.md §3.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Option]

    struct Option: Identifiable {
        let value: Value
        let title: String
        var isEnabled: Bool = true
        var id: Value { value }
    }

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(3)
        .frame(minHeight: 36)
        .overlay(
            Capsule().strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline)
        )
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }

    private func segment(_ option: Option) -> some View {
        Button {
            guard option.isEnabled else { return }
            withAnimation(reduceMotion ? nil : SquishTheme.Motion.select) {
                selection = option.value
            }
        } label: {
            Text(option.title)
                .typeStyle(.m1)
                .foregroundStyle(tint(for: option))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 30)
                .background {
                    if selection == option.value {
                        if reduceMotion {
                            Capsule().fill(SquishTheme.ink).transition(.opacity)
                        } else {
                            Capsule().fill(SquishTheme.ink)
                                .matchedGeometryEffect(id: "selection", in: pill)
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .accessibilityAddTraits(selection == option.value ? [.isButton, .isSelected] : .isButton)
    }

    private func tint(for option: Option) -> Color {
        if selection == option.value { return SquishTheme.chalk }
        // `soft` fails AA at 10 pt; ink at 62 % measures 4.6:1. UX-SPEC §7.3.
        return option.isEnabled ? SquishTheme.quietInk : SquishTheme.soft.opacity(0.4)
    }
}

// MARK: - Photo plate

enum PlateState {
    case filled(UIImage)
    case empty
    case pending
    case failed
}

struct PhotoPlate<Overlay: View>: View {
    let state: PlateState
    var cornerRadius: CGFloat = SquishTheme.Radius.plate
    var showsBorder: Bool = true
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(SquishTheme.chalk)
            .overlay {
                switch state {
                case .filled(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .failed:
                    // No icon, no spinner, no shimmer — a shimmer gradient is
                    // chrome colour and the chrome has no colour. UX-SPEC §3.5.
                    MonoLabel(text: "Image unavailable")
                case .empty, .pending:
                    Color.clear
                }
            }
            .clipShape(shape)
            .overlay {
                if showsBorder {
                    shape.strokeBorder(SquishTheme.line, lineWidth: SquishTheme.hairline)
                }
            }
            .overlay { overlay() }
    }
}

extension PhotoPlate where Overlay == EmptyView {
    init(state: PlateState,
         cornerRadius: CGFloat = SquishTheme.Radius.plate,
         showsBorder: Bool = true) {
        self.init(state: state, cornerRadius: cornerRadius, showsBorder: showsBorder) { EmptyView() }
    }

    init(image: UIImage?,
         cornerRadius: CGFloat = SquishTheme.Radius.plate,
         showsBorder: Bool = true) {
        self.init(state: image.map { PlateState.filled($0) } ?? .pending,
                  cornerRadius: cornerRadius,
                  showsBorder: showsBorder) { EmptyView() }
    }
}

// MARK: - Palette strip

/// One accessibility element and one hit target, always: 13 pt swatches 3 pt
/// apart can never carry individual 44 pt regions. UX-SPEC §3.7.
struct PaletteStrip: View {
    let hexes: [String]
    var swatchSize: CGFloat = 13
    /// Non-nil switches to the proportion bar used on the specimen sheet.
    var proportions: [Double]?

    var body: some View {
        Group {
            if hexes.isEmpty {
                // Never pad missing slots with grey — that fabricates data.
                EmptyView()
            } else if let proportions, proportions.count == hexes.count {
                proportionBar(proportions)
            } else {
                uniformSwatches
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Palette")
        .accessibilityValue(hexes.isEmpty ? "None extracted" : "\(hexes.count) colours")
    }

    private var uniformSwatches: some View {
        HStack(spacing: SquishTheme.Space.xxs) {
            ForEach(hexes.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hexString: hexes[index]) ?? SquishTheme.chalk)
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(SquishTheme.ink.opacity(0.08), lineWidth: SquishTheme.hairline)
                    )
            }
        }
    }

    private func proportionBar(_ proportions: [Double]) -> some View {
        GeometryReader { proxy in
            let total = max(proportions.reduce(0, +), 0.0001)
            HStack(spacing: 0) {
                ForEach(hexes.indices, id: \.self) { index in
                    (Color(hexString: hexes[index]) ?? SquishTheme.chalk)
                        .frame(width: proxy.size.width * proportions[index] / total)
                }
            }
        }
        .frame(height: 22)
        .clipShape(Capsule())
    }
}

// MARK: - Hero numeral

struct HeroNumeral: View {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(value)")
            .typeStyle(.d1)
            .foregroundStyle(SquishTheme.ink)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
            .animation(SquishTheme.Motion.readout, value: value)
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// The full-width ink pill used for every primary action outside the grid.
struct PrimaryPill: View {
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.b2)
                .foregroundStyle(SquishTheme.chalk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(SquishTheme.ink, in: Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

/// SPEC.md §2 licenses a shadow here and on the bottom sheet, nowhere else.
struct FloatingCTA: View {
    let title: String
    let systemImage: String
    var isCollapsed: Bool = false
    var isBarMode: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SquishTheme.Space.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                if !isCollapsed {
                    Text(title)
                        .typeStyle(isBarMode ? .b2 : .m1)
                        .transition(.blurReplace)
                }
            }
            .foregroundStyle(SquishTheme.chalk)
            .padding(.horizontal, isCollapsed ? 0 : SquishTheme.Space.margin)
            .frame(maxWidth: isBarMode ? .infinity : nil)
            .frame(width: isCollapsed ? 52 : nil, height: 52)
            .background(SquishTheme.ink, in: Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.96))
        // With zero content there is nothing to float over, so the empty
        // state's bar mode drops the shadow. UX-SPEC §4.2.
        .shadow(color: isBarMode ? .clear : SquishTheme.Shadow.ambient.color,
                radius: SquishTheme.Shadow.ambient.radius,
                y: SquishTheme.Shadow.ambient.y)
        .shadow(color: isBarMode ? .clear : SquishTheme.Shadow.contact.color,
                radius: SquishTheme.Shadow.contact.radius,
                y: SquishTheme.Shadow.contact.y)
        .accessibilityLabel("Capture a specimen")
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

// MARK: - Name field

struct NameField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    /// Soft cap, enforced by silently refusing further input — no error, no
    /// counter. UX-SPEC §3.13.
    private let softCap = 48

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.gutter) {
            TextField("", text: $text, prompt: promptText)
                .typeStyle(.d3)
                .foregroundStyle(SquishTheme.ink)
                .tint(SquishTheme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .submitLabel(.done)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .focused($isFocused)
                .frame(minHeight: 44)
                .onChange(of: text) { _, new in
                    if new.count > softCap { text = String(new.prefix(softCap)) }
                }
            Rectangle()
                .fill(isFocused ? SquishTheme.ink : SquishTheme.line)
                .frame(height: isFocused ? 1.5 : SquishTheme.hairline)
                .animation(SquishTheme.Motion.readout, value: isFocused)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .accessibilityLabel("Specimen name")
    }

    // The placeholder is the field's only affordance, so it renders in `soft`
    // even though the rule below it renders in `line`. UX-SPEC §3.13.
    private var promptText: Text {
        Text("Name this one")
            .foregroundColor(SquishTheme.soft)
    }
}

// MARK: - Index header

struct IndexHeader: View {
    let title: String
    let specimenCount: Int
    let averageSquish: Double?
    var filteredCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.xs) {
            Text(title)
                .typeStyle(.d2)
                .foregroundStyle(SquishTheme.ink)
            Text(statLine)
                .typeStyle(.m1)
                .foregroundStyle(SquishTheme.soft)
            if let filteredCount, filteredCount != specimenCount {
                Text("Showing \(filteredCount) of \(specimenCount)")
                    .typeStyle(.m1)
                    .foregroundStyle(SquishTheme.soft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The mean of an empty set is undefined, so at zero the average clause is
    /// omitted rather than printed as an em-dash. UX-SPEC §4.1.
    private var statLine: String {
        let noun = specimenCount == 1 ? "specimen" : "specimens"
        guard let averageSquish, specimenCount > 0 else { return "\(specimenCount) \(noun)" }
        return String(format: "%d %@ · avg squish %.1f", specimenCount, noun, averageSquish)
    }
}
