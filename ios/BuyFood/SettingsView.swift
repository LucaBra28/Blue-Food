import PhotosUI
import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var photo: PhotosPickerItem?
    @State private var isUploading = false
    @State private var cropItem: CropItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        AvatarView(url: auth.user?.avatarURL(thumb: "300x300"), name: auth.user?.name ?? "", size: 112)
                            .overlay { if isUploading { ProgressView().frame(width: 112, height: 112).background(.ultraThinMaterial, in: Circle()) } }
                        HStack(spacing: 20) {
                            PhotosPicker(selection: $photo, matching: .images) {
                                Text(hasAvatar ? "Foto ändern" : "Foto auswählen")
                            }
                            if hasAvatar {
                                Button("Entfernen", role: .destructive) { Task { await update(nil) } }
                            }
                        }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent("Name", value: displayName)
                    LabeledContent("Anmeldung", value: "Apple")
                }
                Section {
                    Button("Abmelden") { auth.signOut(); dismiss() }
                }
                Section {
                    Button("Konto löschen", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Löscht dein Konto und alle Listen, die du erstellt hast.")
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let image = await loadUIImage(from: item) { cropItem = CropItem(image: image) }
                    photo = nil
                }
            }
            .fullScreenCover(item: $cropItem) { item in
                ImageCropperView(image: item.image, shape: .circle) { jpeg in
                    Task { await update(jpeg) }
                }
            }
            .navigationTitle("Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .confirmationDialog("Konto wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Konto endgültig löschen", role: .destructive) {
                    Task { await auth.deleteAccount(); dismiss() }
                }
            } message: { Text("Das kann nicht rückgängig gemacht werden.") }
        }
    }

    private var hasAvatar: Bool { !(auth.user?.avatar.isEmpty ?? true) }

    private func update(_ jpeg: Data?) async {
        isUploading = true
        await auth.setAvatar(jpeg)
        isUploading = false
    }

    private var displayName: String {
        let n = auth.user?.name ?? ""
        return n.isEmpty ? "–" : n
    }
}
