import XCTest

final class XcodeScaffoldTests: XCTestCase {
    func testRequiredIOSScaffoldFilesExist() throws {
        for path in requiredScaffoldPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path), "Missing \(path)")
        }
    }

    func testRequiredMacOSScaffoldFilesExist() throws {
        for path in requiredMacOSScaffoldPaths {
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

    func testMacOSEntitlementTemplatesDeclareSharedAppGroupAndPacketTunnelCapability() throws {
        let appEntitlements = try loadPlist("apps/irock-macOS/irockMacApp/irockMacApp.entitlements")
        let extensionEntitlements = try loadPlist("apps/irock-macOS/irockMacTunnelExtension/irockMacTunnelExtension.entitlements")

        XCTAssertEqual(appEntitlements["com.apple.security.application-groups"] as? [String], ["group.dev.irock.shared"])
        XCTAssertEqual(extensionEntitlements["com.apple.security.application-groups"] as? [String], ["group.dev.irock.shared"])
        XCTAssertEqual(extensionEntitlements["com.apple.developer.networking.networkextension"] as? [String], ["packet-tunnel-provider"])
    }

    func testMacOSExtensionInfoPlistDeclaresPacketTunnelExtensionPoint() throws {
        let plist = try loadPlist("apps/irock-macOS/irockMacTunnelExtension/Info.plist")
        let extensionDictionary = try XCTUnwrap(plist["NSExtension"] as? [String: Any])

        XCTAssertEqual(extensionDictionary["NSExtensionPointIdentifier"] as? String, "com.apple.networkextension.packet-tunnel")
        XCTAssertEqual(extensionDictionary["NSExtensionPrincipalClass"] as? String, "$(PRODUCT_MODULE_NAME).PacketTunnelProvider")
    }

    func testSigningTemplateAndDeviceSmokeRunbookArePlaceholderSafe() throws {
        let signingTemplate = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/Signing/LocalSigning.xcconfig.example"))
        let smokeRunbook = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/Signing/DEVICE-SMOKE.md"))

        XCTAssertTrue(signingTemplate.contains("IROCK_DEVELOPMENT_TEAM = YOUR_TEAM_ID"))
        XCTAssertTrue(signingTemplate.contains("IROCK_APP_BUNDLE_ID = com.example.irock"))
        XCTAssertTrue(signingTemplate.contains("IROCK_TUNNEL_BUNDLE_ID = com.example.irock.tunnel"))
        XCTAssertTrue(signingTemplate.contains("IROCK_APP_GROUP = group.com.example.irock"))
        XCTAssertFalse(signingTemplate.contains("DEVELOPMENT_TEAM = [A-Z0-9]"))

        XCTAssertTrue(smokeRunbook.contains("Apple Developer account"))
        XCTAssertTrue(smokeRunbook.contains("Network Extension"))
        XCTAssertTrue(smokeRunbook.contains("App Groups"))
        XCTAssertTrue(smokeRunbook.contains("Packet Tunnel"))
        XCTAssertTrue(smokeRunbook.contains("Expected result"))
        XCTAssertTrue(smokeRunbook.contains("Do not commit"))
    }

    func testMacOSSigningTemplateAndDeviceSmokeRunbookArePlaceholderSafe() throws {
        let signingTemplate = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/Signing/LocalSigning.xcconfig.example"))
        let smokeRunbook = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/Signing/DEVICE-SMOKE.md"))

        XCTAssertTrue(signingTemplate.contains("IROCK_DEVELOPMENT_TEAM = YOUR_TEAM_ID"))
        XCTAssertTrue(signingTemplate.contains("IROCK_MAC_APP_BUNDLE_ID = com.example.irock.macos"))
        XCTAssertTrue(signingTemplate.contains("IROCK_MAC_TUNNEL_BUNDLE_ID = com.example.irock.macos.tunnel"))
        XCTAssertTrue(signingTemplate.contains("IROCK_APP_GROUP = group.com.example.irock"))
        XCTAssertFalse(signingTemplate.contains("DEVELOPMENT_TEAM = [A-Z0-9]"))

        XCTAssertTrue(smokeRunbook.contains("Apple Developer account"))
        XCTAssertTrue(smokeRunbook.contains("Network Extension"))
        XCTAssertTrue(smokeRunbook.contains("App Groups"))
        XCTAssertTrue(smokeRunbook.contains("Packet Tunnel"))
        XCTAssertTrue(smokeRunbook.contains("Expected result"))
        XCTAssertTrue(smokeRunbook.contains("Do not commit"))
    }

    func testSigningSecretsAndProvisioningArtifactsAreNotCommitted() throws {
        let iOSProject = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irock.xcodeproj/project.pbxproj"))
        let macOSProject = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj"))
        for project in [iOSProject, macOSProject] {
            XCTAssertTrue(project.contains("DEVELOPMENT_TEAM = \"\""))
            XCTAssertFalse(project.contains("PROVISIONING_PROFILE_SPECIFIER ="))
            XCTAssertFalse(project.contains("CODE_SIGN_IDENTITY = Apple Development"))
        }

        let forbiddenExtensions = Set(["mobileprovision", "p12", "cer"])
        for appRoot in ["apps/irock-iOS", "apps/irock-macOS"] {
            let forbiddenFiles = try allFiles(under: repositoryRoot.appendingPathComponent(appRoot)).filter { forbiddenExtensions.contains($0.pathExtension) }
            XCTAssertEqual(forbiddenFiles, [])
        }
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

    func testIOSScaffoldDeclaresExpectedPlatformImports() throws {
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
        XCTAssertTrue(project.contains("IOSPlatformTCPDialer.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsConfiguration.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsFactory.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsApplicator.swift in Sources"))
        XCTAssertTrue(project.contains("irockTunnelExtension.appex in Embed App Extensions"))
        XCTAssertTrue(project.contains("relativePath = ../.."))
    }

    func testXcodeProjectDeclaresMacOSAppAndTunnelTargetShape() throws {
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj"))

        XCTAssertTrue(project.contains("com.apple.product-type.application"))
        XCTAssertTrue(project.contains("com.apple.product-type.app-extension"))
        XCTAssertTrue(project.contains("SDKROOT = macosx"))
        XCTAssertTrue(project.contains("SUPPORTED_PLATFORMS = macosx"))
        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET = 14.0"))
        XCTAssertEqual(project.components(separatedBy: "ALWAYS_SEARCH_USER_PATHS = NO").count - 1, 2)
        XCTAssertTrue(project.contains("APPLICATION_EXTENSION_API_ONLY = YES"))
        XCTAssertTrue(project.contains("IrockMacApp.swift in Sources"))
        XCTAssertTrue(project.contains("ContentView.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelProvider.swift in Sources"))
        XCTAssertTrue(project.contains("NEPacketTunnelFlowPacketFlowIO.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelAppGroupStoreResolver.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSPacketTunnelSmokeRunner.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSPacketTunnelLoopRunner.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSPlatformTCPDialer.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsConfiguration.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsFactory.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsApplicator.swift in Sources"))
        XCTAssertTrue(project.contains("irockMacTunnelExtension.appex in Embed App Extensions"))
        XCTAssertTrue(project.contains("relativePath = ../.."))
    }

    func testMacOSAppIconAssetCatalogIsWired() throws {
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj"))
        let appIconContents = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/Assets.xcassets/AppIcon.appiconset/Contents.json"))

        XCTAssertTrue(project.contains("Assets.xcassets in Resources"))
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon"))
        XCTAssertTrue(appIconContents.contains("icon_512x512@2x.png"))
        XCTAssertTrue(appIconContents.contains("\"idiom\" : \"mac\""))
    }

    func testMacOSAppWiresLocalProxyControllerForUnsignedUsability() throws {
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj"))
        let app = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/IrockMacApp.swift"))
        let contentView = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/ContentView.swift"))
        let controller = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift"))
        let tunController = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/MacOSUserModeTunController.swift"))
        let tunDevice = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/MacOSUserModeTunDevice.swift"))
        let tunRouteCommands = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/MacOSUserModeTunRouteCommands.swift"))
        let tunPacketFlow = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/MacOSUserModeTunPacketFlowIO.swift"))
        let tunCredentialResolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacApp/MacOSImportedShadowsocksCredentialResolver.swift"))
        let buildScript = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/build-unsigned-app.sh"))
        let readme = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/README.md"))

        XCTAssertTrue(project.contains("MacOSLocalProxyController.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSUserModeTunController.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSUserModeTunDevice.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSUserModeTunRouteCommands.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSUserModeTunPacketFlowIO.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSImportedShadowsocksCredentialResolver.swift in Sources"))
        XCTAssertTrue(project.contains("MacOSPlatformTCPDialer.swift in Sources"))
        XCTAssertTrue(project.contains("IROCKPKGPROTOCOLS0000001 /* IrockProtocols */"))
        XCTAssertTrue(project.contains("IROCKPKGTRANSPORT0000001 /* IrockTransport */"))
        XCTAssertTrue(project.contains("IROCKPKGTUNNELCORE000001 /* IrockTunnelCore */"))
        XCTAssertTrue(project.contains("IROCKPKGNATIVEHY20000001 /* IrockNativeHysteria2 */"))
        XCTAssertTrue(app.contains("IROCK_SELF_TEST_URI"))
        XCTAssertTrue(app.contains("startLocalProxyMode()"))
        XCTAssertTrue(app.contains("IROCK_SELF_TEST_READY"))
        XCTAssertTrue(app.contains("IROCK_SELF_TEST_FAILED"))
        XCTAssertTrue(contentView.contains("localProxyController: MacOSLocalProxyController()"))
        XCTAssertTrue(contentView.contains("userModeTunController: MacOSUserModeTunController(runtimeStores: stores)"))
        XCTAssertTrue(controller.contains("final class MacOSLocalProxyController: LocalProxyControlling"))
        XCTAssertTrue(controller.contains("Darwin.socket"))
        XCTAssertTrue(controller.contains("Darwin.accept"))
        XCTAssertTrue(controller.contains("SIGPIPE"))
        XCTAssertTrue(controller.contains("DispatchQueue(label: \"dev.irock.macos-local-proxy.socks-listener\")"))
        XCTAssertTrue(controller.contains("DispatchQueue(label: \"dev.irock.macos-local-proxy.http-listener\")"))
        XCTAssertTrue(controller.contains("import IrockNativeHysteria2"))
        XCTAssertTrue(controller.contains("NativeHysteria2ClientConfiguration"))
        XCTAssertTrue(controller.contains("certificatePinSHA256: node.tls.fingerprint"))
        XCTAssertTrue(controller.contains("openHysteria2OutboundAndRelay"))
        XCTAssertTrue(controller.contains("ShadowsocksStreamRequest"))
        XCTAssertTrue(controller.contains("ShadowsocksAEADStreamEncoder"))
        XCTAssertTrue(controller.contains("ShadowsocksAEADStreamDecoder"))
        XCTAssertTrue(controller.contains("requestSalt: clientSalt"))
        XCTAssertTrue(controller.contains("saltLength(forCredential:"))
        XCTAssertTrue(controller.contains("VLESSOpenRequest"))
        XCTAssertTrue(controller.contains("openVLESSOutboundAndRelay"))
        XCTAssertTrue(controller.contains("VMessOpenRequest"))
        XCTAssertTrue(controller.contains("openVMessOutboundAndRelay"))
        XCTAssertTrue(controller.contains("isSupportedLocalProxyNode"))
        XCTAssertTrue(controller.contains("node.tls.enabled"))
        XCTAssertTrue(controller.contains("node.tls.fingerprint == nil"))
        XCTAssertTrue(controller.contains("node.tls.reality == nil"))
        XCTAssertTrue(project.contains("MacOSPlatformQUICStreamDialer.swift in Sources"))
        XCTAssertFalse(controller.contains("2022-blake3-aes-128-gcm"))
        XCTAssertTrue(controller.contains("HTTP/1.1 501 Not Implemented"))
        XCTAssertTrue(tunController.contains("final class MacOSUserModeTunController: UserModeTunControlling"))
        XCTAssertTrue(tunController.contains("MacOSUserModeTunDevice"))
        XCTAssertTrue(tunController.contains("MacOSUserModeTunRouteCommands"))
        XCTAssertTrue(tunController.contains("TunnelRuntimeController.runShadowsocksTCPBatch"))
        XCTAssertTrue(tunController.contains("authorizationRequired"))
        XCTAssertTrue(tunDevice.contains("PF_SYSTEM"))
        XCTAssertTrue(tunDevice.contains("UTUN_OPT_IFNAME"))
        XCTAssertTrue(tunDevice.contains("com.apple.net.utun_control"))
        XCTAssertTrue(tunRouteCommands.contains("ifconfig"))
        XCTAssertTrue(tunRouteCommands.contains("route"))
        XCTAssertTrue(tunRouteCommands.contains("delete"))
        XCTAssertTrue(tunRouteCommands.contains("utun"))
        XCTAssertTrue(tunPacketFlow.contains("struct MacOSUserModeTunPacketFlowIO: PacketFlowIO"))
        XCTAssertTrue(tunPacketFlow.contains("Darwin.read"))
        XCTAssertTrue(tunPacketFlow.contains("Darwin.write"))
        XCTAssertTrue(tunCredentialResolver.contains("struct MacOSImportedShadowsocksCredentialResolver: ShadowsocksCredentialResolver"))
        XCTAssertTrue(buildScript.contains("-scheme irockMacApp"))
        XCTAssertTrue(buildScript.contains("CODE_SIGNING_ALLOWED=NO"))
        XCTAssertTrue(buildScript.contains("Contents/Frameworks"))
        XCTAssertTrue(buildScript.contains("libngtcp2"))
        XCTAssertTrue(buildScript.contains("libnghttp3"))
        XCTAssertTrue(buildScript.contains("libssl"))
        XCTAssertTrue(buildScript.contains("libcrypto"))
        XCTAssertTrue(buildScript.contains("install_name_tool"))
        XCTAssertTrue(buildScript.contains("realpath"))
        XCTAssertTrue(buildScript.contains("codesign --force --deep --sign -"))
        XCTAssertTrue(readme.contains("build/unsigned/irockMacApp.app"))
        XCTAssertTrue(readme.contains("127.0.0.1:10808"))
        XCTAssertTrue(readme.contains("用户态 TUN"))
        XCTAssertTrue(readme.contains("sudo"))
        XCTAssertTrue(readme.contains("Unsigned builds cannot install or start the Network Extension Packet Tunnel"))
    }

    func testPackageDefinesNativeHysteria2FFIBoundary() throws {
        let package = try String(contentsOf: repositoryRoot.appendingPathComponent("Package.swift"))

        XCTAssertTrue(package.contains(".library(name: \"IrockNativeHysteria2\""))
        XCTAssertTrue(package.contains(".systemLibrary("))
        XCTAssertTrue(package.contains("name: \"CNgtcp2\""))
        XCTAssertTrue(package.contains("pkgConfig: \"libngtcp2\""))
        XCTAssertTrue(package.contains("name: \"CNgtcp2CryptoOpenSSL\""))
        XCTAssertTrue(package.contains("pkgConfig: \"libngtcp2_crypto_ossl\""))
        XCTAssertTrue(package.contains("name: \"CNghttp3\""))
        XCTAssertTrue(package.contains("pkgConfig: \"libnghttp3\""))
        XCTAssertTrue(package.contains("name: \"IrockNativeHysteria2\""))
    }

    func testMacOSPacketTunnelRuntimeIntegrationUsesSharedRuntimeAndPlatformTCPDialer() throws {
        let smokeRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacTunnelExtension/MacOSPacketTunnelSmokeRunner.swift"))
        let dialer = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-macOS/irockMacTunnelExtension/MacOSPlatformTCPDialer.swift"))

        XCTAssertTrue(smokeRunner.contains("TunnelRuntimeController.runShadowsocksTCPBatch"))
        XCTAssertTrue(smokeRunner.contains("NEPacketTunnelFlowPacketFlowIO(packetFlow: packetFlow)"))
        XCTAssertTrue(smokeRunner.contains("TCPTransportAdapter(dialer: MacOSPlatformTCPDialer())"))
        XCTAssertTrue(smokeRunner.contains("UnsupportedTransportAdapter(transport: .tcp)"))
        XCTAssertTrue(smokeRunner.contains("MissingShadowsocksCredentialResolver"))
        XCTAssertTrue(dialer.contains("import " + "Network"))
        XCTAssertTrue(dialer.contains("NWConnection"))
        XCTAssertTrue(dialer.contains("withTaskCancellationHandler"))
        XCTAssertTrue(dialer.contains("Task.sleep(nanoseconds: timeoutNanoseconds)"))
        XCTAssertTrue(dialer.contains("connection.send(content: initialPayload"))
        XCTAssertTrue(dialer.contains("TCPDialResult"))
        XCTAssertTrue(dialer.contains("TransportError"))
    }

    func testPacketTunnelProviderWiresLoopRunner() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

        XCTAssertTrue(provider.contains("IOSPacketTunnelLoopRunner"))
        XCTAssertTrue(provider.contains("startTunnelTask"))
        XCTAssertTrue(provider.contains("packetFlow"))
        XCTAssertTrue(provider.contains("cancel()"))
    }

    func testPacketTunnelProviderReportsStoppedLifecycle() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

        XCTAssertTrue(provider.contains("reportStoppedLifecycle"))
        XCTAssertTrue(provider.contains("PacketTunnelAppGroupStoreResolver"))
        XCTAssertTrue(provider.contains("TunnelRuntimeReporter"))
        XCTAssertTrue(provider.contains("reportStopped()"))
        XCTAssertTrue(provider.contains("try await task.value"))
    }

    func testPacketTunnelSmokeRunnerReportsRuntimeStoreUnavailableDuringStartupValidation() throws {
        let smokeRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift"))

        XCTAssertTrue(smokeRunner.contains("reportRuntimeStoreUnavailable"))
        XCTAssertTrue(smokeRunner.contains("TunnelRuntimeReporter"))
        XCTAssertTrue(smokeRunner.contains("catch TunnelRuntimeControllerError.missingRuntimeSnapshot"))
    }

    func testM35AlphaSmokeRunbookDocumentsDiagnosticExpectations() throws {
        let runbook = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/Signing/M35-ALPHA-SMOKE.md"))

        XCTAssertTrue(runbook.contains("Runtime snapshot unavailable"))
        XCTAssertTrue(runbook.contains("Runtime store unavailable"))
        XCTAssertTrue(runbook.contains("Proxy adapter failed"))
        XCTAssertTrue(runbook.contains("Packet batch failed"))
        XCTAssertTrue(runbook.contains("Tunnel stopped"))
        XCTAssertTrue(runbook.contains("External blocker"))
        XCTAssertTrue(runbook.contains("Do not commit"))
    }

    func testContainerAppDeclaresVPNManagerBoundary() throws {
        let configuration = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IOSVPNManagerConfiguration.swift"))
        let manager = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IOSVPNManager.swift"))
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irock.xcodeproj/project.pbxproj"))

        XCTAssertTrue(configuration.contains("struct IOSVPNManagerConfiguration"))
        XCTAssertTrue(configuration.contains("dev.irock.app.tunnel"))
        XCTAssertTrue(configuration.contains("group.dev.irock.shared"))
        XCTAssertTrue(manager.contains("import " + "NetworkExtension"))
        XCTAssertTrue(manager.contains("final class IOSVPNManager"))
        XCTAssertTrue(manager.contains("NETunnelProviderManager.loadAllFromPreferences"))
        XCTAssertTrue(manager.contains("NETunnelProviderProtocol"))
        XCTAssertTrue(manager.contains("providerBundleIdentifier"))
        XCTAssertTrue(manager.contains("saveToPreferences"))
        XCTAssertTrue(manager.contains("startVPNTunnel"))
        XCTAssertTrue(manager.contains("stopVPNTunnel"))
        XCTAssertTrue(project.contains("IOSVPNManagerConfiguration.swift in Sources"))
        XCTAssertTrue(project.contains("IOSVPNManager.swift in Sources"))
    }

    func testContainerAppDeclaresAppGroupRuntimeStoreResolver() throws {
        let resolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IOSAppGroupRuntimeStoreResolver.swift"))
        let extensionResolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift"))
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irock.xcodeproj/project.pbxproj"))

        XCTAssertTrue(resolver.contains("struct IOSAppGroupRuntimeStoreResolver"))
        XCTAssertTrue(resolver.contains("group.dev.irock.shared"))
        XCTAssertTrue(resolver.contains("containerURL(forSecurityApplicationGroupIdentifier:"))
        XCTAssertTrue(resolver.contains("AppGroupRuntimeStoreDirectory"))
        XCTAssertTrue(resolver.contains("makeRuntimeStoreBundle"))
        XCTAssertTrue(extensionResolver.contains("group.dev.irock.shared"))
        XCTAssertTrue(extensionResolver.contains("AppGroupRuntimeStoreDirectory"))
        XCTAssertTrue(project.contains("IOSAppGroupRuntimeStoreResolver.swift in Sources"))
    }

    func testContainerAppHostsSharedRootView() throws {
        let contentView = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/ContentView.swift"))

        XCTAssertTrue(contentView.contains("import " + "IrockAppFeature"))
        XCTAssertTrue(contentView.contains("@StateObject"))
        XCTAssertTrue(contentView.contains("AppViewModel"))
        XCTAssertTrue(contentView.contains("IrockRootView(viewModel: viewModel)"))
        XCTAssertFalse(contentView.contains("Text(\"irock\")"))
    }

    func testContentViewInjectsAppGroupRuntimeStoresWithFallback() throws {
        let contentView = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/ContentView.swift"))

        XCTAssertTrue(contentView.contains("IOSAppGroupRuntimeStoreResolver"))
        XCTAssertTrue(contentView.contains("makeRuntimeStoreBundle"))
        XCTAssertTrue(contentView.contains("runtimeSnapshotStore: stores.snapshotStore"))
        XCTAssertTrue(contentView.contains("runtimeStatusStore: stores.statusStore"))
        XCTAssertTrue(contentView.contains("runtimeLogStore: stores.logStore"))
        XCTAssertTrue(contentView.contains("AppViewModel(nodes: [])"))
    }

    func testNEPacketTunnelFlowAdapterWritesOnlyExplicitResponseBytes() throws {
        let flowAdapter = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift"))

        XCTAssertTrue(flowAdapter.contains("result.responsePacketBytes"))
        XCTAssertTrue(flowAdapter.contains("Data(responsePacketBytes)"))
        XCTAssertTrue(flowAdapter.contains("protocolFamily(for: responsePacketBytes)"))
        XCTAssertTrue(flowAdapter.contains("case 4:"))
        XCTAssertTrue(flowAdapter.contains("case 6:"))
        XCTAssertTrue(flowAdapter.contains("AF_INET6"))
        XCTAssertFalse(flowAdapter.contains("Data(result.packet.bytes)"))
        XCTAssertFalse(flowAdapter.contains("protocolFamily: sa_family_t(AF_INET))"))
    }

    func testPacketTunnelSmokePathFilesDeclareExpectedBoundaries() throws {
        let flowAdapter = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift"))
        let storeResolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift"))
        let smokeRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift"))

        XCTAssertTrue(flowAdapter.contains("import " + "NetworkExtension"))
        XCTAssertTrue(flowAdapter.contains("PacketFlowIO"))
        XCTAssertTrue(flowAdapter.contains("readPacketObjects"))
        XCTAssertTrue(flowAdapter.contains("guard !Task.isCancelled else { return [] }"))
        XCTAssertTrue(flowAdapter.contains("withTaskCancellationHandler"))
        XCTAssertTrue(flowAdapter.contains("withCheckedContinuation"))
        XCTAssertTrue(flowAdapter.contains("CancellationResumeGate"))
        XCTAssertTrue(flowAdapter.contains("writePacketObjects"))
        XCTAssertTrue(storeResolver.contains("containerURL(forSecurityApplicationGroupIdentifier:"))
        XCTAssertTrue(storeResolver.contains("AppGroupRuntimeStoreDirectory"))
        XCTAssertTrue(storeResolver.contains("group.dev.irock.shared"))
        XCTAssertTrue(smokeRunner.contains("validateStartup"))
        XCTAssertTrue(smokeRunner.contains("stores.snapshotStore"))
        XCTAssertTrue(smokeRunner.contains("stores.statusStore"))
        XCTAssertTrue(smokeRunner.contains("stores.logStore"))
        XCTAssertTrue(smokeRunner.contains("reportMissingSnapshot(stores: stores)"))
        XCTAssertTrue(smokeRunner.contains("RuntimeConnectionStatus("))
        XCTAssertTrue(smokeRunner.contains("RuntimeLogEntry("))
        XCTAssertTrue(smokeRunner.contains("TunnelRuntimeControllerError.missingRuntimeSnapshot"))
        XCTAssertTrue(smokeRunner.contains("missingRuntimeSnapshot"))
        XCTAssertTrue(smokeRunner.contains("TunnelRuntimeController.runShadowsocksTCPBatch"))
        XCTAssertTrue(smokeRunner.contains("TCPTransportAdapter(dialer: IOSPlatformTCPDialer())"))
        XCTAssertTrue(smokeRunner.contains("tls: UnsupportedTransportAdapter(transport: .tcp)"))
    }

    func testPacketTunnelLoopRunnerDeclaresCancellableLongRunningBoundary() throws {
        let loopRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift"))
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

        XCTAssertTrue(loopRunner.contains("import " + "NetworkExtension"))
        XCTAssertTrue(loopRunner.contains("IOSPacketTunnelSmokeRunner"))
        XCTAssertTrue(loopRunner.contains("Task.isCancelled"))
        XCTAssertTrue(loopRunner.contains("Task.sleep"))
        XCTAssertTrue(loopRunner.contains("while !Task.isCancelled"))
        XCTAssertTrue(loopRunner.contains("validateStartup"))
        XCTAssertTrue(provider.contains("IOSPacketTunnelLoopRunner"))
        XCTAssertTrue(provider.contains("try loopRunner.validateStartup"))
        XCTAssertFalse(provider.contains("runStartupBatch"))
        XCTAssertFalse(provider.contains("IOSPacketTunnelSmokeRunner().runOnce"))
    }

    func testPlatformTCPDialerDeclaresNetworkConnectionBoundary() throws {
        let dialer = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift"))

        XCTAssertTrue(dialer.contains("import " + "IrockTransport"))
        XCTAssertTrue(dialer.contains("import " + "Network"))
        XCTAssertTrue(dialer.contains("struct IOSPlatformTCPDialer: TCPDialer"))
        XCTAssertTrue(dialer.contains("NWConnection"))
        XCTAssertTrue(dialer.contains("NWEndpoint.Host"))
        XCTAssertTrue(dialer.contains("NWEndpoint.Port"))
        XCTAssertTrue(dialer.contains("connection.start"))
        XCTAssertTrue(dialer.contains("withTaskCancellationHandler"))
        XCTAssertTrue(dialer.contains("private static let queue"))
        XCTAssertTrue(dialer.contains("waiter.cancel()"))
        XCTAssertTrue(dialer.contains("let timeoutTask = Task"))
        XCTAssertTrue(dialer.contains("resume(with: .failure(TransportError.tcpConnectFailed(\"tcp dial timed out\")))"))
        XCTAssertTrue(dialer.contains("missing tcp host"))
        XCTAssertTrue(dialer.contains("Task.sleep"))
        XCTAssertFalse(dialer.contains("withThrowingTaskGroup"))
        XCTAssertTrue(dialer.contains("case .ready"))
        XCTAssertTrue(dialer.contains("case .failed"))
        XCTAssertTrue(dialer.contains("case .waiting"))
        XCTAssertTrue(dialer.contains("case .waiting:\n            break"))
        XCTAssertTrue(dialer.contains("TCPDialResult"))
        XCTAssertTrue(dialer.contains("TransportError.tcpConnectFailed"))
    }

    func testPlatformImportsStayInsidePlatformTargets() throws {
        let forbiddenPackageModules = Set(["NetworkExtension", "Network", "Security", "UIKit", "AppKit"])
        for file in try swiftFiles(under: repositoryRoot.appendingPathComponent("packages")) {
            let importedModules = try importedModules(in: file)
            XCTAssertTrue(importedModules.isDisjoint(with: forbiddenPackageModules), "Platform imports leaked into \(file.path): \(importedModules.intersection(forbiddenPackageModules))")
        }

        let forbiddenAppModules = Set(["Network", "Security", "UIKit", "AppKit"])
        for file in try swiftFiles(under: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp")) {
            let importedModules = try importedModules(in: file)
            XCTAssertTrue(importedModules.isDisjoint(with: forbiddenAppModules), "Forbidden app imports leaked into \(file.path): \(importedModules.intersection(forbiddenAppModules))")
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
            "apps/irock-iOS/Signing/LocalSigning.xcconfig.example",
            "apps/irock-iOS/Signing/DEVICE-SMOKE.md",
            "apps/irock-iOS/Signing/M35-ALPHA-SMOKE.md",
            "apps/irock-iOS/irockApp/IrockApp.swift",
            "apps/irock-iOS/irockApp/ContentView.swift",
            "apps/irock-iOS/irockApp/IOSVPNManagerConfiguration.swift",
            "apps/irock-iOS/irockApp/IOSVPNManager.swift",
            "apps/irock-iOS/irockApp/IOSAppGroupRuntimeStoreResolver.swift",
            "apps/irock-iOS/irockApp/Info.plist",
            "apps/irock-iOS/irockApp/irockApp.entitlements",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift",
            "apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift",
            "apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift",
            "apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift",
            "apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift",
            "apps/irock-iOS/irockTunnelExtension/Info.plist",
            "apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements"
        ]
    }

    private var requiredMacOSScaffoldPaths: [String] {
        [
            "apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj",
            "apps/irock-macOS/irock-macOS.xcodeproj/xcshareddata/xcschemes/irockMacApp.xcscheme",
            "apps/irock-macOS/build-unsigned-app.sh",
            "apps/irock-macOS/Signing/LocalSigning.xcconfig.example",
            "apps/irock-macOS/Signing/DEVICE-SMOKE.md",
            "apps/irock-macOS/irockMacApp/IrockMacApp.swift",
            "apps/irock-macOS/irockMacApp/ContentView.swift",
            "apps/irock-macOS/irockMacApp/MacOSVPNManagerConfiguration.swift",
            "apps/irock-macOS/irockMacApp/MacOSVPNManager.swift",
            "apps/irock-macOS/irockMacApp/MacOSAppGroupRuntimeStoreResolver.swift",
            "apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift",
            "apps/irock-macOS/irockMacApp/MacOSUserModeTunController.swift",
            "apps/irock-macOS/irockMacApp/MacOSUserModeTunDevice.swift",
            "apps/irock-macOS/irockMacApp/MacOSUserModeTunRouteCommands.swift",
            "apps/irock-macOS/irockMacApp/MacOSUserModeTunPacketFlowIO.swift",
            "apps/irock-macOS/irockMacApp/MacOSImportedShadowsocksCredentialResolver.swift",
            "apps/irock-macOS/irockMacApp/Info.plist",
            "apps/irock-macOS/irockMacApp/irockMacApp.entitlements",
            "apps/irock-macOS/irockMacTunnelExtension/PacketTunnelProvider.swift",
            "apps/irock-macOS/irockMacTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift",
            "apps/irock-macOS/irockMacTunnelExtension/PacketTunnelAppGroupStoreResolver.swift",
            "apps/irock-macOS/irockMacTunnelExtension/MacOSPacketTunnelSmokeRunner.swift",
            "apps/irock-macOS/irockMacTunnelExtension/MacOSPacketTunnelLoopRunner.swift",
            "apps/irock-macOS/irockMacTunnelExtension/MacOSPlatformTCPDialer.swift",
            "apps/irock-macOS/irockMacTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift",
            "apps/irock-macOS/irockMacTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift",
            "apps/irock-macOS/irockMacTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift",
            "apps/irock-macOS/irockMacTunnelExtension/Info.plist",
            "apps/irock-macOS/irockMacTunnelExtension/irockMacTunnelExtension.entitlements"
        ]
    }

    private func loadPlist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    private func allFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        try allFiles(under: directory).filter { $0.pathExtension == "swift" }
    }

    private func importedModules(in file: URL) throws -> Set<String> {
        let contents = try String(contentsOf: file)
        return Set(contents.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 2, parts[0] == "import" else { return nil }
            return String(parts[1])
        })
    }
}
