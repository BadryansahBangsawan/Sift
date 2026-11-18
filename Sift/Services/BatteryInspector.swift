import Foundation
import IOKit
import IOKit.ps

/// Battery state as the Performance page shows it.
///
/// Every field except `isInstalled` is optional on purpose: `pmset` and the
/// IORegistry are two independent sources and either can be missing a value
/// (desktop Macs have no battery, some VMs expose no cycle count). A field we
/// could not read is reported as unknown rather than as zero.
struct BatteryStatus: Sendable {
    var isInstalled: Bool
    var chargePercent: Int?
    var isCharging: Bool?
    var cycleCount: Int?
    var maxCapacityMAh: Int?
    var designCapacityMAh: Int?
    /// `maxCapacity / designCapacity`, nil when either capacity is unknown or
    /// the design capacity is zero (a divide-by-zero, not a 0% battery).
    var healthPercent: Int?
    /// True when drawing from an adapter, false on battery, nil when unknown.
    var isOnACPower: Bool?
    /// Minutes until fully charged. Nil while macOS is still estimating, when
    /// not charging, or when the power source does not report it.
    var minutesToFull: Int?

    static let notInstalled = BatteryStatus(isInstalled: false)
}

/// Reads the battery from `pmset` and the IORegistry.
///
/// No logging here: this type runs off the main actor and `Logger.shared` is
/// main-actor isolated, so a log call would either warn or break isolation.
final class BatteryInspector {
    func inspect() async -> BatteryStatus {
        await Task.detached(priority: .utility) {
            var status = BatteryStatus.notInstalled
            let registry = Self.readPowerSourceProperties()
            let pmset = await Self.readPmsetOutput()

            // IORegistry is the authoritative source for whether a battery
            // exists; `pmset -g batt` on a desktop prints "AC Power" only.
            if let installed = registry["BatteryInstalled"] as? Bool, installed {
                status.isInstalled = true
            } else if registry.isEmpty, let pmset, pmset.contains("InternalBattery") {
                status.isInstalled = true
            } else {
                status.isInstalled = registry["BatteryInstalled"] as? Bool ?? false
            }
            guard status.isInstalled else { return BatteryStatus.notInstalled }

            // `CurrentCapacity`/`MaxCapacity` are percentages on modern Macs
            // (100 = full), not mAh — verified on this machine: MaxCapacity is
            // 100 while DesignCapacity is 4629. The mAh figures live in the
            // AppleRaw* keys, and health must only ever divide mAh by mAh.
            let currentPercentCapacity = Self.integer(registry["CurrentCapacity"])
            let maxPercentCapacity = Self.integer(registry["MaxCapacity"])
            let currentMAh = Self.integer(registry["AppleRawCurrentCapacity"])
            let maxMAh = Self.integer(registry["AppleRawMaxCapacity"])
                ?? Self.integer(registry["NominalChargeCapacity"])
            let designCapacity = Self.integer(registry["DesignCapacity"])

            status.cycleCount = Self.integer(registry["CycleCount"])
            status.maxCapacityMAh = maxMAh
            status.designCapacityMAh = designCapacity
            if let maxMAh, let designCapacity, designCapacity > 0 {
                status.healthPercent = Int((Double(maxMAh) / Double(designCapacity) * 100).rounded())
            }

            if let charging = registry["IsCharging"] as? Bool {
                status.isCharging = charging
            }

            let powerSource = Self.powerSourceReading(from: Self.readInternalBatteryDescription())
            status.isOnACPower = powerSource.isOnACPower ?? registry["ExternalConnected"] as? Bool
            status.minutesToFull = powerSource.minutesToFull

            if let currentPercentCapacity, let maxPercentCapacity, maxPercentCapacity > 0 {
                status.chargePercent = Int(
                    (Double(currentPercentCapacity) / Double(maxPercentCapacity) * 100).rounded()
                )
            }

            if let pmset {
                // "Now drawing from 'AC Power'"; the percentage only as a
                // fallback for machines that expose no usable capacities.
                if status.chargePercent == nil,
                   let range = pmset.range(of: #"(\d+)%"#, options: .regularExpression) {
                    status.chargePercent = Int(pmset[range].dropLast())
                }
                if status.chargePercent == nil, let currentMAh, let maxMAh, maxMAh > 0 {
                    status.chargePercent = Int((Double(currentMAh) / Double(maxMAh) * 100).rounded())
                }
                if status.isCharging == nil {
                    status.isCharging = Self.chargingState(fromPmset: pmset)
                }
            }
            return status
        }.value
    }

    /// Charging state from `pmset -g batt`, nil when the line says neither.
    ///
    /// Order matters: "discharging" and "not charging" both contain the
    /// substring "charging". Optimised charging reports
    /// "AC attached; not charging" while it holds the battery at a
    /// percentage, which is not a charge in progress. "charged" (full) counts
    /// as charging so the UI can show its "Fully charged" state.
    static func chargingState(fromPmset output: String) -> Bool? {
        let text = output.lowercased()
        if text.contains("discharging") { return false }
        if text.contains("not charging") { return false }
        if text.contains("finishing charge") { return true }
        if text.contains("charging") { return true }
        if text.contains("charged") { return true }
        return nil
    }

    /// What the power-sources API says about the internal battery.
    struct PowerSourceReading: Equatable, Sendable {
        var isOnACPower: Bool?
        var minutesToFull: Int?
    }

    /// Reads one `IOPSGetPowerSourceDescription` dictionary. The time to full
    /// is reported in minutes, -1 while macOS is still estimating, and is only
    /// meaningful while charging.
    static func powerSourceReading(from description: [String: Any]) -> PowerSourceReading {
        var reading = PowerSourceReading()
        switch description[kIOPSPowerSourceStateKey] as? String {
        case kIOPSACPowerValue: reading.isOnACPower = true
        case kIOPSBatteryPowerValue: reading.isOnACPower = false
        default: break
        }
        if description[kIOPSIsChargingKey] as? Bool == true,
           let minutes = integer(description[kIOPSTimeToFullChargeKey]),
           minutes >= 0 {
            reading.minutesToFull = minutes
        }
        return reading
    }

    private static func readInternalBatteryDescription() -> [String: Any] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return [:] }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return description
            }
        }
        return [:]
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func readPowerSourceProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMPowerSource"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return [:] }
        return properties
    }

    private static func readPmsetOutput() async -> String? {
        do {
            let result = try await PerformanceInspector.runCommand(
                executable: URL(fileURLWithPath: "/usr/bin/pmset"),
                arguments: ["-g", "batt"],
                timeout: 10
            )
            guard result.status == 0 else { return nil }
            return result.standardOutput
        } catch {
            return nil
        }
    }
}
