import SwiftUI
import AVKit

// MARK: - Multi-view: up to four live channels at once (Apple player only)

/// One window: its own AVPlayer, muted unless it holds the sound.
final class MultiTile: ObservableObject, Identifiable {
    enum Phase { case loading, playing, failed }

    let id = UUID()
    let item: Item
    let player: AVPlayer
    @Published var phase: Phase = .loading
    private var obs: NSKeyValueObservation?

    init(item: Item, url: URL) {
        self.item = item
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "RaMtv/1.0"]])
        let playerItem = AVPlayerItem(asset: asset)
        // Several streams share the connection; keep each buffer short.
        playerItem.preferredForwardBufferDuration = 4
        player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.allowsExternalPlayback = false
        obs = playerItem.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch it.status {
                case .readyToPlay: self.phase = .playing
                case .failed: self.phase = .failed
                default: break
                }
            }
        }
        player.play()
    }

    func stop() {
        obs = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    deinit { stop() }
}

final class MultiViewSession: ObservableObject {
    static let maxWindows = 4

    @Published private(set) var tiles: [MultiTile?] = [nil, nil]
    @Published private(set) var audioIndex = 0
    @Published var expanded: Int?

    var canAddWindow: Bool { tiles.count < MultiViewSession.maxWindows }

    func set(_ item: Item, url: URL, at index: Int) {
        guard tiles.indices.contains(index) else { return }
        tiles[index]?.stop()
        tiles[index] = MultiTile(item: item, url: url)
        if tiles[audioIndex] == nil { audioIndex = index }
        applyAudio()
    }

    func addWindow() {
        guard canAddWindow else { return }
        tiles.append(nil)
    }

    func remove(at index: Int) {
        guard tiles.indices.contains(index) else { return }
        tiles[index]?.stop()
        if tiles.count > 2 {
            tiles.remove(at: index)
        } else {
            tiles[index] = nil
        }
        if expanded == index { expanded = nil }
        if !tiles.indices.contains(audioIndex) || tiles[audioIndex] == nil {
            audioIndex = tiles.firstIndex(where: { $0 != nil }) ?? 0
        }
        applyAudio()
    }

    func selectAudio(_ index: Int) {
        guard tiles.indices.contains(index), tiles[index] != nil else { return }
        audioIndex = index
        applyAudio()
    }

    func toggleExpanded(_ index: Int) {
        expanded = expanded == index ? nil : index
    }

    func stopAll() {
        for t in tiles { t?.stop() }
    }

    private func applyAudio() {
        for (i, t) in tiles.enumerated() { t?.player.isMuted = i != audioIndex }
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

struct MultiViewScreen: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = MultiViewSession()
    @State private var pickingSlot: Int?
    @State private var showHint = true

    private func columns(for count: Int, landscape: Bool) -> Int {
        if count <= 1 { return 1 }
        if landscape { return 2 }
        return count <= 2 ? 1 : 2
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let indices: [Int] = session.expanded.map { [$0] } ?? Array(session.tiles.indices)
            let cols = columns(for: indices.count, landscape: landscape)
            let rows = Int(ceil(Double(indices.count) / Double(cols)))
            let w = geo.size.width / CGFloat(cols)
            let h = geo.size.height / CGFloat(max(rows, 1))
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                VStack(spacing: 2) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 2) {
                            ForEach(0..<cols, id: \.self) { c in
                                let n = r * cols + c
                                if n < indices.count {
                                    window(indices[n]).frame(width: w - 2, height: h - 2)
                                }
                            }
                        }
                    }
                }
                topBar
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            if session.tiles.allSatisfy({ $0 == nil }),
               let last = store.recents.first(where: { $0.kind == .live }),
               let url = store.streamURL(for: last) {
                session.set(last, url: url, at: 0)
            }
        }
        .onDisappear { session.stopAll() }
        .sheet(isPresented: Binding(get: { pickingSlot != nil }, set: { if !$0 { pickingSlot = nil } })) {
            MultiChannelPicker { item in
                if let slot = pickingSlot, let url = store.streamURL(for: item) {
                    session.set(item, url: url, at: slot)
                }
                pickingSlot = nil
            }
            .environmentObject(store)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(t("Close"))
            if showHint {
                Text(t("Tap a window to hear it. Double-tap to enlarge."))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .onTapGesture { showHint = false }
            }
            Spacer()
            if session.canAddWindow && session.expanded == nil {
                Button { session.addWindow() } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(t("Add window"))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func window(_ index: Int) -> some View {
        if let tile = session.tiles[index] {
            MultiTileView(tile: tile, hasAudio: session.audioIndex == index)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { session.toggleExpanded(index) }
                .onTapGesture { session.selectAudio(index) }
                .contextMenu {
                    Button { pickingSlot = index } label: { Label(t("Change channel"), systemImage: "arrow.left.arrow.right") }
                    Button(role: .destructive) { session.remove(at: index) } label: { Label(t("Remove"), systemImage: "xmark.circle") }
                }
        } else {
            Button { pickingSlot = index } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.largeTitle)
                    Text(t("Add channel")).font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.1))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}

struct MultiTileView: View {
    @ObservedObject var tile: MultiTile
    let hasAudio: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PlayerLayerRepresentable(player: tile.player)
            switch tile.phase {
            case .loading:
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                Text(t("Not playable in multi-view"))
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .playing:
                EmptyView()
            }
            HStack(spacing: 6) {
                Image(systemName: hasAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                Text(tile.item.displayTitle).lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(8)
        }
        .foregroundStyle(.white)
        .overlay {
            Rectangle().stroke(hasAudio ? Color.ram : .clear, lineWidth: 3)
        }
        .clipped()
    }
}

struct MultiChannelPicker: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (Item) -> Void

    private var channels: [Item] {
        let q = query.trimmed
        if q.count >= 2 {
            return Array(store.live.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(300))
        }
        let favs = store.favorites
        let first = store.live.filter { favs.contains($0.id) }
        let rest = store.live.filter { !favs.contains($0.id) }
        return Array((first + rest).prefix(300))
    }

    var body: some View {
        NavigationStack {
            List(channels) { item in
                Button { onPick(item) } label: {
                    HStack(spacing: 12) {
                        ArtThumb(item: item, fit: true)
                            .frame(width: 56, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle).lineLimit(1)
                            Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if store.isFavorite(item) { Image(systemName: "heart.fill").foregroundStyle(Color.ram) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: t("Search channels, movies, series"))
            .navigationTitle(t("Add channel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Cancel")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
