import PhotosUI
import SwiftUI

enum ListTab: Hashable { case items, members, map }

struct ScannedProduct: Identifiable {
    let id = UUID()
    let name: String
    let imageURL: String
}

struct ListDetailView: View {
    let listID: String
    @Environment(AuthStore.self) private var auth
    @Environment(ListsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ListTab = .items
    @State private var itemsStore: ItemsStore
    @State private var members: [ListMember] = []
    @State private var showNewItem = false
    @State private var editingItem: ListItem?
    @State private var showSettings = false
    @State private var showInvite = false
    @State private var prefs = ListPrefsStore()
    @State private var showScanner = false
    @State private var banner: String?
    @State private var isLookingUp = false
    @State private var unknownBarcode = false
    @State private var scanned: ScannedProduct?

    init(listID: String) {
        self.listID = listID
        _itemsStore = State(initialValue: ItemsStore(listID: listID))
    }

    var body: some View {
        Group {
            if let list = store.list(id: listID) {
                TabView(selection: $selection) {
                    Tab("Artikel", systemImage: "checklist", value: ListTab.items) {
                        ItemsView(store: itemsStore, members: memberMap, editing: $editingItem)
                    }
                    Tab("Mitglieder", systemImage: "person.2", value: ListTab.members) {
                        MembersTab(list: list, members: members, reload: { members = await store.members(of: list) }) { dismiss() }
                    }
                    Tab("Karte", systemImage: "map", value: ListTab.map) {
                        MapTabView(listID: listID)
                    }
                }
                .navigationTitle(list.name)
                .navigationBarTitleDisplayMode(selection == .map ? .inline : .large)
                .toolbar {
                    if selection == .members && list.isOwned(by: auth.user?.id ?? "") {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Person einladen", systemImage: "person.badge.plus") { showInvite = true }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
                    }
                    if selection == .items {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu("Artikel hinzufügen", systemImage: "plus") {
                                Button("Barcode scannen", systemImage: "barcode.viewfinder") { showScanner = true }
                                Button("Eintrag", systemImage: "square.and.pencil") { showNewItem = true }
                            }
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    ListSettingsView(listID: list.id, prefs: prefs) { dismiss() }
                }
                .sheet(isPresented: $showInvite) {
                    InviteSheet(list: list)
                }
                .sheet(isPresented: $showNewItem) {
                    ItemSheet(title: "Neuer Artikel", confirm: "Hinzufügen") { name, quantity, unit in
                        await itemsStore.add(name: name, quantity: quantity, unit: unit, userID: auth.user?.id ?? "")
                    }
                }
                .sheet(item: $editingItem) { item in
                    ItemSheet(title: "Artikel bearbeiten", initialName: item.name, initialQuantity: item.quantity, initialUnit: item.unit,
                              previewImageURL: item.imageURL, confirm: "Sichern") { name, quantity, unit in
                        await itemsStore.update(item, name: name, quantity: quantity, unit: unit)
                        return true
                    }
                }
                .sheet(item: $scanned) { product in
                    ItemSheet(title: "Artikel hinzufügen", initialName: product.name,
                              previewImageURL: URL(string: product.imageURL), confirm: "Hinzufügen") { name, quantity, unit in
                        let ok = await itemsStore.addMerging(name: name, quantity: quantity, unit: unit, imageURL: product.imageURL, userID: auth.user?.id ?? "")
                        if ok { showBanner("„\(name)“ hinzugefügt") }
                        return ok
                    }
                }
                .fullScreenCover(isPresented: $showScanner) {
                    BarcodeScannerView { code in handleScan(code) }
                }
                .alert("Artikel nicht gefunden", isPresented: $unknownBarcode) {
                    Button("Manuell hinzufügen") { showNewItem = true }
                    Button("Abbrechen", role: .cancel) {}
                } message: { Text("Zu diesem Barcode gibt es keinen bekannten Artikel.") }
                .overlay(alignment: .top) {
                    if let banner {
                        Label(banner, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if isLookingUp {
                        ProgressView("Suche Artikel …")
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                }
                .animation(.default, value: banner)
                .task(id: "\(selection)-\(LiveUpdates.shared.listsVersion)-\(LiveUpdates.shared.reconnectVersion)") {
                    members = await store.members(of: list)
                }
                .task(id: LiveUpdates.shared.reconnectVersion) {
                    await prefs.load(listID: listID, userID: auth.user?.id ?? "")
                }
            } else {
                ContentUnavailableView("Liste nicht verfügbar", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func handleScan(_ code: String) {
        isLookingUp = true
        Task {
            let product = await ProductLookup.product(forBarcode: code)
            isLookingUp = false
            if let product {
                scanned = ScannedProduct(name: product.name, imageURL: product.imageURL)
            } else {
                unknownBarcode = true
            }
        }
    }

    private func showBanner(_ text: String) {
        Task {
            banner = text
            try? await Task.sleep(for: .seconds(2.5))
            banner = nil
        }
    }

    private var memberMap: [String: ListMember] {
        Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Mitglieder der Liste; der Ersteller lädt hier ein, Mitglieder können die Liste verlassen.
struct MembersTab: View {
    let list: ShoppingList
    let members: [ListMember]
    var reload: () async -> Void
    var onLeft: () -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(ListsStore.self) private var store
    @State private var sent: [SentInvite] = []
    @State private var confirmLeave = false
    @State private var memberToRemove: ListMember?

    private var isOwner: Bool { list.isOwned(by: auth.user?.id ?? "") }

    var body: some View {
        List {
            if isOwner && !sent.isEmpty {
                Section("Ausstehende Einladungen") {
                    ForEach(sent) { inv in
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .foregroundStyle(.secondary)
                                .frame(width: 36)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inv.email).lineLimit(1)
                                Text("Ausstehend").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Zurückziehen", role: .destructive) {
                                Task { await store.cancel(inv); await reloadSent() }
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button("Zurückziehen", systemImage: "xmark", role: .destructive) {
                                Task { await store.cancel(inv); await reloadSent() }
                            }
                        }
                    }
                }
            }

            Section("Mitglieder") {
                ForEach(members) { m in
                    HStack(spacing: 12) {
                        AvatarView(url: m.avatarURL(), name: m.name, size: 36)
                        Text(m.name.isEmpty ? "Unbekannt" : m.name)
                        Spacer()
                        if m.id == auth.user?.id { Text("Du").foregroundStyle(.secondary) }
                        else if m.isOwner { Text("Ersteller").foregroundStyle(.secondary) }
                        if isOwner && !m.isOwner {
                            Menu {
                                Button("Aus Liste entfernen", systemImage: "person.badge.minus", role: .destructive) { memberToRemove = m }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("Optionen für \(m.name)")
                        }
                    }
                    .swipeActions {
                        if isOwner && !m.isOwner {
                            Button("Entfernen", systemImage: "person.badge.minus", role: .destructive) { memberToRemove = m }
                        }
                    }
                }
            }

            if !isOwner {
                Section {
                    Button("Liste verlassen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                }
            }
        }
        .task(id: LiveUpdates.shared.invitesVersion &+ LiveUpdates.shared.listsVersion &+ LiveUpdates.shared.reconnectVersion) {
            await reloadSent()
        }
        .refreshable {
            await store.load()
            await reload()
            await reloadSent()
        }
        .confirmationDialog("Mitglied entfernen?", isPresented: .constant(memberToRemove != nil), titleVisibility: .visible, presenting: memberToRemove) { m in
            Button("„\(m.name.isEmpty ? "Unbekannt" : m.name)“ entfernen", role: .destructive) {
                Task { await store.removeMember(m, from: list); await reload(); memberToRemove = nil }
            }
            Button("Abbrechen", role: .cancel) { memberToRemove = nil }
        } message: { _ in Text("Die Person sieht die Liste danach nicht mehr. Ihre Artikel bleiben erhalten.") }
        .confirmationDialog("Liste verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Verlassen", role: .destructive) {
                Task { await store.leave(list); onLeft() }
            }
        }
    }

    private func reloadSent() async {
        if isOwner { sent = await store.sentInvites(for: list) }
    }
}

struct InviteSheet: View {
    let list: ShoppingList
    @Environment(ListsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-Mail-Adresse", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else { Text("Gib die E-Mail-Adresse der Apple-ID ein, mit der sich die Person anmeldet.") }
                }
            }
            .navigationTitle("Person einladen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Einladen", action: send).disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func send() {
        isWorking = true
        Task {
            error = await store.invite(email: email, to: list)
            isWorking = false
            if error == nil { dismiss() }
        }
    }
}

/// Einstellungen der Liste: für alle Mitglieder (Benachrichtigungen).
/// Der Ersteller sieht zusätzlich Name, Bild und Löschen.
struct ListSettingsView: View {
    let listID: String
    let prefs: ListPrefsStore
    var onDeleted: () -> Void
    @Environment(AuthStore.self) private var auth
    @Environment(ListsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var isUploading = false
    @State private var cropItem: CropItem?
    @State private var confirmDelete = false

    private var list: ShoppingList? { store.list(id: listID) }
    private var isOwner: Bool { list?.isOwned(by: auth.user?.id ?? "") ?? false }
    private var userID: String { auth.user?.id ?? "" }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if isOwner, let list {
                    Section("Name") {
                        TextField("Listenname", text: $name)
                            .submitLabel(.done)
                            .onSubmit(saveName)
                    }
                    Section("Bild") {
                        HStack(spacing: 14) {
                            ListImageView(url: list.imageURL(thumb: "120x120"), isShared: list.memberCount > 1, size: 56)
                                .overlay {
                                    if isUploading { ProgressView().tint(.primary) }
                                }
                            PhotosPicker(selection: $photo, matching: .images) {
                                Text(list.image.isEmpty ? "Bild auswählen" : "Bild ändern")
                            }
                            Spacer()
                            if !list.image.isEmpty {
                                Button("Entfernen", role: .destructive) { Task { await setImage(nil) } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Benachrichtigungen") {
                    Toggle("Wenn Artikel hinzugefügt werden", isOn: binding(\.notifyAdded))
                    Toggle("Wenn meine Artikel abgehakt werden", isOn: binding(\.notifyChecked))
                }

                if isOwner {
                    Section {
                        Button("Liste löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        saveName()
                        dismiss()
                    }
                }
            }
            .onAppear { name = list?.name ?? "" }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let image = await loadUIImage(from: item) { cropItem = CropItem(image: image) }
                    photo = nil
                }
            }
            .fullScreenCover(item: $cropItem) { item in
                ImageCropperView(image: item.image, shape: .roundedSquare) { jpeg in
                    Task { await setImage(jpeg) }
                }
            }
            .confirmationDialog("Liste löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Für alle löschen", role: .destructive) {
                    guard let list else { return }
                    Task { await store.delete(list); dismiss(); onDeleted() }
                }
            } message: { Text("Die Liste verschwindet auch bei allen Mitgliedern.") }
        }
        .presentationDetents([.medium, .large])
    }

    /// Schalter, der die Einstellung sofort ändert und speichert.
    private func binding(_ keyPath: WritableKeyPath<ListPrefs, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs.prefs[keyPath: keyPath] },
            set: { value in
                var new = prefs.prefs
                new[keyPath: keyPath] = value
                Task { await prefs.update(new, listID: listID, userID: userID) }
            }
        )
    }

    private func saveName() {
        guard isOwner, let list, !trimmedName.isEmpty, trimmedName != list.name else { return }
        Task { await store.rename(list, to: trimmedName) }
    }

    private func setImage(_ jpeg: Data?) async {
        guard let list else { return }
        isUploading = true
        await store.setImage(jpeg, for: list)
        isUploading = false
    }
}
