import SwiftUI
import AVKit
import MobileVLCKit

// MARK: - Engine preference memory (per server host)

enum EnginePrefs {
    static func get(_ host: String?) -> String? {
        UserDefaults.standard.string(forKey: "engine.\(host ?? "")")
    }
    static func set(_ value: String, host: String?) {
        UserDefaults.standard.set(value, forKey: "engine.\(host ?? "")")
    }
}


enum Engine: Equatable {
    case av(URL, fallback: URL)
    case vlc(URL)

    static func initial(for r: PlayRequest) -> Engine {
        let url = r.url
        let ext = url.pathExtension.lowercased()
        if ["m3u8", "mp4", "m4v", "mov"].contains(ext) { return .av(url, fallback: url) }
        if ext.isEmpty && r.isLive {
            if EnginePrefs.get(url.host) == "vlc" { return .vlc(url) }
            return .av(url.appendingPathExtension("m3u8"), fallback: url)
        }
        return .vlc(url)
    }
}

// MARK: - Keeps a Picture-in-Picture player alive after the player screen closes

final class PlayerHub {
    static let shared = PlayerHub()
    private(set) var heldVC: AVPlayerViewController?
    var onRestore: (() -> Void)?

    func hold(_ vc: AVPlayerViewController) { heldVC = vc }
    func release() {
        heldVC?.player?.pause()
        heldVC = nil
    }
    func isHolding(_ p: AVPlayer) -> Bool { heldVC?.player === p }
}

// MARK: - Player screen

struct PlayerScreen: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var req: PlayRequest
    @State private var engine: Engine
    @State private var showChrome = true
    @State private var showList = false

    init(req: PlayRequest) {
        _req = State(initialValue: req)
        _engine = State(initialValue: Engine.initial(for: req))
    }

    private var isAV: Bool {
        if case .av = engine { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            Group {
                switch engine {
                case .av(let url, let fb):
                    AVPlayerScreen(
                        url: url,
                        onReady: { if url != fb { EnginePrefs.set("av", host: fb.host) } },
                        onFail: {
                            if url != fb { EnginePrefs.set("vlc", host: fb.host) }
                            engine = .vlc(fb)
                        },
                        onPiPStart: { dismiss() })
                case .vlc(let url):
                    VLCPlayerView(url: url, isLive: req.isLive, showChrome: $showChrome)
                }
            }
            .id(req.id)
            topBar
        }
        .sheet(isPresented: $showList) {
            ChannelPickerSheet(currentId: req.item?.id) { item in
                if let r = store.jump(to: item) { switchTo(r) }
                showList = false
            }
            .environmentObject(store)
        }
    }

    private func switchTo(_ r: PlayRequest) {
        req = r
        engine = Engine.initial(for: r)
        showChrome = true
    }

    private func zap(_ d: Int) {
        if let r = store.zap(by: d) { switchTo(r) }
    }

    private func barButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            barButton("xmark") { dismiss() }
            if req.isLive && store.queue.count > 1 {
                barButton("backward.end.fill") { zap(-1) }
                barButton("forward.end.fill") { zap(1) }
                barButton("list.bullet") { showList = true }
            }
            Text(req.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .shadow(radius: 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, isAV ? 150 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(isAV || showChrome ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showChrome)
    }
}

struct ChannelPickerSheet: View {
    @EnvironmentObject var store: AppStore
    let currentId: String?
    let onPick: (Item) -> Void

