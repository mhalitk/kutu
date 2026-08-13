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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            do {
                try process.run()
            } catch {
                NSLog("kutu: failed to launch \(spec.kind.rawValue) for \(box.name): \(error)")
            }
        }
    }
}
