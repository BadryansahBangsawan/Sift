import Foundation
import Combine

@MainActor
class SchedulerService: ObservableObject {
    @Published var config: ScheduleConfig {
        didSet { saveConfig() }
    }

    private var timer: Timer?
    private let configKey = "PureMac.ScheduleConfig"
    private var onTrigger: (() async -> Void)?

    init() {
        self.config = Self.restoredConfig(from: UserDefaults.standard.data(forKey: configKey))
    }

    /// The persisted config made safe to run, or the default config when
    /// `data` is missing or unreadable.
    nonisolated static func restoredConfig(from data: Data?, now: Date = Date()) -> ScheduleConfig {
        guard let data, var saved = try? JSONDecoder().decode(ScheduleConfig.self, from: data) else {
            return ScheduleConfig()
        }
        // Refuse to honor an already-past nextRunDate loaded from disk -
        // otherwise an attacker who can write our plist (same-UID foothold)
        // sets nextRunDate to a past timestamp and our first tick after
        // launch triggers autoClean. Reset the schedule so the first run
        // is always at least one full interval after launch.
        if let next = saved.nextRunDate, next.timeIntervalSince(now) < 60 {
            saved.nextRunDate = nil
            saved.lastRunDate = nil
        }
        // Categories this build no longer has (e.g. Trash Bins) are reset
        // while decoding (see ScheduleConfig.init(from:)); withdrawn cases
        // that still decode, such as the app-modifying ones, are reset here,
        // so an older profile keeps its schedule with the default scan set.
        if saved.categoriesToScan.contains(where: { !CleaningCategory.scannable.contains($0) }) {
            saved.categoriesToScan = CleaningCategory.scannable
        }
        return saved
    }

    func setTrigger(_ handler: @escaping () async -> Void) {
        self.onTrigger = handler
    }

    func start() {
        stop()
        guard config.isEnabled else { return }

        updateNextRunDate()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndRun()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateSchedule(interval: ScheduleInterval) {
        config.interval = interval
        updateNextRunDate()
        if config.isEnabled {
            start()
        }
    }

    /// Sets the day and hour a weekly schedule runs and reschedules.
    /// `weekday` uses Calendar numbering (1 = Sunday ... 7 = Saturday).
    func updateWeeklySchedule(weekday: Int, hour: Int) {
        config.weekday = weekday
        config.hour = hour
        updateNextRunDate()
        if config.isEnabled {
            start()
        }
    }

    func toggleEnabled(_ enabled: Bool) {
        config.isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Private

    private func checkAndRun() {
        guard config.isEnabled,
              let nextRun = config.nextRunDate,
              Date() >= nextRun else { return }

        config.lastRunDate = Date()
        updateNextRunDate()

        Task {
            await onTrigger?()
        }
    }

    private func updateNextRunDate() {
        config.nextRunDate = Self.nextRunDate(for: config, now: Date())
    }

    /// When the schedule should run next. Weekly runs at the first
    /// `weekday`/`hour` (on the hour) strictly after `now`; every other
    /// interval runs one interval after the last run, or after `now` if it
    /// never ran.
    nonisolated static func nextRunDate(for config: ScheduleConfig, now: Date,
                                        calendar: Calendar = .current) -> Date {
        if config.interval == .weekly {
            let slot = DateComponents(hour: config.hour, minute: 0, second: 0, weekday: config.weekday)
            if let next = calendar.nextDate(after: now, matching: slot, matchingPolicy: .nextTime) {
                return next
            }
        }
        return (config.lastRunDate ?? now).addingTimeInterval(config.interval.seconds)
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    // MARK: - LaunchAgent Management

    func installLaunchAgent() {
        let plistName = "com.sift.scheduler"
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(plistName).plist")

        guard let appPath = Bundle.main.executablePath else { return }

        let intervalSeconds = Int(config.interval.seconds)
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(plistName)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appPath)</string>
                <string>--scheduled-clean</string>
            </array>
            <key>StartInterval</key>
            <integer>\(intervalSeconds)</integer>
            <key>RunAtLoad</key>
            <false/>
        </dict>
        </plist>
        """

        do {
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
        } catch {
            Logger.shared.log("LaunchAgent plist write failed: \(error.localizedDescription)", level: .error)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", plistPath.path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Logger.shared.log("launchctl load failed: \(error.localizedDescription)", level: .error)
        }
    }

    func uninstallLaunchAgent() {
        let plistName = "com.sift.scheduler"
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(plistName).plist")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", plistPath.path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Logger.shared.log("launchctl unload failed: \(error.localizedDescription)", level: .error)
        }

        do {
            try FileManager.default.removeItem(at: plistPath)
        } catch {
            Logger.shared.log("LaunchAgent plist removal failed: \(error.localizedDescription)", level: .warning)
        }
    }
}

extension ScheduleConfig {
    /// The calendar's standalone name for `weekday` ("Sunday" in English,
    /// "dimanche" in French), for building "Every Sunday" in the UI.
    func weekdaySymbol(calendar: Calendar = .current) -> String {
        let symbols = calendar.standaloneWeekdaySymbols
        return symbols[min(max(weekday, 1), symbols.count) - 1]
    }
}
