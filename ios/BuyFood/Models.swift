import Foundation

struct AppUser: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var avatar: String

    init(id: String, name: String, avatar: String = "") { self.id = id; self.name = name; self.avatar = avatar }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
    }

    func avatarURL(thumb: String = "96x96") -> URL? {
        Config.fileURL(collection: "users", id: id, file: avatar, thumb: thumb)
    }
}

struct ShoppingList: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let owner: String
    let members: [String]
    let image: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        owner = try c.decode(String.self, forKey: .owner)
        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []
        image = try c.decodeIfPresent(String.self, forKey: .image) ?? ""
    }

    func isOwned(by userID: String) -> Bool { owner == userID }
    var memberCount: Int { members.count + 1 }

    func imageURL(thumb: String = "120x120") -> URL? {
        Config.fileURL(collection: "lists", id: id, file: image, thumb: thumb)
    }
}

struct ListMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let avatar: String?
    let isOwner: Bool

    func avatarURL(thumb: String = "96x96") -> URL? {
        Config.fileURL(collection: "users", id: id, file: avatar ?? "", thumb: thumb)
    }
}

struct AuthResponse: Decodable {
    let token: String
    let record: AppUser
}

struct ListPage: Decodable {
    let items: [ShoppingList]
}

/// Einladung, die ich erhalten habe.
struct ListInvite: Codable, Identifiable, Hashable {
    let id: String
    let listName: String
    let inviterName: String
}

/// Einladung, die ich als Ersteller verschickt habe.
struct SentInvite: Codable, Identifiable, Hashable {
    let id: String
    let email: String
}

enum ItemUnit: String, CaseIterable, Identifiable {
    case piece = "Stück", g, kg, mg, ml, l, pack = "Packung", bottle = "Flasche", can = "Dose", crate = "Kiste"
    var id: String { rawValue }

    /// Schrittweite für die +/−-Tasten.
    var step: Double {
        switch self {
        case .piece, .pack, .bottle, .can, .crate: 1
        case .g, .mg: 50
        case .ml: 100
        case .kg, .l: 0.5
        }
    }

    var short: String {
        switch self {
        case .piece: "×"
        case .pack: "Pck."
        case .bottle: "Fl."
        default: rawValue
        }
    }

    /// z. B. "3×", "500 g", "1,5 kg", "2 Pck."
    func formatted(_ amount: Double) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        return self == .piece ? "\(number)×" : "\(number) \(short)"
    }
}

struct ListItem: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var checked: Bool
    let createdBy: String
    var quantity: Double
    var unitName: String
    var imageURLString: String

    var unit: ItemUnit { ItemUnit(rawValue: unitName) ?? .piece }
    var imageURL: URL? { imageURLString.isEmpty ? nil : URL(string: imageURLString) }
    /// Automatisches Emoji zum Namen (nur wenn es logisch passt).
    var emoji: String? { EmojiMatcher.emoji(for: name) }
    var quantityText: String { unit.formatted(quantity) }

    enum CodingKeys: String, CodingKey { case id, name, checked, createdBy, quantity, unitName = "unit", imageURLString = "imageUrl" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        let q = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? 1
        quantity = q > 0 ? q : 1
        let u = try c.decodeIfPresent(String.self, forKey: .unitName) ?? ""
        unitName = u.isEmpty ? ItemUnit.piece.rawValue : u
        imageURLString = try c.decodeIfPresent(String.self, forKey: .imageURLString) ?? ""
    }
}

struct ItemPage: Decodable {
    let items: [ListItem]
}