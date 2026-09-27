#if DEBUG
import SwiftUI

/// Debug builds only: switches friends to the simulator and drives the
/// simulated friends. Sits at the top of the Friends screen.
struct FriendsDebugPanel: View {
    @Environment(FriendsStore.self) private var store
    @State private var expanded = FriendsDebug.isOn
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
            Button {
                withAnimation(SquishTheme.Motion.select) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "ladybug")
                    Text("Debug · simulate friends")
                        .typeStyle(.m1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .foregroundStyle(SquishTheme.ink)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Toggle("Simulate iCloud friends", isOn: Binding(
                    get: { store.isSimulating },
                    set: { on in Task { await store.setSimulation(on) } }))
                    .typeStyle(.b2)

                if let simulator = store.simulator {
                    controls(simulator)
                } else {
                    Text("Off: friends use real iCloud. On: a pretend friend, Mia, shares her shelf, answers requests and can meet you at a trade table.")
                        .typeStyle(.b3)
                        .foregroundStyle(SquishTheme.soft)
                }
            }
        }
        .padding(SquishTheme.Space.gutter)
        .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.top, SquishTheme.Space.gutter)
    }

    @ViewBuilder
    private func controls(_ simulator: FriendsSimulator) -> some View {
        @Bindable var simulator = simulator
        VStack(alignment: .leading, spacing: SquishTheme.Space.sm) {
            Picker("Friends answer requests with", selection: $simulator.replyBehaviour) {
                ForEach(FriendsSimulator.ReplyBehaviour.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Friends hand over on their own", isOn: $simulator.autoHandOver)
                .typeStyle(.b2)

            FlowRow(spacing: SquishTheme.Space.sm) {
                action("Seed my shelf") { store.debugSeedShelf() }
                action("Pair a friend") { store.debugPairFriend() }
                action("Friend sends request") { message = store.debugIncomingRequest() }
                action("Friends act now") { store.debugForceFriends() }
            }

            if let message {
                Text(message).typeStyle(.b3).foregroundStyle(.red)
            }

            if !simulator.log.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(simulator.log.prefix(6), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SquishTheme.soft)
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
                .typeStyle(.m1)
                .foregroundStyle(SquishTheme.ink)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(SquishTheme.chalk, in: Capsule())
                .overlay(Capsule().strokeBorder(SquishTheme.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

/// Debug builds only: plays the other phone at a trade table.
struct TableDebugControls: View {
    let session: TradeTableSession

    var body: some View {
        if let partner = session.simulated {
            @Bindable var partner = partner
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "ladybug")
                    Text("Debug · plays \(partner.peer.displayName)").typeStyle(.m1)
                    Spacer()
                    Toggle("Auto yes", isOn: $partner.autoYes)
                        .labelsHidden()
                    Text("Auto yes").typeStyle(.m1)
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
            .foregroundStyle(SquishTheme.ink)
            .padding(10)
            .background(Color.yellow.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, SquishTheme.Space.margin)
        }
    }

    private func chip(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .typeStyle(.m1)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(SquishTheme.chalk, in: Capsule())
                .overlay(Capsule().strokeBorder(SquishTheme.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}
#endif
