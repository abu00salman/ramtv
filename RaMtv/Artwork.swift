import SwiftUI

// MARK: - Title cleaning

struct ParsedTitle {
    var title: String
    var year: String?
}

enum TitleCleaner {
    static func parse(_ raw: String) -> ParsedTitle {
        var s = raw
        var year: String?
        if let r = s.range(of: "\\((19|20)\\d{2}\\)", options: .regularExpression) {
            year = String(s[r].dropFirst().dropLast())
            s.removeSubrange(r)
        } else if let r = s.range(of: "\\b(19|20)\\d{2}\\s*$", options: .regularExpression) {
            let candidate = String(s[r]).trimmed
            let rest = String(s[..<r.lowerBound]).trimmed
            if !rest.isEmpty { year = candidate; s = rest }
        }
        s = s.replacingOccurrences(of: "\\[.*?\\]|\\(.*?\\)", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\bS\\d{1,4}\\s*E\\d+.*$", with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "^\\s*[A-Za-z]{2,3}\\s*[|:]\\s*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[._]", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(
            of: "\\b(4k|8k|uhd|fhd|hd|1080p|720p|2160p|bluray|blu-ray|web-?dl|webrip|hdrip|x264|x265|h264|h265|hevc|hdr|dolby|atmos|dubbed|multi|sub|subbed)\\b",
            with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " -_.:|"))
        return ParsedTitle(title: s, year: year)
    }

    static func normalize(_ raw: String) -> String {
        var t = raw.lowercased()
        t = t.replacingOccurrences(of: "^\\s*[\\[\\(|]*[a-z]{2,3}[\\]\\)|]*\\s*[|:\\-]\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\(.*?\\)|\\[.*?\\]", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\b(hd|fhd|uhd|sd|4k|8k|hevc|h265|h264|1080p|720p|hq|backup|raw|tv|channel)\\b", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "sports", with: "sport")
        t = t.replacingOccurrences(of: "\\b0+(\\d)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression)
        return t
    }
}

// MARK: - Channel logo index (iptv-org public database)

@MainActor
final class LogoIndex {
    static let shared = LogoIndex()

    private var map: [String: String] = [:]
    private(set) var ready = false
    private var tried = false
    private var loading: Task<Void, Never>?

    private var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("logo-index.json")
    }

    func logo(for name: String) async -> (url: String?, cacheable: Bool) {
        await ensureLoaded()
        guard ready else { return (nil, false) }
        let key = TitleCleaner.normalize(name)
        if key.isEmpty { return (nil, true) }
        return (map[key], true)
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        map = [:]
        ready = false
        tried = false
    }

    private func ensureLoaded() async {
        if ready || tried { return }
        if let t = loading { await t.value; return }
        let t = Task { await self.load() }
        loading = t
        await t.value
        loading = nil
    }

    private func load() async {
        if let d = try? Data(contentsOf: fileURL),
           let m = try? JSONDecoder().decode([String: String].self, from: d), !m.isEmpty {
            map = m
            ready = true
            return
        }
        let built = await Task.detached(priority: .utility) { await LogoIndex.build() }.value
        tried = true
        if !built.isEmpty {
            map = built
            ready = true
            if let d = try? JSONEncoder().encode(built) { try? d.write(to: fileURL) }
        }
    }

    nonisolated private static func fetchJSON(_ s: String) async -> Any? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 180)
        req.setValue("RaMtv/1.0", forHTTPHeaderField: "User-Agent")
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    nonisolated private static func build() async -> [String: String] {
        let channels = await fetchJSON("https://iptv-org.github.io/api/channels.json")
        let logos = await fetchJSON("https://iptv-org.github.io/api/logos.json")
        var best: [String: (String, Int)] = [:]
        for l in (logos as? [[String: Any]]) ?? [] {
            guard let id = l["channel"] as? String, let url = l["url"] as? String else { continue }
            let area = ((l["width"] as? Int) ?? 0) * ((l["height"] as? Int) ?? 0)
            if let cur = best[id], cur.1 >= area { continue }
            best[id] = (url, area)
        }
        var out: [String: String] = [:]
        for c in (channels as? [[String: Any]]) ?? [] {
            guard let id = c["id"] as? String else { continue }
            let url = best[id]?.0 ?? (c["logo"] as? String)
            guard let u = url, !u.isEmpty else { continue }
            var names: [String] = [(c["name"] as? String) ?? ""]
            names += (c["alt_names"] as? [String]) ?? []
            for n in names {
                let k = TitleCleaner.normalize(n)
                if !k.isEmpty && out[k] == nil { out[k] = u }
            }
        }
        return out
    }
}

// MARK: - Artwork service (posters + logos)

@MainActor
final class ArtworkService {
    static let shared = ArtworkService()

    private var cache: [String: String] = [:]
    private var inflight: [String: Task<String?, Never>] = [:]
    private var dirty = 0
    private var nextSlot = Date.distantPast

