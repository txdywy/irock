import XCTest
@testable import IrockCore

final class IrockCoreTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(IrockCoreModule.name, "IrockCore")
    }
}
