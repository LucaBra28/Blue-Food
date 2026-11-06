import Foundation

enum Config {
    /// PocketBase-Server (derzeit HTTP, nur für die Entwicklung – siehe ATS-Ausnahme in Config/Info.plist).
    static let baseURL = URL(string: "http://89.58.8.83:8097")!

    /// URL einer Datei in PocketBase (Collection-Name, Record-ID, Dateiname, optionale Thumbnail-Größe).
    static func fileURL(collection: String, id: String, file: String, thumb: String? = nil) -> URL? {
        guard !file.isEmpty else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/files/\(collection)/\(id)/\(file)"), resolvingAgainstBaseURL: false)
        if let thumb { comps?.queryItems = [URLQueryItem(name: "thumb", value: thumb)] }
        return comps?.url
    }
}
