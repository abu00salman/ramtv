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
        // Xtream commonly offers HLS beside its TS endpoint. Retain VLC fallback.
        if r.isLive && ext == "ts" && url.path.contains("/live/") {
            return .av(url.deletingPathExtension().appendingPathExtension("m3u8"), fallback: url)
        }
        if ext.isEmpty && r.isLive {
            if EnginePrefs.get(url.host) == "vlc" { return .vlc(url) }
            return .av(url.appendingPathExtension("m3u8"), fallback: url)
        }
        // Apple's player first (PiP, AirPlay, system controls); VLC only if it fails to open.
        return .av(url, fallback: url)
    }
}

// MARK: - Resume positions

enum ResumeStore {
    private static let key = "resume.v1"

    private static func load() -> [String: [Double]] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]]) ?? [:]
    }

    static func save(_ id: String, seconds: Double, duration: Double) {
        guard duration > 120, seconds.isFinite else { return }
        var m = load()
        if seconds / duration > 0.95 {
            m.removeValue(forKey: id)
        } else if seconds >= 20 {
            m[id] = [seconds, duration]
        }
        UserDefaults.standard.set(m, forKey: key)
    }

    static func get(_ id: String) -> (seconds: Double, duration: Double)? {
        guard let v = load()[id], v.count == 2 else { return nil }
        return (v[0], v[1])
    }

    static func fraction(_ id: String) -> Double? {
        guard let r = get(id), r.duration > 0 else { return nil }
        return min(1, max(0, r.seconds / r.duration))
    }

    static func clear(_ id: String) {
        var m = load()
        m.removeValue(forKey: id)
        UserDefaults.standard.set(m, forKey: key)
    }
}

// MARK: - Keeps a Picture-in-Picture player alive after the player screen closes

final class PlayerHub {
    static let shared = PlayerHub()
    private(set) var heldVC: AVPlayerViewController?
    var onRestore: (() -> Void)?
    private(set) var heldModel: AVModel?
    private var heldDelegate: AnyObject?
    var restoring = false
    var restoreCompletion: ((Bool) -> Void)?

    func finishRestore() {
        let completion = restoreCompletion
        restoreCompletion = nil
        completion?(true)
    }

    func hold(_ vc: AVPlayerViewController, model: AVModel?, delegate: AnyObject) {
        heldVC = vc
        heldModel = model
        heldDelegate = delegate
    }
    func reusableModel(for url: URL) -> AVModel? {
        heldModel?.url == url ? heldModel : nil
    }
    func release(pause: Bool = true) {
        if pause && !restoring { heldVC?.player?.pause() }
        heldVC = nil
        heldModel = nil
        heldDelegate = nil
        restoring = false
        if let completion = restoreCompletion {
            restoreCompletion = nil
            completion(false)
        }
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
                        resumeKey: req.resumeKey,
                        onReady: { if url != fb { EnginePrefs.set("av", host: fb.host) } },
                        onFail: {
                            if url != fb { EnginePrefs.set("vlc", host: fb.host) }
                            engine = .vlc(fb)
                        },
                        onEnded: { ended() },
                        onPiPStart: { dismiss() })
                case .vlc(let url):
                    VLCPlayerView(url: url, isLive: req.isLive, resumeKey: req.resumeKey,
                                  showChrome: $showChrome, onEnded: { ended() })
                }
            }
            .id(req.id)
            topBar
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .onAppear { PlayerHub.shared.finishRestore() }
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

    private func ended() {
        if req.isEpisode, let r = store.zap(by: 1) { switchTo(r) }
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
            barButton("xmark") { dismiss() }.accessibilityLabel(t("Close"))
            if store.canStep {
                barButton("backward.end.fill") { zap(-1) }.accessibilityLabel(t("Previous channel"))
                barButton("forward.end.fill") { zap(1) }.accessibilityLabel(t("Next channel"))
            }
            if req.isLive && store.queue.count > 1 {
                barButton("list.bullet") { showList = true }.accessibilityLabel(t("Channel list"))
            }
            if !isAV {
                Menu {
                    Button(t("Apple player")) {
                        let url = req.url
                        let candidate = req.isLive && url.pathExtension.lowercased() == "ts" && url.path.contains("/live/")
                            ? url.deletingPathExtension().appendingPathExtension("m3u8") : url
                        engine = .av(candidate, fallback: url)
                    }
                    Text(t("Apple player offers Picture in Picture for compatible streams."))
                } label: {
                    Image(systemName: "pip.enter")
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(t("Apple player"))
            }
            Text(req.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .shadow(radius: 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, isAV ? 120 : 0)
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
                        Text(item.displayTitle).lineLimit(1)
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
    let url: URL
    private var obs: NSKeyValueObservation?
    private var timeObs: Any?
    private var endObs: NSObjectProtocol?
    private var didResume = false
    private var onReadyHandler: () -> Void
    private var onFailHandler: () -> Void
    private var onEndedHandler: () -> Void

    func updateHandlers(onReady: @escaping () -> Void, onFail: @escaping () -> Void, onEnded: @escaping () -> Void) {
        onReadyHandler = onReady
        onFailHandler = onFail
        onEndedHandler = onEnded
    }

    init(url: URL, resumeKey: String?,
         onReady: @escaping () -> Void, onFail: @escaping () -> Void, onEnded: @escaping () -> Void) {
        self.url = url
        self.onReadyHandler = onReady
        self.onFailHandler = onFail
        self.onEndedHandler = onEnded
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "RaMtv/1.0"]])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true

        obs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if it.status == .failed { self.onFailHandler() }
                if it.status == .readyToPlay {
                    if !self.didResume {
                        self.didResume = true
                        if let key = resumeKey, let r = ResumeStore.get(key), r.seconds > 20 {
                            self.player.seek(to: CMTime(seconds: max(0, r.seconds - 3), preferredTimescale: 600))
                        }
                    }
                    self.onReadyHandler()
                }
            }
        }

        if let key = resumeKey {
            timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] t in
                guard let self = self,
                      let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
                ResumeStore.save(key, seconds: t.seconds, duration: d)
            }
        }

        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            if let key = resumeKey { ResumeStore.clear(key) }
            self?.onEndedHandler()
        }
        player.play()
    }

    deinit {
        if let o = timeObs { player.removeTimeObserver(o) }
        if let e = endObs { NotificationCenter.default.removeObserver(e) }
        if !PlayerHub.shared.isHolding(player) { player.pause() }
    }
}

