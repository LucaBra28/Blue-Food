import Foundation
import Observation

/// Anmeldung und Listen auf der Uhr.
@Observable
@MainActor
final class WatchStore {
    static let shared = WatchStore()

    private(set) var lists: [ShoppingList] = []
    private(set) var userID: String?
    private(set) var isSignedIn = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let api = APIClient.shared

    func setSession(token: String?, userID: String?) {
        api.token = token
        self.userID = userID
        isSignedIn = token != nil
        if token == nil {
            lists = []
            hasLoaded = false
            WatchLive.shared.stop()
        } else {
            Task { await loadLists() }
            WatchLive.shared.start()
        }
    }

    func loadLists() async {
        guard isSignedIn else { return }
        do {
            let page: ListPage = try await api.get("api/collections/lists/records", query: [
                URLQueryItem(name: "perPage", value: "200"),
                URLQueryItem(name: "sort", value: "-created"),
            ])
            lists = page.items
            errorMessage = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }
}

/// Artikel einer Liste auf der Uhr.
@Observable
@MainActor
final class WatchListModel {
    let listID: String
    private(set) var items: [ListItem] = []
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let api = APIClient.shared

    init(listID: String) { self.listID = listID }

    var open: [ListItem] { items.filter { !$0.checked } }
    var done: [ListItem] { items.filter { $0.checked } }

    func load() async {
        do {
            let page: ItemPage = try await api.get("api/collections/items/records", query: [
                URLQueryItem(name: "filter", value: "list = \"\(listID)\""),
                URLQueryItem(name: "sort", value: "created"),
                URLQueryItem(name: "perPage", value: "500"),
            ])
            items = page.items
            errorMessage = nil
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    func toggle(_ item: ListItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newValue = !items[index].checked
        items[index].checked = newValue // sofort anzeigen
        do {
            let updated: ListItem = try await api.patch("api/collections/items/records/\(item.id)", body: ["checked": newValue])
            replace(updated)
        } catch {
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].checked = !newValue }
            errorMessage = error.localizedDescription
        }
    }

    func add(name: String, quantity: Double, unit: ItemUnit, userID: String) async -> Bool {
        do {
            let item: ListItem = try await api.post("api/collections/items/records", body: [
                "list": listID,
                "name": name,
                "quantity": quantity,
                "unit": unit.rawValue,
                "createdBy": userID,
            ])
            if !items.contains(where: { $0.id == item.id }) { items.append(item) }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func update(_ item: ListItem, name: String, quantity: Double, unit: ItemUnit) async -> Bool {
        do {
            let updated: ListItem = try await api.patch("api/collections/items/records/\(item.id)", body: [
                "name": name,
                "quantity": quantity,
                "unit": unit.rawValue,
            ])
            replace(updated)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ item: ListItem) async {
        let backup = items
        items.removeAll { $0.id == item.id }
        do {
            try await api.delete("api/collections/items/records/\(item.id)")
        } catch {
            items = backup
            errorMessage = error.localizedDescription
        }
    }

    /// Änderung von einem anderen Gerät übernehmen (Live-Verbindung).
    func apply(action: String, record: [String: Any]) {
        guard (record["list"] as? String) == listID, let id = record["id"] as? String else { return }
        if action == "delete" {
            items.removeAll { $0.id == id }
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let item = try? JSONDecoder().decode(ListItem.self, from: data) else { return }
        if let index = items.firstIndex(where: { $0.id == id }) { items[index] = item } else { items.append(item) }
    }

    private func replace(_ item: ListItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
    }
}