    var body: some View {
        NavigationStack {
            List(store.queue) { item in
                Button { onPick(item) } label: {
                    HStack(spacing: 12) {
                        ArtThumb(item: item, fit: true)
                            .frame(width: 56, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(item.name).lineLimit(1)
                        Spacer()
                        if item.id == currentId {
                            Image(systemName: "play.fill").foregroundStyle(Color.ram)
                        }
                    }
                }
                .foregroundStyle(.white)
            }
            .listStyle(.plain)
            .navigationTitle(t("Live"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - AVPlayer engine (native controls: PiP, AirPlay, speed, subtitles)

final class AVModel: ObservableObject {
    let player: AVPlayer
    private var obs: NSKeyValueObservation?

    init(url: URL, onReady: @escaping () -> Void, onFail: @escaping () -> Void) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "RaMtv/1.0"]])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        obs = item.observe(\.status, options: [.new]) { it, _ in
            DispatchQueue.main.async {
                if it.status == .failed { onFail() }
                if it.status == .readyToPlay { onReady() }
            }
        }
        player.play()
    }

    deinit {
        if !PlayerHub.shared.isHolding(player) { player.pause() }
    }
}

struct AVPlayerScreen: View {
    @StateObject private var model: AVModel
    let onPiPStart: () -> Void

    init(url: URL, onReady: @escaping () -> Void, onFail: @escaping () -> Void, onPiPStart: @escaping () -> Void) {
        _model = StateObject(wrappedValue: AVModel(url: url, onReady: onReady, onFail: onFail))
        self.onPiPStart = onPiPStart
    }

    var body: some View {
        AVPlayerView(player: model.player, onPiPStart: onPiPStart).ignoresSafeArea()
    }
}

struct AVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onPiPStart: () -> Void

    func makeCoordinator() -> Coord { Coord() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.delegate = context.coordinator
        context.coordinator.onPiPStart = onPiPStart
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        context.coordinator.onPiPStart = onPiPStart
    }

    final class Coord: NSObject, AVPlayerViewControllerDelegate {
        var onPiPStart: () -> Void = {}

        func playerViewControllerWillStartPictureInPicture(_ vc: AVPlayerViewController) {
            PlayerHub.shared.hold(vc)
            DispatchQueue.main.async { self.onPiPStart() }
        }

        func playerViewControllerDidStopPictureInPicture(_ vc: AVPlayerViewController) {
            PlayerHub.shared.release()
        }

        func playerViewController(_ vc: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            PlayerHub.shared.onRestore?()
            completionHandler(true)
        }
    }
}

// MARK: - VLC engine (MKV, TS and everything AVPlayer cannot open)

final class VLCModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    weak var surface: UIView?

    @Published var message = "Loading..."
    @Published var failed = false
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var seekable = false
    @Published var timeText = "00:00"
    @Published var durationText = ""
    @Published var audioNames: [String] = []
    @Published var audioIndexes: [Int32] = []
    @Published var subNames: [String] = []
    @Published var subIndexes: [Int32] = []
    @Published var currentAudio: Int32 = -1
    @Published var currentSub: Int32 = -1
    @Published var aspect = 0
    @Published var rate: Float = 1.0

