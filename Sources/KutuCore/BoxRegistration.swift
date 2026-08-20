// Sources/KutuCore/BoxRegistration.swift
import Foundation

/// Decision logic behind `kutu register`. Kept separate from the CLI so it is
/// testable without touching the filesystem: the caller reads and writes
/// `boxes.toml`, this just decides what that write should be.
public enum BoxRegistration {
    public enum Outcome: Sendable, Equatable {
        case alreadyRegistered
        case conflict(existingDir: String)
        case append(block: String)
        /// The name or directory could not be written to the config safely.
        case invalid(field: String, reason: String)
    }

    /// Whether `value` can be interpolated into a TOML basic string as-is.
    ///
    /// The block `plan` returns is appended verbatim to the user's global
    /// boxes.toml, and a box name arrives straight from a repo's kutu.toml —
    /// which the user may not have written. Rejecting exactly the characters
    /// that would need escaping is what keeps the interpolation below safe:
    /// there is then nothing left that could close the string early and add
    /// entries of its own. A box name is also something you type into the
    /// palette, so nothing being refused here has a legitimate use.
    ///
    /// Deliberately not an allowlist of ASCII — the rule is about TOML
    /// escaping, not about which alphabet a box is named in.
    public static func isSafeForConfig(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return !value.unicodeScalars.contains { scalar in
            scalar == "\"" || scalar == "\\"
                || CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
        }
    }

    /// Decides what registering `name` at `dir` means against an existing
    /// config. Pure: the caller does the file I/O.
    ///
    /// `dir` is compared against `BoxSpec.dir` — which `KutuConfig.parse` has
    /// already tilde-expanded — by expanding it here too and stripping a
    /// trailing slash from both sides, so `~/w/a` vs `/Users/x/w/a/` is
    /// recognised as the same directory rather than a false conflict. `dir`
    /// itself (tilde form or absolute, whatever the caller wants stored) is
    /// used verbatim in the appended block.
    public static func plan(existing: KutuConfig, name: String, dir: String) -> Outcome {
        guard isSafeForConfig(name) else {
            return .invalid(field: "name",
                            reason: "a box name cannot be empty or contain quotes, backslashes or control characters")
        }
        guard isSafeForConfig(dir) else {
            return .invalid(field: "dir",
                            reason: "the directory path contains quotes, backslashes or control characters")
        }
        let normalizedNewDir = withoutTrailingSlash((dir as NSString).expandingTildeInPath)
        if let match = existing.boxes.first(where: { $0.name == name }) {
            let normalizedExistingDir = withoutTrailingSlash(match.dir)
            if normalizedExistingDir == normalizedNewDir {
                return .alreadyRegistered
            }
            return .conflict(existingDir: match.dir)
        }
        let block = "\n[[box]]\nname = \"\(name)\"\ndir  = \"\(dir)\"\n"
        return .append(block: block)
    }

    /// "~/workspace/x" when `absolute` is under `home`, else `absolute` unchanged.
    public static func displayPath(_ absolute: String, home: String) -> String {
        let normalizedHome = withoutTrailingSlash(home)
        if absolute == normalizedHome {
            return "~"
        }
        if absolute.hasPrefix(normalizedHome + "/") {
            return "~" + absolute.dropFirst(normalizedHome.count)
        }
        return absolute
    }

    private static func withoutTrailingSlash(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
