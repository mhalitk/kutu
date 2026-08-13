import Foundation

/// Every filesystem location kutu uses, in one place. The CLI links only
/// KutuCore, so anything it shares with the app has to live here or the two
/// silently drift apart.
public enum KutuPaths {
    public static var stateFile: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/state/kutu/state.json")
    }
    public static var socket: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/state/kutu/kutu.sock")
    }
    public static var config: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/kutu/boxes.toml")
    }
}
