import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Schlanker PocketBase-Client.
final class APIClient {
    static let shared = APIClient()
    var token: String?

    private let session = URLSession.shared
    private let decoder = JSONDecoder()

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(method: "GET", path: path, query: query, body: nil)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any] = [:]) async throws -> T {
        try await send(method: "POST", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await send(method: "PATCH", path: path, body: body)
    }

    /// Lädt eine Datei per multipart/form-data hoch (PATCH auf einen Record).
    func patchFile<T: Decodable>(_ path: String, field: String, data: Data, filename: String, mime: String = "image/jpeg") async throws -> T {
        let boundary = "bf-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: Config.baseURL.appendingPathComponent(path))
        req.httpMethod = "PATCH"
        req.timeoutInterval = 60
        if let token { req.setValue(token, forHTTPHeaderField: "Authorization") }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (respData, response) = try await session.upload(for: req, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any])?["message"] as? String
            throw APIError(status: status, message: msg ?? "Serverfehler (\(status))")
        }
        return try decoder.decode(T.self, from: respData)
    }

    func delete(_ path: String) async throws {
        _ = try await raw(method: "DELETE", path: path, query: [], body: nil)
    }

    func postVoid(_ path: String, body: [String: Any] = [:]) async throws {
        _ = try await raw(method: "POST", path: path, query: [], body: body)
    }

    private func send<T: Decodable>(method: String, path: String, query: [URLQueryItem] = [], body: [String: Any]?) async throws -> T {
        let data = try await raw(method: method, path: path, query: query, body: body)
        return try decoder.decode(T.self, from: data)
    }

    private func raw(method: String, path: String, query: [URLQueryItem], body: [String: Any]?) async throws -> Data {
        var comps = URLComponents(url: Config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 20
        if let token { req.setValue(token, forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw APIError(status: status, message: msg ?? "Serverfehler (\(status))")
        }
        return data
    }
}
