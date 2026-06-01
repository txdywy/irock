import Foundation
import IrockStorage

public struct PacketTunnelAppGroupStoreResolver: Sendable {
    public enum ResolverError: Error, Equatable, Sendable {
        case missingContainer(String)
    }

    public let appGroupIdentifier: String
    private let fileManager: FileManager

    public init(appGroupIdentifier: String = "group.dev.irock.shared", fileManager: FileManager = .default) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
    }

    public func makeRuntimeStoreBundle(logLimit: Int = 200) throws -> RuntimeStoreBundle {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ResolverError.missingContainer(appGroupIdentifier)
        }
        return AppGroupRuntimeStoreDirectory(containerURL: containerURL).makeRuntimeStoreBundle(logLimit: logLimit, fileManager: fileManager)
    }
}
