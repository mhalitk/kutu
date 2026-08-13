import Foundation

public enum LaunchCommand {
    public static func build(for spec: AppSpec, in dir: String) -> (executable: String, arguments: [String])? {
        switch spec.kind {
        case .iterm:
            let command = spec.cmd ?? ""
            let script = """
            tell application "iTerm"
                create window with default profile
                tell current session of current window
                    write text "cd '\(shellEscape(dir))' && \(shellEscape(command))"
                end tell
            end tell
            """
            return ("/usr/bin/osascript", ["-e", script])

        case .chrome:
            var arguments = ["-na", "Google Chrome", "--args"]
            if let profile = spec.profile { arguments.append("--profile-directory=\(profile)") }
            arguments.append(contentsOf: spec.urls)
            return ("/usr/bin/open", arguments)

        case .vscode:
            return ("/usr/bin/open", ["-a", "Visual Studio Code", dir])

        case .app:
            guard let bundleID = spec.bundleID else { return nil }
            return ("/usr/bin/open", ["-b", bundleID])
        }
    }

    /// Single quotes are the only character that can break out of the single
    /// quoting used above; the standard shell idiom closes, escapes, reopens.
    private static func shellEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }
}
