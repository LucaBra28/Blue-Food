import SwiftUI

struct WatchRootView: View {
    @State private var store = WatchStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private var live: WatchLive { .shared }

    var body: some View {
        NavigationStack {
            Group {
                if !store.isSignedIn {
                    ContentUnavailableView {
                        Label("Nicht angemeldet", systemImage: "iphone")
                    } description: {
                        Text("Melde dich auf dem iPhone bei BuyFood an.")
                    }
                } else if store.hasLoaded && store.lists.isEmpty {
                    ContentUnavailableView("Keine Listen", systemImage: "list.bullet")
                } else {
                    List(store.lists) { list in
                        NavigationLink(value: list) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name).font(.headline)
                                Text(list.memberCount > 1 ? "Geteilt" : "Privat")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Listen")
            .navigationDestination(for: ShoppingList.self) { WatchItemsView(list: $0) }
            .task(id: live.version) { await store.loadLists() }
            .refreshable { await store.loadLists() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.isSignedIn { WatchLive.shared.start() }
        }
    }
}

struct WatchItemsView: View {
    let list: ShoppingList
    @State private var model: WatchListModel
    @State private var showNew = false
    @State private var editing: ListItem?
    @State private var showDone = false

    init(list: ShoppingList) {
        self.list = list
        _model = State(initialValue: WatchListModel(listID: list.id))
    }

    private var live: WatchLive { .shared }

    var body: some View {
        List {
            Section {
                Button {
                    showNew = true
                } label: {
                    Label("Neuer Artikel", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
            }

            Section("Offen") {
                if model.open.isEmpty && model.hasLoaded {
                    Text("Alles erledigt").foregroundStyle(.secondary)
                }
                ForEach(model.open) { row($0) }
            }

            if !model.done.isEmpty {
                Section {
                    Button {
                        showDone.toggle()
                    } label: {
                        HStack {
                            Text("Erledigt (\(model.done.count))")
                            Spacer()
                            Image(systemName: showDone ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    if showDone {
                        ForEach(model.done) { row($0) }
                    }
                }
            }

            if let error = model.errorMessage {
                Section { Text(error).font(.caption2).foregroundStyle(.red) }
            }
        }
        .navigationTitle(list.name)
        .task(id: live.version) { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showNew) {
            WatchItemForm(title: "Neuer Artikel", confirm: "Hinzufügen") { name, quantity, unit in
                await model.add(name: name, quantity: quantity, unit: unit, userID: WatchStore.shared.userID ?? "")
            }
        }
        .sheet(item: $editing) { item in
            WatchItemForm(title: "Bearbeiten", initialName: item.name, initialQuantity: item.quantity,
                          initialUnit: item.unit, confirm: "Sichern") { name, quantity, unit in
                await model.update(item, name: name, quantity: quantity, unit: unit)
            }
        }
    }

    private func row(_ item: ListItem) -> some View {
        Button {
            Task { await model.toggle(item) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Color.blue : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .strikethrough(item.checked)
                        .foregroundStyle(item.checked ? .secondary : .primary)
                    Text(item.quantityText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.checked ? "\(item.name), erledigt" : "\(item.name), offen")
        .accessibilityHint("Tippen zum Umschalten")
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash", role: .destructive) {
                Task { await model.delete(item) }
            }
            Button("Bearbeiten", systemImage: "pencil") { editing = item }
                .tint(.blue)
        }
    }
}

/// Artikel anlegen oder bearbeiten: Name, Menge und Einheit wie auf dem iPhone.
struct WatchItemForm: View {
    let title: String
    let confirm: String
    var onSave: (String, Double, ItemUnit) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: Double
    @State private var unit: ItemUnit
    @State private var isSaving = false

    init(title: String, initialName: String = "", initialQuantity: Double = 1, initialUnit: ItemUnit = .piece,
         confirm: String, onSave: @escaping (String, Double, ItemUnit) async -> Bool) {
        self.title = title
        self.confirm = confirm
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _quantity = State(initialValue: initialQuantity)
        _unit = State(initialValue: initialUnit)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Artikel", text: $name)
                }
                Section("Menge") {
                    HStack {
                        Button {
                            quantity = max(unit.step, quantity - unit.step)
                        } label: {
                            Image(systemName: "minus.circle.fill").font(.title2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .disabled(quantity - unit.step < unit.step)
                        .accessibilityLabel("Menge verringern")

                        Spacer()
                        Text(unit.formatted(quantity))
                            .font(.headline)
                            .monospacedDigit()
                        Spacer()

                        Button {
                            quantity = min(100000, quantity + unit.step)
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Menge erhöhen")
                    }
                }
                Section {
                    Picker("Einheit", selection: $unit) {
                        ForEach(ItemUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                        .disabled(trimmed.isEmpty || isSaving)
                        .accessibilityLabel(confirm)
                }
            }
            .onChange(of: unit) { _, newUnit in
                quantity = max(quantity, newUnit.step)
            }
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        isSaving = true
        Task {
            if await onSave(trimmed, quantity, unit) { dismiss() }
            isSaving = false
        }
    }
}
