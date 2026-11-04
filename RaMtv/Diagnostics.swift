import SwiftUI

/// One measured playback start. Stored locally only; no URLs or hosts are kept.
struct PlaybackLogEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let engine: String      // "AVPlayer" or "VLC"
    let ms: Int             // time from creating the player to the first playing frame (or to the failure)
    let outcome: String     // "ok", "failed", "timeout"
    let detail: String      // e.g. resolution, empty when unknown
}

struct PlaybackSummary: Identifiable {
    var id: String { engine }
    let engine: String
    let starts: Int
    let failures: Int
    let medianMs: Int?
}

enum PlaybackLog {
    private static let key = "playlog.v1"
    private static let limit = 40

    static func load() -> [PlaybackLogEntry] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([PlaybackLogEntry].self, from: d) else { return [] }
        return list
    }

    static func record(engine: String, ms: Int, outcome: String, detail: String = "") {
        var list = load()
        list.append(PlaybackLogEntry(date: Date(), engine: engine, ms: max(0, ms), outcome: outcome, detail: detail))
        if list.count > limit { list.removeFirst(list.count - limit) }
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func summary(_ entries: [PlaybackLogEntry]) -> [PlaybackSummary] {
        let engines = Array(Set(entries.map(\.engine))).sorted()
        return engines.map { e in
            let mine = entries.filter { $0.engine == e }
            let ok = mine.filter { $0.outcome == "ok" }.map(\.ms)
            return PlaybackSummary(engine: e, starts: ok.count,
                                   failures: mine.count - ok.count, medianMs: median(ok))
        }
    }
}

struct DiagnosticsView: View {
    @State private var entries = PlaybackLog.load()

    var body: some View {
        List {
            Section(t("Startup time")) {
                if entries.isEmpty {
                    Text(t("No plays yet")).foregroundStyle(.secondary)
                }
                ForEach(PlaybackLog.summary(entries)) { s in
                    HStack {
                        Text(s.engine).font(.headline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(s.medianMs.map { "\($0) ms" } ?? "—").monospacedDigit()
                            Text("\(s.starts) ✓  \(s.failures) ✕")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !entries.isEmpty {
                Section(t("Recent plays")) {
                    ForEach(Array(entries.reversed().prefix(20))) { e in
                        HStack {
                            Text(e.engine)
                            if !e.detail.isEmpty { Text(e.detail).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text(e.outcome == "ok" ? "\(e.ms) ms" : e.outcome)
                                .monospacedDigit()
                                .foregroundStyle(e.outcome == "ok" ? Color.primary : Color.red)
                        }
                    }
                }
                Section {
                    Button(t("Clear"), role: .destructive) {
                        PlaybackLog.clear()
                        entries = []
                    }
                }
            }
        }
        .navigationTitle(t("Diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
