import Foundation

public enum LaunchCommand {
    /// What to execute. `.path` is a concrete executable; `.appBundle` names an
    /// application by bundle id and leaves resolution to the caller, because
    /// finding an installed app needs LaunchServices and KutuCore stays free of
    /// AppKit.
    public enum Target: Sendable, Equatable {
        case path(String)
        case appBundle(String)
    }

    public static func build(for spec: AppSpec, in dir: String) -> (target: Target, arguments: [String])? {
        switch spec.kind {
        case .iterm:
            // Two layers of quoting, escaped in the right order and for the
            // right layer. The shell line is built first: `dir` sits inside
            // single quotes so it needs the close-escape-reopen idiom, while
            // `cmd` IS a shell command line and must stay unquoted — shell
            // escaping it would corrupt a legitimate `say it's done`.
            //
            // With no command this is just a `cd`: appending an unconditional
            // `&&` would leave a dangling operator and the shell would reject
            // the whole line.
            let command = spec.cmd?.trimmingCharacters(in: .whitespaces) ?? ""
            let shellLine = command.isEmpty
                ? "cd '\(singleQuoteEscaped(dir))'"
                : "cd '\(singleQuoteEscaped(dir))' && \(command)"
            // The whole line is then embedded in an AppleScript string
            // literal, which has escaping rules of its own. Without this a
            // double quote in either value closes the literal early and the
            // remainder is parsed as AppleScript source.
            // Bind to the window this script creates. `current window` is a
            // global that the NEXT concurrently-launched iTerm script will
            // change out from under this one — two [[app]] entries racing meant
            // one window received both commands and the other received none.
            let script = """
            tell application "iTerm"
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(appleScriptEscaped(shellLine))"
                end tell
            end tell
            """
            return (.path("/usr/bin/osascript"), ["-e", script])

        case .chrome:
            var arguments = ["-na", "Google Chrome", "--args"]
            if let profile = spec.profile { arguments.append("--profile-directory=\(profile)") }
            arguments.append(contentsOf: spec.urls)
            return (.path("/usr/bin/open"), arguments)

        case .vscode:
            return (.path("/usr/bin/open"), ["-a", "Visual Studio Code", dir])

        case .app:
            guard let bundleID = spec.bundleID else { return nil }
            // `open -b <id> <urls…>` hands the URLs to that application. This
            // is the general path for any browser or document app; `chrome`
            // exists separately only because profile selection needs a
            // Chrome-specific flag.
            return (.path("/usr/bin/open"), ["-b", bundleID] + spec.urls)

        case .firefox:
            // Firefox must be driven through its own binary, not `open`.
            // With Firefox already running, `open -b <id> <urls>` loads them as
            // tabs in an EXISTING window — which belongs to whatever box that
            // window was already in, so hydration cannot claim it and the
            // switch that follows parks it. `open --args` is ignored outright
            // for a running app.
            //
            // `--url` is the one form that yields exactly one NEW window with
            // every URL as a tab, which is what makes the window claimable.
            // (`--new-window` with several URLs opens several windows, and
            // `--new-tab` targets the last-focused window, not the new one.)
            guard !spec.urls.isEmpty else {
                return (.appBundle("org.mozilla.firefox"), ["--new-window"])
            }
            return (.appBundle("org.mozilla.firefox"), ["--url"] + spec.urls)
        }
    }

    /// For a value sitting inside shell single quotes: close, escape, reopen.
    private static func singleQuoteEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// For a value sitting inside an AppleScript string literal. Backslash is
    /// replaced first, or the escapes introduced below would themselves be
    /// escaped. A raw newline is invalid inside an AppleScript literal, so it
    /// becomes the `\n` escape rather than being passed through.
    ///
    /// Carriage return gets the same treatment for the same reason: it ends a
    /// statement in AppleScript exactly as a newline does, and it is legal in a
    /// macOS filename, so a directory can carry one in without anyone typing it
    /// deliberately.
    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
