import XCTest
@testable import PureMac

final class SystemInfoTests: XCTestCase {
    func testModelNameFromIdentifierMapsKnownFamilies() {
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "MacBookPro18,3"), "MacBook Pro")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "MacBookAir10,1"), "MacBook Air")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "MacBook10,1"), "MacBook")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "Macmini9,1"), "Mac mini")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "iMac21,1"), "iMac")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "iMacPro1,1"), "iMac Pro")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "MacPro7,1"), "Mac Pro")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "Mac16,12"), "Mac")
    }

    func testModelNameFallsBackToMacForUnknownOrMissingIdentifier() {
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: nil), "Mac")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: ""), "Mac")
        XCTAssertEqual(SystemInfo.modelName(productName: nil, modelIdentifier: "VirtualMac2,1"), "Mac")
    }

    func testModelNamePrefersProductNameWithoutItsDetailParenthetical() {
        XCTAssertEqual(
            SystemInfo.modelName(productName: "MacBook Air (13-inch, M4, 2025)", modelIdentifier: "Mac16,12"),
            "MacBook Air"
        )
        XCTAssertEqual(SystemInfo.modelName(productName: "Mac Studio", modelIdentifier: "Mac13,1"), "Mac Studio")
        XCTAssertEqual(
            SystemInfo.modelName(productName: "   ", modelIdentifier: "Macmini9,1"),
            "Mac mini",
            "A blank product name falls back to the identifier"
        )
    }

    func testProductNameDecodesNulTerminatedRegistryData() {
        let data = Data("MacBook Air (13-inch, M4, 2025)".utf8) + Data([0])
        XCTAssertEqual(SystemInfo.productName(fromRegistryData: data), "MacBook Air (13-inch, M4, 2025)")
        XCTAssertNil(SystemInfo.productName(fromRegistryData: Data([0])))
        XCTAssertNil(SystemInfo.productName(fromRegistryData: Data()))
    }

    func testMacOSVersionStringOmitsZeroPatch() {
        XCTAssertEqual(
            SystemInfo.macOSVersionString(OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)),
            "macOS 26.2"
        )
        XCTAssertEqual(
            SystemInfo.macOSVersionString(OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 1)),
            "macOS 15.6.1"
        )
    }

    func testLiveValuesAreNonEmpty() {
        XCTAssertFalse(SystemInfo.modelName.isEmpty)
        XCTAssertTrue(SystemInfo.macOSVersion.hasPrefix("macOS "))
    }
}
