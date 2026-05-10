import XCTest
import IrockCore
@testable import IrockAppFeature

final class URIImportTests: XCTestCase {
    func testClassifiesSupportedSchemes() throws {
        XCTAssertEqual(try URIImport.classify("ss://abc").protocolType, .shadowsocks)
        XCTAssertEqual(try URIImport.classify("vmess://abc").protocolType, .vmess)
        XCTAssertEqual(try URIImport.classify("vless://abc").protocolType, .vless)
        XCTAssertEqual(try URIImport.classify("trojan://abc").protocolType, .trojan)
        XCTAssertEqual(try URIImport.classify("hysteria2://abc").protocolType, .hysteria2)
        XCTAssertEqual(try URIImport.classify("tuic://abc").protocolType, .tuic)
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try URIImport.classify("https://example.com")) { error in
            XCTAssertEqual(error as? URIImportError, .unsupportedScheme("https"))
        }
    }
}
