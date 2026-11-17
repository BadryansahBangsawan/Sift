import XCTest
@testable import PureMac

@MainActor
final class AppStatePreferencesTests: XCTestCase {
    private let keys = [AppState.lastScanDateKey, AppState.confirmBeforeDeleteKey]
    private var saved: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDownWithError() throws {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try super.tearDownWithError()
    }

    func testLastScanDateSurvivesRelaunch() {
        XCTAssertEqual(AppState.lastScanDateKey, "PureMac.LastScanDate")
        XCTAssertNil(AppState(performStartupTasks: false).lastScanDate)

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        AppState(performStartupTasks: false).lastScanDate = date

        XCTAssertEqual(AppState(performStartupTasks: false).lastScanDate, date)
    }

    func testConfirmBeforeDeleteDefaultsOnAndFollowsTheSetting() {
        let state = AppState(performStartupTasks: false)
        XCTAssertEqual(AppState.confirmBeforeDeleteKey, "settings.general.confirmBeforeDelete")
        XCTAssertTrue(state.confirmBeforeDelete)

        UserDefaults.standard.set(false, forKey: AppState.confirmBeforeDeleteKey)
        XCTAssertFalse(state.confirmBeforeDelete)

        UserDefaults.standard.set(true, forKey: AppState.confirmBeforeDeleteKey)
        XCTAssertTrue(state.confirmBeforeDelete)
    }
}