    let aspectNames = ["Fit", "Fill", "Stretch", "16:9", "4:3"]

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
        surface = view
        player.drawable = view
        player.play()
    }

    func toggle() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(to p: Double) { player.position = Float(p) }

    func skip(_ seconds: Int32) {
        if seconds > 0 { player.jumpForward(seconds) } else { player.jumpBackward(-seconds) }
    }

    func setRate(_ r: Float) {
        rate = r
        player.rate = r
    }

    private func setCString(_ s: String?, apply: (UnsafeMutablePointer<Int8>?) -> Void) {
        if let s = s {
            s.withCString { apply(UnsafeMutablePointer(mutating: $0)) }
        } else {
            apply(nil)
        }
    }

    func setAspect(_ index: Int) {
        aspect = index
        setCString(nil) { self.player.videoAspectRatio = $0 }
        setCString(nil) { self.player.videoCropGeometry = $0 }
        let b = surface?.bounds ?? .zero
        let screen = "\(Int(b.width)):\(Int(b.height))"
        switch index {
        case 1: setCString(screen) { self.player.videoCropGeometry = $0 }
        case 2: setCString(screen) { self.player.videoAspectRatio = $0 }
        case 3: setCString("16:9") { self.player.videoAspectRatio = $0 }
        case 4: setCString("4:3") { self.player.videoAspectRatio = $0 }
        default: break
        }
    }

    func selectAudio(_ i: Int32) {
        player.currentAudioTrackIndex = i
        currentAudio = i
    }

    func selectSub(_ i: Int32) {
        player.currentVideoSubTitleIndex = i
        currentSub = i
    }

    private func refreshTracks() {
        audioNames = (player.audioTrackNames as? [String]) ?? []
        audioIndexes = ((player.audioTrackIndexes as? [NSNumber]) ?? []).map { $0.int32Value }
        subNames = (player.videoSubTitlesNames as? [String]) ?? []
        subIndexes = ((player.videoSubTitlesIndexes as? [NSNumber]) ?? []).map { $0.int32Value }
        currentAudio = player.currentAudioTrackIndex
        currentSub = player.currentVideoSubTitleIndex
    }

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
                self.refreshTracks()
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
            self.durationText = self.player.media?.length.stringValue ?? ""
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
    @Binding var showChrome: Bool
    let isLive: Bool
    @State private var hideTask: Task<Void, Never>?

    init(url: URL, isLive: Bool, showChrome: Binding<Bool>) {
        _model = StateObject(wrappedValue: VLCModel(url: url))
        _showChrome = showChrome
        self.isLive = isLive
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && model.isPlaying {
                await MainActor.run { withAnimation { showChrome = false } }
            }
        }
    }

    private func toggleOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let landscape = scene.interfaceOrientation.isLandscape
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .portrait : .landscape)) { _ in }
    }

    private func iconButton(_ name: String, size: Font = .title3, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
            scheduleHide()
        } label: {
            Image(systemName: name).font(size).frame(width: 44, height: 44)
        }
        .foregroundStyle(.white)
    }

    var body: some View {
        ZStack {
            VLCSurface(model: model).ignoresSafeArea()
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { showChrome.toggle() }
                    if showChrome { scheduleHide() }
                }

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

            if showChrome {
                VStack {
                    Spacer()
                    controlPanel
                }
                .transition(.opacity)
            }
        }
        .onAppear { scheduleHide() }
        .onChange(of: model.isPlaying) { playing in
            if playing { scheduleHide() } else { hideTask?.cancel(); withAnimation { showChrome = true } }
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 8) {
            if model.seekable {
                Slider(value: Binding(get: { model.position }, set: { model.seek(to: $0) }), in: 0...1)
                HStack {
                    Text(model.timeText)
                    Spacer()
                    Text(model.durationText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if isLive {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("LIVE").font(.caption.weight(.bold))
                    Spacer()
                }
            }

            HStack(spacing: 0) {
                Menu {
                    if !model.audioNames.isEmpty {
                        Section("Audio") {
                            ForEach(Array(model.audioNames.enumerated()), id: \.offset) { i, name in
                                if i < model.audioIndexes.count {
                                    Button {
                                        model.selectAudio(model.audioIndexes[i])
                                    } label: {
                                        Label(name, systemImage: model.currentAudio == model.audioIndexes[i] ? "checkmark" : "")
                                    }
                                }
                            }
                        }
                    }
                    if !model.subNames.isEmpty {
                        Section("Subtitles") {
                            ForEach(Array(model.subNames.enumerated()), id: \.offset) { i, name in
                                if i < model.subIndexes.count {
                                    Button {
                                        model.selectSub(model.subIndexes[i])
                                    } label: {
                                        Label(name, systemImage: model.currentSub == model.subIndexes[i] ? "checkmark" : "")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "captions.bubble").font(.title3).frame(width: 44, height: 44)
                }
                .foregroundStyle(.white)

                Menu {
                    ForEach(Array(model.aspectNames.enumerated()), id: \.offset) { i, name in
                        Button {
                            model.setAspect(i)
                        } label: {
                            Label(name, systemImage: model.aspect == i ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "aspectratio").font(.title3).frame(width: 44, height: 44)
                }
                .foregroundStyle(.white)

                Spacer()
                if model.seekable { iconButton("gobackward.10", size: .title2) { model.skip(-10) } }
                iconButton(model.isPlaying ? "pause.fill" : "play.fill", size: .largeTitle) { model.toggle() }
                if model.seekable { iconButton("goforward.10", size: .title2) { model.skip(10) } }
                Spacer()

                if model.seekable {
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                            Button {
                                model.setRate(Float(r))
                            } label: {
                                Label("\(r, specifier: "%g")x", systemImage: model.rate == Float(r) ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "speedometer").font(.title3).frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.white)
                }

                iconButton("rotate.right") { toggleOrientation() }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}
