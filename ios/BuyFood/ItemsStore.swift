import Foundation
import Observation

@Observable
@MainActor
final class ItemsStore {
    let listID: String
    private(set) var items: [ListItem] = []
    private(set) var hasLoaded = false
    var errorMessage: String?

    private let api = APIClient.shared

    init(listID: String) { self.listID = listID }

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

    func add(name: String, quantity: Double = 1, unit: ItemUnit = .piece, imageURL: String = "", userID: String) async -> Bool {
        do {
            let item: ListItem = try await api.post("api/collections/items/records",
                                                    body: ["list": listID, "name": name, "quantity": quantity, "unit": unit.rawValue, "imageUrl": imageURL, "createdBy": userID])
            // Die Live-Verbindung kann den neuen Artikel schon eingefügt haben; dann nicht doppelt anhängen.
            if !items.contains(where: { $0.id == item.id }) { items.append(item) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func update(_ item: ListItem, name: String, quantity: Double, unit: ItemUnit) async {
        do {
            let updated: ListItem = try await api.patch("api/collections/items/records/\(item.id)",
                                                        body: ["name": name, "quantity": quantity, "unit": unit.rawValue])
            replace(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    func setQuantity(_ item: ListItem, _ quantity: Double) async {
        let q = (min(max(quantity, 0.01), 100000) * 100).rounded() / 100
        guard q != item.quantity else { return }
        var changed = item
        changed.quantity = q
        replace(changed) // sofort anzeigen
        do {
            let updated: ListItem = try await api.patch("api/collections/items/records/\(item.id)", body: ["quantity": q])
            replace(updated)
        } catch {
            replace(item)
            errorMessage = error.localizedDescription
        }
    }

    /// Fügt hinzu; gibt es denselben Artikel (gleicher Name und Einheit) schon offen, wird die Menge erhöht.
    func addMerging(name: String, quantity: Double, unit: ItemUnit, imageURL: String = "", userID: String) async -> Bool {
        if let existing = items.first(where: {
            !$0.checked && $0.unit == unit && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            await setQuantity(existing, existing.quantity + quantity)
            return errorMessage == nil
        }
        return await add(name: name, quantity: quantity, unit: unit, imageURL: imageURL, userID: userID)
    }

    func toggle(_ item: ListItem) async {
        var flipped = item
        flipped.checked.toggle()
        replace(flipped) // sofort anzeigen
        do {
            let updated: ListItem = try await api.patch("api/collections/items/records/\(item.id)", body: ["checked": flipped.checked])
            replace(updated)
        } catch {
            replace(item) // zurückrollen
            errorMessage = error.localizedDescription
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

    /// Änderung von einem anderen Gerät übernehmen.
    func apply(_ event: LiveEvent) {
        guard (event.record["list"] as? String) == listID, let id = event.record["id"] as? String else { return }
        if event.action == "delete" {
            items.removeAll { $0.id == id }
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: event.record),
              let item = try? JSONDecoder().decode(ListItem.self, from: data) else { return }
        if let index = items.firstIndex(where: { $0.id == id }) { items[index] = item } else { items.append(item) }
    }

    private func replace(_ item: ListItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
    }
}
