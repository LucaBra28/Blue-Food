import Foundation
import Observation

/// Persönliche Einstellungen eines Nutzers für eine Liste. Standard: alles an.
struct ListPrefs: Equatable {
    var notifyAdded = true
    var notifyChecked = true
}

/// Eintrag aus der Collection `listPrefs`.
private struct PrefsRecord: Decodable {
    let id: String
    let notifyAdded: Bool?
    let notifyChecked: Bool?

    var prefs: ListPrefs {
        ListPrefs(
            notifyAdded: notifyAdded ?? true,
            notifyChecked: notifyChecked ?? true
        )
    }
}

private struct PrefsPage: Decodable {
    let items: [PrefsRecord]
}

@Observable
@MainActor
final class ListPrefsStore {
    private(set) var prefs = ListPrefs()
    private(set) var isLoaded = false
    var errorMessage: String?

    private var recordID: String?
    private let api = APIClient.shared

    func load(listID: String, userID: String) async {
        do {
            let page: PrefsPage = try await api.get("api/collections/listPrefs/records", query: [
                URLQueryItem(name: "filter", value: "user = \"\(userID)\" && list = \"\(listID)\""),
                URLQueryItem(name: "perPage", value: "1"),
            ])
            if let record = page.items.first {
                recordID = record.id
                prefs = record.prefs
            } else {
                recordID = nil
                prefs = ListPrefs()
            }
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }

    /// Speichert die Einstellungen. Die Anzeige ändert sich sofort, bei einem Fehler wird zurückgesetzt.
    func update(_ new: ListPrefs, listID: String, userID: String) async {
        let old = prefs
        prefs = new
        let body: [String: Any] = [
            "notifyAdded": new.notifyAdded,
            "notifyChecked": new.notifyChecked,
        ]
        do {
            if let recordID {
                let _: PrefsRecord = try await api.patch("api/collections/listPrefs/records/\(recordID)", body: body)
            } else {
                var create = body
                create["user"] = userID
                create["list"] = listID
                let record: PrefsRecord = try await api.post("api/collections/listPrefs/records", body: create)
                recordID = record.id
            }
            errorMessage = nil
        } catch {
            prefs = old
            errorMessage = error.localizedDescription
        }
    }
}
