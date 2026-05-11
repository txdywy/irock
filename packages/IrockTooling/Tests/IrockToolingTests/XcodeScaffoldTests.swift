import XCTest

final class XcodeScaffoldTests: XCTestCase {
    func testRequiredIOSScaffoldFilesExist() throws {
        for path in requiredScaffoldPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path), "Missing \(path)")
        }
    }

    func testExtensionInfoPlistDeclaresPacketTunnelExtensionPoint() throws {
        let plist = try loadPlist("apps/irock-iOS/irockTunnelExtension/Info.plist")
        let extensionDictionary = try XCTUnwrap(plist["NSExtension"] as? [String: Any])

        XCTAssertEqual(extensionDictionary["NSExtensionPointIdentifier"] as? String, "com.apple.networkextension.packet-tunnel")
        XCTAssertEqual(extensionDictionary["NSExtensionPrincipalClass"] as? String, "$(PRODUCT_MODULE_NAME).PacketTunnelProvider")
    }

    func testEntitlementTemplatesDeclareSharedAppGroupAndPacketTunnelCapability() throws {
        let appEntitlements = try loadPlist("apps/irock-iOS/irockApp/irockApp.entitlements")
        let extensionEntitlements = try loadPlist("apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements")

        XCTAssertEqual(appEntitlements["com.apple.security.application-groups"] as? [String], ["group.dev.irock.shared"])
        XCTAssertEqual(extensionEntitlements["com.apple.security.application-groups"] as? [String], ["group.dev.irock.shared"])
        XCTAssertEqual(extensionEntitlements["com.apple.developer.networking.networkextension"] as? [String], ["packet-tunnel-provider"])
    }

    func testPlatformImportsStayOutOfSharedPackages() throws {
        let forbiddenImports = [
            "import " + "NetworkExtension",
            "import " + "Network",
            "import " + "Security",
            "import " + "UIKit",
            "import " + "AppKit"
        ]
        let packageFiles = try swiftFiles(under: repositoryRoot.appendingPathComponent("packages"))

        for file in packageFiles {
            let contents = try String(contentsOf: file)
            for forbiddenImport in forbiddenImports {
                XCTAssertFalse(contents.contains(forbiddenImport), "\(forbiddenImport) leaked into \(file.path)")
            }
        }
    }

    func testPlatformImportsExistOnlyInIOSScaffold() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))
        let app = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IrockApp.swift"))
        let contentView = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/ContentView.swift"))

        XCTAssertTrue(provider.contains("import " + "NetworkExtension"))
        XCTAssertTrue(app.contains("import " + "SwiftUI"))
        XCTAssertTrue(contentView.contains("import " + "SwiftUI"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var requiredScaffoldPaths: [String] {
        [
            "apps/irock-iOS/irock.xcodeproj/project.pbxproj",
            "apps/irock-iOS/irockApp/IrockApp.swift",
            "apps/irock-iOS/irockApp/ContentView.swift",
            "apps/irock-iOS/irockApp/Info.plist",
            "apps/irock-iOS/irockApp/irockApp.entitlements",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift",
            "apps/irock-iOS/irockTunnelExtension/Info.plist",
            "apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements"
        ]
    }

    private func loadPlist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }
}
