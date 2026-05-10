import XCTest
@testable import IrockTunnelCore

final class IrockTunnelCoreTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(IrockTunnelCoreModule.name, "IrockTunnelCore")
    }
}
