import Foundation
import Security
import SwiftUI

extension Color {
    static let ram = Color(red: 0, green: 0.341, blue: 1)
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

func makeURL(_ s: String) -> URL? {
    if let u = URL(string: s) { return u }
    if let e = s.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#%:/?&=@+"))) {
        return URL(string: e)
    }
    return nil
}

enum Kind: String, Codable { case live, movie, series }
enum SourceType: String, Codable { case m3u, xtream, demo }

struct Source: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: SourceType
    var url: String
    var username: String = ""
    var password: String { Keychain.read(id.uuidString) ?? "" }
}

struct Item: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var logo: String?
    var group: String
    var url: String?
    var kind: Kind
    var seriesId: String?
    var sourceId: UUID
}

struct Episode: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let season: Int
    let number: Int
}

struct PlayRequest: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

// MARK: - Keychain (with UserDefaults fallback for sideloaded builds)

enum Keychain {
    private static let service = "com.ramzi.ramtv"

    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func save(_ value: String, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        var q = base(key)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess {
            UserDefaults.standard.set(value, forKey: "pw.\(key)")
        }
    }

    static func read(_ key: String) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let d = out as? Data, let s = String(data: d, encoding: .utf8) {
            return s
        }
        return UserDefaults.standard.string(forKey: "pw.\(key)")
    }

    static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "pw.\(key)")
    }
}

// MARK: - M3U

enum M3UParser {
    static func parse(_ text: String, sourceId: UUID) -> [Item] {
        var items: [Item] = []
        var pendingName: String?
        var pendingLogo: String?
        var pendingGroup = "Other"

        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                if let idx = line.lastIndex(of: ",") {
                    pendingName = String(line[line.index(after: idx)...]).trimmed
                } else {
                    pendingName = "Channel"
                }
                pendingLogo = attr("tvg-logo", in: line)
                pendingGroup = attr("group-title", in: line) ?? "Other"
            } else if !line.isEmpty, !line.hasPrefix("#"), let name = pendingName {
                let lower = line.lowercased()
                let kind: Kind
                if lower.contains("/series/") { kind = .series }
                else if lower.contains("/movie/") || lower.hasSuffix(".mp4") || lower.hasSuffix(".mkv") || lower.hasSuffix(".avi") { kind = .movie }
                else { kind = .live }
                items.append(Item(id: "\(kind.rawValue)|\(line)",
                                  name: name.isEmpty ? "Channel" : name,
                                  logo: pendingLogo,
                                  group: pendingGroup,
                                  url: line,
                                  kind: kind,
                                  seriesId: nil,
                                  sourceId: sourceId))
                pendingName = nil
                pendingLogo = nil
                pendingGroup = "Other"
            }
        }
        return items
    }

    private static func attr(_ key: String, in line: String) -> String? {
        guard let r = line.range(of: key + "=\"") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let v = String(rest[..<end]).trimmed
        return v.isEmpty ? nil : v
    }
}

// MARK: - Xtream Codes

struct XtreamClient {
    let base: String
    let user: String
    let pass: String

    init(source: Source) {
        var b = source.url.trimmed
        if !b.lowercased().hasPrefix("http") { b = "http://" + b }
        for suffix in ["/player_api.php", "/get.php"] {
            if let r = b.range(of: suffix) { b = String(b[..<r.lowerBound]) }
        }
        while b.hasSuffix("/") { b.removeLast() }
        base = b
        user = source.username
        pass = source.password
    }

    private func s(_ v: Any?) -> String {
        if let x = v as? String { return x }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    func call(_ action: String? = nil, _ extra: [String: String] = [:]) async throws -> Any {
        guard var c = URLComponents(string: base + "/player_api.php") else { throw URLError(.badURL) }
        var q = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: pass)]
        if let a = action { q.append(URLQueryItem(name: "action", value: a)) }
        for (k, v) in extra { q.append(URLQueryItem(name: k, value: v)) }
        c.queryItems = q
        guard let url = c.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.setValue("RaMtv/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func categories(_ any: Any?) -> [String: String] {
        var m: [String: String] = [:]
        for d in (any as? [[String: Any]]) ?? [] {
            m[s(d["category_id"])] = s(d["category_name"])
        }
        return m
    }

