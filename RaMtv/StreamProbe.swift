import Foundation

// MARK: - Stream type probe
//
// For links whose type is not obvious from the extension, read only the first 2 KB
// (HTTP Range) and decide which engine can play them. Apple's player cannot open
// MPEG-TS, Matroska or DASH, so those go to VLC at once instead of waiting for
// Apple's player to time out. Dead links (401/403/404/410) get a clear message.

enum StreamKind: Equatable {
    case hls, dash, mpegTS, matroska, mp4, unknown

    /// True when Apple's player can open this container.
    var playsInApplePlayer: Bool { self == .hls || self == .mp4 }
}

enum ProbeOutcome: Equatable {
    case kind(StreamKind)
    case httpError(Int)
    case unreachable
}

enum StreamProbe {
    static let headBytes = 2048
    static let timeout: TimeInterval = 8

    static func classify(contentType: String?, head: Data) -> StreamKind {
        let ct = (contentType ?? "").lowercased()
        if ct.contains("mpegurl") { return .hls }
        if ct.contains("dash+xml") { return .dash }
        if ct.contains("mp2t") { return .mpegTS }
        if ct.contains("matroska") || ct.contains("webm") { return .matroska }
        if ct.contains("video/mp4") || ct.contains("quicktime") { return .mp4 }
        return sniff(head)
    }

    static func sniff(_ head: Data) -> StreamKind {
        let b = [UInt8](head.prefix(headBytes))
        guard !b.isEmpty else { return .unknown }
        if b.count >= 4, b[0] == 0x1A, b[1] == 0x45, b[2] == 0xDF, b[3] == 0xA3 { return .matroska }
        if b[0] == 0x47, b.count < 189 || b[188] == 0x47 { return .mpegTS }
        if b.count >= 8, String(bytes: b[4..<8], encoding: .ascii) == "ftyp" { return .mp4 }
        let text = String(decoding: b, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        if text.hasPrefix("#EXTM3U") { return .hls }
        if text.contains("<MPD") { return .dash }
        return .unknown
    }

    /// Only links Apple's player would otherwise try blindly are probed.
    static func needsProbe(_ r: PlayRequest) -> Bool {
        guard let scheme = r.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        let ext = r.url.pathExtension.lowercased()
        if ["m3u8", "mp4", "m4v", "mov"].contains(ext) { return false }
        if r.isLive && (ext.isEmpty || (ext == "ts" && r.url.path.contains("/live/"))) { return false }
        return true
    }

    static func probe(_ url: URL) async -> ProbeOutcome {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("bytes=0-\(headBytes - 1)", forHTTPHeaderField: "Range")
        req.setValue("RaMtv/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            let http = response as? HTTPURLResponse
            if let code = http?.statusCode, [401, 403, 404, 410].contains(code) { return .httpError(code) }
            var head = Data()
            for try await byte in bytes {
                head.append(byte)
                if head.count >= headBytes { break }
            }
            bytes.task.cancel()
            return .kind(classify(contentType: http?.value(forHTTPHeaderField: "Content-Type"), head: head))
        } catch is CancellationError {
            return .kind(.unknown)
        } catch {
            if let e = error as? URLError,
               [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
                .contains(e.code) {
                return .unreachable
            }
            return .kind(.unknown)
        }
    }
}

extension Engine {
    /// Engine for a probed link. Unknown types keep the usual order (Apple first, then VLC).
    static func after(probe kind: StreamKind, for r: PlayRequest) -> Engine {
        switch kind {
        case .hls, .mp4: return .av(r.url, fallback: r.url)
        case .mpegTS, .matroska, .dash: return .vlc(r.url)
        case .unknown: return initial(for: r)
        }
    }
}

enum PlaybackMessage {
    static func text(for outcome: ProbeOutcome) -> String? {
        switch outcome {
        case .kind: return nil
        case .unreachable: return t("No connection to the server. Check your internet and try again.")
        case .httpError(let code):
            return code == 401 || code == 403
                ? t("The server refused this link. Check your subscription or login.") + " (\(code))"
                : t("This link no longer exists on the server.") + " (\(code))"
        }
    }
}
