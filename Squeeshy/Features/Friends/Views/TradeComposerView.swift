import SwiftUI
import SwiftData

/// Ask a friend for one of theirs, offering one or more of yours. No text box:
/// the optional line comes from a fixed list, so there is nothing to moderate.
struct TradeComposerView: View {
    var friend: Friend
    var wanted: FriendItem

    @Query(sort: \Squishy.addedAt, order: .reverse) private var all: [Squishy]
    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var offered: Set<UUID> = []
    @State private var preset: TradePreset?
    @State private var isSending = false
    @State private var error: String?

    /// Already promised in another open trade? Not offerable again, or it could
    /// end up promised to two people.
    private var promised: Set<String> { store.promisedIDs }
    private var offeredSquishies: [Squishy] { all.filter { offered.contains($0.id) } }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: Tint.single(wanted.hue))
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Request trade")
                            .font(.display(24, .heavy))
                            .foregroundStyle(Color.ink)
                        MetaLabel(text: "with \(friend.name)")
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .buttonStyle(.tap)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        friendsSectionLabel("You'd get")
                        HStack(spacing: 13) {
                            wanted.picture
                                .frame(width: 56, height: 56)
                                .padding(5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(wanted.name)
                                    .font(.display(16, .semibold))
                                    .foregroundStyle(Color.ink)
                                MetaLabel(text: wanted.traitLine)
                            }
                            Spacer()
                            Text(String(format: "%.1f", wanted.squeeshiness))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.ink)
                        }
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        .accessibilityElement(children: .combine)

                        friendsSectionLabel("You'd give",
                                            detail: offered.isEmpty ? "pick one or more" : "\(offered.count) for 1")
                        if all.isEmpty {
                            Text("Your collection is empty. Photograph a squeeshy first.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.ink2)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                            ForEach(all) { squishy in
                                let isPromised = promised.contains(squishy.lineageID.uuidString)
                                PickTile(name: squishy.name,
                                         tint: squishy.color,
                                         isOn: offered.contains(squishy.id),
                                         isEnabled: !isPromised) {
                                    SquishyImage(squishy: squishy)
                                } action: {
                                    toggle(squishy)
                                }
                            }
                        }

                        friendsSectionLabel("Add a line", detail: "optional")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                            ForEach(TradePreset.allCases) { option in
                                Button {
                                    preset = preset == option ? nil : option
                                } label: {
                                    Text(option.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.ink)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 38)
                                        .background {
                                            if preset == option {
                                                Capsule().fill(Tint.single(wanted.hue).primary.opacity(0.45))
                                            }
                                        }
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                }
                                .buttonStyle(.tap(19))
                                .accessibilityAddTraits(preset == option ? [.isButton, .isSelected] : .isButton)
                            }
                        }

                        if let error {
                            FriendsNotice(title: "Not sent", message: error)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) {
            TintedCTA(title: sendTitle,
                      tint: Tint.single(wanted.hue),
                      isEnabled: !offered.isEmpty && !isSending,
                      action: send)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .sensoryFeedback(.selection, trigger: offered)
    }

    private var sendTitle: String {
        if isSending { return "Sending…" }
        return offered.isEmpty ? "Send request" : "Send request · \(offered.count) for 1"
    }

    private func toggle(_ squishy: Squishy) {
        if offered.contains(squishy.id) {
            offered.remove(squishy.id)
        } else {
            offered.insert(squishy.id)
        }
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            defer { isSending = false }
            do {
                try await store.sendRequest(to: friend, wanting: [wanted],
                                            offering: offeredSquishies, line: preset)
                dismiss()
            } catch {
                self.error = FriendsStore.describe(error)
            }
        }
    }
}
