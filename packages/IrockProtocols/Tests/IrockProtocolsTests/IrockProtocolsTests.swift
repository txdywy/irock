import XCTest
@testable import IrockProtocols

final class IrockProtocolsTests: XCTestCase {
    func testModuleNameAndDependencies() {
        XCTAssertEqual(IrockProtocolsModule.name, "IrockProtocols")
        XCTAssertEqual(IrockProtocolsModule.coreName, "IrockCore")
        XCTAssertEqual(IrockProtocolsModule.transportName, "IrockTransport")
    }
}
