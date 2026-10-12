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
        var t = ArtworkLookup.channelName(raw).lowercased()
        t = t.replacingOccurrences(of: "^\\s*[\\[\\(|]*[a-z]{2,3}[\\]\\)|]*\\s*[|:\\-]\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\(.*?\\)|\\[.*?\\]", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\b(hd|fhd|uhd|sd|4k|8k|hevc|h265|h264|1080p|720p|hq|backup|raw|tv|channel)\\b", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "sports", with: "sport")
        t = t.replacingOccurrences(of: "\\b0+(\\d)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression)
        return t
    }
}

// MARK: - Display helpers

enum LiveName {
    static func prefixSplit(_ s: String) -> (prefix: String?, rest: String) {
        for sep in [":", "|"] {
            if let r = s.range(of: sep) {
                let p = String(s[..<r.lowerBound]).trimmed
                let rest = String(s[r.upperBound...]).trimmed
                if !p.isEmpty && !rest.isEmpty && p.count <= 24 { return (p, rest) }
            }
        }
        return (nil, s)
    }

    static func clean(_ s: String) -> String {
        var t = prefixSplit(s).rest
        t = t.replacingOccurrences(of: "\\b(4k|uhd|fhd|hd|sd|hevc|h265)\\b", with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
        return t.isEmpty ? s : t
    }
}

extension Item {
    var displayTitle: String {
        if kind == .live { return LiveName.clean(name) }
        let t = TitleCleaner.parse(name).title
        return t.isEmpty ? name : t
    }

    var year: String? { kind == .live ? nil : TitleCleaner.parse(name).year }

