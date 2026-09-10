import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Publishes a complete file on the same volume without replacing any existing
/// directory entry, including a dangling symlink. Failed work stays private.
enum SafeFileWriter {
    static func write(to destination: URL, body: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".siftly-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent(destination.lastPathComponent)
        try body(temporary)
        #if canImport(Darwin)
        let result = temporary.path.withCString { source in
            destination.path.withCString { target in
                renamex_np(source, target, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            if errno == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        #else
        try fm.moveItem(at: temporary, to: destination)
        #endif
    }
}
