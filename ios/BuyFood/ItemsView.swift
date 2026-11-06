import SwiftUI
import UIKit

struct ItemsView: View {
    let store: ItemsStore
    let members: [String: ListMember]
    @Binding var editing: ListItem?

    @State private var showDone = false
    /// Gerade abgehakte Artikel: bleiben 3 Sekunden im Bereich „Offen“, bevor sie nach „Erledigt“ wandern.
    @State private var justChecked: Set<String> = []

    var open: [ListItem] { store.items.filter { !$0.checked || justChecked.contains($0.id) } }
    var done: [ListItem] { store.items.filter { $0.checked && !justChecked.contains($0.id) } }

    var body: some View {
        Group {
            if store.items.isEmpty && store.hasLoaded {
                ScrollView {
                    ContentUnavailableView {
                        Label("Noch keine Artikel", systemImage: "cart")
                    } description: {
                        Text("Tippe oben auf +, um den ersten Artikel hinzuzufügen.")
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
                .scrollBounceBehavior(.always)
            } else {
                List {
                    if !open.isEmpty {
                        Section { ForEach(open) { row($0) } }
                    }
                    if !done.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $showDone) {
                                ForEach(done) { row($0) }
                            } label: {
                                Label("Erledigt (\(done.count))", systemImage: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await store.load() }
        .task(id: LiveUpdates.shared.reconnectVersion) { await store.load() }
        .task {
            for await event in LiveUpdates.shared.itemEvents() { store.apply(event) }
        }
        .alert("Fehler", isPresented: .constant(store.errorMessage != nil && store.hasLoaded)) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func row(_ item: ListItem) -> some View {
        HStack(spacing: 12) {
            Button {
                check(item)
            } label: {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.checked ? Color.accentColor : Color.secondary)
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.checked ? "Als offen markieren" : "Abhaken")

            thumbnail(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
                Text("von \(creator(of: item))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            quantityControl(item)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = item }
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash", role: .destructive) { Task { await store.delete(item) } }
            Button("Bearbeiten", systemImage: "pencil") { editing = item }.tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button(item.checked ? "Offen" : "Abhaken", systemImage: item.checked ? "arrow.uturn.backward" : "checkmark") {
                check(item)
            }
            .tint(.green)
        }
    }

    /// Abhaken mit Vibration; das Rückgängigmachen wirkt sofort.
    private func check(_ item: ListItem) {
        if item.checked {
            justChecked.remove(item.id)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            justChecked.insert(item.id)
            let id = item.id
            Task {
                try? await Task.sleep(for: .seconds(3))
                justChecked.remove(id)
            }
        }
        Task { await store.toggle(item) }
    }

    @ViewBuilder
    private func thumbnail(_ item: ListItem) -> some View {
        if let url = item.imageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if let emoji = item.emoji {
                    Text(emoji).font(.title2)
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(item.checked ? 0.5 : 1)
            .accessibilityHidden(true)
        } else if let emoji = item.emoji {
            Text(emoji)
                .font(.title)
                .frame(width: 40, height: 40)
                .opacity(item.checked ? 0.5 : 1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func quantityControl(_ item: ListItem) -> some View {
        if item.checked {
            Text(item.quantityText).font(.body.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        } else {
            HStack(spacing: 0) {
                Button { Task { await store.setQuantity(item, item.quantity - item.unit.step) } } label: {
                    Image(systemName: "minus.circle").font(.title3).frame(width: 30, height: 44).contentShape(Rectangle())
                }
                .disabled(item.quantity - item.unit.step <= 0)
                .accessibilityLabel("Menge verringern")
                Text(item.quantityText)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 36)
                    .accessibilityLabel("Menge \(item.quantityText)")
                Button { Task { await store.setQuantity(item, item.quantity + item.unit.step) } } label: {
                    Image(systemName: "plus.circle").font(.title3).frame(width: 30, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Menge erhöhen")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    private func creator(of item: ListItem) -> String {
        let name = members[item.createdBy]?.name ?? ""
        return name.isEmpty ? "Unbekannt" : name
    }
}

/// Artikel anlegen oder bearbeiten (Name, Menge und Einheit).
struct ItemSheet: View {
    let title: String
    let confirm: String
    var previewImageURL: URL? = nil
    var onSave: (String, Double, ItemUnit) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: Double
    @State private var unit: ItemUnit
    @State private var isSaving = false
    @FocusState private var focused: Bool

    init(title: String, initialName: String = "", initialQuantity: Double = 1, initialUnit: ItemUnit = .piece,
         previewImageURL: URL? = nil, confirm: String, onSave: @escaping (String, Double, ItemUnit) async -> Bool) {
        self.title = title; self.confirm = confirm; self.onSave = onSave; self.previewImageURL = previewImageURL
        _name = State(initialValue: initialName)
        _quantity = State(initialValue: initialQuantity)
        _unit = State(initialValue: initialUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let previewImageURL {
                    Section {
                        AsyncImage(url: previewImageURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                        }
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                    }
                }
                TextField("Artikel", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                Section {
                    Stepper(value: $quantity, in: unit.step...100000, step: unit.step) {
                        HStack {
                            Text("Menge")
                            Spacer()
                            TextField("1", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                    Picker("Einheit", selection: $unit) {
                        ForEach(ItemUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm, action: save).disabled(trimmed.isEmpty || quantity <= 0 || isSaving)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty, quantity > 0 else { return }
        isSaving = true
        Task {
            if await onSave(trimmed, quantity, unit) { dismiss() }
            isSaving = false
        }
    }
}
