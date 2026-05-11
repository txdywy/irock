import Foundation
import XCTest

final class ProtocolValidationTests: XCTestCase {
    func testM51CrossProtocolValidationArtifactsExist() throws {
        for path in requiredM51ValidationPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path), "Missing \(path)")
        }
    }

    func testM51ProtocolMatrixCoversAlphaProtocolsAndTransportsWithoutSecrets() throws {
        let matrix = try String(contentsOf: repositoryRoot.appendingPathComponent("tests/protocol-fixtures/ALPHA-PROTOCOL-MATRIX.md"))

        for protocolName in alphaProtocolNames {
            XCTAssertTrue(matrix.contains(protocolName), "Missing \(protocolName)")
        }
        for transportName in ["TCP", "TLS", "WebSocket", "HTTP/2", "gRPC", "QUIC", "Reality"] {
            XCTAssertTrue(matrix.contains(transportName), "Missing \(transportName)")
        }
        XCTAssertTrue(matrix.contains("sanitized fixture"))
        XCTAssertTrue(matrix.contains("no real credentials"))
        XCTAssertFalse(matrix.localizedCaseInsensitiveContains("password123"))
        XCTAssertFalse(matrix.localizedCaseInsensitiveContains("secret-token"))
    }

    func testM51RealNodeRunbookDocumentsInputsObservationsRedactionAndBlockers() throws {
        let runbook = try String(contentsOf: repositoryRoot.appendingPathComponent("tools/protocol-lab/REAL-NODE-VALIDATION.md"))

        for protocolName in alphaProtocolNames {
            XCTAssertTrue(runbook.contains(protocolName), "Missing \(protocolName)")
        }
        for expectedText in [
            "Required inputs",
            "Expected observations",
            "Redaction rules",
            "External blocker",
            "Do not commit",
            "Apple Developer signing",
            "physical iOS or macOS device"
        ] {
            XCTAssertTrue(runbook.contains(expectedText), "Missing \(expectedText)")
        }
        XCTAssertFalse(runbook.localizedCaseInsensitiveContains("password123"))
        XCTAssertFalse(runbook.localizedCaseInsensitiveContains("secret-token"))
    }

    private var alphaProtocolNames: [String] {
        ["Shadowsocks", "VMess", "VLESS", "Trojan", "Hysteria2", "TUIC"]
    }

    private var requiredM51ValidationPaths: [String] {
        [
            "docs/superpowers/specs/2026-05-12-irock-m51-cross-protocol-real-node-validation-design.md",
            "docs/superpowers/plans/2026-05-12-irock-m51-cross-protocol-real-node-validation.md",
            "tests/protocol-fixtures/ALPHA-PROTOCOL-MATRIX.md",
            "tools/protocol-lab/REAL-NODE-VALIDATION.md"
        ]
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
