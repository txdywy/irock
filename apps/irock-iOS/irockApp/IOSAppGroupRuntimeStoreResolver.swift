import Foundation
import IrockStorage

struct IOSAppGroupRuntimeStoreResolver: @unchecked Sendable {
    enum ResolverError: Error, Equatable, Sendable {
        case missingContainer(String)
    }

    let appGroupIdentifier: String
    private let fileManager: FileManager

    init(appGroupIdentifier: String = "group.dev.irock.shared", fileManager: FileManager = .default) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
    }

    func makeRuntimeStoreBundle(logLimit: Int = 200) throws -> RuntimeStoreBundle {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ResolverError.missingContainer(appGroupIdentifier)
        }
        return AppGroupRuntimeStoreDirectory(containerURL: containerURL).makeRuntimeStoreBundle(logLimit: logLimit, fileManager: fileManager)
    }
}
