import XCTest
@testable import IrockDiagnostics

final class IrockDiagnosticsTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockDiagnosticsModule.name, "IrockDiagnostics")
        XCTAssertEqual(IrockDiagnosticsModule.coreName, "IrockCore")
    }
}
