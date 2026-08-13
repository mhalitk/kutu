// Sources/KutuMac/StatusServer.swift
import Foundation
import KutuCore

/// One JSON payload per connection over a unix socket. Connection-per-message
/// keeps every client a single `nc` invocation with no framing to get wrong,
/// which is what lets an arbitrary tool report status in one shell line.
public final class StatusServer {
    private let path: String
    private let onPayload: (Data) -> Void
    private var listener: DispatchSourceRead?
    private var socketFD: Int32 = -1

    public init(path: String, onPayload: @escaping (Data) -> Void) {
        self.path = path
        self.onPayload = onPayload
    }

    public static var defaultPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/state/kutu/kutu.sock")
    }

    public func start() throws {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        unlink(path)

        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        // Size is read before taking the pointer: computing it inside the
        // closure is an overlapping access to `address.sun_path` and violates
        // Swift's exclusivity rules.
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path) - 1
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                        source, maxPathLength)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, size) }
        }
        guard bound == 0, listen(socketFD, 16) == 0 else {
            close(socketFD)
            throw POSIXError(.EADDRINUSE)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD,
                                                   queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        listener = source
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        if socketFD >= 0 { close(socketFD) }
        unlink(path)
    }

    private func accept() {
        let client = Darwin.accept(socketFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        // This socket carries control commands as well as status, and GCD will
        // not re-enter a single source's handler concurrently. A client that
        // connects and never writes would therefore stall every later
        // connection — including `kutu go`. Bound the read instead.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                   socklen_t(MemoryLayout<timeval>.size))

        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            payload.append(contentsOf: buffer[0..<count])
            if payload.count > 64_000 { break }
        }
        guard !payload.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in self?.onPayload(payload) }
    }
}
