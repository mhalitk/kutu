// Sources/KutuCore/HotKeySpec.swift
import Foundation

/// A parsed hotkey. Kept in KutuCore so the parsing rules are unit-testable
/// without dragging Carbon into a test binary.
public struct HotKeySpec: Sendable, Equatable {
    public let keyCode: UInt32
    public let usesCommand: Bool
    public let usesOption: Bool
    public let usesControl: Bool
    public let usesShift: Bool

    private static let keyCodes: [String: UInt32] = [
        "space": 49, "return": 36, "tab": 48, "escape": 53,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
        "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25, "0": 29
    ]

    public static func parse(_ spec: String) -> HotKeySpec? {
        let parts = spec.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, let code = keyCodes[key] else { return nil }

        let modifiers = Set(parts.dropLast())
        let usesCommand = modifiers.contains("cmd") || modifiers.contains("command")
        let usesOption = modifiers.contains("alt") || modifiers.contains("option")
        let usesControl = modifiers.contains("ctrl") || modifiers.contains("control")
        let usesShift = modifiers.contains("shift")

        // Validate RECOGNISED modifiers, not merely that some token preceded the
        // key. "fn+space" has a token but no recognised modifier, and would
        // otherwise register an unmodified global Space — swallowing the space
        // bar system-wide.
        guard usesCommand || usesOption || usesControl || usesShift else { return nil }

        return HotKeySpec(keyCode: code,
                          usesCommand: usesCommand,
                          usesOption: usesOption,
                          usesControl: usesControl,
                          usesShift: usesShift)
    }
}
