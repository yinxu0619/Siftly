import Foundation

/// A minimal thread-safe cancellation flag.
///
/// Directory enumeration is synchronous and runs on a detached task that isn't a
/// child of the scan task, so structured cancellation doesn't reach it. This
/// flag is the signal that lets the walk stop early when the user switches
/// cards or ejects one mid-scan.
final class ScanFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
