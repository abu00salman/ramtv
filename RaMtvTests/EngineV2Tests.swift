import XCTest
@testable import RaMtv

final class EngineV2Tests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testSniffRecognisesContainersFromTheirFirstBytes() {
        XCTAssertEqual(StreamProbe.sniff(Data("#EXTM3U\n#EXT-X-VERSION:3".utf8)), .hls)
        XCTAssertEqual(StreamProbe.sniff(Data("\u{FEFF}\n#EXTM3U".utf8)), .hls)
        XCTAssertEqual(StreamProbe.sniff(Data("<?xml version=\"1.0\"?><MPD>".utf8)), .dash)
        var ts = [UInt8](repeating: 0, count: 376); ts[0] = 0x47; ts[188] = 0x47
        XCTAssertEqual(StreamProbe.sniff(Data(ts)), .mpegTS)
        XCTAssertEqual(StreamProbe.sniff(Data([0x1A, 0x45, 0xDF, 0xA3, 0x01])), .matroska)
        XCTAssertEqual(StreamProbe.sniff(Data([0, 0, 0, 0x20] + Array("ftypisom".utf8))), .mp4)
        XCTAssertEqual(StreamProbe.sniff(Data("<html>".utf8)), .unknown)
    }

    func testContentTypeWinsOverSniffing() {
        XCTAssertEqual(StreamProbe.classify(contentType: "application/vnd.apple.mpegurl", head: Data()), .hls)
        XCTAssertEqual(StreamProbe.classify(contentType: "video/MP2T", head: Data()), .mpegTS)
        XCTAssertEqual(StreamProbe.classify(contentType: "video/x-matroska", head: Data()), .matroska)
        XCTAssertEqual(StreamProbe.classify(contentType: "application/octet-stream", head: Data("#EXTM3U".utf8)), .hls)
    }

    func testOnlyUnclearLinksAreProbed() {
        XCTAssertFalse(StreamProbe.needsProbe(PlayRequest(title: "a", url: url("https://h.test/a.m3u8"))))
        XCTAssertFalse(StreamProbe.needsProbe(PlayRequest(title: "b", url: url("https://h.test/live/u/p/7.ts"), isLive: true)))
        XCTAssertFalse(StreamProbe.needsProbe(PlayRequest(title: "c", url: url("https://h.test/stream"), isLive: true)))
        XCTAssertFalse(StreamProbe.needsProbe(PlayRequest(title: "d", url: url("file:///tmp/a.mkv"))))
        XCTAssertTrue(StreamProbe.needsProbe(PlayRequest(title: "e", url: url("https://h.test/movie/u/p/9.mkv"))))
        XCTAssertTrue(StreamProbe.needsProbe(PlayRequest(title: "f", url: url("https://h.test/play?id=4"))))
    }

    func testProbedTypePicksTheEngineThatCanPlayIt() {
        let r = PlayRequest(title: "x", url: url("https://h.test/x.bin"))
        XCTAssertEqual(Engine.after(probe: .hls, for: r), .av(r.url, fallback: r.url))
        XCTAssertEqual(Engine.after(probe: .mpegTS, for: r), .vlc(r.url))
        XCTAssertEqual(Engine.after(probe: .matroska, for: r), .vlc(r.url))
        XCTAssertEqual(Engine.after(probe: .dash, for: r), .vlc(r.url))
        XCTAssertEqual(Engine.after(probe: .unknown, for: r), Engine.initial(for: r))
    }

    func testDeadLinksGetAClearMessage() {
        XCTAssertNil(PlaybackMessage.text(for: .kind(.hls)))
        XCTAssertNotNil(PlaybackMessage.text(for: .httpError(404)))
        XCTAssertNotNil(PlaybackMessage.text(for: .httpError(403)))
        XCTAssertNotNil(PlaybackMessage.text(for: .unreachable))
    }

    func testLiveReconnectIsBoundedWithGrowingDelays() {
        XCTAssertEqual(AVModel.maxReconnects, 4)
        XCTAssertEqual((1...4).map(AVModel.reconnectDelay), [1, 2, 4, 8])
    }

    func testShortEPGDecodesBase64TitlesAndPicksNowNext() {
        let b64 = { (s: String) in Data(s.utf8).base64EncodedString() }
        let json: [String: Any] = ["epg_listings": [
            ["title": b64("الأخبار"), "start_timestamp": "2000", "stop_timestamp": "3000"],
            ["title": b64("Morning"), "start_timestamp": 1000, "stop_timestamp": 2000]
        ]]
        let list = EpgParser.parseShortEPG(json)
        XCTAssertEqual(list.map(\.title), ["Morning", "الأخبار"])
        let r = EpgParser.nowNext(list, at: Date(timeIntervalSince1970: 1500))
        XCTAssertEqual(r.now?.title, "Morning")
        XCTAssertEqual(r.next?.title, "الأخبار")
    }
}