    private var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("artwork.json")
    }

    private var tmdbKey: String { (UserDefaults.standard.string(forKey: "tmdbKey") ?? "").trimmed }

    init() {
        if let d = try? Data(contentsOf: fileURL),
           let m = try? JSONDecoder().decode([String: String].self, from: d) { cache = m }
    }

    func clear() {
        cache = [:]
        try? FileManager.default.removeItem(at: fileURL)
        LogoIndex.shared.reset()
    }

    private func key(for item: Item) -> String {
        if item.kind == .live { return "l|" + TitleCleaner.normalize(item.name) }
        let p = TitleCleaner.parse(item.name)
        return "\(item.kind.rawValue)|\(p.title.lowercased())|\(p.year ?? "")"
    }

    func artwork(for item: Item) async -> String? {
        let k = key(for: item)
        if let c = cache[k] { return c.isEmpty ? nil : c }
        if let t = inflight[k] { return await t.value }
        let task = Task { () -> String? in
            let r: (url: String?, cacheable: Bool)
            if item.kind == .live {
                r = await LogoIndex.shared.logo(for: item.name)
            } else {
                r = await self.poster(for: item)
            }
            if r.cacheable {
                self.cache[k] = r.url ?? ""
                self.dirty += 1
                if self.dirty >= 15 { self.dirty = 0; self.save() }
            }
            self.inflight[k] = nil
            return r.url
        }
        inflight[k] = task
        return await task.value
    }

    private func save() {
        let snapshot = cache
        let url = fileURL
        Task.detached {
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url) }
        }
    }

    private func poster(for item: Item) async -> (url: String?, cacheable: Bool) {
        let p = TitleCleaner.parse(item.name)
        if p.title.isEmpty { return (nil, true) }
        let key = tmdbKey
        if !key.isEmpty { return await tmdb(p, series: item.kind == .series, key: key) }
        return await itunes(p, series: item.kind == .series)
    }

    private func tmdb(_ p: ParsedTitle, series: Bool, key: String) async -> (url: String?, cacheable: Bool) {
        guard var c = URLComponents(string: "https://api.themoviedb.org/3/search/\(series ? "tv" : "movie")") else { return (nil, false) }
        var q = [URLQueryItem(name: "query", value: p.title)]
        if let y = p.year { q.append(URLQueryItem(name: series ? "first_air_date_year" : "year", value: y)) }
        let bearer = key.hasPrefix("eyJ")
        if !bearer { q.append(URLQueryItem(name: "api_key", value: key)) }
        c.queryItems = q
        guard let url = c.url else { return (nil, false) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        if bearer { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            if let code = (resp as? HTTPURLResponse)?.statusCode, code == 401 || code == 429 { return (nil, false) }
            guard let root = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let results = root["results"] as? [[String: Any]] else { return (nil, false) }
            if let path = results.compactMap({ $0["poster_path"] as? String }).first {
                return ("https://image.tmdb.org/t/p/w342" + path, true)
            }
            if p.year != nil {
                var p2 = p
                p2.year = nil
                return await tmdb(p2, series: series, key: key)
            }
            return (nil, true)
        } catch {
            return (nil, false)
        }
    }

    private func itunes(_ p: ParsedTitle, series: Bool) async -> (url: String?, cacheable: Bool) {
        // Gentle throttle: the public iTunes search API is rate limited.
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(1.2)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }

        guard var c = URLComponents(string: "https://itunes.apple.com/search") else { return (nil, false) }
        c.queryItems = [
            URLQueryItem(name: "term", value: p.title),
            URLQueryItem(name: "media", value: series ? "tvShow" : "movie"),
            URLQueryItem(name: "entity", value: series ? "tvSeason" : "movie"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = c.url else { return (nil, false) }
        do {
            let (d, resp) = try await URLSession.shared.data(from: url)
            if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 { return (nil, false) }
            guard let root = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let results = root["results"] as? [[String: Any]] else { return (nil, false) }
            let target = TitleCleaner.normalize(p.title)
            let pick = results.first(where: {
                let n = TitleCleaner.normalize(($0["trackName"] as? String) ?? ($0["collectionName"] as? String) ?? "")
                return !n.isEmpty && (n.contains(target) || target.contains(n))
            })
            guard let art = (pick?["artworkUrl100"] as? String) else { return (nil, true) }
            return (art.replacingOccurrences(of: "100x100bb", with: "400x600bb"), true)
        } catch {
            return (nil, false)
        }
    }
}

// MARK: - Views

struct ArtPlaceholder: View {
    let item: Item

    private var hue: Double {
        let h = item.name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Double(abs(h) % 360) / 360
    }

    private var label: String {
        if item.kind == .live {
            let words = item.name.split(separator: " ").prefix(2)
            return words.compactMap { $0.first }.map { String($0) }.joined().uppercased()
        }
        return TitleCleaner.parse(item.name).title
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.5),
                                    Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(label)
                .font(item.kind == .live ? .headline.weight(.heavy) : .caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(item.kind == .live ? 1 : 4)
                .padding(item.kind == .live ? 4 : 10)
        }
    }
}

struct ArtThumb: View {
    let item: Item
    var fit = false
    @State private var resolved: String?

    var body: some View {
        let urlString = item.logo ?? resolved
        Group {
            if let s = urlString, let u = makeURL(s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        ZStack {
                            Color(white: 0.1)
                            if fit {
                                img.resizable().scaledToFit().padding(6)
                            } else {
                                img.resizable().scaledToFill()
                            }
                        }
                    default:
                        ArtPlaceholder(item: item)
                    }
                }
            } else {
                ArtPlaceholder(item: item)
            }
        }
        .task(id: item.id) {
            if item.logo == nil { resolved = await ArtworkService.shared.artwork(for: item) }
        }
    }
}
