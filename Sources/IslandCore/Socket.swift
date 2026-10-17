import Foundation
import Darwin

private func makeAddr(_ path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    guard path.utf8.count < cap else { return nil }
    withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: cap) { _ = strlcpy($0, path, cap) }
    }
    return addr
}

private func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { buf in
        var off = 0
        while off < buf.count {
            let n = write(fd, buf.baseAddress! + off, buf.count - off)
            if n <= 0 { return }
            off += n
        }
    }
}

/// Reads until '\n' or EOF. Returns nil on timeout/error. timeout in seconds, nil = block.
private func readLine(_ fd: Int32, timeout: TimeInterval?) -> Data? {
    var data = Data()
    var byte: UInt8 = 0
    let deadline = timeout.map { Date().addingTimeInterval($0) }
    while true {
        if let deadline {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ms = Int32(max(0, deadline.timeIntervalSinceNow) * 1000)
            if poll(&p, 1, ms) <= 0 { return nil }
        }
        let n = read(fd, &byte, 1)
        if n <= 0 { return data.isEmpty ? nil : data }
        if byte == 0x0A { return data }
        data.append(byte)
    }
}

/// Write side of one hook connection. Detects the hook process going away (e.g. you answered
/// in the terminal and Claude Code killed the hook) and fires `onCancel`.
public final class ReplyChannel: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var finished = false
    private var cancelHandler: (@Sendable () -> Void)?

    init(fd: Int32) { self.fd = fd }

    public func send(_ reply: Reply) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        guard fd >= 0, var out = try? JSONEncoder().encode(reply) else { return }
        out.append(0x0A)
        writeAll(fd, out)
    }

    public func onCancel(_ handler: @escaping @Sendable () -> Void) {
        lock.lock(); cancelHandler = handler; lock.unlock()
    }

    /// Owns the fd: closes it once the reply is sent or the peer is gone.
    fileprivate func monitor() {
        Thread.detachNewThread { [self] in
            while true {
                lock.lock(); let done = finished; lock.unlock()
                if done { break }
                var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                guard poll(&p, 1, 200) > 0 else { continue }
                var b: UInt8 = 0
                let n = recv(fd, &b, 1, MSG_PEEK | MSG_DONTWAIT)
                if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
                    lock.lock()
                    let already = finished
                    finished = true
                    let h = cancelHandler
                    lock.unlock()
                    if !already { h?() }
                    break
                }
                usleep(100_000)
            }
            close(fd)
        }
    }
}

/// Listens on a unix socket. Each connection carries one Envelope line; if
/// `expectsReply`, the handler answers through the ReplyChannel.
public final class SocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Envelope, ReplyChannel) -> Void

    private let path: String

    public init(path: String = IslandPaths.socket) { self.path = path }

    public func start(handler: @escaping Handler) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        unlink(path)
        guard var addr = makeAddr(path) else { throw POSIXError(.ENAMETOOLONG) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        chmod(path, 0o600)
        Thread.detachNewThread { [fd] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EINTR { continue }; return }
                Thread.detachNewThread { Self.serve(client, handler) }
            }
        }
    }

    private static func serve(_ client: Int32, _ handler: @escaping Handler) {
        guard let line = readLine(client, timeout: 5),
              let env = try? JSONDecoder().decode(Envelope.self, from: line)
        else { close(client); return }
        if env.expectsReply {
            let ch = ReplyChannel(fd: client)
            ch.monitor()
            handler(env, ch)
        } else {
            handler(env, ReplyChannel(fd: -1))
            close(client)
        }
    }
}

public enum HookClient {
    /// Sends the envelope. If it expects a reply, blocks until one arrives or `wait` elapses.
    /// Returns nil when the app is not running or no answer came (caller falls through to `ask`).
    public static func send(_ env: Envelope, wait: TimeInterval) -> Reply? {
        guard var addr = makeAddr(IslandPaths.socket) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0, var out = try? JSONEncoder().encode(env) else { return nil }
        out.append(0x0A)
        writeAll(fd, out)
        guard env.expectsReply, let line = readLine(fd, timeout: wait) else { return nil }
        return try? JSONDecoder().decode(Reply.self, from: line)
    }
}
