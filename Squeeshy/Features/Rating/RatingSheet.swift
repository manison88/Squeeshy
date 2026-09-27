import SwiftUI
import SwiftData

/// Squeeshiness, set on the glass scale. The squeeshy above inflates with the score
/// and wobbles whenever the bead moves, so the number always has a body attached.
struct RatingSheet: View {
    var squishy: Squishy
    var tint: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var position: Double
    @State private var wobble: Double = 0

    private let domain = TraitDomain(trait: .squeeshiness, lower: 0, upper: 10)

    init(squishy: Squishy, tint: Color) {
        self.squishy = squishy
        self.tint = tint
        // Seeded here rather than in onAppear: the scale is a child, so its own
        // onAppear runs first and would latch onto a stale starting value.
        _position = State(initialValue: (squishy.squeeshiness / 10).clamped(to: 0...1))
    }

    private var score: Double { domain.value(at: position) }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: Tint.single(squishy.hue))

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.ink3)
                    .frame(width: 38, height: 4)
                    .padding(.top, 10)

                SquishyImage(squishy: squishy)
                    .frame(width: 118, height: 118)
                    // Inflates with the score, so a 9 is visibly plumper than a 3.
                    .scaleEffect(0.84 + position * 0.28)
                    .squish(wobble, anchor: .center)
                    .padding(.top, 18)
                    .animation(Motion.rebound, value: wobble)

                Text(squishy.name)
                    .font(.display(20, .bold))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 12)

                GlassScale(domain: domain, style: .score, position: $position,
                           tint: tint, label: "squeeshiness")
                    .padding(.horizontal, 22)
                    .padding(.top, 22)

                HStack(spacing: 10) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(SheetButton(filled: false, tint: tint))
                    Button("Save") { save() }
                        .buttonStyle(SheetButton(filled: true, tint: tint))
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)

                Spacer(minLength: 12)
            }
        }
        .onChange(of: position) { old, new in
            // A kick whenever the bead crosses a whole point, harder the softer the
            // squeeshy is said to be, so the object above agrees with the control.
            if Int(old * 10) != Int(new * 10) {
                wobble = 0.10 + position * 0.26
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { wobble = 0 }
            }
        }
    }

    private func save() {
        squishy.squeeshiness = (score * 10).rounded() / 10
        try? context.save()
        dismiss()
    }
}

struct SheetButton: ButtonStyle {
    var filled: Bool
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(filled ? Color(red: 0.05, green: 0.04, blue: 0.08) : Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if filled {
                    Capsule().fill(tint)
                }
            }
            .glassEffect(filled ? .clear : .regular.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

// MARK: - Trait editing

enum EditableTrait: String, Identifiable {
    case shape, size, colour
    var id: String { rawValue }

    var title: String {
        switch self {
        case .shape:  return "Body"
        case .size:   return "Size"
        case .colour: return "Colour"
        }
    }
}

/// Tapping any trait chip lands here. Corrections should feel like fixing a label,
/// not filling in a form.
struct TraitEditor: View {
    var trait: EditableTrait
    var squishy: Squishy?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.04, blue: 0.08).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                MetaLabel(text: trait.title)
                    .padding(.top, 18)

                switch trait {
                case .shape:
                    chipGrid(Species.allCases.map(\.rawValue.capitalized)) { raw in
                        if let s = Species(rawValue: raw.lowercased()) { squishy?.species = s }
                    }
                case .size:
                    chipGrid(SizeClass.allCases.map(\.label)) { label in
                        if let match = SizeClass.allCases.first(where: { $0.label == label }) {
                            squishy?.size = match
                        }
                    }
                case .colour:
                    slider(range: 0...359, value: squishy?.hue ?? 0, unit: "°") {
                        squishy?.hue = $0
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 22)
        }
        .onDisappear { try? context.save() }
    }

    private func chipGrid(_ options: [String], apply: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    apply(option)
                    dismiss()
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.tap)
            }
        }
    }

    private func slider(range: ClosedRange<Double>, value: Double, unit: String,
                        apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(Int(value))\(unit)")
                .font(.display(28, .heavy))
                .foregroundStyle(Color.ink)
            Slider(value: Binding(get: { value }, set: apply), in: range)
                .tint(.white)
            Button("Done") { dismiss() }
                .buttonStyle(SheetButton(filled: true, tint: .white))
        }
    }
}
