#if DEBUG
import SwiftUI

/// Debug builds only: switches friends to the simulator and drives the simulated
/// friends. Sits at the top of the Friends screen. Launch with
/// `-SimulateFriends YES` to start with it on.
struct FriendsDebugPanel: View {
    @Environment(FriendsStore.self) private var store
    @State private var expanded = FriendsDebug.isOn
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.tap) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "ladybug")
                    MetaLabel(text: "debug · simulate friends", color: .ink)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .foregroundStyle(Color.ink)
                .frame(minHeight: 34)
            }
            .buttonStyle(.tap)

            if expanded {
                Toggle("Simulate iCloud friends", isOn: Binding(
                    get: { store.isSimulating },
                    set: { on in Task { await store.setSimulation(on) } }))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)

                if let simulator = store.simulator {
                    controls(simulator)
                } else {
                    Text("Off: friends use real iCloud. On: a pretend friend, Mia, shares her collection, answers requests and can meet you at a trade table.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink2)
                }
            }
        }
        .padding(14)
        .background(Color.yellow.opacity(0.16), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.top, 6)
    }

    @ViewBuilder
    private func controls(_ simulator: FriendsSimulator) -> some View {
        @Bindable var simulator = simulator
        VStack(alignment: .leading, spacing: 10) {
            Picker("Friends answer requests with", selection: $simulator.replyBehaviour) {
                ForEach(FriendsSimulator.ReplyBehaviour.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Friends hand over on their own", isOn: $simulator.autoHandOver)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                action("Seed my collection") { store.debugSeedShelf() }
                action("Pair a friend") { store.debugPairFriend() }
                action("Friend sends request") { message = store.debugIncomingRequest() }
                action("Friends act now") { store.debugForceFriends() }
            }

            if let message {
                Text(message).font(.system(size: 13)).foregroundStyle(.red)
            }

            if !simulator.log.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(simulator.log.prefix(6), id: \.self) { line in
                        Text(line)
                            .font(.mono(10))
                            .foregroundStyle(Color.ink2)
                    }
                }
            }
        }
    }

    private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button {
            message = nil
            perform()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.tap(17))
    }
}

/// Debug builds only: plays the other phone at a trade table.
struct TableDebugControls: View {
    var session: TradeTableSession

    var body: some View {
        if let partner = session.simulated {
            @Bindable var partner = partner
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "ladybug")
                    MetaLabel(text: "debug · plays \(partner.peer.displayName)", color: .ink)
                    Spacer()
                    Toggle("Auto yes", isOn: $partner.autoYes)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        switch session.phase {
                        case .looking, .idle:
                            chip("They invite me") { session.debugSimulatedInvite() }
                        case .atTable:
                            chip("Put one in") { partner.putInRandom() }
                            chip("Take one out") { partner.takeOneOut() }
                            chip("Vote yes") { partner.vote(true) }
                            chip("Vote no") { partner.vote(false) }
                            chip("Leave") { session.debugSimulatedLeaves() }
                        default:
                            EmptyView()
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(Color.ink)
            .padding(12)
            .background(Color.yellow.opacity(0.18), in: .rect(cornerRadius: 18))
        }
    }

    private func chip(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.tap(15))
    }
}
#endif
