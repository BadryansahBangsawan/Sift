import Foundation
import Darwin

/// Lightweight live system telemetry for the menu-bar monitor (CPU / memory /
/// disk). Each visible consumer owns a sampling request. The fastest request
/// determines the interval; releasing the last request stops sampling. The
/// enabled menu-bar monitor can continue independently of the Performance page.
///
/// All readings use public Mach / Foundation APIs (no sandbox-incompatible
/// shelling out), so this stays valid under the app's hardened-runtime,
/// notarized build.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    /// Raw CPU tick counters as `host_statistics(HOST_CPU_LOAD_INFO)` reports them.
    struct CPUTicks: Equatable, Sendable {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64

        var total: UInt64 { user &+ system &+ idle &+ nice }
    }

    /// Share of CPU time between two samples, each 0.0 - 1.0. Nice time is
    /// counted as user time, as Activity Monitor does.
    struct CPULoad: Equatable, Sendable {
        var user: Double
        var system: Double
        var idle: Double

        var total: Double { min(1, user + system) }
    }

    /// Memory split in bytes, from `host_statistics64(HOST_VM_INFO64)`.
    struct MemoryBreakdown: Equatable, Sendable {
        var wired: Int64
        var active: Int64
        var compressed: Int64
        var free: Int64

        /// Active + wired + compressed: what `memoryUsed` reports.
        var used: Int64 { active + wired + compressed }
    }

    /// Number of samples `cpuHistory` keeps.
    nonisolated static let cpuHistoryLimit = 30

    /// 0.0 - 1.0 fraction of total CPU time spent non-idle since the last sample.
    @Published private(set) var cpuUsage: Double = 0
    /// 0.0 - 1.0 fraction of CPU time spent in user code (including nice) since the last sample.
    @Published private(set) var cpuUser: Double = 0
    /// 0.0 - 1.0 fraction of CPU time spent in the kernel since the last sample.
    @Published private(set) var cpuSystem: Double = 0
    /// 0.0 - 1.0 fraction of CPU time spent idle since the last sample.
    @Published private(set) var cpuIdle: Double = 0
    /// The last `cpuHistoryLimit` values of `cpuUsage`, oldest first. Kept
    /// across pauses; it only grows while sampling.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: Int64 = 0
    @Published private(set) var memoryTotal: Int64 = 0
    /// Wired memory in bytes: kernel memory that cannot be paged out.
    @Published private(set) var memoryWired: Int64 = 0
    /// Active memory in bytes: pages in recent use.
    @Published private(set) var memoryActive: Int64 = 0
    /// Compressed memory in bytes: pages the compressor holds.
    @Published private(set) var memoryCompressed: Int64 = 0
    /// Free memory in bytes: pages not in use at all.
    @Published private(set) var memoryFree: Int64 = 0
    @Published private(set) var diskUsed: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0

    var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    var diskFraction: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }

    private var timer: Timer?
    /// Previous CPU tick counters, kept to turn the kernel's monotonically
    /// increasing totals into a per-interval delta.
    private var previousTicks: CPUTicks?
    // Idempotent subscriptions prevent repeated view activation from leaking a
    // timer. Each consumer releases only its own request.
    private var requests: [UUID: TimeInterval] = [:]
    private var timerGeneration = UUID()
    private let sampleAction: (() -> Void)?
    private(set) var samplingInterval: TimeInterval?
    var isSampling: Bool { timer != nil }

    init(sampleAction: (() -> Void)? = nil) {
        self.sampleAction = sampleAction
    }

    func start(owner: UUID, interval: TimeInterval = 2.0) {
        requests[owner] = interval.isFinite ? max(0.1, interval) : 2
        configureTimer()
    }

    func stop(owner: UUID) {
        requests.removeValue(forKey: owner)
        configureTimer()
    }

    private func configureTimer() {
        let interval = requests.values.min()
        guard interval != samplingInterval else { return }
        let wasStopped = timer == nil
        timer?.invalidate()
        timer = nil
        timerGeneration = UUID()
        samplingInterval = interval
        guard let interval else {
            previousTicks = nil
            return
        }
        if wasStopped {
            memoryTotal = Int64(ProcessInfo.processInfo.physicalMemory)
            cpuUsage = 0
            cpuUser = 0
            cpuSystem = 0
            cpuIdle = 0
            sample()
        }
        let generation = timerGeneration
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.timerGeneration == generation, !self.requests.isEmpty else { return }
                self.sample()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        if let sampleAction {
            sampleAction()
        } else {
            sampleCPU()
            sampleMemory()
            sampleDisk()
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - CPU

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let ticks = CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        defer { previousTicks = ticks }
        guard let previousTicks, let load = Self.cpuLoad(from: previousTicks, to: ticks) else { return }
        cpuUser = load.user
        cpuSystem = load.system
        cpuIdle = load.idle
        cpuUsage = load.total
        cpuHistory = Self.appendingHistory(load.total, to: cpuHistory)
    }

    /// CPU share between two tick samples. Nil when there is no baseline yet
    /// (`previous` is all zeros) or no ticks elapsed.
    nonisolated static func cpuLoad(from previous: CPUTicks, to current: CPUTicks) -> CPULoad? {
        guard previous.total != 0, current.total > previous.total else { return nil }
        let totalDelta = Double(current.total &- previous.total)
        func share(_ now: UInt64, _ before: UInt64) -> Double {
            min(1, max(0, Double(now &- before) / totalDelta))
        }
        return CPULoad(
            user: share(current.user &+ current.nice, previous.user &+ previous.nice),
            system: share(current.system, previous.system),
            idle: share(current.idle, previous.idle)
        )
    }

    /// `history` plus `value`, trimmed to the newest `limit` entries.
    nonisolated static func appendingHistory(
        _ value: Double,
        to history: [Double],
        limit: Int = cpuHistoryLimit
    ) -> [Double] {
        Array((history + [value]).suffix(limit))
    }

    // MARK: - Memory

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let breakdown = Self.memoryBreakdown(
            wireCount: UInt64(stats.wire_count),
            activeCount: UInt64(stats.active_count),
            compressorPageCount: UInt64(stats.compressor_page_count),
            freeCount: UInt64(stats.free_count),
            pageSize: UInt64(vm_kernel_page_size)
        )
        memoryWired = breakdown.wired
        memoryActive = breakdown.active
        memoryCompressed = breakdown.compressed
        memoryFree = breakdown.free
        memoryUsed = breakdown.used
    }

    /// Page counts times page size. "App Memory" + wired + compressed mirrors
    /// what Activity Monitor counts as memory pressure; free + purgeable + most
    /// file-backed pages are not pressure, so `used` excludes them.
    nonisolated static func memoryBreakdown(
        wireCount: UInt64,
        activeCount: UInt64,
        compressorPageCount: UInt64,
        freeCount: UInt64,
        pageSize: UInt64
    ) -> MemoryBreakdown {
        MemoryBreakdown(
            wired: Int64(wireCount * pageSize),
            active: Int64(activeCount * pageSize),
            compressed: Int64(compressorPageCount * pageSize),
            free: Int64(freeCount * pageSize)
        )
    }

    // MARK: - Disk

    private func sampleDisk() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return }

        if let total = values.volumeTotalCapacity {
            diskTotal = Int64(total)
        }
        if let available = values.volumeAvailableCapacityForImportantUsage {
            diskUsed = max(0, diskTotal - available)
        }
    }
}
