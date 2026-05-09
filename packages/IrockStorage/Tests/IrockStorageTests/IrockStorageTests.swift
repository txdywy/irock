import XCTest
@testable import IrockStorage

final class IrockStorageTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockStorageModule.name, "IrockStorage")
        XCTAssertEqual(IrockStorageModule.coreName, "IrockCore")
    }
}
