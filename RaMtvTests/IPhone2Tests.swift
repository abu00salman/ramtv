import XCTest
@testable import RaMtv

final class IPhone2Tests: XCTestCase {
    private func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }

    func testShortEPGDecodesBase64TitlesAndSortsByStart() {
        let json: [String: Any] = ["epg_listings": [
            ["title": b64("الأخبار"), "start_timestamp": "2000", "stop_timestamp": "3000"],
            ["title": b64("Morning Show"), "start_timestamp": 1000, "stop_timestamp": 2000],
            ["title": "", "start_timestamp": "3000", "stop_timestamp": "4000"],
            ["title": b64("Broken"), "start_timestamp": "5000", "stop_timestamp": "4000"]
        ]]
        let list = EpgParser.parseShortEPG(json)
        XCTAssertEqual(list.map(\.title), ["Morning Show", "الأخبار"])
    }

    func testPlainTitlesAreKeptWhenNotBase64() {
        XCTAssertEqual(EpgParser.decodeTitle("Live: Match"), "Live: Match")
    }

    func testNowNextPicksProgrammeOnAirAndTheFollowingOne() {
        let a = EpgEntry(title: "A", start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 2000))
        let b = EpgEntry(title: "B", start: Date(timeIntervalSince1970: 2000), end: Date(timeIntervalSince1970: 3000))
        let r = EpgParser.nowNext([a, b], at: Date(timeIntervalSince1970: 1500))
        XCTAssertEqual(r.now, a)
        XCTAssertEqual(r.next, b)
        XCTAssertEqual(a.progress(at: Date(timeIntervalSince1970: 1500)), 0.5, accuracy: 0.001)
        let gap = EpgParser.nowNext([b], at: Date(timeIntervalSince1970: 1500))
        XCTAssertNil(gap.now)
        XCTAssertEqual(gap.next, b)
    }

    func testXtreamStreamIdComesFromLiveItemIdOnly() {
        let src = UUID()
        let live = Item(id: "ABCD1234-live-987", name: "Ch", logo: nil, group: "G", url: nil, kind: .live, seriesId: nil, sourceId: src)
        let movie = Item(id: "ABCD1234-vod-5", name: "M", logo: nil, group: "G", url: nil, kind: .movie, seriesId: nil, sourceId: src)
        XCTAssertEqual(XtreamClient.streamId(of: live), "987")
        XCTAssertNil(XtreamClient.streamId(of: movie))
    }

    func testAccentDefaultsToBlueAndFollowsSavedChoice() {
        let key = AppAccent.storageKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved = saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppAccent.current, .blue)
        UserDefaults.standard.set("teal", forKey: key)
        XCTAssertEqual(AppAccent.current, .teal)
        UserDefaults.standard.set("unknown", forKey: key)
        XCTAssertEqual(AppAccent.current, .blue)
    }

    func testMultiViewStartsWithTwoWindowsAndStopsAtFour() {
        let session = MultiViewSession()
        XCTAssertEqual(session.tiles.count, 2)
        session.addWindow()
        session.addWindow()
        session.addWindow()
        XCTAssertEqual(session.tiles.count, MultiViewSession.maxWindows)
        XCTAssertFalse(session.canAddWindow)
        session.remove(at: 3)
        XCTAssertEqual(session.tiles.count, 3)
        session.remove(at: 0)
        session.remove(at: 0)
        XCTAssertEqual(session.tiles.count, 2, "two windows always remain")
    }

    func testOnlyTheSelectedWindowPlaysSound() throws {
        let session = MultiViewSession()
        let src = UUID()
        let url = try XCTUnwrap(URL(string: "https://example.test/a.m3u8"))
        let a = Item(id: "a", name: "A", logo: nil, group: "G", url: url.absoluteString, kind: .live, seriesId: nil, sourceId: src)
        let b = Item(id: "b", name: "B", logo: nil, group: "G", url: url.absoluteString, kind: .live, seriesId: nil, sourceId: src)
        session.set(a, url: url, at: 0)
        session.set(b, url: url, at: 1)
        XCTAssertEqual(session.audioIndex, 0)
        XCTAssertEqual(session.tiles[0]?.player.isMuted, false)
        XCTAssertEqual(session.tiles[1]?.player.isMuted, true)
        session.selectAudio(1)
        XCTAssertEqual(session.tiles[0]?.player.isMuted, true)
        XCTAssertEqual(session.tiles[1]?.player.isMuted, false)
        session.stopAll()
    }

    func testQualityTagsAndEmptyBracketsAreRemovedFromChannelNames() {
        XCTAssertEqual(LiveName.clean("BeIN Sport 01 (FHD)"), "BeIN Sport 01")
        XCTAssertEqual(LiveName.clean("beIN Sports (A): BeIN Sport 02 [1080p]"), "BeIN Sport 02")
        XCTAssertEqual(LiveName.clean("MBC 1 HD"), "MBC 1")
    }
}
