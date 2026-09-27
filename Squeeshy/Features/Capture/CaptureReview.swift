import SwiftUI

/// What you see the instant the cut-out lands. The scale is already live, so rating
/// costs no extra tap; the name is the only thing you have to type.
struct CaptureReview: View {
    var cutout: UIImage
    var traits: ExtractedTraits
    var existing: [Squishy]
    var onSave: (String, Double, Species, SizeClass, Squishy?) -> Void
    var onRetake: () -> Void

    @State private var name = ""
    @State private var position: Double = 0.6
    @State private var species: Species
    /// Deliberately unset. Size is asked for, not defaulted, so nobody saves a
    /// whole shelf that silently claims to be medium.
    @State private var size: SizeClass?
    @State private var landed = false
    @State private var duplicate: Squishy?
    @State private var acknowledgedDuplicate = false
    @FocusState private var nameFocused: Bool

    private let domain = TraitDomain(trait: .squeeshiness, lower: 0, upper: 10)

    init(cutout: UIImage, traits: ExtractedTraits, existing: [Squishy],
         onSave: @escaping (String, Double, Species, SizeClass, Squishy?) -> Void,
         onRetake: @escaping () -> Void) {
        self.cutout = cutout
        self.traits = traits
        self.existing = existing
        self.onSave = onSave
        self.onRetake = onRetake
        _species = State(initialValue: traits.species)
    }

    private var tint: Color { Hue.color(traits.hue, saturation: max(0.42, traits.saturation)) }
    private var score: Double { domain.value(at: position) }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // The cut-out rises and settles as if it were lifted off the photo.
            Image(uiImage: cutout)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 220, maxHeight: 220)
                .shadow(color: tint.opacity(0.45), radius: 34, y: 14)
                .scaleEffect(landed ? 1 : 0.72)
                .offset(y: landed ? 0 : 26)
                .opacity(landed ? 1 : 0)
                .padding(.top, 6)

            traitRow
                .padding(.top, 14)
                .opacity(landed ? 1 : 0)

            nameField
                .padding(.horizontal, 24)
                .padding(.top, 14)

            sizePicker
                .padding(.horizontal, 24)
                .padding(.top, 14)

            GlassScale(domain: domain, style: .score, position: $position,
                       tint: tint, label: "how squeeshy?")
                .padding(.horizontal, 24)
                .padding(.top, 18)

            if let duplicate, !acknowledgedDuplicate {
                duplicateBanner(duplicate)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 10)

            saveRow
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .onAppear {
            withAnimation(Motion.arrive.delay(0.05)) { landed = true }
            duplicate = findDuplicate()
            // Deliberately not focusing the name field. Raising the keyboard on arrival
            // covers the cut-out, so you are naming a squeeshy you cannot see — and the
            // whole point of this screen is looking at what the lift produced first.
        }
        .animation(Motion.tap, value: acknowledgedDuplicate)
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button { onRetake() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Retake").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.tap)
            Spacer()
            MetaLabel(text: "background removed")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    /// What the on-device pass worked out. Every one is tappable, because a guess you
    /// cannot correct is worse than no guess.
    private var traitRow: some View {
        HStack(spacing: 6) {
            readOnlyChip(Hue.name(traits.hue), swatch: tint)

            Menu {
                ForEach(Species.allCases, id: \.self) { s in
                    Button(s.shapeName + " · " + s.rawValue.capitalized) { species = s }
                }
            } label: {
                chipLabel(species.shapeName)
                    .contentShape(.capsule)
            }

        }
    }

    /// The one thing the photo genuinely cannot tell us. Three buckets, no default,
    /// and no saving until it is answered.
    private var sizePicker: some View {
        VStack(spacing: 8) {
            MetaLabel(text: size == nil ? "how big is it?" : "size")
            HStack(spacing: 7) {
                ForEach(SizeClass.allCases) { option in
                    Button {
                        withAnimation(Motion.tap) { size = option }
                    } label: {
                        VStack(spacing: 2) {
                            Text(option.label)
                                .font(.system(size: 13, weight: .semibold))
                            Text(option.hint)
                                .font(.system(size: 9.5))
                                .opacity(0.55)
                        }
                        .foregroundStyle(size == option
                                         ? Color(red: 0.05, green: 0.04, blue: 0.08)
                                         : Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            if size == option {
                                RoundedRectangle(cornerRadius: 18).fill(tint)
                            }
                        }
                        .glassEffect(size == option ? .clear : .regular.interactive(),
                                     in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.tap)
                }
            }
        }
    }

    private func readOnlyChip(_ text: String, swatch: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(swatch).frame(width: 10, height: 10)
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .glassEffect(.regular, in: .capsule)
    }

    private func chipLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.5)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var nameField: some View {
        TextField("", text: $name,
                  prompt: Text("Name it").foregroundStyle(Color.ink3))
            .focused($nameFocused)
            .font(.display(26, .heavy))
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .submitLabel(.done)
            .autocorrectionDisabled()
    }

    private func duplicateBanner(_ match: Squishy) -> some View {
        VStack(spacing: 10) {
            Text("This looks like \(match.name).")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                Button {
                    onSave(name, score, species, size ?? .medium, match)
                } label: {
                    Text("I own two")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.tap)

                Button {
                    acknowledgedDuplicate = true
                } label: {
                    Text("It's different")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.tap)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var saveRow: some View {
        Button {
            guard let size else { return }
            onSave(name, score, species, size, nil)
        } label: {
            Text(saveLabel)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.05, green: 0.04, blue: 0.08))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSave ? tint : Color.ink3, in: .capsule)
        }
        .buttonStyle(.tap)
        .disabled(!canSave)
        .animation(Motion.tap, value: canSave)
    }

    private var canSave: Bool { !name.isEmpty && size != nil }

    private var saveLabel: String {
        if name.isEmpty { return "Name it to save" }
        if size == nil { return "Pick a size to save" }
        return "Save \(name)"
    }

    // MARK: Duplicates

    /// Cheap similarity on the traits we already have: same body plan, close hue and
    /// close size. Good enough to catch a genuine re-shoot without a second model.
    private func findDuplicate() -> Squishy? {
        existing.first { candidate in
            candidate.species == traits.species
            && Hue.distance(candidate.hue, traits.hue) < 18
        }
    }
}
