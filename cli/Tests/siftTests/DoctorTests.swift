import Foundation
import XCTest
@testable import sift

final class DoctorTests: XCTestCase {
    private func plist(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(body)</dict></plist>
        """.utf8)
    }

    func testSmartStatusIsReadFromDiskutilPlist() {
        let data = plist("""
        <key>SMARTStatus</key><string>Verified</string>
        <key>DeviceIdentifier</key><string>disk1s1</string>
        """)
        XCTAssertEqual(DoctorSupport.parseSmartStatus(data), "Verified")
    }

    func testMissingOrNonStringSmartStatusIsNil() {
        XCTAssertNil(DoctorSupport.parseSmartStatus(plist("<key>DeviceIdentifier</key><string>disk1s1</string>")))
        XCTAssertNil(DoctorSupport.parseSmartStatus(plist("<key>SMARTStatus</key><integer>1</integer>")))
        XCTAssertNil(DoctorSupport.parseSmartStatus(plist("<key>SMARTStatus</key><string>   </string>")))
        XCTAssertNil(DoctorSupport.parseSmartStatus(Data("not a plist".utf8)))
    }

    func testLaunchAgentLabelIsReadFromPlist() {
        let data = plist("""
        <key>Label</key><string>com.example.agent</string>
        <key>ProgramArguments</key><array><string>/usr/bin/true</string></array>
        """)
        XCTAssertEqual(DoctorSupport.launchAgentLabel(data), "com.example.agent")
    }

    func testLaunchAgentLabelRejectsMissingOrBlankLabel() {
        XCTAssertNil(DoctorSupport.launchAgentLabel(plist("<key>RunAtLoad</key><true/>")))
        XCTAssertNil(DoctorSupport.launchAgentLabel(plist("<key>Label</key><string> </string>")))
        XCTAssertNil(DoctorSupport.launchAgentLabel(Data("garbage".utf8)))
    }

    func testOnlyNonZeroStatusCountsAsBroken() {
        XCTAssertTrue(DoctorSupport.isBroken(1))
        XCTAssertTrue(DoctorSupport.isBroken(113))
        XCTAssertFalse(DoctorSupport.isBroken(0))
    }
}
