import ArgumentParser
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check disk, memory, SMART status, launch agents, and Trash size.",
        discussion: """
        Read-only. Every section reports what macOS answered; nothing is
        changed, deleted, or repaired. Use --json for scripted checks.
        """
    )

    @Flag(name: .long, help: "Emit machine-readable JSON instead of a report.")
    var json = false

    func run() throws {
        let volume = try? SystemInfo.volumeStatus("/")
        let memory = try? SystemInfo.memoryStatus()
        let smart = smartStatus()
        let agents = launchAgentHealth()
        let trashBytes = trashSize()
        let configPath = AppPaths.configDir.path

        if json {
            print(try report(
                volume: volume,
                memory: memory,
                smart: smart,
                agents: agents,
                trashBytes: trashBytes,
                configPath: configPath
            ))
            return
        }

        print("")
        print(Term.bold("Disk and memory"))
        if let volume {
            print("  " + Term.dim(Render.pad("Volume", 18)) + ByteCount.human(volume.total) + Term.dim(" total"))
            print("  " + Term.dim(Render.pad("Available", 18)) + ByteCount.human(volume.availableNow))
            if volume.systemManagedCapacity > 0 {
                print("  " + Term.dim(Render.pad("Purgeable", 18)) + ByteCount.human(volume.systemManagedCapacity))
            }
        } else {
            print("  " + Term.yellow("Storage capacity is unavailable for /"))
        }
        if let memory {
            print("  " + Term.dim(Render.pad("Memory", 18)) + ByteCount.human(memory.total) + Term.dim(" total"))
            print("  " + Term.dim(Render.pad("Free", 18)) + ByteCount.human(memory.free + memory.inactive))
        } else {
            print("  " + Term.yellow("Memory statistics are unavailable"))
        }

        print("")
        print(Term.bold("Disk health"))
        switch smart {
        case .some(let status):
            let tinted = status == "Verified" ? Term.green(status) : Term.yellow(status)
            print("  " + Term.dim(Render.pad("SMART", 18)) + tinted)
        case .none:
            print("  " + Term.dim(Render.pad("SMART", 18)) + Term.dim("unavailable"))
        }

        print("")
        print(Term.bold("Launch agents"))
        if agents.total == 0 {
            print("  " + Term.dim("none found in ~/Library/LaunchAgents"))
        } else {
            print(
                "  " + Term.green("\(agents.healthy) healthy")
                    + Term.dim(", ")
                    + (agents.broken.isEmpty ? Term.dim("0 broken") : Term.yellow("\(agents.broken.count) broken"))
            )
            for label in agents.broken {
                print("  " + Term.red("  ! ") + Term.sanitize(label) + Term.dim(" not loaded by launchd"))
            }
        }

        print("")
        print(Term.bold("Trash"))
        print("  " + ByteCount.human(trashBytes) + Term.dim(" in the Trash"))

        print("")
        print(Term.bold("Configuration"))
        print("  " + Term.dim(Render.pad("Config", 18)) + Term.sanitize(configPath))
        print("")
    }

    // MARK: - Sections

    private func smartStatus() -> String? {
        let result = Shell.run("/usr/sbin/diskutil", ["info", "-plist", "/"], timeout: 20)
        guard result.status == 0 else { return nil }
        return DoctorSupport.parseSmartStatus(Data(result.out.utf8))
    }

    private struct AgentHealth {
        var total = 0
        var healthy = 0
        var broken: [String] = []
    }

    private func launchAgentHealth() -> AgentHealth {
        var health = AgentHealth()
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return health }

        for file in files where file.pathExtension.lowercased() == "plist" {
            health.total += 1
            guard let data = try? Data(contentsOf: file),
                  let label = DoctorSupport.launchAgentLabel(data)
            else {
                health.broken.append(file.lastPathComponent)
                continue
            }
            let status = Shell.run("/bin/launchctl", ["list", label], timeout: 5).status
            if DoctorSupport.isBroken(status) {
                health.broken.append(label)
            } else {
                health.healthy += 1
            }
        }
        return health
    }

    private func trashSize() -> Int64 {
        guard let ignore = try? IgnoreStore(fileURL: AppPaths.ignoreFile, legacyFileURL: AppPaths.legacyIgnoreFile) else { return 0 }
        let scan = CategoryScanner.scan(categoryID: "trash", title: "Trash", ignore: ignore)
        return scan.allBytes
    }

    // MARK: - JSON

    private func report(
        volume: VolumeStatus?,
        memory: MemoryStatus?,
        smart: String?,
        agents: AgentHealth,
        trashBytes: Int64,
        configPath: String
    ) throws -> String {
        struct Out: Encodable {
            struct Volume: Encodable { let total, availableNow, availableForImportantUsage: Int64 }
            struct Memory: Encodable { let total, free, active, wired, compressed: Int64 }
            struct Agents: Encodable { let total: Int; let healthy: Int; let broken: [String] }
            let volume: Volume?
            let memory: Memory?
            let smartStatus: String?
            let launchAgents: Agents
            let trashBytes: Int64
            let configPath: String
        }
        let out = Out(
            volume: volume.map { Out.Volume(
                total: $0.total,
                availableNow: $0.availableNow,
                availableForImportantUsage: $0.availableForImportantUsage
            ) },
            memory: memory.map { Out.Memory(
                total: $0.total,
                free: $0.free,
                active: $0.active,
                wired: $0.wired,
                compressed: $0.compressed
            ) },
            smartStatus: smart,
            launchAgents: Out.Agents(total: agents.total, healthy: agents.healthy, broken: agents.broken),
            trashBytes: trashBytes,
            configPath: configPath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(out), as: UTF8.self)
    }
}
