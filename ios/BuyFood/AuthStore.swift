import AuthenticationServices
import CryptoKit
import Foundation
import Observation

@Observable
@MainActor
final class AuthStore {
    private(set) var user: AppUser?
    var errorMessage: String?
    var isWorking = false

    private let api = APIClient.shared
    private var currentNonce = ""

    init() {
        if let token = Keychain.get("token"),
           let json = Keychain.get("user"),
           let user = try? JSONDecoder().decode(AppUser.self, from: Data(json.utf8)) {
            api.token = token
            self.user = user
        }
    }

    // MARK: Sign in with Apple

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        currentNonce = Self.randomNonce()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(currentNonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Anmeldung fehlgeschlagen: \(error.localizedDescription)"
            }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple hat kein gültiges Token geliefert."
                return
            }
            let name = PersonNameComponentsFormatter().string(from: cred.fullName ?? PersonNameComponents())
            isWorking = true
            defer { isWorking = false }
            do {
                let res: AuthResponse = try await api.post("api/buyfood/apple-auth", body: [
                    "identityToken": identityToken,
                    "nonce": currentNonce,
                    "fullName": name,
                ])
                store(token: res.token, user: res.record)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Session

    func refreshOnLaunch() async {
        guard api.token != nil else { return }
        do {
            let res: AuthResponse = try await api.post("api/collections/users/auth-refresh")
            store(token: res.token, user: res.record)
        } catch let error as APIError where [401, 403, 404].contains(error.status) {
            signOut()
        } catch {
            // Offline o. Ä.: gespeicherte Sitzung behalten.
        }
    }

    func setAvatar(_ jpeg: Data?) async {
        guard let user else { return }
        let path = "api/collections/users/records/\(user.id)"
        do {
            let updated: AppUser
            if let jpeg {
                updated = try await api.patchFile(path, field: "avatar", data: jpeg, filename: "avatar.jpg")
            } else {
                updated = try await api.patch(path, body: ["avatar": NSNull()])
            }
            var merged = user
            merged.avatar = updated.avatar
            self.user = merged
            if let data = try? JSONEncoder().encode(merged) { Keychain.set(String(data: data, encoding: .utf8), for: "user") }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        if let token = api.token {
            Task { await PushManager.shared.unregister(authToken: token) }
        }
        api.token = nil
        user = nil
        Keychain.set(nil, for: "token")
        Keychain.set(nil, for: "user")
    }

    func deleteAccount() async {
        guard let user else { return }
        do {
            try await api.delete("api/collections/users/records/\(user.id)")
            signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func store(token: String, user: AppUser) {
        api.token = token
        self.user = user
        Keychain.set(token, for: "token")
        if let data = try? JSONEncoder().encode(user) {
            Keychain.set(String(data: data, encoding: .utf8), for: "user")
        }
    }

    // MARK: Nonce

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
