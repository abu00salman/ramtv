import XCTest
@testable import RaMtv

final class AppleStyleTests: XCTestCase {
    func testQualityTagsAndEmptyBracketsAreRemovedFromChannelNames() {
        XCTAssertEqual(LiveName.clean("BeIN Sport 01 (FHD)"), "BeIN Sport 01")
        XCTAssertEqual(LiveName.clean("Bein sport 2-720"), "Bein sport 2")
        XCTAssertEqual(LiveName.clean("Channel 100"), "Channel 100")
        XCTAssertEqual(LiveName.clean("MBC 1 HD"), "MBC 1")
    }

    func testRemainingTimeIsHiddenWhenAlmostDone() {
        XCTAssertNil(RemainingTime.text(seconds: 5950, duration: 6000))
        XCTAssertNil(RemainingTime.text(seconds: 10, duration: 0))
        XCTAssertNotNil(RemainingTime.text(seconds: 600, duration: 6000))
    }
}
