import SwiftUI
import SwiftData

/// Naming a shelf when you make it. A shelf called "New shelf" is a shelf nobody
/// ever uses, so the name is asked for up front rather than left to be fixed later.
struct NewShelfSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @FocusState private var focused: Bool

    /// Handed back so the caller can drop straight into picking squeeshies for it.
    var onCreated: (Shelf) -> Void

    private let suggestions = ["Favourites", "On my bed", "From Grandma", "Travel crew"]

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: .fallback)
            VStack(alignment: .leading, spacing: 18) {
                MetaLabel(text: "new shelf")
                    .padding(.top, 20)

                TextField("", text: $name,
                          prompt: Text("Call it something").foregroundStyle(Color.ink3))
                    .focused($focused)
                    .font(.display(26, .heavy))
                    .foregroundStyle(Color.ink)
                    .submitLabel(.done)
                    .onSubmit(create)

                FlowChips(options: suggestions) { name = $0 }

                Spacer()

                Button(action: create) {
                    Text("Create")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.04, blue: 0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(name.isEmpty ? Color.ink3 : Tint.fallback.primary, in: .capsule)
                }
                .buttonStyle(.tap)
                .disabled(name.isEmpty)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 22)
        }
        .onAppear { focused = true }
    }

    private func create() {
        guard !name.isEmpty else { return }
        let shelf = Shelf(name: name)
        context.insert(shelf)
        try? context.save()
        onCreated(shelf)
        dismiss()
    }
}

/// Choosing what goes on a hand-made shelf. A grid rather than a list, because you
/// recognise a squeeshy by its face long before you recall what you named it.
struct ShelfContentsPicker: View {
    var shelf: Shelf
    @Query(sort: \Squishy.addedAt, order: .reverse) private var all: [Squishy]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private var chosen: Set<UUID> {
        Set((shelf.items ?? []).map(\.id))
    }

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: Tint.sampled(from: all.map(\.hue)))

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shelf.name)
                            .font(.display(24, .heavy))
                            .foregroundStyle(Color.ink)
                        MetaLabel(text: "\(chosen.count) on this shelf")
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(all) { squishy in
                            PickerTile(squishy: squishy, isOn: chosen.contains(squishy.id)) {
                                toggle(squishy)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func toggle(_ squishy: Squishy) {
        var items = shelf.items ?? []
        if let index = items.firstIndex(where: { $0.id == squishy.id }) {
            items.remove(at: index)
        } else {
            items.append(squishy)
        }
        shelf.items = items
        try? context.save()
    }
}

/// The same job as ShelfContentsPicker, approached from the other end: standing on one
/// squeeshy, tick the collections it belongs to. Filling a shelf from the shelf side is
/// right when you are building a shelf, and wrong when you have just photographed
/// something and want to file it.
struct AddToShelfSheet: View {
    var squishy: Squishy
    @Query(sort: \Shelf.createdAt) private var shelves: [Shelf]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var creating = false

    var body: some View {
        ZStack {
            AdaptiveBackground(tint: Tint.single(squishy.hue))

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to")
                            .font(.display(24, .heavy))
                            .foregroundStyle(Color.ink)
                        MetaLabel(text: squishy.name)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(shelves) { shelf in
                            row(for: shelf)
                        }

                        Button { creating = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("New collection")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.tap)

                        if shelves.isEmpty {
                            MetaLabel(text: "no collections yet", color: .ink3)
                                .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $creating) {
            // Straight from naming into membership: a collection made from here is
            // almost always being made *for* the squeeshy in hand.
            NewShelfSheet { shelf in
                shelf.items = (shelf.items ?? []) + [squishy]
                try? context.save()
            }
            .presentationDetents([.height(360)])
        }
    }

    private func row(for shelf: Shelf) -> some View {
        let isOn = (shelf.items ?? []).contains { $0.id == squishy.id }
        return Button { toggle(shelf, isOn: isOn) } label: {
            HStack(spacing: 12) {
                MiniStack(items: shelf.items ?? [])
                VStack(alignment: .leading, spacing: 2) {
                    Text(shelf.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    MetaLabel(text: "\((shelf.items ?? []).count) squeeshies")
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? squishy.color : Color.ink3)
            }
            .padding(.horizontal, 14)
            .frame(height: 74)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .rebuildsOnSchemeChange()
        }
        .buttonStyle(.tap)
    }

    private func toggle(_ shelf: Shelf, isOn: Bool) {
        var items = shelf.items ?? []
        if isOn {
            items.removeAll { $0.id == squishy.id }
        } else {
            items.append(squishy)
        }
        shelf.items = items
        try? context.save()
    }
}

private struct PickerTile: View {
    var squishy: Squishy
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                SquishyImage(squishy: squishy)
                    .frame(width: 54, height: 54)
                Text(squishy.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(squishy.color.opacity(0.30))
                }
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .rebuildsOnSchemeChange()
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.ink)
                        .padding(7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isOn ? 1 : 0.97)
        }
        .buttonStyle(.tap)
        .animation(Motion.tap, value: isOn)
    }
}

/// Suggested names, tappable. Cheap way to make an empty text field feel answerable.
struct FlowChips: View {
    var options: [String]
    var onPick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button { onPick(option) } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.tap)
            }
        }
    }
}
