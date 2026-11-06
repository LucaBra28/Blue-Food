import Foundation
import Observation

struct LiveEvent {
    let collection: String
    let action: String
    let record: [String: Any]
}

/// Live-Verbindung zu PocketBase (Server-Sent Events). Änderungen anderer Geräte kommen sofort an.
@Observable
@MainActor
final class LiveUpdates {
    static let shared = LiveUpdates()

    /// Zähler, die sich bei Änderungen erhöhen; Views laden damit gezielt neu (`.task(id:)`).
    private(set) var listsVersion = 0
    private(set) var invitesVersion = 0
    private(set) var reconnectVersion = 0
    private(set) var isConnected = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var itemListeners: [UUID: AsyncStream<LiveEvent>.Continuation] = [:]

    /// (Neu) verbinden – etwa nach der Anmeldung oder wenn die App wieder aktiv wird.
    func start() {
        task?.cancel()
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        isConnected = false
    }

    /// Änderungen an Artikeln (alle Listen, die der Nutzer sehen darf).
    func itemEvents() -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in
            let id = UUID()
            itemListeners[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.itemListeners[id] = nil }
            }
        }
    }

    // MARK: Verbindung

    private func run() async {
        var delay = 1.0
        while !Task.isCancelled {
            let started = Date()
            do { try await connectOnce() } catch {}
            isConnected = false
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
                "subscriptions": ["lists", "items", "invites"],
            ])
            isConnected = true
            reconnectVersion += 1 // alles einmal frisch laden
            return
        }

        guard let action = object["action"] as? String, let record = object["record"] as? [String: Any] else { return }
        switch event {
        case "lists": listsVersion += 1
        case "invites": invitesVersion += 1        case "items":
            let live = LiveEvent(collection: event, action: action, record: record)
            for continuation in itemListeners.values { continuation.yield(live) }
        default: break
        }
    }
}
