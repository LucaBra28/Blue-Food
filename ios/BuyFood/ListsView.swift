import SwiftUI

struct ListsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var store = ListsStore()
    @State private var showNew = false
    @State private var showSettings = false
    @State private var pendingDelete: ShoppingList?
    @State private var pendingLeave: ShoppingList?

    var body: some View {
        NavigationStack {
            Group {
                if store.lists.isEmpty && store.invites.isEmpty && store.hasLoaded {
                    ScrollView {
                        ContentUnavailableView {
                            Label("Keine Listen", systemImage: "list.bullet.clipboard")
                        } description: {
                            Text("Erstelle eine neue Liste oder tritt der Liste einer anderen Person bei.")
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                    }
                    .scrollBounceBehavior(.always)
                } else {
                    List {
                        if !store.invites.isEmpty {
                            Section("Einladungen") {
                                ForEach(store.invites) { invite in
                                    InviteRow(invite: invite)
                                }
                            }
                        }
                        Section {
                            ForEach(store.lists) { list in
                                NavigationLink(value: list.id) { ListRow(list: list, isOwner: list.isOwned(by: userID)) }
                                    .swipeActions(edge: .trailing) {
                                        if list.isOwned(by: userID) {
                                            Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = list }
                                        } else {
                                            Button("Verlassen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { pendingLeave = list }
                                        }
                                    }
                            }
                        } header: {
                            if !store.invites.isEmpty { Text("Meine Listen") }
                        }
                    }
                }
            }
            .navigationTitle("Listen")
            .navigationDestination(for: String.self) { id in
                ListDetailView(listID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        if let user = auth.user, !user.avatar.isEmpty {
                            AvatarView(url: user.avatarURL(), name: user.name, size: 30)
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityLabel("Konto")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Neue Liste", systemImage: "plus") { showNew = true }
                }
            }
            .refreshable { await store.load() }
            .task(id: live.listsVersion &+ live.invitesVersion &+ live.reconnectVersion) { await store.load() }
            .alert("Fehler", isPresented: .constant(store.errorMessage != nil && store.hasLoaded)) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
            .confirmationDialog("Liste löschen?", isPresented: .constant(pendingDelete != nil), titleVisibility: .visible, presenting: pendingDelete) { list in
                Button("„\(list.name)“ für alle löschen", role: .destructive) {
                    Task { await store.delete(list) }
                    pendingDelete = nil
                }
                Button("Abbrechen", role: .cancel) { pendingDelete = nil }
            } message: { _ in Text("Die Liste wird auch für alle Mitglieder gelöscht.") }
            .confirmationDialog("Liste verlassen?", isPresented: .constant(pendingLeave != nil), titleVisibility: .visible, presenting: pendingLeave) { list in
                Button("„\(list.name)“ verlassen", role: .destructive) {
                    Task { await store.leave(list) }
                    pendingLeave = nil
                }
                Button("Abbrechen", role: .cancel) { pendingLeave = nil }
            }
            .sheet(isPresented: $showNew) { NewListSheet() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .environment(store)
    }

    private var live: LiveUpdates { .shared }

    private var userID: String { auth.user?.id ?? "" }
}

private struct ListRow: View {
    let list: ShoppingList
    let isOwner: Bool

    var body: some View {
        HStack(spacing: 12) {
            ListImageView(url: list.imageURL(), isShared: list.memberCount > 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name).font(.body)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if list.memberCount > 1 {
            return isOwner ? "Geteilt · \(list.memberCount) Personen" : "Mit dir geteilt · \(list.memberCount) Personen"
        }
        return "Privat"
    }
}

struct NewListSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ListsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name der Liste", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle("Neue Liste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen", action: save).disabled(trimmed.isEmpty || isSaving)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty, let uid = auth.user?.id else { return }
        isSaving = true
        Task {
            if await store.create(name: trimmed, ownerID: uid) { dismiss() }
            isSaving = false
        }
    }
}

private struct InviteRow: View {
    @Environment(ListsStore.self) private var store
    let invite: ListInvite
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge")
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.listName).font(.body.weight(.semibold))
                    Text("\(invite.inviterName) lädt dich ein").font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button("Ablehnen") { run { await store.decline(invite) } }
                    .buttonStyle(.bordered)
                Button("Annehmen") { run { await store.accept(invite) } }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
            .disabled(isWorking)
        }
        .padding(.vertical, 4)
    }

    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task { await work(); isWorking = false }
    }
}
