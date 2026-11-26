import Foundation

/// Builds POSIX shell commands and the AppleScript sources that run them.
///
/// A path crosses two escaping layers before `/bin/sh` sees it:
/// 1. shell quoting makes the path one literal shell word;
/// 2. AppleScript string-literal escaping lets that command line sit inside
///    `do shell script "..."`.
enum ShellQuoting {
    /// Wraps a value as a single shell word.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The shell command line running `executable` with `arguments` and `paths`.
    static func command(executable: String, arguments: [String] = [], paths: [String]) -> String {
        ([executable] + arguments.map(singleQuoted) + paths.map(singleQuoted))
            .joined(separator: " ")
    }

    /// AppleScript source that removes `paths` with `rm -rf --`, without the
    /// privilege clause: production appends " with administrator privileges".
    ///
    /// `executable` and `arguments` are parameters so a test can run a
    /// harmless command through the exact same quoting and AppleScript
    /// escaping the real removal uses.
    static func removalAppleScript(
        paths: [String],
        executable: String = "/bin/rm",
        arguments: [String] = ["-rf", "--"]
    ) -> String {
        appleScript(running: command(executable: executable, arguments: arguments, paths: paths))
    }

    /// AppleScript source that runs a shell command line; the caller adds the
    /// privilege clause.
    static func appleScript(running shellCommand: String) -> String {
        let literal = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(literal)\""
    }
}