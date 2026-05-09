import XCTest
@testable import IrockRouting

final class IrockRoutingTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockRoutingModule.name, "IrockRouting")
        XCTAssertEqual(IrockRoutingModule.coreName, "IrockCore")
    }
}
