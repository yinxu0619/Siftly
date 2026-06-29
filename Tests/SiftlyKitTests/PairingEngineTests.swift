import XCTest
@testable import SiftlyKit

final class PairingEngineTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Volumes/CARD/DCIM/100MSDCF")

    private func file(_ name: String) -> MediaFile {
        MediaFile(url: dir.appendingPathComponent(name))
    }

    func testBasicRAWJPGPair() {
        let arw = file("DSC001.ARW")
        let jpg = file("DSC001.JPG")
        let result = PairingEngine().computePairs([arw, jpg], rule: .default)
        XCTAssertEqual(result.partners(of: arw.url), [jpg.url])
        XCTAssertEqual(result.partners(of: jpg.url), [arw.url])
    }

    func testSingleFileHasNoPair() {
        let arw = file("DSC001.ARW")
        let result = PairingEngine().computePairs([arw], rule: .default)
        XCTAssertTrue(result.partners(of: arw.url).isEmpty)
        XCTAssertFalse(result.isPaired(arw.url))
    }

    func testSameNameDifferentDirectoryDoesNotPair() {
        let arw = MediaFile(url: URL(fileURLWithPath: "/Volumes/CARD/A/DSC001.ARW"))
        let jpg = MediaFile(url: URL(fileURLWithPath: "/Volumes/CARD/B/DSC001.JPG"))
        let result = PairingEngine().computePairs([arw, jpg], rule: .default)
        XCTAssertTrue(result.partners(of: arw.url).isEmpty)
        XCTAssertTrue(result.partners(of: jpg.url).isEmpty)
    }

    func testMultiSuffixPairing() {
        let arw = file("DSC001.ARW")
        let jpg = file("DSC001.JPG")
        let jpeg = file("DSC001.JPEG")
        let result = PairingEngine().computePairs([arw, jpg, jpeg], rule: .default)
        XCTAssertEqual(result.partners(of: arw.url), [jpg.url, jpeg.url])
    }

    func testCaseInsensitiveBaseName() {
        let arw = file("dsc001.arw")
        let jpg = file("DSC001.JPG")
        let result = PairingEngine().computePairs([arw, jpg], rule: .default)
        XCTAssertEqual(result.partners(of: arw.url), [jpg.url])
    }

    func testDifferentGroupsDoNotPair() {
        let rule = PairingRule(name: "test", groups: [["arw"], ["jpg"]])
        let arw = file("DSC001.ARW")
        let jpg = file("DSC001.JPG")
        let result = PairingEngine().computePairs([arw, jpg], rule: rule)
        XCTAssertTrue(result.partners(of: arw.url).isEmpty)
    }

    func testUniversalRulePairsOtherBrands() {
        // Default (universal) rule should pair Canon/Nikon/Fuji RAW with JPG.
        let cr3 = file("IMG_0001.CR3")
        let cr3jpg = file("IMG_0001.JPG")
        let nef = file("DSC_0002.NEF")
        let nefjpg = file("DSC_0002.JPG")
        let raf = file("DSCF0003.RAF")
        let rafjpg = file("DSCF0003.JPG")
        let result = PairingEngine().computePairs(
            [cr3, cr3jpg, nef, nefjpg, raf, rafjpg], rule: .default
        )
        XCTAssertEqual(result.partners(of: cr3.url), [cr3jpg.url])
        XCTAssertEqual(result.partners(of: nef.url), [nefjpg.url])
        XCTAssertEqual(result.partners(of: raf.url), [rafjpg.url])
    }

    func testCanonPresetDoesNotPairNikon() {
        let nef = file("DSC_0002.NEF")
        let jpg = file("DSC_0002.JPG")
        // Canon preset only knows CR2/CR3 — a NEF should not pair under it.
        let result = PairingEngine().computePairs([nef, jpg], rule: .canon)
        XCTAssertTrue(result.partners(of: nef.url).isEmpty)
    }

    func testCrossCardPairingByName() {
        // Dual-slot: ARW on card B, JPG on card A (different volumes/dirs).
        let jpgCardA = MediaFile(url: URL(fileURLWithPath: "/Volumes/CARD_A/DCIM/100MSDCF/DSC00370.JPG"))
        let arwCardB = MediaFile(url: URL(fileURLWithPath: "/Volumes/CARD_B/DCIM/100MSDCF/DSC00370.ARW"))

        // Without cross-location, different directories must NOT pair.
        let single = PairingEngine().computePairs([jpgCardA, arwCardB], rule: .default)
        XCTAssertTrue(single.partners(of: arwCardB.url).isEmpty)

        // With cross-location enabled, they pair by base name across cards.
        var crossRule = PairingRule.default
        crossRule.crossLocation = true
        let cross = PairingEngine().computePairs([jpgCardA, arwCardB], rule: crossRule)
        XCTAssertEqual(cross.partners(of: arwCardB.url), [jpgCardA.url])
        XCTAssertEqual(cross.partners(of: jpgCardA.url), [arwCardB.url])
    }
}
