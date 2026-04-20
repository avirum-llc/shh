import XCTest
@testable import ShhCore

final class ShhCoreTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(Shh.version.isEmpty)
    }
}
