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

    func testXcodeProjectDeclaresIOSAppAndTunnelTargetShape() throws {
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irock.xcodeproj/project.pbxproj"))

        XCTAssertTrue(project.contains("com.apple.product-type.application"))
        XCTAssertTrue(project.contains("com.apple.product-type.app-extension"))
        XCTAssertTrue(project.contains("SDKROOT = iphoneos"))
        XCTAssertTrue(project.contains("SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\""))
        XCTAssertTrue(project.contains("TARGETED_DEVICE_FAMILY = \"1,2\""))
        XCTAssertEqual(project.components(separatedBy: "ALWAYS_SEARCH_USER_PATHS = NO").count - 1, 2)
        XCTAssertTrue(project.contains("APPLICATION_EXTENSION_API_ONLY = YES"))
        XCTAssertTrue(project.contains("IrockApp.swift in Sources"))
        XCTAssertTrue(project.contains("ContentView.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelProvider.swift in Sources"))
        XCTAssertTrue(project.contains("NEPacketTunnelFlowPacketFlowIO.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelAppGroupStoreResolver.swift in Sources"))
        XCTAssertTrue(project.contains("IOSPacketTunnelSmokeRunner.swift in Sources"))
        XCTAssertTrue(project.contains("IOSPacketTunnelLoopRunner.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsConfiguration.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsFactory.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsApplicator.swift in Sources"))
        XCTAssertTrue(project.contains("irockTunnelExtension.appex in Embed App Extensions"))
        XCTAssertTrue(project.contains("relativePath = ../.."))
    }

    func testPacketTunnelProviderWiresLoopRunner() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

        XCTAssertTrue(provider.contains("IOSPacketTunnelLoopRunner"))
        XCTAssertTrue(provider.contains("startTunnelTask"))
        XCTAssertTrue(provider.contains("packetFlow"))
        XCTAssertTrue(provider.contains("cancel()"))
    }

    func testPacketTunnelSmokePathFilesDeclareExpectedBoundaries() throws {
        let flowAdapter = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift"))
        let storeResolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift"))
        let smokeRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift"))

        XCTAssertTrue(flowAdapter.contains("import " + "NetworkExtension"))
        XCTAssertTrue(flowAdapter.contains("PacketFlowIO"))
        XCTAssertTrue(flowAdapter.contains("readPacketObjects"))
        XCTAssertTrue(flowAdapter.contains("writePacketObjects"))
        XCTAssertTrue(storeResolver.contains("containerURL(forSecurityApplicationGroupIdentifier:"))
        XCTAssertTrue(storeResolver.contains("AppGroupRuntimeStoreDirectory"))
        XCTAssertTrue(storeResolver.contains("group.dev.irock.shared"))
        XCTAssertTrue(smokeRunner.contains("TunnelRuntimeController.runShadowsocksTCPBatch"))
        XCTAssertTrue(smokeRunner.contains("UnsupportedTransportAdapter"))
    }

    func testPacketTunnelLoopRunnerDeclaresCancellableLongRunningBoundary() throws {
        let loopRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift"))
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

        XCTAssertTrue(loopRunner.contains("import " + "NetworkExtension"))
        XCTAssertTrue(loopRunner.contains("IOSPacketTunnelSmokeRunner"))
        XCTAssertTrue(loopRunner.contains("Task.isCancelled"))
        XCTAssertTrue(loopRunner.contains("Task.sleep"))
        XCTAssertTrue(loopRunner.contains("while !Task.isCancelled"))
        XCTAssertTrue(loopRunner.contains("runStartupBatch"))
        XCTAssertTrue(provider.contains("IOSPacketTunnelLoopRunner"))
        XCTAssertTrue(provider.contains("try await loopRunner.runStartupBatch"))
        XCTAssertFalse(provider.contains("IOSPacketTunnelSmokeRunner().runOnce"))
    }

    func testNetworkExtensionImportsStayInsideTunnelExtension() throws {
        let forbiddenRoots = [
            repositoryRoot.appendingPathComponent("packages"),
            repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp")
        ]

        for root in forbiddenRoots {
            for file in try swiftFiles(under: root) {
                let contents = try String(contentsOf: file)
                XCTAssertFalse(contents.contains("import " + "NetworkExtension"), "NetworkExtension leaked into \(file.path)")
            }
        }
    }

    func testPacketTunnelRuntimeSettingsFilesDeclareExpectedDefaults() throws {
        let configuration = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift"))
        let factory = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift"))
        let applicator = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift"))

        XCTAssertTrue(configuration.contains("10.255.0.2"))
        XCTAssertTrue(configuration.contains("255.255.255.0"))
        XCTAssertTrue(configuration.contains("1.1.1.1"))
        XCTAssertTrue(configuration.contains("8.8.8.8"))
        XCTAssertTrue(configuration.contains("1500"))
        XCTAssertTrue(factory.contains("NEPacketTunnelNetworkSettings"))
        XCTAssertTrue(factory.contains("NEIPv4Settings"))
        XCTAssertTrue(factory.contains("NEDNSSettings"))
        XCTAssertTrue(factory.contains(".default()"))
        XCTAssertTrue(applicator.contains("setTunnelNetworkSettings"))
    }

    func testPacketTunnelProviderAppliesSettingsBeforeLoopRunner() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))
        let settingsRange = try XCTUnwrap(provider.range(of: "PacketTunnelRuntimeSettingsApplicator"))
        let loopRange = try XCTUnwrap(provider.range(of: "IOSPacketTunnelLoopRunner"))

        XCTAssertLessThan(settingsRange.lowerBound, loopRange.lowerBound)
        XCTAssertTrue(provider.contains("apply(to: self)"))
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
            "apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift",
            "apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift",
            "apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift",
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
