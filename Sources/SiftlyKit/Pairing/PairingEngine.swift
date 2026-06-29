import Foundation

/// Result of pairing: for each file, the set of its partner files.
public struct PairingResult {
    public private(set) var partners: [URL: Set<URL>]

    public static let empty = PairingResult(partners: [:])

    public init(partners: [URL: Set<URL>]) {
        self.partners = partners
    }

    public func partners(of url: URL) -> Set<URL> {
        partners[url] ?? []
    }

    public func isPaired(_ url: URL) -> Bool {
        !(partners[url]?.isEmpty ?? true)
    }
}

/// Computes file pairings in O(n) using a single bucketing pass.
public struct PairingEngine {
    public init() {}

    public func computePairs(_ files: [MediaFile], rule: PairingRule) -> PairingResult {
        // Map extension -> group index for O(1) lookup.
        var extToGroup: [String: Int] = [:]
        for (index, group) in rule.groups.enumerated() {
            for ext in group { extToGroup[ext] = index }
        }

        // Bucket files by (directory, group, base name). Using a NUL separator
        // avoids collisions between path components.
        var buckets: [String: [URL]] = [:]
        for file in files {
            guard let groupIndex = extToGroup[file.ext] else { continue }
            let base = rule.caseInsensitiveName ? file.baseName.lowercased() : file.baseName
            // Cross-location pairing ignores the directory so dual-slot RAW/JPG
            // on separate cards (same base name) pair together.
            let locationKey = rule.crossLocation ? "" : file.directory.path
            let key = "\(locationKey)\u{0}\(groupIndex)\u{0}\(base)"
            buckets[key, default: []].append(file.url)
        }

        var partners: [URL: Set<URL>] = [:]
        for (_, urls) in buckets where urls.count > 1 {
            let full = Set(urls)
            for url in urls {
                partners[url] = full.subtracting([url])
            }
        }
        return PairingResult(partners: partners)
    }
}
