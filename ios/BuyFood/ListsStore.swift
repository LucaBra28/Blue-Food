import Foundation
import Observation

@Observable
@MainActor
final class ListsStore {
    private(set) var lists: [ShoppingList] = []
    private(set) var invites: [ListInvite] = []
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let api = APIClient.shared

    func load() async {
        do {
            let page: ListPage = try await api.get("api/collections/lists/records", query: [
                URLQueryItem(name: "perPage", value: "200"),
                URLQueryItem(name: "sort", value: "-created"),
            ])
            lists = page.items
            invites = (try? await api.get("api/buyfood/invites")) ?? invites
            errorMessage = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    @discardableResult
    func create(name: String, ownerID: String) async -> Bool {
        do {
            let list: ShoppingList = try await api.post("api/collections/lists/records", body: ["name": name, "owner": ownerID])
            lists.insert(list, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func rename(_ list: ShoppingList, to name: String) async {
        do {
            let updated: ShoppingList = try await api.patch("api/collections/lists/records/\(list.id)", body: ["name": name])
            replace(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    func setImage(_ jpeg: Data?, for list: ShoppingList) async {
        let path = "api/collections/lists/records/\(list.id)"
        do {
            let updated: ShoppingList
            if let jpeg {
                updated = try await api.patchFile(path, field: "image", data: jpeg, filename: "list.jpg")
            } else {
                updated = try await api.patch(path, body: ["image": NSNull()])
            }
            replace(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ list: ShoppingList) async {
        do {
            try await api.delete("api/collections/lists/records/\(list.id)")
            lists.removeAll { $0.id == list.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func leave(_ list: ShoppingList) async {
        do {
            try await api.postVoid("api/buyfood/lists/\(list.id)/leave")
            lists.removeAll { $0.id == list.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func removeMember(_ member: ListMember, from list: ShoppingList) async {
        do {
            let updated: ShoppingList = try await api.post("api/buyfood/lists/\(list.id)/remove-member", body: ["userId": member.id])
            replace(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    func accept(_ invite: ListInvite) async {
        do {
            let list: ShoppingList = try await api.post("api/buyfood/invites/\(invite.id)/accept")
            invites.removeAll { $0.id == invite.id }
            if lists.contains(where: { $0.id == list.id }) { replace(list) } else { lists.insert(list, at: 0) }
        } catch { errorMessage = error.localizedDescription; await load() }
    }

    func decline(_ invite: ListInvite) async {
        do {
            try await api.postVoid("api/buyfood/invites/\(invite.id)/decline")
            invites.removeAll { $0.id == invite.id }
        } catch { errorMessage = error.localizedDescription; await load() }
    }

    /// Gibt eine Fehlermeldung zurück oder nil bei Erfolg.
    func invite(email: String, to list: ShoppingList) async -> String? {
        do {
            try await api.postVoid("api/buyfood/lists/\(list.id)/invite", body: ["email": email])
            return nil
        } catch { return error.localizedDescription }
    }

    func sentInvites(for list: ShoppingList) async -> [SentInvite] {
        (try? await api.get("api/buyfood/lists/\(list.id)/invites")) ?? []
    }

    func cancel(_ invite: SentInvite) async {
        try? await api.delete("api/buyfood/invites/\(invite.id)")
    }

    func members(of list: ShoppingList) async -> [ListMember] {
        (try? await api.get("api/buyfood/lists/\(list.id)/members")) ?? []
    }

    func list(id: String) -> ShoppingList? { lists.first { $0.id == id } }

    private func replace(_ list: ShoppingList) {
        if let i = lists.firstIndex(where: { $0.id == list.id }) { lists[i] = list }
    }
}
