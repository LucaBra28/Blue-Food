import Foundation
import UIKit
import UserNotifications

/// Push-Nachrichten: fragt die Berechtigung an und meldet das APNs-Token des Geräts beim Server an.
@MainActor
final class PushManager {
    static let shared = PushManager()

    /// Sandbox für Xcode-Builds vom Kabel, Production für TestFlight und App Store.
    #if DEBUG
    private static let environment = "sandbox"
    #else
    private static let environment = "production"
    #endif

    private static let tokenKey = "apnsDeviceToken"

    private var userID: String?
    private var authToken: String?

    /// Nach der Anmeldung: Berechtigung anfragen und das Token melden.
    func register(userID: String, authToken: String) {
        self.userID = userID
        self.authToken = authToken
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
        if let stored = UserDefaults.standard.string(forKey: Self.tokenKey) {
            Task { await upload(stored) }
        }
    }

    /// Vom AppDelegate aufgerufen, sobald iOS das Token liefert.
    func didReceive(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        Task { await upload(token) }
    }

    /// Beim Abmelden das Gerät entfernen, damit keine Nachrichten mehr an diese Person gehen.
    func unregister(authToken: String) async {
        guard let token = UserDefaults.standard.string(forKey: Self.tokenKey) else { return }
        do {
            let data = try await call("GET", "api/collections/devices/records",
                                      query: [URLQueryItem(name: "filter", value: "token = \"\(token)\"")],
                                      token: authToken)
            for device in try JSONDecoder().decode(DeviceList.self, from: data).items {
                _ = try await call("DELETE", "api/collections/devices/records/\(device.id)", token: authToken)
            }
        } catch {
            // Offline o. Ä.: beim nächsten Abmelden erneut versuchen.
        }
    }

    private func upload(_ token: String) async {
        guard let userID, let authToken else { return }
        do {
            let data = try await call("GET", "api/collections/devices/records",
                                      query: [URLQueryItem(name: "filter", value: "token = \"\(token)\"")],
                                      token: authToken)
            if let existing = try JSONDecoder().decode(DeviceList.self, from: data).items.first {
                _ = try await call("PATCH", "api/collections/devices/records/\(existing.id)",
                                   body: ["user": userID, "env": Self.environment], token: authToken)
            } else {
                _ = try await call("POST", "api/collections/devices/records",
                                   body: ["user": userID, "token": token, "env": Self.environment], token: authToken)
            }
        } catch {
            // Wird beim nächsten Start oder Anmelden erneut versucht.
        }
    }

    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil, token: String) async throws -> Data {
        var comps = URLComponents(url: Config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(token, forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct DeviceRecord: Decodable { let id: String }
    private struct DeviceList: Decodable { let items: [DeviceRecord] }
}

/// Empfängt Token und Mitteilungen von iOS.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PhoneLink.shared.activate()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didReceive(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs-Registrierung fehlgeschlagen: \(error.localizedDescription)")
    }

    /// Auch im Vordergrund als Banner zeigen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