    var badges: [String] {
        let n = name.lowercased()
        func has(_ p: String) -> Bool { n.range(of: "\\b(\(p))\\b", options: .regularExpression) != nil }
        var out: [String] = []
        if has("4k|uhd") { out.append("4K") }
        else if has("fhd") { out.append("FHD") }
        else if has("hd") { out.append("HD") }
        if has("hevc|h265") { out.append("HEVC") }
        return out
    }
}

struct BadgeRow: View {
    let item: Item
    var body: some View {
        HStack(spacing: 6) {
            if let y = item.year { Text(y).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            ForEach(item.badges, id: \.self) { b in
                Text(b)
                    .font(.system(size: 10, weight: .heavy))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

// MARK: - Channel logo index (iptv-org public database)

@MainActor
final class LogoIndex {
    static let shared = LogoIndex()

    private var map: [String: String] = [:]
    private(set) var ready = false
    private var tried = false
    private var lastAttempt: Date?
    private var generation = 0
    private var loading: Task<Void, Never>?

    private var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("logo-index.json")
    }

    func logo(for name: String) async -> (url: String?, cacheable: Bool) {
        await ensureLoaded()
        guard ready else { return (nil, false) }
        let candidates = [TitleCleaner.normalize(name),
                          TitleCleaner.normalize(LiveName.prefixSplit(name).rest),
                          TitleCleaner.normalize(LiveName.clean(name))]
        for k in candidates where !k.isEmpty {
            if let u = map[k] { return (u, true) }
        }
        return (nil, true)
    }

    func reset() {
        generation += 1
        loading?.cancel()
        loading = nil
        lastAttempt = nil
        try? FileManager.default.removeItem(at: fileURL)
        map = [:]
        ready = false
        tried = false
    }

    private func ensureLoaded() async {
        if ready { return }
        if tried, let lastAttempt = lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        if let t = loading { await t.value; return }
        let t = Task { await self.load() }
        loading = t
        await t.value
        loading = nil
    }

    private func load() async {
        let generation = self.generation
        lastAttempt = Date()
        if let d = try? Data(contentsOf: fileURL),
           let m = try? JSONDecoder().decode([String: String].self, from: d), !m.isEmpty {
            map = m
            ready = true
            return
        }
        let built = await LogoIndex.build()
        guard !Task.isCancelled, generation == self.generation else { return }
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
        guard let (d, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    nonisolated private static func build() async -> [String: String] {
        async let channelsRequest = fetchJSON("https://iptv-org.github.io/api/channels.json")
        async let logosRequest = fetchJSON("https://iptv-org.github.io/api/logos.json")
        let (channels, logos) = await (channelsRequest, logosRequest)
        var best: [String: (String, Int)] = [:]
        for l in (logos as? [[String: Any]]) ?? [] {
            guard let id = l["channel"] as? String, let url = l["url"] as? String,
                  let imageURL = ArtworkLookup.validURL(url), imageURL.pathExtension.lowercased() != "svg" else { continue }
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
final class ArtworkService: ObservableObject {
    @Published private(set) var generation = 0
    static let shared = ArtworkService()

    private var cache: [String: String] = [:]
    private var inflight: [String: Task<String?, Never>] = [:]
    private var dirty = 0
    private var misses: [String: Date] = [:]
    private var nextSlot = Date.distantPast
    private var nextSeriesSlot = Date.distantPast

    private var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("artwork2.json")
    }

    private var tmdbKey: String {
        let user = (UserDefaults.standard.string(forKey: "tmdbKey") ?? "").trimmed
        return user.isEmpty ? builtInTMDBKey : user
    }

    init() {
        if let d = try? Data(contentsOf: fileURL),
           let m = try? JSONDecoder().decode([String: String].self, from: d) { cache = m.filter { ArtworkLookup.validURL($0.value) != nil } }
    }

    func clear() {
        generation += 1
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
        misses.removeAll()
        cache = [:]
        try? FileManager.default.removeItem(at: fileURL)
        LogoIndex.shared.reset()
    }

    private func key(for item: Item) -> String {
        if item.kind == .live { return "l|" + TitleCleaner.normalize(LiveName.clean(item.name)) }
        let p = TitleCleaner.parse(item.kind == .series ? ArtworkLookup.seriesTitle(item.name) : item.name)
        return "\(item.kind.rawValue)|\(p.title.lowercased())|\(p.year ?? "")"
    }

    func artwork(for item: Item, excluding failedURLs: Set<String> = []) async -> String? {
        let k = key(for: item)
        if let c = cache[k], !failedURLs.contains(c) { return c }
        cache[k] = nil
        if let miss = misses[k], Date().timeIntervalSince(miss) < 300 { return nil }
        if let t = inflight[k] { return await t.value }
        let generation = self.generation
        let task = Task { () -> String? in
            let r: (url: String?, cacheable: Bool)
            if item.kind == .live {
                r = await LogoIndex.shared.logo(for: item.name)
            } else {
                r = await self.poster(for: item)
            }
            guard !Task.isCancelled, self.generation == generation else { return nil }
            let url = ArtworkLookup.validURL(r.url)?.absoluteString
            if let url = url, !failedURLs.contains(url) {
                self.cache[k] = url
                self.misses[k] = nil
                self.dirty += 1
                if self.dirty >= 15 { self.dirty = 0; self.save() }
            } else if r.cacheable {
                self.misses[k] = Date()
            }
            self.inflight[k] = nil
            return url.flatMap { failedURLs.contains($0) ? nil : $0 }
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
        let p = TitleCleaner.parse(item.kind == .series ? ArtworkLookup.seriesTitle(item.name) : item.name)
        if p.title.isEmpty { return (nil, true) }
        let key = tmdbKey
        if !key.isEmpty {
            let result = await tmdb(p, series: item.kind == .series, key: key)
            if result.url != nil { return result }
        }
        if item.kind == .series {
            let result = await tvmaze(p)
            if result.url != nil { return result }
        }
        return await itunes(p, series: item.kind == .series)
    }

    private func tvmaze(_ title: ParsedTitle) async -> (url: String?, cacheable: Bool) {
        let slot = max(Date(), nextSeriesSlot)
        nextSeriesSlot = slot.addingTimeInterval(0.6)
        let delay = slot.timeIntervalSinceNow
        if delay > 0 {
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return (nil, false) }
        }
        guard !Task.isCancelled,
              var components = URLComponents(string: "https://api.tvmaze.com/singlesearch/shows") else { return (nil, false) }
        components.queryItems = [URLQueryItem(name: "q", value: title.title)]
        guard let url = components.url else { return (nil, false) }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let show = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = show["name"] as? String,
                  let images = show["image"] as? [String: Any] else { return (nil, false) }
            let target = TitleCleaner.normalize(title.title)
            let result = TitleCleaner.normalize(ArtworkLookup.seriesTitle(name))
            guard !target.isEmpty, result.contains(target) || target.contains(result) else { return (nil, true) }
            let image = (images["medium"] as? String) ?? (images["original"] as? String)
            return (ArtworkLookup.validURL(image)?.absoluteString, true)
        } catch {
            return (nil, false)
        }
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
                let name = ($0["trackName"] as? String) ?? ($0["collectionName"] as? String) ?? ""
                let n = TitleCleaner.normalize(series ? ArtworkLookup.seriesTitle(name) : name)
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
        return Double(UInt(bitPattern: h) % 360) / 360
    }

    private var label: String {
        if item.kind == .live {
            let words = item.displayTitle.split(separator: " ").prefix(2)
            return words.compactMap { $0.first }.map { String($0) }.joined().uppercased()
        }
        return item.displayTitle
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
    @ObservedObject private var artwork = ArtworkService.shared
    @State private var resolved: String?
    @State private var failedURLs = Set<String>()

    private var lookupID: String {
        "\(item.id)|\(item.logo ?? "")|\(artwork.generation)|\(failedURLs.sorted().joined(separator: "|"))"
    }

    private var imageURL: URL? {
        if let provider = ArtworkLookup.validURL(item.logo), !failedURLs.contains(provider.absoluteString) {
            return provider
        }
        if let fallback = ArtworkLookup.validURL(resolved), !failedURLs.contains(fallback.absoluteString) {
            return fallback
        }
        return nil
    }

    var body: some View {
        Group {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack {
                            Color(white: 0.1)
                            if fit { image.resizable().scaledToFit().padding(6) }
                            else { image.resizable().scaledToFill() }
                        }
                    case .failure:
                        ArtPlaceholder(item: item)
                            .onAppear { failedURLs.insert(url.absoluteString) }
                    default:
                        ArtPlaceholder(item: item)
                    }
                }
            } else {
                ArtPlaceholder(item: item)
            }
        }
        .task(id: lookupID) {
            if let provider = ArtworkLookup.validURL(item.logo), !failedURLs.contains(provider.absoluteString) { return }
            resolved = await artwork.artwork(for: item, excluding: failedURLs)
        }
        .onChange(of: item.id) { _ in resolved = nil; failedURLs.removeAll() }
        .onChange(of: artwork.generation) { _ in resolved = nil; failedURLs.removeAll() }
    }
}
