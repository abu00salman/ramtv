import SwiftUI
import AVKit
import MobileVLCKit

// MARK: - Entry: AVPlayer for HLS/MP4, VLC for everything else (and as fallback)

struct PlayerScreen: View {
    let req: PlayRequest
    @Environment(\.dismiss) private var dismiss
    @State private var useVLC: Bool

    init(req: PlayRequest) {
        self.req = req
        let ext = req.url.pathExtension.lowercased()
        _useVLC = State(initialValue: !["m3u8", "mp4", "m4v", "mov"].contains(ext))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if useVLC {
                VLCPlayerView(url: req.url)
            } else {
                AVPlayerScreen(url: req.url, onFail: { useVLC = true })
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

// MARK: - AVPlayer engine

final class AVModel: ObservableObject {
    let player: AVPlayer
    private var obs: NSKeyValueObservation?

    init(url: URL, onFail: @escaping () -> Void) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "RaMtv/1.0"]])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        obs = item.observe(\.status, options: [.new]) { it, _ in
            if it.status == .failed { DispatchQueue.main.async { onFail() } }
        }
        player.play()
    }

    deinit { player.pause() }
}

struct AVPlayerScreen: View {
    @StateObject private var model: AVModel

    init(url: URL, onFail: @escaping () -> Void) {
        _model = StateObject(wrappedValue: AVModel(url: url, onFail: onFail))
    }

    var body: some View {
        AVPlayerView(player: model.player).ignoresSafeArea()
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
}

// MARK: - VLC engine

final class VLCModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    @Published var message = "Loading..."
    @Published var failed = false
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var seekable = false
    @Published var timeText = ""

    init(url: URL) {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1500")
        player.media = media
        player.delegate = self
    }

    func attach(to view: UIView) {
        player.drawable = view
        player.play()
    }

    func toggle() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(to p: Double) { player.position = Float(p) }
    func skip(_ seconds: Int32) { seconds > 0 ? player.jumpForward(seconds) : player.jumpBackward(-seconds) }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async {
            switch self.player.state {
            case .error:
                self.failed = true
                self.message = "Playback failed (stream not reachable or not supported)"
            case .opening, .buffering:
                if !self.player.isPlaying { self.message = "Loading..." }
            case .playing:
                self.message = ""
                self.failed = false
            default: break
            }
            self.isPlaying = self.player.isPlaying
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async {
            self.seekable = self.player.isSeekable
            self.position = Double(self.player.position)
            self.timeText = self.player.time.stringValue ?? ""
            if !self.message.isEmpty && self.player.isPlaying { self.message = "" }
        }
    }

    deinit { player.stop() }
}

struct VLCSurface: UIViewRepresentable {
    let model: VLCModel

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        model.attach(to: v)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct VLCPlayerView: View {
    @StateObject private var model: VLCModel
    @State private var showControls = true

    init(url: URL) {
        _model = StateObject(wrappedValue: VLCModel(url: url))
    }

    var body: some View {
        ZStack {
            VLCSurface(model: model).ignoresSafeArea()
            Color.clear.contentShape(Rectangle())
                .onTapGesture { withAnimation { showControls.toggle() } }

            if !model.message.isEmpty {
                HStack(spacing: 10) {
                    if !model.failed { ProgressView() }
                    Text(model.message)
                        .font(.footnote)
                        .foregroundStyle(model.failed ? Color.red : Color.white)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
            }

            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        if model.seekable {
                            Slider(value: Binding(get: { model.position }, set: { model.seek(to: $0) }), in: 0...1)
                            HStack { Text(model.timeText).font(.caption).foregroundStyle(.secondary); Spacer() }
                        }
                        HStack(spacing: 36) {
                            if model.seekable {
                                Button { model.skip(-10) } label: { Image(systemName: "gobackward.10") }
                            }
                            Button { model.toggle() } label: {
                                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title)
                            }
                            if model.seekable {
                                Button { model.skip(10) } label: { Image(systemName: "goforward.10") }
                            }
                        }
                        .font(.title2)
                        .foregroundStyle(.white)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
