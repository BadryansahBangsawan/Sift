import Combine
import Foundation

/// What the settings UI and the menu command need from an updater. Tests use
/// a fake; the app uses `SparkleUpdaterBridge`, so views never import Sparkle.
@MainActor
protocol UpdaterBridge: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    /// Called when the updater's state changes (KVO from Sparkle).
    var onChange: (() -> Void)? { get set }
    func checkForUpdates()
}

/// Version shown in Settings. Read from the bundle so it follows the build.
enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

/// Observable facade over an `UpdaterBridge`.
@MainActor
final class AppUpdateController: ObservableObject {
    private let bridge: UpdaterBridge

    init(bridge: UpdaterBridge) {
        self.bridge = bridge
        bridge.onChange = { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var canCheckForUpdates: Bool { bridge.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { bridge.automaticallyChecksForUpdates }
        set {
            bridge.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { bridge.automaticallyDownloadsUpdates }
        set {
            // Sparkle disallows automatic downloads without automatic checks;
            // the UI disables the toggle, and this keeps programmatic writes
            // from fighting it.
            guard bridge.automaticallyChecksForUpdates else { return }
            bridge.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    /// The download toggle is only meaningful while automatic checks are on.
    var canAutomaticallyDownloadUpdates: Bool { bridge.automaticallyChecksForUpdates }

    func checkForUpdates() {
        bridge.checkForUpdates()
    }
}

/// Used when the app must not start a real updater (the XCTest host).
@MainActor
final class InertUpdaterBridge: UpdaterBridge {
    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var onChange: (() -> Void)?

    func checkForUpdates() {}
}
