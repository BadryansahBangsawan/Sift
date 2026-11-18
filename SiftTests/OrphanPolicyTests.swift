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

}
