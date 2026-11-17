import AppKit

/// Blocks removing an app while it is running, and can ask it to quit.
///
/// Usage from the uninstall flow:
///
///     let appGuard = RunningAppGuard(app: app)
///     if !appGuard.canRemove {
///         appGuard.requestQuit()   // polite quit; the app may show a save prompt
///     }
///
/// The running check is injectable for tests; `requestQuit()` always talks to
/// the real running applications.
struct RunningAppGuard {
    /// Returns whether an app with this bundle identifier or bundle URL is running.
    typealias RunningCheck = (_ bundleIdentifier: String, _ appURL: URL?) -> Bool

    let bundleIdentifier: String
    let appURL: URL?
    private let runningCheck: RunningCheck

    init(bundleIdentifier: String, appURL: URL? = nil,
         isRunning: @escaping RunningCheck = RunningAppGuard.systemIsRunning) {
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.runningCheck = isRunning
    }

    init(app: InstalledApp, isRunning: @escaping RunningCheck = RunningAppGuard.systemIsRunning) {
        self.init(bundleIdentifier: app.bundleIdentifier, appURL: app.path, isRunning: isRunning)
    }

    /// Re-checked on every read, so it reflects the app quitting after `requestQuit()`.
    var isRunning: Bool { runningCheck(bundleIdentifier, appURL) }

    /// Removal is blocked while the app is running.
    var canRemove: Bool { !isRunning }

    /// Asks every running instance to quit the normal way (like Cmd-Q), never
    /// force-terminating. Returns true if at least one instance accepted the
    /// request; the app may still refuse later (e.g. an unsaved-changes prompt),
    /// so re-check `isRunning` before removing.
    @discardableResult
    func requestQuit() -> Bool {
        Self.runningInstances(bundleIdentifier: bundleIdentifier, appURL: appURL)
            .map { $0.terminate() }
            .contains(true)
    }

    static func systemIsRunning(bundleIdentifier: String, appURL: URL?) -> Bool {
        !runningInstances(bundleIdentifier: bundleIdentifier, appURL: appURL).isEmpty
    }

    /// Matches on bundle identifier, or on bundle location for apps whose
    /// identifier was a fallback name (see `AppInfoFetcher.loadAppInfo`).
    private static func runningInstances(bundleIdentifier: String, appURL: URL?) -> [NSRunningApplication] {
        let appPath = appURL?.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.filter { running in
            if running.bundleIdentifier == bundleIdentifier { return true }
            guard let appPath, let runningPath = running.bundleURL?.standardizedFileURL.path else { return false }
            return runningPath == appPath
        }
    }
}
