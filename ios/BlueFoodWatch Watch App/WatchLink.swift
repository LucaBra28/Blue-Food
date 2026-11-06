import Foundation
import WatchConnectivity

/// Empfängt Anmeldung (Token und Nutzer-ID) vom iPhone.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchLink()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        let token = context["token"] as? String
        let userID = context["userID"] as? String
        Task { @MainActor in WatchStore.shared.setSession(token: token, userID: userID) }
    }
}
