import XCTest
@testable import IrockPerformanceKit

final class IrockPerformanceKitTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockPerformanceKitModule.name, "IrockPerformanceKit")
        XCTAssertEqual(IrockPerformanceKitModule.coreName, "IrockCore")
    }
}
