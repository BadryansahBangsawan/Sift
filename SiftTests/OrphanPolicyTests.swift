import XCTest
@testable import Sift

/// The safety policy decides what may even be offered as a leftover.
final class OrphanPolicyTests: XCTestCase {
    func testMetadataAndSharedWebKitFoldersAreNeverOrphanCandidates() {
        let cases = [
            "\(home)/Library/HTTPStorages/.DS_Store",
            "\(home)/Library/WebKit/.DS_Store",
            "\(home)/Library/WebKit/LocalStorage",
            "\(home)/Library/Caches/org.swift.swiftpm",
        ]
        for path in cases {
            XCTAssertFalse(
                OrphanSafetyPolicy.isSafeCandidate(URL(fileURLWithPath: path)),
                "\(path) is Finder or WebKit metadata, not an app's leftover"
            )
        }
        XCTAssertTrue(
            OrphanSafetyPolicy.isSafeCandidate(URL(fileURLWithPath: "\(home)/Library/Caches/com.example.goneapp"))
        )
    }


    func testOnlyTheExactSharedPathsAreExcluded() {
        XCTAssertTrue(
            OrphanSafetyPolicy.isSafeCandidate(URL(fileURLWithPath: "\(home)/Library/WebKit/com.example.goneapp")),
            "An app's own WebKit folder is still a leftover"
        )
        XCTAssertTrue(
            OrphanSafetyPolicy.isSafeCandidate(URL(fileURLWithPath: "\(home)/Library/Caches/org.swift.swiftpm.extra")),
            "Only the toolchain's own cache is excluded, not a look-alike name"
        )
        XCTAssertTrue(
            OrphanSafetyPolicy.isSafeCandidate(URL(fileURLWithPath: "\(home)/Library/Caches/com.example.goneapp")),
            "Ordinary app caches stay candidates"
        )
    }
}