struct AVPlayerScreen: View {
    @StateObject private var model: AVModel
    let onPiPStart: () -> Void
    let onReady: () -> Void
    let onFail: () -> Void
    let onEnded: () -> Void

    init(url: URL, resumeKey: String?,
         onReady: @escaping () -> Void, onFail: @escaping () -> Void,
         onEnded: @escaping () -> Void, onPiPStart: @escaping () -> Void) {
        _model = StateObject(wrappedValue: PlayerHub.shared.reusableModel(for: url) ?? AVModel(url: url, resumeKey: resumeKey,
                                                   onReady: onReady, onFail: onFail, onEnded: onEnded))
        self.onPiPStart = onPiPStart
        self.onReady = onReady
        self.onFail = onFail
        self.onEnded = onEnded
    }

    var body: some View {
        AVPlayerView(model: model, onPiPStart: onPiPStart).ignoresSafeArea()
            .onAppear { model.updateHandlers(onReady: onReady, onFail: onFail, onEnded: onEnded) }
    }
}

struct AVPlayerView: UIViewControllerRepresentable {
    let model: AVModel
    private var player: AVPlayer { model.player }
    let onPiPStart: () -> Void

    func makeCoordinator() -> Coord { Coord() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = PlayerHub.shared.isHolding(player) ? (PlayerHub.shared.heldVC ?? AVPlayerViewController()) : AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.requiresLinearPlayback = false
        context.coordinator.model = model
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
        weak var model: AVModel?

        func playerViewControllerWillStartPictureInPicture(_ vc: AVPlayerViewController) {
            PlayerHub.shared.hold(vc, model: model, delegate: self)
        }

        func playerViewControllerDidStartPictureInPicture(_ vc: AVPlayerViewController) {
            DispatchQueue.main.async { self.onPiPStart() }
        }

        func playerViewController(_ vc: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) {
            PlayerHub.shared.release(pause: false)
        }

        func playerViewControllerDidStopPictureInPicture(_ vc: AVPlayerViewController) {
            PlayerHub.shared.release()
        }

        func playerViewController(_ vc: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            guard let restore = PlayerHub.shared.onRestore else {
                completionHandler(false)
                return
            }
            PlayerHub.shared.restoring = true
            PlayerHub.shared.restoreCompletion = completionHandler
            restore()
        }
    }
}

// MARK: - VLC engine (MKV, TS and everything AVPlayer cannot open)

