import AppKit
import Foundation
import KutuCore

/// Starts everything a box declares in its kutu.toml, and tells the Assigner to
/// attribute the resulting windows to that box rather than to whatever happens
/// to be active.
public final class Launcher {
    private let assigner: Assigner

    public init(assigner: Assigner) {
        self.assigner = assigner
    }

    public func manifest(for box: BoxSpec) -> BoxManifest? {
        let path = (box.dir as NSString).appendingPathComponent("kutu.toml")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return try? BoxManifest.parse(text)
    }

    public func hydrate(box: BoxSpec) {
        guard let manifest = manifest(for: box) else { return }
        assigner.claimNextWindows(for: box.name, seconds: 20)
        for spec in manifest.apps {
            guard let command = LaunchCommand.build(for: spec, in: box.dir) else { continue }
            guard let executable = executable(for: command.target) else {
                if case .appBundle(let bundleID) = command.target {
                    NSLog("kutu: could not find the application for \(bundleID)")
                }
                continue
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = command.arguments
            do {
                try process.run()
            } catch {
                NSLog("kutu: failed to launch \(spec.kind.rawValue) for \(box.name): \(error)")
            }
        }
    }

    /// Resolves an app bundle id to its executable through LaunchServices, so
    /// the app works wherever the user installed it rather than only in
    /// /Applications.
    private func executable(for target: LaunchCommand.Target) -> String? {
        switch target {
        case .path(let path):
            return path
        case .appBundle(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  let bundle = Bundle(url: url),
                  let name = bundle.infoDictionary?["CFBundleExecutable"] as? String else {
                return nil
            }
            return url.appendingPathComponent("Contents/MacOS").appendingPathComponent(name).path
        }
    }
}
