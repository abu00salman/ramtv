import XCTest
import AVKit
@testable import RaMtv

final class PreferencesTests: XCTestCase {
    private var originalLanguage: Any?

    override func setUp() {
        super.setUp()
        originalLanguage = UserDefaults.standard.object(forKey: "appLanguage")
    }

    override func tearDown() {
        if let originalLanguage = originalLanguage {
            UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }
        super.tearDown()
    }

    func testArabicSelectionOverridesDeviceLanguage() {
        UserDefaults.standard.set("ar", forKey: "appLanguage")
        XCTAssertEqual(AppLanguage.selected, .arabic)
        XCTAssertTrue(AppLanguage.selected.isArabic)
        XCTAssertEqual(t("Live"), "مباشر")
        XCTAssertEqual(t("Grid"), "بطاقات")
    }

    func testEnglishSelectionOverridesDeviceLanguage() {
        UserDefaults.standard.set("en", forKey: "appLanguage")
        XCTAssertEqual(t("Live"), "Live")
        XCTAssertFalse(AppLanguage.selected.isArabic)
    }

    func testUnknownSavedLanguageFallsBackToSystem() {
        UserDefaults.standard.set("unknown", forKey: "appLanguage")
        XCTAssertEqual(AppLanguage.selected, .system)
        XCTAssertEqual(t("Untranslated provider name"), "Untranslated provider name")
    }

    @MainActor
    func testPiPRetainsControllerAndDelegateUntilRelease() {
        let hub = PlayerHub.shared
        let controller = AVPlayerViewController()
        controller.player = AVPlayer()
        var delegate: NSObject? = NSObject()
        weak var reference = delegate
        hub.hold(controller, model: nil, delegate: delegate!)
        delegate = nil
        XCTAssertNotNil(reference)
        XCTAssertTrue(hub.isHolding(controller.player!))
        hub.release()
        XCTAssertNil(hub.heldVC)
        XCTAssertNil(reference)
    }

    func testXtreamTSOffersHLSAndPreservesFallbackAndQuery() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/live/user/fixture/42.ts?token=test"))
        let request = PlayRequest(title: "Channel", url: url, isLive: true)
        guard case .av(let candidate, let fallback) = Engine.initial(for: request) else {
            return XCTFail("Expected compatible HLS attempt")
        }
        XCTAssertEqual(candidate.pathExtension, "m3u8")
        XCTAssertEqual(candidate.query, url.query)
        XCTAssertEqual(fallback, url)
    }

    func testOtherContainersStartWithApplePlayerAndFallBackToVLC() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/movie.mkv"))
        XCTAssertEqual(Engine.initial(for: PlayRequest(title: "Movie", url: url)), .av(url, fallback: url))
    }
}