final class VLCModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    weak var surface: UIView?
    private let url: URL
    private let isLive: Bool
    private let resumeKey: String?
    private let onEnded: () -> Void
    private var didResume = false
    private var lastBucket = -1
    private var retries = 0
    private var reconnectPending = false

    @Published var message = t("Loading") + "..."
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
    @Published var volume = 100

    let aspectNames = ["Fit", "Fill", "Stretch", "16:9", "4:3"]

    init(url: URL, isLive: Bool, resumeKey: String?, onEnded: @escaping () -> Void) {
        self.url = url
        self.isLive = isLive
        self.resumeKey = resumeKey
        self.onEnded = onEnded
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.media = makeMedia()
        player.delegate = self
    }

    private func makeMedia() -> VLCMedia {
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1500")
        return media
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

    func setVolume(_ v: Int) {
        let c = min(200, max(0, v))
        volume = c
        player.audio?.volume = Int32(c)
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

    private func reconnect() {
        if reconnectPending { return }
        guard retries < 6 else {
            failed = true
            message = t("Stream unavailable. Check your connection or try another channel.")
            return
        }
        retries += 1
        reconnectPending = true
        failed = false
        message = t("Reconnecting") + "... (\(retries))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.reconnectPending = false
            self.player.media = self.makeMedia()
            self.player.play()
        }
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async {
            switch self.player.state {
            case .error:
                if self.isLive {
                    self.reconnect()
                } else {
                    self.failed = true
                    self.message = t("Playback failed (stream not reachable or not supported)")
                }
            case .ended:
                if self.isLive {
                    self.reconnect()
                } else {
                    if let k = self.resumeKey { ResumeStore.clear(k) }
                    self.onEnded()
                }
            case .opening, .buffering:
                if !self.player.isPlaying && !self.reconnectPending { self.message = t("Loading") + "..." }
            case .playing:
                self.retries = 0
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

            let secs = Double(self.player.time.value?.intValue ?? 0) / 1000
            let dur = Double(self.player.media?.length.value?.intValue ?? 0) / 1000

            if !self.didResume && self.seekable && dur > 0 {
                self.didResume = true
                if let key = self.resumeKey, let r = ResumeStore.get(key), r.seconds > 20 {
                    self.player.time = VLCTime(int: Int32(max(0, r.seconds - 3) * 1000))
                }
            }
            if let key = self.resumeKey, dur > 0, self.didResume, Int(secs) / 5 != self.lastBucket {
                self.lastBucket = Int(secs) / 5
                ResumeStore.save(key, seconds: secs, duration: dur)
            }
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
    @State private var hud: (icon: String, text: String)?
    @State private var hudTask: Task<Void, Never>?
    @State private var lastDragY: CGFloat = 0

    init(url: URL, isLive: Bool, resumeKey: String?, showChrome: Binding<Bool>, onEnded: @escaping () -> Void) {
        _model = StateObject(wrappedValue: VLCModel(url: url, isLive: isLive, resumeKey: resumeKey, onEnded: onEnded))
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

    private func flash(_ icon: String, _ text: String) {
        hud = (icon, text)
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !Task.isCancelled { await MainActor.run { hud = nil } }
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

    private func zone(left: Bool) -> some View {
        Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard model.seekable else { return }
                model.skip(left ? -10 : 10)
                flash(left ? "gobackward.10" : "goforward.10", "")
            }
            .onTapGesture {
                withAnimation { showChrome.toggle() }
                if showChrome { scheduleHide() }
            }
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { drag in
                        let dy = drag.translation.height - lastDragY
                        lastDragY = drag.translation.height
                        let delta = -Double(dy) / 320
                        if left {
                            let b = min(1, max(0, Double(UIScreen.main.brightness) + delta))
                            UIScreen.main.brightness = CGFloat(b)
                            flash("sun.max.fill", "\(Int(b * 100))%")
                        } else {
                            let nv = min(200, max(0, model.volume + Int((delta * 200).rounded())))
                            model.setVolume(nv)
                            flash("speaker.wave.2.fill", "\(nv)%")
                        }
                    }
                    .onEnded { _ in lastDragY = 0 }
            )
    }

    var body: some View {
        ZStack {
            VLCSurface(model: model).ignoresSafeArea()
            HStack(spacing: 0) {
                zone(left: true)
                zone(left: false)
            }
            .ignoresSafeArea()

            if let h = hud {
                VStack(spacing: 6) {
                    Image(systemName: h.icon).font(.title)
                    if !h.text.isEmpty { Text(h.text).font(.headline.monospacedDigit()) }
                }
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
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
                    HStack(spacing: 32) {
                        if model.seekable {
                            iconButton("gobackward.10", size: .title) { model.skip(-10) }
                        }
                        Button {
                            model.toggle()
                            scheduleHide()
                        } label: {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 38, weight: .semibold))
                                .frame(width: 80, height: 80)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t(model.isPlaying ? "Pause" : "Play"))
                        if model.seekable {
                            iconButton("goforward.10", size: .title) { model.skip(10) }
                        }
                    }
                    Spacer()
                    controlPanel
                }
                .transition(.opacity)
            }
        }
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel(); hudTask?.cancel() }
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
                        Section(t("Audio")) {
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
                        Section(t("Subtitles")) {
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
                            Label(t(name), systemImage: model.aspect == i ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "aspectratio").font(.title3).frame(width: 44, height: 44)
                }
                .foregroundStyle(.white)

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
