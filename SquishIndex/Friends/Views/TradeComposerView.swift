import SwiftData
import SwiftUI

/// F3 — ask a friend for one of theirs, offering one or more of yours.
/// No text box: the optional line comes from a fixed list.
struct TradeComposerView: View {
    let friend: Friend
    let wanted: FriendItem

    @Query(sort: \Squishy.addedAt, order: .reverse) private var allSpecimens: [Squishy]
    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var offered: Set<UUID> = []
    @State private var preset: TradePreset?
    @State private var isSending = false
    @State private var error: String?

    /// Already promised in another open trade? Not offerable again.
    private var mine: [Squishy] {
        let promised = store.promisedIDs
        return allSpecimens.filter { !$0.isTraded && !promised.contains($0.lineageID.uuidString) }
    }
    private var offeredSpecimens: [Squishy] { mine.filter { offered.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .typeStyle(.b1)
                    .foregroundStyle(SquishTheme.soft)
                    .frame(minHeight: 44)
                Spacer()
                Eyebrow("Request trade", tint: SquishTheme.ink)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, SquishTheme.Space.margin)
            .padding(.vertical, SquishTheme.Space.sm)
            .background(SquishTheme.chalk)
            HairlineRule()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("You'd get · from \(friend.name)")
                        .padding(.top, SquishTheme.Space.margin)
                    wantedRow.padding(.top, SquishTheme.Space.sm)

                    SectionHeading(title: "You'd give",
                                   detail: offered.isEmpty ? "Pick 1 or more" : "\(offered.count) for 1")
                    if mine.isEmpty {
                        Text("Your shelf is empty. Photograph a squishy first.")
                            .typeStyle(.b1)
                            .foregroundStyle(SquishTheme.soft)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SquishTheme.Space.gutter), count: 3),
                                  spacing: SquishTheme.Space.gutter) {
                            ForEach(mine) { specimen in
                                PickablePlate(image: specimen.image,
                                              name: specimen.name,
                                              squish: specimen.squishLevel,
                                              isSelected: offered.contains(specimen.id)) {
                                    toggle(specimen)
                                }
                            }
                        }
                    }

                    Eyebrow("Add a line · optional")
                        .padding(.top, SquishTheme.Space.margin)
                    FlowRow(spacing: SquishTheme.Space.sm) {
                        ForEach(TradePreset.allCases) { option in
                            Chip(title: option.rawValue,
                                 isActive: preset == option,
                                 accessibilityValueText: preset == option ? "Selected" : "") {
                                preset = preset == option ? nil : option
                            }
                        }
                    }
                    .padding(.top, SquishTheme.Space.sm)

                    if let error {
                        FriendsNotice(title: "Not sent", message: error)
                            .padding(.top, SquishTheme.Space.margin)
                    }
                }
                .padding(.horizontal, SquishTheme.Space.margin)
                .padding(.bottom, SquishTheme.Space.margin)
            }
            .scrollIndicators(.hidden)

            HairlineRule()
            PrimaryPill(title: sendTitle, action: send)
                .disabled(offered.isEmpty || isSending)
                .opacity(offered.isEmpty ? 0.4 : 1)
                .padding(SquishTheme.Space.margin)
                .background(SquishTheme.chalk)
        }
        .background(SquishTheme.putty.ignoresSafeArea())
        .presentationCornerRadius(SquishTheme.Radius.sheet)
        .sensoryFeedback(.selection, trigger: offered)
    }

    private var sendTitle: String {
        if isSending { return "Sending…" }
        return offered.isEmpty ? "Send request" : "Send request · \(offered.count) for 1"
    }

    private var wantedRow: some View {
        HStack(spacing: SquishTheme.Space.gutter) {
            PhotoPlate(image: wanted.image, cornerRadius: SquishTheme.Radius.card)
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: SquishTheme.Space.xs) {
                Text(wanted.name)
                    .typeStyle(.d4)
                    .foregroundStyle(SquishTheme.ink)
                MonoLabel(text: "Squish \(wanted.squish.padded)" + sizeSuffix)
                PaletteStrip(hexes: wanted.paletteHex)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var sizeSuffix: String {
        guard let width = wanted.widthMM else { return "" }
        return String(format: " · %.0f mm", width)
    }

    private func toggle(_ specimen: Squishy) {
        if offered.contains(specimen.id) {
            offered.remove(specimen.id)
        } else {
            offered.insert(specimen.id)
        }
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                try await store.sendRequest(to: friend, wanting: [wanted],
                                            offering: offeredSpecimens, line: preset)
                dismiss()
            } catch {
                self.error = FriendsStore.describe(error)
            }
        }
    }
}
