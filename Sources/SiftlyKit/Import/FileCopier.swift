import Foundation
import CryptoKit

public enum ImportError: LocalizedError, Equatable {
    case cannotReadSource(String)
    case cannotCreateDestination(String)
    case verificationFailed(String)
    case notEnoughSpace(needed: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .cannotReadSource(let name):
            return L10n.Error.importCannotRead(name)
        case .cannotCreateDestination(let name):
            return L10n.Error.importCannotWrite(name)
        case .verificationFailed(let name):
            return L10n.Error.importVerifyFailed(name)
        case .notEnoughSpace(let needed, let available):
            let f = ByteCountFormatter()
            f.countStyle = .file
            return L10n.Error.importNoSpace(
                f.string(fromByteCount: needed), f.string(fromByteCount: available)
            )
        }
    }
}

/// Copies files off a card with optional checksum verification.
///
/// The copy is streamed and hashed in a single pass, so verifying costs one
/// extra read of the *destination* rather than a second read of the card — the
/// card is the slow device, and re-reading it would roughly double import time.
public enum FileCopier {
    /// 4 MB: large enough to keep a card reader streaming, small enough that
    /// progress stays smooth and memory flat.
    static let chunkSize = 4 * 1024 * 1024

    /// Copies `source` to `destination`, creating parent folders as needed.
    /// Returns the SHA-256 of the bytes written.
    ///
    /// `onBytes` reports incremental progress; returning `false` aborts the copy
    /// and removes the partial file.
    @discardableResult
    public static func copy(
        from source: URL,
        to destination: URL,
        onBytes: (Int64) -> Bool = { _ in true }
    ) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        guard let input = try? FileHandle(forReadingFrom: source) else {
            throw ImportError.cannotReadSource(source.lastPathComponent)
        }
        defer { try? input.close() }

        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw ImportError.cannotCreateDestination(destination.lastPathComponent)
        }
        guard let output = try? FileHandle(forWritingTo: destination) else {
            throw ImportError.cannotCreateDestination(destination.lastPathComponent)
        }

        var hasher = SHA256()
        var cancelled = false
        do {
            while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
                hasher.update(data: chunk)
                if !onBytes(Int64(chunk.count)) { cancelled = true; break }
            }
            try output.close()
        } catch {
            try? output.close()
            try? fm.removeItem(at: destination)
            throw error
        }

        if cancelled {
            // Never leave a half-written file behind for the user to mistake
            // for a complete import.
            try? fm.removeItem(at: destination)
            throw CancellationError()
        }

        // Carry the capture timestamp across, so the copy sorts correctly and a
        // re-import lands in the same dated folder.
        if let modified = try? source.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate {
            try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: destination.path)
        }

        return digestString(hasher.finalize())
    }

    /// SHA-256 of a file on disk, read in chunks so large videos don't balloon
    /// memory.
    public static func checksum(of url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ImportError.cannotReadSource(url.lastPathComponent)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return digestString(hasher.finalize())
    }

    private static func digestString(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Free bytes at `url`'s volume, used to fail an import before it starts
    /// rather than half way through.
    public static func availableCapacity(at url: URL) -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
