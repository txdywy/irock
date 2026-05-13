// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "irock",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "IrockCore", targets: ["IrockCore"]),
        .library(name: "IrockProtocols", targets: ["IrockProtocols"]),
        .library(name: "IrockRouting", targets: ["IrockRouting"]),
        .library(name: "IrockTransport", targets: ["IrockTransport"]),
        .library(name: "IrockStorage", targets: ["IrockStorage"]),
        .library(name: "IrockDiagnostics", targets: ["IrockDiagnostics"]),
        .library(name: "IrockPerformanceKit", targets: ["IrockPerformanceKit"]),
        .library(name: "IrockAppFeature", targets: ["IrockAppFeature"]),
        .library(name: "IrockTunnelCore", targets: ["IrockTunnelCore"]),
        .library(name: "IrockTooling", targets: ["IrockTooling"]),
        .library(name: "IrockNativeHysteria2", targets: ["IrockNativeHysteria2"])
    ],
    targets: [
        .target(
            name: "IrockCore",
            path: "packages/IrockCore/Sources/IrockCore"
        ),
        .testTarget(
            name: "IrockCoreTests",
            dependencies: ["IrockCore"],
            path: "packages/IrockCore/Tests/IrockCoreTests"
        ),
        .target(
            name: "IrockTransport",
            dependencies: ["IrockCore"],
            path: "packages/IrockTransport/Sources/IrockTransport"
        ),
        .testTarget(
            name: "IrockTransportTests",
            dependencies: ["IrockTransport"],
            path: "packages/IrockTransport/Tests/IrockTransportTests"
        ),
        .target(
            name: "IrockProtocols",
            dependencies: ["IrockCore", "IrockTransport"],
            path: "packages/IrockProtocols/Sources/IrockProtocols"
        ),
        .testTarget(
            name: "IrockProtocolsTests",
            dependencies: ["IrockProtocols"],
            path: "packages/IrockProtocols/Tests/IrockProtocolsTests"
        ),
        .target(
            name: "IrockRouting",
            dependencies: ["IrockCore"],
            path: "packages/IrockRouting/Sources/IrockRouting"
        ),
        .testTarget(
            name: "IrockRoutingTests",
            dependencies: ["IrockRouting"],
            path: "packages/IrockRouting/Tests/IrockRoutingTests"
        ),
        .target(
            name: "IrockStorage",
            dependencies: ["IrockCore"],
            path: "packages/IrockStorage/Sources/IrockStorage"
        ),
        .testTarget(
            name: "IrockStorageTests",
            dependencies: ["IrockStorage"],
            path: "packages/IrockStorage/Tests/IrockStorageTests"
        ),
        .target(
            name: "IrockDiagnostics",
            dependencies: ["IrockCore", "IrockProtocols", "IrockRouting", "IrockTransport"],
            path: "packages/IrockDiagnostics/Sources/IrockDiagnostics"
        ),
        .testTarget(
            name: "IrockDiagnosticsTests",
            dependencies: ["IrockDiagnostics", "IrockProtocols", "IrockRouting", "IrockTransport"],
            path: "packages/IrockDiagnostics/Tests/IrockDiagnosticsTests"
        ),
        .target(
            name: "IrockPerformanceKit",
            dependencies: ["IrockCore"],
            path: "packages/IrockPerformanceKit/Sources/IrockPerformanceKit"
        ),
        .testTarget(
            name: "IrockPerformanceKitTests",
            dependencies: ["IrockPerformanceKit"],
            path: "packages/IrockPerformanceKit/Tests/IrockPerformanceKitTests"
        ),
        .target(
            name: "IrockAppFeature",
            dependencies: ["IrockCore", "IrockRouting", "IrockStorage", "IrockDiagnostics", "IrockProtocols"],
            path: "packages/IrockAppFeature/Sources/IrockAppFeature"
        ),
        .testTarget(
            name: "IrockAppFeatureTests",
            dependencies: ["IrockAppFeature"],
            path: "packages/IrockAppFeature/Tests/IrockAppFeatureTests"
        ),
        .target(
            name: "IrockTunnelCore",
            dependencies: ["IrockCore", "IrockRouting", "IrockStorage", "IrockProtocols", "IrockTransport"],
            path: "packages/IrockTunnelCore/Sources/IrockTunnelCore"
        ),
        .testTarget(
            name: "IrockTunnelCoreTests",
            dependencies: ["IrockTunnelCore", "IrockStorage", "IrockProtocols", "IrockTransport"],
            path: "packages/IrockTunnelCore/Tests/IrockTunnelCoreTests"
        ),
        .target(
            name: "IrockTooling",
            path: "packages/IrockTooling/Sources/IrockTooling"
        ),
        .testTarget(
            name: "IrockToolingTests",
            dependencies: ["IrockTooling"],
            path: "packages/IrockTooling/Tests/IrockToolingTests"
        ),
        .systemLibrary(
            name: "CNgtcp2",
            path: "packages/CNgtcp2",
            pkgConfig: "libngtcp2"
        ),
        .systemLibrary(
            name: "CNgtcp2CryptoOpenSSL",
            path: "packages/CNgtcp2CryptoOpenSSL",
            pkgConfig: "libngtcp2_crypto_ossl"
        ),
        .systemLibrary(
            name: "CNghttp3",
            path: "packages/CNghttp3",
            pkgConfig: "libnghttp3"
        ),
        .systemLibrary(
            name: "COpenSSL",
            path: "packages/COpenSSL",
            pkgConfig: "openssl"
        ),
        .target(
            name: "CIrockNativeHysteria2Runtime",
            dependencies: ["CNgtcp2", "CNgtcp2CryptoOpenSSL", "CNghttp3", "COpenSSL"],
            path: "packages/IrockNativeHysteria2/Sources/CIrockNativeHysteria2Runtime",
            publicHeadersPath: "."
        ),
        .target(
            name: "IrockNativeHysteria2",
            dependencies: ["CIrockNativeHysteria2Runtime", "CNgtcp2", "CNgtcp2CryptoOpenSSL", "CNghttp3", "COpenSSL"],
            path: "packages/IrockNativeHysteria2/Sources/IrockNativeHysteria2"
        ),
        .testTarget(
            name: "IrockNativeHysteria2Tests",
            dependencies: ["IrockNativeHysteria2"],
            path: "packages/IrockNativeHysteria2/Tests/IrockNativeHysteria2Tests"
        )
    ]
)
