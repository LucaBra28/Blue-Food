import Foundation
import Observation

/// Live-Verbindung zu PocketBase (Server-Sent Events) für die Uhr.
/// Änderungen an Listen und Artikeln kommen sofort an, solange die App aktiv ist.
@Observable
@MainActor
final class WatchLive {
    static let shared = WatchLive()

    /// Erhöht sich bei jeder Änderung an Artikeln oder Listen; Views laden damit neu.
    private(set) var version = 0
    /// Einzelne Artikelereignisse, die die offene Liste direkt übernehmen kann.
    private(set) var lastItemEvent: (action: String, record: [String: Any])?

    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        var delay = 1.0
        while !Task.isCancelled {
            let started = Date()
            do { try await connectOnce() } catch {}
            if Task.isCancelled { return }
            delay = Date().timeIntervalSince(started) > 30 ? 1 : min(delay * 2, 15)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func connectOnce() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 86_400
        config.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: Config.baseURL.appendingPathComponent("api/realtime"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 86_400
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        var event = ""
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                try await handle(event: event, json: String(line.dropFirst(5)))
            }
        }
    }

    private func handle(event: String, json: String) async throws {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if event == "PB_CONNECT" {
            guard let clientID = object["clientId"] as? String else { return }
            try await APIClient.shared.postVoid("api/realtime", body: [
                "clientId": clientID,
                "subscriptions": ["lists", "items"],
            ])
            version += 1 // alles einmal frisch laden
            return
        }

        guard let action = object["action"] as? String, let record = object["record"] as? [String: Any] else { return }
        switch event {
        case "lists":
            version += 1
        case "items":
            lastItemEvent = (action, record)
            version += 1
        default:
            break
        }
    }
}
