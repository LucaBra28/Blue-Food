import Foundation
import WatchConnectivity

/// Überträgt die Anmeldung (Token und Nutzer-ID) an die Apple Watch.
final class PhoneLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneLink()

    private var pending: [String: Any]?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sendet die Anmeldung; `nil` bedeutet abgemeldet.
    func send(token: String?, userID: String?) {
        var context: [String: Any] = [:]
        if let token, let userID {
            context["token"] = token
            context["userID"] = userID
        }
        pending = context
        flush()
    }

    private func flush() {
        guard WCSession.isSupported(), let context = pending else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(context)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.flush() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
