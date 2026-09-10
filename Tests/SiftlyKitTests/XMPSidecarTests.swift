import XCTest
@testable import SiftlyKit

final class XMPSidecarTests: XCTestCase {
    private func tempFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("siftly-xmp-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    func testSidecarPathReplacesExtensionAdobeStyle() {
        let url = URL(fileURLWithPath: "/Volumes/CARD/DCIM/DSC001.ARW")
        XCTAssertEqual(XMPSidecar.url(for: url).path, "/Volumes/CARD/DCIM/DSC001.xmp")
    }

    func testRoundTripThroughDisk() throws {
        let image = tempFile("DSC001.ARW")
        try FileManager.default.createDirectory(
            at: image.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }

        try XMPSidecar.write(FileMark(rating: .four, label: .red), for: image)
        let read = XMPSidecar.read(for: image)
        XCTAssertEqual(read?.rating, .four)
        XCTAssertEqual(read?.label, .red)
    }

    /// Clearing marks preserves the document and explicitly clears external ratings.
    func testWritingAnEmptyMarkClearsPropertiesAndKeepsTheSidecar() throws {
        let image = tempFile("DSC002.ARW")
        try FileManager.default.createDirectory(
            at: image.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }

        try XMPSidecar.write(FileMark(rating: .three), for: image)
        XCTAssertTrue(XMPSidecar.exists(for: image))
        try XMPSidecar.write(FileMark(), for: image)
        XCTAssertTrue(XMPSidecar.exists(for: image))
        XCTAssertNil(XMPSidecar.read(for: image))
    }

    /// Writers disagree on whether XMP properties are attributes or elements,
    /// so both spellings have to parse.
    func testParsesAttributeAndElementForms() {
        let asAttributes = """
        <rdf:Description rdf:about="" xmp:Rating="5" xmp:Label="Blue"/>
        """
        XCTAssertEqual(XMPSidecar.parse(asAttributes)?.rating, .five)
        XCTAssertEqual(XMPSidecar.parse(asAttributes)?.label, .blue)

        let asElements = """
        <rdf:Description rdf:about="">
          <xmp:Rating>2</xmp:Rating>
          <xmp:Label>Green</xmp:Label>
        </rdf:Description>
        """
        XCTAssertEqual(XMPSidecar.parse(asElements)?.rating, .two)
        XCTAssertEqual(XMPSidecar.parse(asElements)?.label, .green)
    }

    /// XMP uses -1 for "rejected" and nothing stops a file claiming 9 stars;
    /// neither may produce a nil Rating or trap.
    func testOutOfRangeRatingsAreClamped() {
        XCTAssertNil(XMPSidecar.parse(#"<x xmp:Rating="-1"/>"#))          // clamps to 0 -> empty
        XCTAssertEqual(XMPSidecar.parse(#"<x xmp:Rating="9"/>"#)?.rating, .five)
    }

    func testUnknownLabelDoesNotBecomeAMark() {
        XCTAssertNil(XMPSidecar.parse(#"<x xmp:Label="Chartreuse"/>"#))
        XCTAssertNil(XMPSidecar.parse("<x/>"))
    }

    func testAlternateNamespacesAndElementPropertiesAreUpdatedWithoutDuplicates() throws {
        let image = tempFile("foreign.ARW")
        try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }
        let xml = """
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:other="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/">
          <rdf:Description rdf:about="" crs:Exposure2012="1.25"><other:Rating>2</other:Rating><other:Label>Blue</other:Label></rdf:Description>
        </rdf:RDF>
        """
        try Data(xml.utf8).write(to: XMPSidecar.url(for: image))
        try XMPSidecar.write(FileMark(rating: .five, label: .red), for: image)
        let result = try String(contentsOf: XMPSidecar.url(for: image))
        XCTAssertFalse(result.contains("other:Rating"))
        XCTAssertFalse(result.contains("other:Label"))
        XCTAssertTrue(result.contains("crs:Exposure2012"))
        XCTAssertEqual(XMPSidecar.read(for: image)?.rating, .five)
        XCTAssertEqual(XMPSidecar.read(for: image)?.label, .red)
    }

    func testMalformedSidecarIsNotOverwritten() throws {
        let image = tempFile("broken.ARW")
        try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }
        let original = Data("<broken".utf8)
        let url = XMPSidecar.url(for: image)
        try original.write(to: url)
        XCTAssertThrowsError(try XMPSidecar.write(FileMark(rating: .five), for: image))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testDocumentOmitsPropertiesThatAreNotSet() {
        let doc = XMPSidecar.document(for: FileMark(rating: .three))
        XCTAssertTrue(doc.contains(#"xmp:Rating="3""#))
        XCTAssertFalse(doc.contains("xmp:Label"))
    }
}
