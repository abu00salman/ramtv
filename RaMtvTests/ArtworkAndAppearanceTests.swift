import XCTest
import SwiftUI
@testable import RaMtv

final class ArtworkAndAppearanceTests: XCTestCase {
    func testResolutionSuffixesDoNotBreakNumberedChannelLogos() {
        XCTAssertEqual(TitleCleaner.normalize("Bein sport 2-540"), TitleCleaner.normalize("beIN Sports 2 HD"))
        XCTAssertEqual(TitleCleaner.normalize("Bein sport 07-720"), TitleCleaner.normalize("beIN Sports 7"))
        XCTAssertNotEqual(TitleCleaner.normalize("Bein sport 7-720"), TitleCleaner.normalize("Bein sport 6-720"))
    }

    func testRepeatedSeasonTitlesUseSeriesSearchName() {
        XCTAssertEqual(ArtworkLookup.seriesTitle("WWE Friday Night SmackDown S2025 WWE Friday Night SmackDown 2025 12 19"), "WWE Friday Night SmackDown")
        XCTAssertEqual(ArtworkLookup.seriesTitle("Raw S2025 WWE Monday Night Raw 2025 09 01"), "WWE Raw")
        XCTAssertEqual(ArtworkLookup.seriesTitle("Example Show S02E03 1080p"), "Example Show")
    }

    func testEmptyAndUnsafeArtworkURLsAreRejected() {
        for value in ["", "null", "undefined", "file:///private/image.png", "javascript:alert(1)", "/images/cover.jpg"] {
            XCTAssertNil(ArtworkLookup.validURL(value))
        }
        XCTAssertEqual(ArtworkLookup.validURL("//example.test/logo.png")?.scheme, "https")
    }

    func testProviderRelativeCoversResolveAgainstTheirServer() {
        XCTAssertEqual(ArtworkLookup.providerURL("/images/cover.jpg", base: "https://example.test"),
                       "https://example.test/images/cover.jpg")
        XCTAssertNil(ArtworkLookup.providerURL("null", base: "https://example.test"))
    }

    func testDayNightAndSystemPreferences() {
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
        XCTAssertNil(AppAppearance.system.colorScheme)
    }
}
