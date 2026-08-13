import AppKit

/// Stage Manager intercepts window positioning: with it on, a window parked at
/// (60000, 60000) is clamped back to a 284px-wide visible fragment instead of
/// 40px, which no mask can cover. kutu refuses to park while it is enabled.
public enum StageManagerGuard {
    public static var isEnabled: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    public static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
