import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

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
        // Namespace-aware parsing also accepts single quotes, alternate prefixes
        // and attribute whitespace emitted by other XML writers.
        if let data = text.data(using: .utf8),
           let doc = try? XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever) {
            var mark = FileMark()
            for element in elements(in: doc) {
                for property in (element.attributes ?? []) + (element.children ?? [])
                where property.uri == xmpNamespace {
                    if property.localName == "Rating", let raw = property.stringValue, let stars = Int(raw.trimmed) {
                        mark.rating = Rating(rawValue: max(0, min(5, stars))) ?? .none
                    } else if property.localName == "Label", let raw = property.stringValue {
                        mark.label = label(fromXMP: raw.trimmed)
                    }
                }
            }
            if !mark.isEmpty { return mark }
        }
        // Accept the legacy namespace-free fragments used by older integrations.
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

    private static let xmpNamespace = "http://ns.adobe.com/xap/1.0/"
    private static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    /// Merge only Siftly's rating and label. Foreign editing metadata must
    /// survive both rating changes and clearing a mark. Malformed XML fails
    /// without touching the existing file.
    public static func write(_ mark: FileMark, for fileURL: URL) throws {
        let destination = url(for: fileURL)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            guard mark.rating != .none || mark.label != .none else { return }
            try SafeFileWriter.write(to: destination) { temporary in
                try Data(document(for: mark).utf8).write(to: temporary)
            }
            return
        }
        let data = try Data(contentsOf: destination)
        let doc = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        let descriptions = elements(in: doc).filter { element in
            guard element.localName == "Description", element.uri == rdfNamespace,
                  let parent = element.parent as? XMLElement,
                  parent.localName == "RDF", parent.uri == rdfNamespace else { return false }
            let about = element.attribute(forLocalName: "about", uri: rdfNamespace)?.stringValue
            return about == nil || about == ""
        }
        guard let target = descriptions.first else { throw CocoaError(.fileReadCorruptFile) }
        for description in descriptions {
            let properties = (description.attributes ?? []) + (description.children ?? [])
            for property in properties where property.uri == xmpNamespace &&
                (property.localName == "Rating" || property.localName == "Label") {
                property.detach()
            }
        }
        var prefix = "xmp"
        var suffix = 0
        while let ns = target.resolveNamespace(forName: "\(prefix):Rating"), ns.stringValue != xmpNamespace {
            suffix += 1
            prefix = "xmp\(suffix)"
        }
        if target.resolveNamespace(forName: "\(prefix):Rating") == nil {
            target.addNamespace(XMLNode.namespace(withName: prefix, stringValue: xmpNamespace) as! XMLNode)
        }
        // Explicit zero/empty values clear marks in other applications too.
        target.addAttribute(XMLNode.attribute(withName: "\(prefix):Rating", stringValue: "\(mark.rating.stars)") as! XMLNode)
        target.addAttribute(XMLNode.attribute(withName: "\(prefix):Label", stringValue: labelNames[mark.label] ?? "") as! XMLNode)
        try doc.xmlData(options: .nodePreserveAll).write(to: destination, options: .atomic)
    }

    private static func elements(in node: XMLNode) -> [XMLElement] {
        (node.children ?? []).flatMap { child in
            (child as? XMLElement).map { [$0] + elements(in: $0) } ?? []
        }
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