    func fetchAll(sourceId: UUID) async throws -> [Item] {
        if let root = try await call() as? [String: Any],
           let info = root["user_info"] as? [String: Any],
           s(info["auth"]) == "0" {
            throw NSError(domain: "RaMtv", code: 401, userInfo: [NSLocalizedDescriptionKey: "Login failed. Check username and password."])
        }

        async let lc = try? call("get_live_categories")
        async let ls = try? call("get_live_streams")
        async let vc = try? call("get_vod_categories")
        async let vs = try? call("get_vod_streams")
        async let sc = try? call("get_series_categories")
        async let ss = try? call("get_series")
        let (liveCats, liveStreams, vodCats, vodStreams, serCats, serList) = await (lc, ls, vc, vs, sc, ss)

        let tag = String(sourceId.uuidString.prefix(8))
        var out: [Item] = []

        let lcm = categories(liveCats)
        for d in (liveStreams as? [[String: Any]]) ?? [] {
            let id = s(d["stream_id"])
            if id.isEmpty { continue }
            out.append(Item(id: "\(tag)-live-\(id)", name: s(d["name"]),
                            logo: s(d["stream_icon"]).isEmpty ? nil : s(d["stream_icon"]),
                            group: lcm[s(d["category_id"])] ?? "Live",
                            url: "\(base)/live/\(user)/\(pass)/\(id).m3u8",
                            kind: .live, seriesId: nil, sourceId: sourceId))
        }

        let vcm = categories(vodCats)
        for d in (vodStreams as? [[String: Any]]) ?? [] {
            let id = s(d["stream_id"])
            if id.isEmpty { continue }
            let ext = s(d["container_extension"]).isEmpty ? "mp4" : s(d["container_extension"])
            out.append(Item(id: "\(tag)-vod-\(id)", name: s(d["name"]),
                            logo: s(d["stream_icon"]).isEmpty ? nil : s(d["stream_icon"]),
                            group: vcm[s(d["category_id"])] ?? "Movies",
                            url: "\(base)/movie/\(user)/\(pass)/\(id).\(ext)",
                            kind: .movie, seriesId: nil, sourceId: sourceId))
        }

        let scm = categories(serCats)
        for d in (serList as? [[String: Any]]) ?? [] {
            let id = s(d["series_id"])
            if id.isEmpty { continue }
            out.append(Item(id: "\(tag)-series-\(id)", name: s(d["name"]),
                            logo: s(d["cover"]).isEmpty ? nil : s(d["cover"]),
                            group: scm[s(d["category_id"])] ?? "Series",
                            url: nil, kind: .series, seriesId: id, sourceId: sourceId))
        }
        return out
    }

    func episodes(seriesId: String) async throws -> [Episode] {
        guard let root = try await call("get_series_info", ["series_id": seriesId]) as? [String: Any] else { return [] }
        var seasons: [(Int, [[String: Any]])] = []
        if let d = root["episodes"] as? [String: Any] {
            for (k, v) in d { seasons.append((Int(k) ?? 0, (v as? [[String: Any]]) ?? [])) }
        } else if let a = root["episodes"] as? [Any] {
            for (i, v) in a.enumerated() { seasons.append((i + 1, (v as? [[String: Any]]) ?? [])) }
        }
        var out: [Episode] = []
        for (season, list) in seasons {
            for e in list {
                let id = s(e["id"])
                if id.isEmpty { continue }
                let ext = s(e["container_extension"]).isEmpty ? "mp4" : s(e["container_extension"])
                let title = s(e["title"]).isEmpty ? "Episode" : s(e["title"])
                out.append(Episode(id: id, title: title,
                                   url: "\(base)/series/\(user)/\(pass)/\(id).\(ext)",
                                   season: season, number: Int(s(e["episode_num"])) ?? 0))
            }
        }
        return out.sorted { ($0.season, $0.number) < ($1.season, $1.number) }
    }
}

// MARK: - Demo (public test streams only)

enum Demo {
    static func items(sourceId: UUID) -> [Item] {
        func mk(_ name: String, _ url: String, _ kind: Kind, _ group: String) -> Item {
            Item(id: "demo|\(url)", name: name, logo: nil, group: group, url: url, kind: kind, seriesId: nil, sourceId: sourceId)
        }
        return [
            mk("Apple Test Stream", "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8", .live, "Demo"),
            mk("Mux Test Stream", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", .live, "Demo"),
            mk("Sintel", "https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8", .movie, "Demo"),
            mk("Apple BipBop 16:9", "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8", .movie, "Demo")
        ]
    }
}
