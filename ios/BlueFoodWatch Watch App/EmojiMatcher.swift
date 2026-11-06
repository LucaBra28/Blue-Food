import Foundation

/// Ordnet Artikelnamen automatisch ein passendes Emoji zu (nur wenn es eindeutig sinnvoll ist).
enum EmojiMatcher {
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ae", with: "a")
            .replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
    }

    private static let table: [(String, [String])] = [
        // Obst
        ("🍎", ["apfel", "aepfel", "äpfel"]), ("🍐", ["birne"]), ("🍌", ["banane"]),
        ("🍊", ["orange", "mandarine", "clementine", "satsuma"]), ("🍋", ["zitrone", "limette"]),
        ("🍓", ["erdbeere", "himbeere", "brombeere"]), ("🫐", ["heidelbeere", "blaubeere"]),
        ("🍒", ["kirsche"]), ("🍇", ["traube", "weintraube"]), ("🍈", ["melone", "honigmelone"]),
        ("🍉", ["wassermelone"]), ("🍍", ["ananas"]), ("🥭", ["mango"]), ("🍑", ["pfirsich", "nektarine", "aprikose"]),
        ("🥝", ["kiwi"]), ("🥥", ["kokosnuss", "kokos"]), ("🥑", ["avocado"]),
        // Gemüse
        ("🍅", ["tomate", "tomaten", "cherrytomate"]), ("🥒", ["gurke", "salatgurke", "zucchini"]),
        ("🫑", ["paprika"]), ("🥕", ["karotte", "moehre", "mohre", "mohrrube", "mohren"]),
        ("🥔", ["kartoffel", "kartoffeln"]), ("🧅", ["zwiebel", "lauchzwiebel", "schalotte"]),
        ("🧄", ["knoblauch"]), ("🥦", ["brokkoli", "blumenkohl"]), ("🥬", ["salat", "spinat", "kohl", "mangold", "rucola", "feldsalat"]),
        ("🌽", ["mais"]), ("🍄", ["pilz", "champignon", "pfifferling"]), ("🍆", ["aubergine"]),
        ("🎃", ["kuerbis", "kurbis"]), ("🌶️", ["chili", "peperoni"]), ("🫚", ["ingwer"]),
        ("🫛", ["erbse"]), ("🫘", ["bohne", "linse", "kichererbse"]), ("🫒", ["olive", "oliven", "olivenoel"]),
        ("🥜", ["nuss", "nuesse", "erdnuss", "mandel", "haselnuss", "walnuss", "cashew"]),
        // Milch & Eier
        ("🥛", ["milch", "joghurt", "sahne", "quark", "kefir", "buttermilch", "schmand"]),
        ("🧀", ["kaese", "mozzarella", "parmesan", "gouda", "feta", "frischkaese"]),
        ("🧈", ["butter", "margarine"]), ("🥚", ["ei", "eier"]),
        // Fleisch & Fisch
        ("🥩", ["fleisch", "steak", "hackfleisch", "hack", "rind", "schwein", "gulasch"]),
        ("🍗", ["haehnchen", "hahnchen", "huhn", "huehnchen", "hahnchenbrust", "pute", "putenbrust"]),
        ("🥓", ["schinken", "speck", "bacon"]), ("🌭", ["wurst", "wuerstchen", "bratwurst", "salami", "leberkaese"]),
        ("🐟", ["fisch", "lachs", "thunfisch", "forelle", "hering"]), ("🍤", ["garnele", "shrimp", "scampi"]),
        // Backwaren & Süßes
        ("🍞", ["brot", "toast", "toastbrot", "vollkornbrot"]), ("🥖", ["broetchen", "brotchen", "semmel", "baguette"]),
        ("🥐", ["croissant", "hoernchen"]), ("🥨", ["brezel", "breze", "salzstange"]),
        ("🍰", ["kuchen", "torte"]), ("🍪", ["keks", "kekse", "plaetzchen"]), ("🍫", ["schokolade", "schoko", "nutella"]),
        ("🍬", ["bonbon", "gummibaerchen", "gummibarchen", "zucker"]), ("🍯", ["honig", "marmelade", "konfituere"]),
        ("🍦", ["eis", "eiscreme", "speiseeis"]), ("🍿", ["popcorn"]),
        // Grundnahrung
        ("🍝", ["nudel", "nudeln", "spaghetti", "pasta", "penne", "tagliatelle"]), ("🍚", ["reis", "basmati"]),
        ("🌾", ["mehl", "haferflocken", "gries", "weizen"]), ("🥣", ["muesli", "mueslis", "cornflakes", "porridge"]),
        ("🧂", ["salz", "pfeffer", "gewuerz", "gewurz"]), ("🍟", ["pommes", "chips"]), ("🍕", ["pizza"]),
        ("🍔", ["burger", "hamburger"]), ("🥫", ["ketchup", "senf", "sauce", "sosse", "konserve", "mayonnaise", "mayo"]),
        ("🍲", ["suppe", "eintopf"]), ("🥗", ["salatmischung"]),
        // Getränke
        ("💧", ["wasser", "mineralwasser", "sprudel"]), ("🧃", ["saft", "orangensaft", "apfelsaft", "schorle"]),
        ("🥤", ["cola", "limo", "limonade", "fanta", "sprite", "energydrink"]), ("🍺", ["bier", "radler", "weizen"]),
        ("🍷", ["wein", "rotwein", "weisswein"]), ("🥂", ["sekt", "prosecco", "champagner"]),
        ("☕", ["kaffee", "espresso", "kapsel"]), ("🍵", ["tee", "kraeutertee", "eistee"]),
        // Haushalt & Drogerie
        ("🧻", ["toilettenpapier", "klopapier", "kuechenrolle", "taschentuecher", "papiertuch"]),
        ("🧼", ["seife", "duschgel", "handseife"]), ("🧴", ["shampoo", "creme", "lotion", "sonnencreme", "deo"]),
        ("🪥", ["zahnpasta", "zahnbuerste", "zahncreme"]), ("🧽", ["spuelmittel", "schwamm", "reiniger", "putzmittel"]),
        ("🧺", ["waschmittel", "weichspueler"]), ("🗑️", ["muellbeutel", "muellsack", "muellsaecke"]),
        ("🔋", ["batterie", "batterien", "akku"]), ("💡", ["gluehbirne", "leuchtmittel", "lampe"]),
        ("🐱", ["katzenfutter", "katzenstreu"]), ("🐶", ["hundefutter", "leckerli"]), ("💐", ["blume", "blumen", "strauss"]),
        ("🕯️", ["kerze", "kerzen"]), ("🎂", ["geburtstag"]), ("🍼", ["windel", "windeln", "babynahrung"]),
    ]

    private static let keywords: [(emoji: String, word: String)] = table.flatMap { emoji, words in
        words.map { (emoji, fold($0)) }
    }

    static func emoji(for name: String) -> String? {
        let words = fold(name)
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !$0.isEmpty }
        var best: (score: Int, emoji: String)?
        for word in words {
            for (emoji, key) in keywords {
                var score = 0
                if word == key {
                    score = 100 + key.count                                   // exakter Treffer
                } else if word.hasPrefix(key), word.count - key.count <= 3, key.count >= 2 {
                    score = 50 + key.count                                    // Mehrzahl/Endung, z. B. „Tomaten“
                } else if key.count >= 4, word.hasSuffix(key) {
                    score = 10 + key.count                                    // Zusammensetzung, z. B. „Vollmilch“ (Grundwort zählt)
                } else if key.count >= 5, word.hasPrefix(key) {
                    score = key.count                                         // z. B. „Kaffeebohnen“
                }
                if score > 0, score > (best?.score ?? 0) { best = (score, emoji) }
            }
        }
        return best?.emoji
    }
}
