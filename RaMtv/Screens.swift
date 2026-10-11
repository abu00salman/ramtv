import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            HomeView().tabItem { Label(t("Home"), systemImage: "house.fill") }
            LiveView().tabItem { Label(t("Live"), systemImage: "antenna.radiowaves.left.and.right") }
            LibraryView().tabItem { Label(t("Library"), systemImage: "film.stack") }
            SearchView().tabItem { Label(t("Search"), systemImage: "magnifyingglass") }
            SettingsView().tabItem { Label(t("Settings"), systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .top) {
            if store.loading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(t("Loading")).font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
            }
        }
        .fullScreenCover(item: $store.nowPlaying) { PlayerScreen(req: $0) }
        .task { await store.bootstrap() }
        .onAppear {
            let s = store
            PlayerHub.shared.onRestore = { [weak s] in
                Task { @MainActor in s?.nowPlaying = s?.lastRequest }
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.sources.isEmpty {
                    EmptyStateView()
                } else {
                    VStack(alignment: .leading, spacing: 26) {
                        if let hero = store.heroItem { HeroView(item: hero) }
                        ShelfView(title: t("Continue Watching"), items: store.recents.filter { $0.kind != .live })
                        ShelfView(title: t("Recent Channels"), items: store.recents.filter { $0.kind == .live })
                        ShelfView(title: t("Favorites"), items: store.favorites.isEmpty ? [] : store.favoriteItems)
                        ShelfView(title: t("Movies"), items: Array(store.movies.prefix(24)))
                        ShelfView(title: t("Series"), items: Array(store.series.prefix(24)))
                        ForEach(Array(store.liveGroups.prefix(5)), id: \.self) { g in
                            ShelfView(title: g, items: Array(store.live.filter { $0.group == g }.prefix(20)))
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Item.self) { SeriesDetailView(item: $0) }
        }
    }
}

struct ChannelRow: View {
    @EnvironmentObject var store: AppStore
    let item: Item
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtThumb(item: item, fit: true)
                .frame(width: 64, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayTitle).font(.body.weight(.semibold)).lineLimit(1)
                    ForEach(item.badges, id: \.self) { b in
                        Text(b)
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { store.toggleFavorite(item) } label: {
                Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart")
                    .foregroundStyle(store.isFavorite(item) ? Color.ram : Color.secondary)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

struct LiveView: View {
    @EnvironmentObject var store: AppStore
    @State private var group: String? = nil
    @State private var favOnly = false

    private var filtered: [Item] {
        if favOnly { return store.live.filter { store.favorites.contains($0.id) } }
        if let g = group { return store.live.filter { $0.group == g } }
        return store.live
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? Color.ram : Color.white.opacity(0.1), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        chip(t("All"), selected: group == nil && !favOnly) { group = nil; favOnly = false }
                        chip("♥ " + t("Favorites"), selected: favOnly) { favOnly = true; group = nil }
                        ForEach(store.liveGroups, id: \.self) { g in
                            chip(g, selected: group == g && !favOnly) { group = g; favOnly = false }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 52)
                List(filtered) { item in
                    ChannelRow(item: item) { store.play(item, in: filtered) }
                        .listRowBackground(Color.clear)
                }
                    .listStyle(.plain)
                    .overlay { if store.live.isEmpty { Text(t("No channels")).foregroundStyle(.secondary) } }
            }
            .background(Color.black)
            .navigationTitle(t("Live"))
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var group: String? = nil

    private var source: [Item] { tab == 0 ? store.movies : store.series }
    private var groups: [String] {
        var seen = Set<String>()
        return source.map(\.group).filter { seen.insert($0).inserted }
    }
    private var shown: [Item] {
        guard let g = group else { return source }
        return source.filter { $0.group == g }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let w = (geo.size.width - 32 - 24) / 3
                ScrollView {
                    Picker("", selection: $tab) {
                        Text(t("Movies")).tag(0)
                        Text(t("Series")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.top, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                        ForEach(shown) { PosterCard(item: $0, width: w) }
                    }
                    .padding(16)
                }
            }
            .background(Color.black)
            .navigationTitle(t("Library"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(t("All")) { group = nil }
                        ForEach(groups, id: \.self) { g in Button(g) { group = g } }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .onChange(of: tab) { _ in group = nil }
            .navigationDestination(for: Item.self) { SeriesDetailView(item: $0) }
        }
    }
}

struct SeriesDetailView: View {
    @EnvironmentObject var store: AppStore
    let item: Item
    @State private var episodes: [Episode] = []
    @State private var loading = true

    private var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ArtThumb(item: item)
                        .frame(width: 90, height: 135)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle).font(.title2.bold())
                        BadgeRow(item: item)
                    }
                }
                .listRowBackground(Color.clear)
            }
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
            } else if episodes.isEmpty {
                Text(t("No episodes")).foregroundStyle(.secondary)
            }
            ForEach(seasons, id: \.self) { s in
                Section("\(t("Season")) \(s)") {
                    ForEach(episodes.filter { $0.season == s }) { e in
                        Button { store.play(episode: e, in: episodes, series: item.displayTitle) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.circle.fill").foregroundStyle(Color.ram)
                                Text("\(e.number). \(e.title)").lineLimit(2)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            episodes = await store.episodes(for: item)
            loading = false
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""

    private var results: [Item] {
        let q = query.trimmed
        guard q.count >= 2 else { return [] }
        return Array(store.items.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(150))
    }

    var body: some View {
        NavigationStack {
            List(results) { item in
                if item.seriesId != nil {
                    NavigationLink(value: item) { row(item) }
                } else {
                    row(item).contentShape(Rectangle()).onTapGesture { store.play(item) }
                }
            }
            .listStyle(.plain)
            .background(Color.black)
            .navigationTitle(t("Search"))
            .searchable(text: $query, prompt: t("Search channels, movies, series"))
            .navigationDestination(for: Item.self) { SeriesDetailView(item: $0) }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            ArtThumb(item: item, fit: item.kind == .live)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).lineLimit(1)
                Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false
    @AppStorage("tmdbKey") private var tmdbKey = ""

    var body: some View {
        NavigationStack {
            List {
                Section(t("Sources")) {
                    ForEach(store.sources) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).font(.headline)
                            Text(s.type == .demo ? t("Demo") : s.url.replacingOccurrences(of: "(?i)(password|pass|pwd)=[^&]+", with: "$1=••••", options: .regularExpression))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .onDelete { store.remove(at: $0) }
                    Button { showAdd = true } label: { Label(t("Add Source"), systemImage: "plus.circle.fill") }
                    Button { Task { await store.refresh() } } label: {
                        HStack {
                            Label(t("Refresh"), systemImage: "arrow.clockwise")
                            if store.loading { Spacer(); ProgressView() }
                        }
                    }
                }
                if let e = store.error {
                    Section { Text(e).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    TextField("TMDB API key (optional)", text: $tmdbKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Clear artwork cache") { ArtworkService.shared.clear() }
                } header: {
                    Text("Artwork")
                } footer: {
                    Text("Posters and channel logos are fetched automatically. For best movie and series posters, add a free API key from themoviedb.org (Settings > API), then restart the app.")
                }
                Section(t("About")) {
                    Text(t("RaM tv is a player only. It does not provide or include any channels, playlists or content. Use only sources you are authorized to access."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack { Text("RaM tv"); Spacer(); Text("1.0").foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(t("Settings"))
            .sheet(isPresented: $showAdd) { AddSourceView() }
        }
    }
}

struct AddSourceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: SourceType = .m3u
    @State private var url = ""
    @State private var user = ""
    @State private var pass = ""

    private var valid: Bool {
        !url.trimmed.isEmpty && (type == .m3u || (!user.trimmed.isEmpty && !pass.isEmpty))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(t("Source Type"), selection: $type) {
                    Text("M3U").tag(SourceType.m3u)
                    Text("Xtream").tag(SourceType.xtream)
                }
                .pickerStyle(.segmented)
                TextField(t("Name"), text: $name)
                TextField(type == .m3u ? t("Playlist URL") : t("Server URL"), text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if type == .xtream {
                    TextField(t("Username"), text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(t("Password"), text: $pass)
                }
            }
            .navigationTitle(t("Add Source"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Save")) {
                        let fallback = type == .m3u ? "Playlist" : "Server"
                        let s = Source(name: name.trimmed.isEmpty ? fallback : name.trimmed,
                                       type: type, url: url.trimmed, username: user.trimmed)
                        store.add(s, password: pass)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        }
    }
}
