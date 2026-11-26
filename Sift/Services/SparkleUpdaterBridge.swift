import Combine
import Sparkle

/// The only file that knows about Sparkle. Owns the standard updater
/// controller for the app's lifetime and republishes its KVO state.
@MainActor
final class SparkleUpdaterBridge: NSObject, UpdaterBridge {
    var onChange: (() -> Void)?

    private let controller: SPUStandardUpdaterController
    private var observations: Set<AnyCancellable> = []

    init(startingUpdater: Bool) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] _ in self?.onChange?() }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in self?.onChange?() }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] _ in self?.onChange?() }
            .store(in: &observations)
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set {
            guard controller.updater.automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
