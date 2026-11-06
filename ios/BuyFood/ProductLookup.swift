import Foundation

/// Sucht Produktnamen zu Barcodes bei Open Food Facts (frei nutzbar, kein Schlüssel nötig).
enum ProductLookup {
    private struct Response: Decodable {
        struct Product: Decodable {
            let product_name: String?
            let product_name_de: String?
            let brands: String?
            let image_front_small_url: String?
            let image_front_url: String?
        }
        let status: Int
        let product: Product?
    }

    struct Product {
        let name: String
        let imageURL: String
    }

    static func product(forBarcode code: String) async -> Product? {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,product_name_de,brands,image_front_small_url,image_front_url")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue("BuyFood/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let res = try? JSONDecoder().decode(Response.self, from: data),
              res.status == 1, let p = res.product else { return nil }
        let name = [p.product_name_de, p.product_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let name else { return nil }
        let brand = p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let image = (p.image_front_small_url ?? p.image_front_url ?? "").replacingOccurrences(of: "http://", with: "https://")
        if !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) { return Product(name: "\(brand) \(name)", imageURL: image) }
        return Product(name: name, imageURL: image)
    }
}
