import Darwin
import Foundation

final class MacOSUserModeTunDevice: @unchecked Sendable {
    private static let ctlIOCGInfo = UInt(0xc0000000) | UInt(MemoryLayout<ctl_info>.size & 0x1fff) << 16 | UInt(UInt8(ascii: "N")) << 8 | 3

    private let lock = NSLock()
    private var descriptor: Int32?
    let fileDescriptor: Int32
    let interfaceName: String

    init(unit: UInt32 = 0) throws {
        let descriptor = Darwin.socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)
        guard descriptor >= 0 else {
            throw UserModeTunDeviceError.openFailed
        }

        do {
            var info = ctl_info()
            try Self.copyControlName("com.apple.net.utun_control", into: &info)
            guard Darwin.ioctl(descriptor, Self.ctlIOCGInfo, &info) == 0 else {
                throw UserModeTunDeviceError.openFailed
            }

            var address = sockaddr_ctl()
            address.sc_len = UInt8(MemoryLayout<sockaddr_ctl>.size)
            address.sc_family = sa_family_t(AF_SYSTEM)
            address.ss_sysaddr = UInt16(AF_SYS_CONTROL)
            address.sc_id = info.ctl_id
            address.sc_unit = unit

            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_ctl>.size))
                }
            }
            guard connected == 0 else {
                throw UserModeTunDeviceError.openFailed
            }

            var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            var nameLength = socklen_t(nameBuffer.count)
            guard Darwin.getsockopt(descriptor, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &nameBuffer, &nameLength) == 0 else {
                throw UserModeTunDeviceError.openFailed
            }

            self.descriptor = descriptor
            self.fileDescriptor = descriptor
            self.interfaceName = String(cString: nameBuffer)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit {
        close()
    }

    func close() {
        lock.lock()
        let descriptor = descriptor
        self.descriptor = nil
        lock.unlock()
        if let descriptor {
            Darwin.close(descriptor)
        }
    }

    private static func copyControlName(_ name: String, into info: inout ctl_info) throws {
        let bytes = Array(name.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: info.ctl_name) else {
            throw UserModeTunDeviceError.openFailed
        }
        withUnsafeMutableBytes(of: &info.ctl_name) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: bytes)
        }
    }
}

enum UserModeTunDeviceError: Error {
    case openFailed
}
