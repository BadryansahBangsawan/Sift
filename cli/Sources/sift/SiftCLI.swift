import ArgumentParser
import Foundation

let siftVersion = "1.1.1"

@main
struct SiftCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sift-cli",
        abstract: "Review caches, clean project artifacts, and explore your storage.",
        discussion: """
        Run sift-cli to open the interactive workspace. Select individual paths,
        review their sizes, and confirm before permanent cleanup.
        Use --help on any command for script-friendly options.
        """,
        version: siftVersion,
        subcommands: [Clean.self, Purge.self, Analyze.self, Optimize.self, Doctor.self, Dupes.self, Uninstall.self, Ignore.self, Config.self]
    )

    func run() throws {
        guard TerminalSession.isSupported else {
            print(Self.helpMessage())
            return
        }
        try HomeMenu.run()
    }
}

enum HomeMenu {
    private static func promptPath(_ label: String, fallback: String) -> String {
        print(Term.dim("\(label) (\(fallback)): "), terminator: "")
        let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return line.isEmpty ? fallback : line
    }

    static func run() throws {
        let options: [(title: String, detail: String)] = [
            ("Clean caches", "Choose tools and individual paths to remove"),
            ("Project cleanup", "Review dependencies and generated build artifacts"),
            ("Explore storage", "Browse folders and find what takes up space"),
            ("System status", "Inspect memory and available disk space"),
            ("Preferences", "View cleanup settings and configuration paths"),
            ("Protected paths", "View folders excluded from cleanup"),
            ("Doctor", "Check disk, memory, SMART, and launch agents"),
            ("Dupes", "Find files with identical contents"),
            ("Uninstall", "Remove an app and its bundle-ID-matched leftovers")
        ]
        while let choice = try TerminalMenu.choose(
            title: "Sift",
            subtitle: "Your Mac, with room to work.  /  \(siftVersion)",
            options: options
        ) {
            switch choice {
            case 0:
                guard let category = try TerminalMenu.choose(
                    title: "Clean caches",
                    subtitle: "Scan first. Choose what to remove afterward.",
                    options: [
                        ("All categories", "Developer caches, user junk, AI tools, and Trash"),
                        ("Developer caches", "Package managers and build tools"),
                        ("User junk", "Logs and generated Xcode files"),
                        ("AI tools", "Caches and logs from local AI tools"),
                        ("Trash", "Review items already in the Trash")
                    ]
                ) else { continue }
                let arguments = [[], ["dev"], ["junk"], ["ai"], ["trash"]]
                try Clean.parse(arguments[category]).run()
            case 1: try Purge.parse([]).run()
            case 2: try Analyze.parse([]).run()
            case 3: try Optimize.parse([]).run()
            case 4: try Config.parse([]).run()
            case 5: try Ignore.List.parse([]).run()
            case 6: try Doctor.parse(["--json"]).run()
            case 7:
                let folder = promptPath("Folder to scan", fallback: NSHomeDirectory())
                try Dupes.parse([folder]).run()
            case 8:
                let app = promptPath("App to uninstall", fallback: "/Applications")
                try Uninstall.parse([app]).run()
            default: return
            }
            print(Term.dim("\nPress Return to return to Sift."), terminator: " ")
            guard readLine() != nil else { return }
        }
    }
}
