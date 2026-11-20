import Foundation

// MARK: - Now / next programme guide (Xtream short EPG)

struct EpgEntry: Equatable {
    let title: String
    let start: Date
    let end: Date

    func progress(at now: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }
}

enum EpgParser {
    /// Parses `get_short_epg`. Titles are usually base64; start/stop come as unix timestamps.
    static func parseShortEPG(_ json: Any) -> [EpgEntry] {
        guard let root = json as? [String: Any],
              let list = root["epg_listings"] as? [[String: Any]] else { return [] }
        var out: [EpgEntry] = []
        for e in list {
            guard let start = timestamp(e["start_timestamp"]),
                  let end = timestamp(e["stop_timestamp"] ?? e["end_timestamp"]),
                  end > start else { continue }
            let title = decodeTitle(e["title"])
            if title.isEmpty { continue }
            out.append(EpgEntry(title: title, start: start, end: end))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// The programme on air at `now` and the one after it.
    static func nowNext(_ entries: [EpgEntry], at now: Date = Date()) -> (now: EpgEntry?, next: EpgEntry?) {
        let upcoming = entries.filter { $0.end > now }
        guard let first = upcoming.first else { return (nil, nil) }
        if first.start <= now { return (first, upcoming.dropFirst().first) }
        return (nil, first)
    }

    static func decodeTitle(_ v: Any?) -> String {
        guard let raw = (v as? String)?.trimmed, !raw.isEmpty else { return "" }
        if let d = Data(base64Encoded: raw), let s = String(data: d, encoding: .utf8), !s.trimmed.isEmpty {
            return s.trimmed
        }
        return raw
    }

    private static func timestamp(_ v: Any?) -> Date? {
        let seconds: Double?
        if let s = v as? String { seconds = Double(s) }
        else if let n = v as? NSNumber { seconds = n.doubleValue }
        else { seconds = nil }
        guard let t = seconds, t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}

extension XtreamClient {
    /// Live items from Xtream carry their stream id in the item id ("<tag>-live-<id>").
    static func streamId(of item: Item) -> String? {
        guard item.kind == .live, let r = item.id.range(of: "-live-") else { return nil }
        let id = String(item.id[r.upperBound...])
        return id.isEmpty ? nil : id
    }

    func shortEPG(streamId: String) async throws -> [EpgEntry] {
        EpgParser.parseShortEPG(try await call("get_short_epg", ["stream_id": streamId, "limit": "4"]))
    }
}

/// Keeps guide data for ten minutes so scrolling the channel list does not refetch it.
@MainActor
final class EpgCache {
    static let shared = EpgCache()
    private var cache: [String: (at: Date, list: [EpgEntry])] = [:]
    private var inFlight: [String: Task<[EpgEntry], Never>] = [:]

    func entries(for item: Item, source: Source?) async -> [EpgEntry] {
        guard let source = source, source.type == .xtream,
              let sid = XtreamClient.streamId(of: item) else { return [] }
        if let c = cache[item.id], Date().timeIntervalSince(c.at) < 600 { return c.list }
        if let t = inFlight[item.id] { return await t.value }
        let client = XtreamClient(source: source)
        let task = Task<[EpgEntry], Never> { (try? await client.shortEPG(streamId: sid)) ?? [] }
        inFlight[item.id] = task
        let list = await task.value
        inFlight[item.id] = nil
        cache[item.id] = (Date(), list)
        return list
    }
}
