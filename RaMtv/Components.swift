import SwiftUI
import AVKit

struct Thumb: View {
    let url: String?
    var fit = false
    var icon = "play.tv"

    var body: some View {
        AsyncImage(url: url.flatMap { makeURL($0) }) { phase in
            switch phase {
            case .success(let img):
                if fit {
                    img.resizable().scaledToFit().padding(8)
                } else {
                    img.resizable().scaledToFill()
                }
            default:
                Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            }
        }
    }
}

struct PosterCard: View {
    @EnvironmentObject var store: AppStore
    let item: Item
    var width: CGFloat = 124

    private var height: CGFloat { item.kind == .live ? width * 0.62 : width * 1.5 }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumb(url: item.logo, fit: item.kind == .live, icon: item.kind == .live ? "tv" : "film")
                .frame(width: width, height: height)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(item.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }

    var body: some View {
        if item.seriesId != nil {
            NavigationLink(value: item) { content }.buttonStyle(.plain)
        } else {
            Button { store.play(item) } label: { content }.buttonStyle(.plain)
        }
    }
}

struct ShelfView: View {
    let title: String
    let items: [Item]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.bold)).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { PosterCard(item: $0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct HeroView: View {
    @EnvironmentObject var store: AppStore
    let item: Item

    private var label: String {
        switch item.kind {
        case .live: return t("Live")
        case .movie: return t("Movies")
        case .series: return t("Series")
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color.ram.opacity(0.6), Color(white: 0.04)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            Color.clear
                .overlay { Thumb(url: item.logo, fit: item.kind == .live, icon: "play.tv.fill").opacity(0.95) }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Text(item.name).font(.largeTitle.weight(.heavy)).lineLimit(2)
                HStack(spacing: 12) {
                    Button { store.play(item) } label: {
                        Label(t("Play"), systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                    }
                    Button { store.toggleFavorite(item) } label: {
                        Image(systemName: store.isFavorite(item) ? "checkmark" : "plus")
                            .font(.headline)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(height: 480)
        .clipped()
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .background(LinearGradient(colors: [Color.ram, Color(red: 0.03, green: 0.1, blue: 0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text(t("Welcome to RaM tv")).font(.title.bold())
            Text(t("Add your own M3U playlist or server login to start watching. RaM tv is a player only and includes no channels or content."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { showAdd = true } label: {
                Text(t("Add Source")).font(.headline).frame(maxWidth: 260).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button(t("Try Demo")) { store.addDemo() }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 640)
        .sheet(isPresented: $showAdd) { AddSourceView() }
    }
}

final class PlayerModel: ObservableObject {
    let player: AVPlayer
    @Published var message = ""
    @Published var failed = false
    private var obs: NSKeyValueObservation?

    init(url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "RaMtv/1.0"]])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        message = "Loading..."
        obs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch it.status {
                case .readyToPlay:
                    self.message = ""
                    self.failed = false
                case .failed:
                    let ns = it.error as NSError?
                    var text = ns?.localizedDescription ?? "Playback failed"
                    if let ns = ns { text += "\n[\(ns.domain) \(ns.code)]" }
                    if let ev = it.errorLog()?.events.last {
                        text += "\nHTTP \(ev.errorStatusCode) \(ev.errorComment ?? "")"
                    }
                    text += "\n" + (url.pathExtension.isEmpty ? "(no ext)" : ".\(url.pathExtension)") + " @ " + (url.host ?? "")
                    self.message = text
                    self.failed = true
                default: break
                }
            }
        }
        player.play()
    }

    deinit { player.pause() }
}

struct PlayerScreen: View {
    let req: PlayRequest
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlayerModel

    init(req: PlayRequest) {
        self.req = req
        _model = StateObject(wrappedValue: PlayerModel(url: req.url))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            AVPlayerView(player: model.player).ignoresSafeArea()
            if !model.message.isEmpty {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        if !model.failed { ProgressView() }
                        Text(model.message)
                            .font(.footnote)
                            .foregroundStyle(model.failed ? Color.red : Color.white)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                }
                .frame(maxWidth: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

struct AVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Text(item.name).font(.largeTitle.weight(.heavy)).lineLimit(2)
                HStack(spacing: 12) {
                    Button { store.play(item) } label: {
                        Label(t("Play"), systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                    }
                    Button { store.toggleFavorite(item) } label: {
                        Image(systemName: store.isFavorite(item) ? "checkmark" : "plus")
                            .font(.headline)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(height: 480)
        .clipped()
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .background(LinearGradient(colors: [Color.ram, Color(red: 0.03, green: 0.1, blue: 0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text(t("Welcome to RaM tv")).font(.title.bold())
            Text(t("Add your own M3U playlist or server login to start watching. RaM tv is a player only and includes no channels or content."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { showAdd = true } label: {
                Text(t("Add Source")).font(.headline).frame(maxWidth: 260).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button(t("Try Demo")) { store.addDemo() }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 640)
        .sheet(isPresented: $showAdd) { AddSourceView() }
    }
}

struct PlayerScreen: View {
    let req: PlayRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            AVPlayerView(url: req.url, title: req.title).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

struct AVPlayerView: UIViewControllerRepresentable {
    let url: URL
    let title: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "RaMtv/1.0"]])
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.allowsExternalPlayback = true
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: ()) {
        vc.player?.pause()
    }
}
