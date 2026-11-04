import XCTest
@testable import RaMtv

final class EngineSelectionTests: XCTestCase {
    private var host = ""

    override func setUp() {
        super.setUp()
        host = "t\(UUID().uuidString.prefix(8).lowercased()).test"
        clean()
    }

    override func tearDown() {
        clean()
        super.tearDown()
    }

    private func clean() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "engine.\(host)")
        d.removeObject(forKey: "engine.failures.\(host)")
    }

    private func tsRequest() throws -> PlayRequest {
        let url = try XCTUnwrap(URL(string: "https://\(host)/live/user/pass/7.ts"))
        return PlayRequest(title: "Channel", url: url, isLive: true)
    }

    @MainActor
    func testStoreKeepsOriginalTSURLSoVLCFallsBackToIt() throws {
        let item = Item(id: "c1", name: "Channel", logo: nil, group: "G",
                        url: "https://\(host)/live/user/pass/7.ts", kind: .live,
                        seriesId: nil, sourceId: UUID())
        let request = try XCTUnwrap(AppStore().makeRequest(item))
        XCTAssertEqual(request.url.pathExtension, "ts")
        guard case .av(let candidate, let fallback) = Engine.initial(for: request) else {
            return XCTFail("Expected an HLS attempt first")
        }
        XCTAssertEqual(candidate.pathExtension, "m3u8")
        XCTAssertEqual(fallback.pathExtension, "ts", "VLC must fall back to the original TS endpoint")
    }

    func testTwoHLSFailuresInARowRememberVLC() throws {
        let request = try tsRequest()
        EnginePrefs.recordAVFailure(host: host)
        XCTAssertNil(EnginePrefs.get(host), "one failure must not condemn the host")
        if case .av = Engine.initial(for: request) {} else { XCTFail("HLS should still be tried") }
        EnginePrefs.recordAVFailure(host: host)
        XCTAssertEqual(EnginePrefs.get(host), "vlc")
        XCTAssertEqual(Engine.initial(for: request), .vlc(request.url))
    }

    func testSuccessClearsEarlierFailures() throws {
        EnginePrefs.recordAVFailure(host: host)
        EnginePrefs.recordAVSuccess(host: host)
        EnginePrefs.recordAVFailure(host: host)
        XCTAssertEqual(EnginePrefs.get(host), "av")
    }
}

final class PlaybackLogTests: XCTestCase {
    override func setUp() { super.setUp(); PlaybackLog.clear() }
    override func tearDown() { PlaybackLog.clear(); super.tearDown() }

    func testMedian() {
        XCTAssertNil(PlaybackLog.median([]))
        XCTAssertEqual(PlaybackLog.median([300, 100, 200]), 200)
        XCTAssertEqual(PlaybackLog.median([100, 200, 300, 400]), 250)
    }

    func testSummaryCountsFailuresSeparatelyFromStartTimes() {
        PlaybackLog.record(engine: "AVPlayer", ms: 400, outcome: "ok")
        PlaybackLog.record(engine: "AVPlayer", ms: 800, outcome: "ok")
        PlaybackLog.record(engine: "AVPlayer", ms: 10_000, outcome: "timeout")
        PlaybackLog.record(engine: "VLC", ms: 900, outcome: "ok")
        let s = PlaybackLog.summary(PlaybackLog.load())
        let av = s.first { $0.engine == "AVPlayer" }
        XCTAssertEqual(av?.starts, 2)
        XCTAssertEqual(av?.failures, 1)
        XCTAssertEqual(av?.medianMs, 600)
        XCTAssertEqual(s.first { $0.engine == "VLC" }?.medianMs, 900)
    }

    func testLogKeepsOnlyTheNewestEntries() {
        for i in 0..<60 { PlaybackLog.record(engine: "VLC", ms: i, outcome: "ok") }
        let list = PlaybackLog.load()
        XCTAssertEqual(list.count, 40)
        XCTAssertEqual(list.last?.ms, 59)
    }
}

final class SearchIndexTests: XCTestCase {
    private func item(_ name: String) -> Item {
        Item(id: name, name: name, logo: nil, group: "G", url: nil, kind: .live, seriesId: nil, sourceId: UUID())
    }

    func testNormalizeIgnoresArabicVariantsAndHarakat() {
        XCTAssertEqual(SearchText.normalize("الأَخبار"), SearchText.normalize("الاخبار"))
        XCTAssertEqual(SearchText.normalize("مدرسة"), SearchText.normalize("مدرسه"))
        XCTAssertEqual(SearchText.normalize("BeIN Sport"), SearchText.normalize("bein sport"))
    }

    func testPrefixMatchesComeFirstAndShortQueriesReturnNothing() {
        let index = SearchIndex(items: [item("Sky beIN"), item("beIN Sport 1"), item("MBC 1")])
        XCTAssertEqual(index.search("be").first?.name, "beIN Sport 1")
        XCTAssertEqual(index.search("be").count, 2)
        XCTAssertTrue(index.search("b").isEmpty)
    }

    func testResultLimit() {
        let index = SearchIndex(items: (0..<500).map { item("Channel \($0)") })
        XCTAssertEqual(index.search("channel", limit: 50).count, 50)
    }
}
