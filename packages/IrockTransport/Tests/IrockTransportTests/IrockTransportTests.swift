import XCTest
@testable import IrockTransport

final class IrockTransportTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockTransportModule.name, "IrockTransport")
        XCTAssertEqual(IrockTransportModule.coreName, "IrockCore")
    }
}
