import XCTest
@testable import IrockAppFeature

final class AppFeatureModelsTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(IrockAppFeatureModule.name, "IrockAppFeature")
    }
}
