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

    /// Clearing every mark should remove the sidecar, not leave an empty one
    /// that other apps would read as "rated 0".
    func testWritingAnEmptyMarkRemovesTheSidecar() throws {
        let image = tempFile("DSC002.ARW")
        try FileManager.default.createDirectory(
            at: image.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }

        try XMPSidecar.write(FileMark(rating: .three), for: image)
        XCTAssertTrue(XMPSidecar.exists(for: image))
        try XMPSidecar.write(FileMark(), for: image)
        XCTAssertFalse(XMPSidecar.exists(for: image))
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

    func testDocumentOmitsPropertiesThatAreNotSet() {
        let doc = XMPSidecar.document(for: FileMark(rating: .three))
        XCTAssertTrue(doc.contains(#"xmp:Rating="3""#))
        XCTAssertFalse(doc.contains("xmp:Label"))
    }
}
