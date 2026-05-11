import Foundation
import XCTest

final class ReleaseReadinessTests: XCTestCase {
    func testM52AlphaReleaseHardeningArtifactsExist() throws {
        for path in requiredM52Paths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path), "Missing \(path)")
        }
    }

    func testAlphaReadinessEvidenceCoversTechnicalGateWithoutSecrets() throws {
        let readiness = try String(contentsOf: repositoryRoot.appendingPathComponent("docs/superpowers/release/ALPHA-READINESS.md"))

        for milestone in ["M30", "M31", "M32", "M33", "M34", "M35", "M36", "M37", "M38", "M39", "M40", "M41", "M42", "M43", "M44", "M45", "M46", "M47", "M48", "M49", "M50", "M51", "M52"] {
            XCTAssertTrue(readiness.contains(milestone), "Missing \(milestone)")
        }
        for requiredArea in ["protocol matrix", "iOS shell", "macOS shell", "routing", "diagnostics", "performance budget", "external blocker", "full swift test", "signing artifact scan"] {
            XCTAssertTrue(readiness.localizedCaseInsensitiveContains(requiredArea), "Missing \(requiredArea)")
        }
        XCTAssertFalse(readiness.localizedCaseInsensitiveContains("password123"))
        XCTAssertFalse(readiness.localizedCaseInsensitiveContains("secret-token"))
        XCTAssertFalse(readiness.contains("BEGIN PRIVATE KEY"))
    }

    private var requiredM52Paths: [String] {
        [
            "docs/superpowers/specs/2026-05-12-irock-m52-alpha-release-hardening-design.md",
            "docs/superpowers/plans/2026-05-12-irock-m52-alpha-release-hardening.md",
            "docs/superpowers/release/ALPHA-READINESS.md"
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
