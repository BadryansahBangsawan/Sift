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

/// Observable facade over an `UpdaterBridge`.
@MainActor
final class AppUpdateController: ObservableObject {
    private let bridge: UpdaterBridge

    init(bridge: UpdaterBridge) {
        self.bridge = bridge
    }

    var canCheckForUpdates: Bool { false }

    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { _ = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { false }
        set { _ = newValue }
    }

    /// The download toggle is only meaningful while automatic checks are on.
    var canAutomaticallyDownloadUpdates: Bool { false }

    func checkForUpdates() {}
}
