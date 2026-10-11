import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var sources: [Source] = []
    @Published private(set) var items: [Item] = []
    @Published private(set) var live: [Item] = []
    @Published private(set) var movies: [Item] = []
    @Published private(set) var series: [Item] = []
    @Published private(set) var liveGroups: [String] = []
    @Published var favorites: Set<String> = []
    @Published var recents: [Item] = []
    @Published var loading = false
    @Published var error: String?
    @Published var nowPlaying: PlayRequest?

    private let defaults = UserDefaults.standard

    init() {
        if let d = defaults.data(forKey: "sources"),
           let s = try? JSONDecoder().decode([Source].self, from: d) { sources = s }
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        if let d = defaults.data(forKey: "recents"),
           let r = try? JSONDecoder().decode([Item].self, from: d) { recents = r }
        if let cached = loadCache() { setItems(cached) }
    }

    func bootstrap() async {
        if items.isEmpty && !sources.isEmpty { await refresh() }
    }

    var heroItem: Item? {
        recents.first
            ?? movies.first(where: { $0.logo != nil && $0.url != nil })
            ?? live.first(where: { $0.logo != nil })
            ?? live.first
    }

    var favoriteItems: [Item] { items.filter { favorites.contains($0.id) } }

    // MARK: Sources

    func add(_ s: Source, password: String = "") {
        if !password.isEmpty { Keychain.save(password, for: s.id.uuidString) }
        sources.append(s)
        saveSources()
        Task { await refresh() }
    }

    func addDemo() { add(Source(name: "Demo", type: .demo, url: "")) }

    func remove(at offsets: IndexSet) {
        for i in offsets { Keychain.delete(sources[i].id.uuidString) }
        sources.remove(atOffsets: offsets)
        saveSources()
        Task { await refresh() }
    }

    func refresh() async {
        guard !sources.isEmpty else { setItems([]); saveCache(); return }
        loading = true
        error = nil
        var all: [Item] = []
        for src in sources {
            do {
                switch src.type {
                case .m3u: all += try await loadM3U(src)
                case .xtream: all += try await XtreamClient(source: src).fetchAll(sourceId: src.id)
                case .demo: all += Demo.items(sourceId: src.id)
                }
            } catch {
                self.error = "\(src.name): \(error.localizedDescription)"
            }
        }
        setItems(all)
        saveCache()
        loading = false
    }

    private func loadM3U(_ src: Source) async throws -> [Item] {
        guard let u = makeURL(src.url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: 90)
        req.setValue("RaMtv/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let id = src.id
        return await Task.detached(priority: .userInitiated) { M3UParser.parse(text, sourceId: id) }.value
    }

    func episodes(for item: Item) async -> [Episode] {
        guard let sid = item.seriesId,
              let src = sources.first(where: { $0.id == item.sourceId }) else { return [] }
        return (try? await XtreamClient(source: src).episodes(seriesId: sid)) ?? []
    }

    // MARK: Playback

    func play(_ item: Item) {
        guard var s = item.url else { return }
        if item.kind == .live, s.contains("/live/"), s.hasSuffix(".ts") {
            s = String(s.dropLast(3)) + ".m3u8"
        }
        guard let u = makeURL(s) else { return }
        nowPlaying = PlayRequest(title: item.name, url: u)
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        if recents.count > 20 { recents.removeLast(recents.count - 20) }
        if let d = try? JSONEncoder().encode(recents) { defaults.set(d, forKey: "recents") }
    }

    func play(episode: Episode) {
        guard let u = makeURL(episode.url) else { return }
        nowPlaying = PlayRequest(title: episode.title, url: u)
    }

    func isFavorite(_ item: Item) -> Bool { favorites.contains(item.id) }

    func toggleFavorite(_ item: Item) {
        if favorites.contains(item.id) { favorites.remove(item.id) } else { favorites.insert(item.id) }
        defaults.set(Array(favorites), forKey: "favorites")
    }

    // MARK: Persistence

    private func saveSources() {
        if let d = try? JSONEncoder().encode(sources) { defaults.set(d, forKey: "sources") }
    }

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("items.json")
    }

    private func saveCache() {
        let snapshot = items
        let url = cacheURL
        Task.detached {
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url) }
        }
    }

    private func loadCache() -> [Item]? {
        guard let d = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode([Item].self, from: d)
    }

    private func setItems(_ new: [Item]) {
        var seenIds = Set<String>()
        let unique = new.filter { seenIds.insert($0.id).inserted }
        items = unique
        live = unique.filter { $0.kind == .live }
        movies = unique.filter { $0.kind == .movie }
        series = unique.filter { $0.kind == .series }
        var seen = Set<String>()
        var groups: [String] = []
        for i in live {
            if seen.insert(i.group).inserted { groups.append(i.group) }
        }
        liveGroups = groups
    }
}
