import Foundation

/// Arabic/Latin-insensitive text normalization used for search.
enum SearchText {
    private static let letterMap: [Unicode.Scalar: Unicode.Scalar] = [
        "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ة": "ه", "ى": "ي",
    ]

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out = String.UnicodeScalarView()
        for u in folded.unicodeScalars {
            let v = u.value
            // Arabic harakat (U+064B...U+065F), superscript alef (U+0670) and tatweel (U+0640)
            if (0x064B...0x065F).contains(v) || v == 0x0670 || v == 0x0640 { continue }
            out.append(letterMap[u] ?? u)
        }
        return String(out)
    }
}

/// Pre-normalized names so each keystroke is a cheap scan done off the main thread.
struct SearchIndex {
    let items: [Item]
    let keys: [String]

    static let empty = SearchIndex(items: [])

    init(items: [Item]) {
        self.items = items
        self.keys = items.map { SearchText.normalize($0.name) }
    }

    /// Names that start with the query come first.
    func search(_ query: String, limit: Int = 150) -> [Item] {
        let q = SearchText.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return [] }
        var starts: [Item] = []
        var others: [Item] = []
        for i in keys.indices {
            let k = keys[i]
            guard k.contains(q) else { continue }
            if k.hasPrefix(q) { starts.append(items[i]) } else { others.append(items[i]) }
            if starts.count >= limit || starts.count + others.count >= limit * 3 { break }
        }
        return Array((starts + others).prefix(limit))
    }
}
