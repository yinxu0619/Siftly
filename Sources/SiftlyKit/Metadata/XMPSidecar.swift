import Foundation

/// Reads and writes Adobe-style XMP sidecar files, the standard way ratings and
/// color labels move between applications.
///
/// Siftly's own index stays the source of truth (it works on read-only or full
/// cards, and never touches the originals). A sidecar is how a cull gets handed
/// to Lightroom / Capture One / Bridge, which would otherwise have no idea which
/// frames were picked.
///
/// The sidecar sits next to the image with the extension replaced —
/// `DSC001.ARW` -> `DSC001.xmp` — matching Adobe's convention.
public enum XMPSidecar {

    public static func url(for fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension("xmp")
    }

    public static func exists(for fileURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileURL).path)
    }

    // MARK: - Label mapping

    /// XMP stores labels as free text; these are the strings Adobe products use
    /// for their default swatches.
    private static let labelNames: [ColorLabel: String] = [
        .red: "Red", .orange: "Yellow", .yellow: "Yellow",
        .green: "Green", .blue: "Blue", .purple: "Purple", .gray: "Second"
    ]

    private static func label(fromXMP name: String) -> ColorLabel {
        switch name.lowercased() {
        case "red": return .red
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "second", "gray", "grey": return .gray
        default: return .none
        }
    }

    // MARK: - Reading

    /// Parses the rating/label out of an existing sidecar, or nil when there is
    /// no sidecar (or nothing usable in it).
    public static func read(for fileURL: URL) -> FileMark? {
        guard let data = try? Data(contentsOf: url(for: fileURL)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Exposed for testing. XMP allows a property to appear either as an
    /// attribute (`xmp:Rating="4"`) or as a child element
    /// (`<xmp:Rating>4</xmp:Rating>`); writers disagree, so both are accepted.
    static func parse(_ text: String) -> FileMark? {
        var mark = FileMark()
        if let raw = value(of: "xmp:Rating", in: text), let stars = Int(raw.trimmed) {
            // -1 is XMP's "rejected"; treat it as unrated rather than crashing
            // on an out-of-range Rating.
            mark.rating = Rating(rawValue: max(0, min(5, stars))) ?? .none
        }
        if let raw = value(of: "xmp:Label", in: text) {
            mark.label = label(fromXMP: raw.trimmed)
        }
        return mark.isEmpty ? nil : mark
    }

    private static func value(of property: String, in text: String) -> String? {
        if let range = text.range(of: "\(property)=\"([^\"]*)\"", options: .regularExpression) {
            let match = String(text[range])
            if let q = match.range(of: "\"") {
                return String(match[q.upperBound...].dropLast())
            }
        }
        if let range = text.range(
            of: "<\(property)>[^<]*</\(property)>", options: .regularExpression
        ) {
            let match = String(text[range])
            return match
                .replacingOccurrences(of: "<\(property)>", with: "")
                .replacingOccurrences(of: "</\(property)>", with: "")
        }
        return nil
    }

    // MARK: - Writing

    /// Writes (or removes, when the mark is empty) the sidecar for `fileURL`.
    public static func write(_ mark: FileMark, for fileURL: URL) throws {
        let destination = url(for: fileURL)
        guard !mark.isEmpty else {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            return
        }
        try Data(document(for: mark).utf8).write(to: destination, options: .atomic)
    }

    static func document(for mark: FileMark) -> String {
        var properties = ""
        if mark.rating != .none {
            properties += "\n    xmp:Rating=\"\(mark.rating.stars)\""
        }
        if let name = labelNames[mark.label] {
            properties += "\n    xmp:Label=\"\(name)\""
        }
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Siftly">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
           xmlns:xmp="http://ns.adobe.com/xap/1.0/"\(properties)/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
