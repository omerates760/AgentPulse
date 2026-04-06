// SocketServer.swift — AgentPulse
// Unix domain socket server for bridge communication

import Foundation

protocol SocketServerDelegate: AnyObject {
    func socketServer(_ server: SocketServer, didReceiveEvent event: [String: Any], connection: SocketConnection)
}

class SocketConnection {
    let fd: Int32
    var isOpen = true

    init(handle: FileHandle) {
        self.fd = handle.fileDescriptor
    }

    init(fd: Int32) {
        self.fd = fd
    }

    func send(_ data: Data) {
        guard isOpen, fd >= 0 else { return }
        let result = data.withUnsafeBytes { bytes -> Int in
            guard let ptr = bytes.baseAddress else { return -1 }
            return Darwin.write(fd, ptr, bytes.count)
        }
        if result < 0 {
            DiagnosticLogger.shared.log("Socket send error: errno=\(errno)")
            isOpen = false
        }
    }

    func sendJSON(_ dict: [String: Any]) {
        guard isOpen else {
            DiagnosticLogger.shared.log("Socket sendJSON: connection closed")
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        var payload = data
        payload.append(contentsOf: [0x0A])
        send(payload)
        DiagnosticLogger.shared.log("Socket reply sent: \(payload.count) bytes")
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        Darwin.close(fd)
    }
}

class SocketServer {
    static let socketPath = "/tmp/agent-pulse.sock"

    weak var delegate: SocketServerDelegate?

    private var serverSocket: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "com.agentpulse.socket.accept", qos: .userInitiated)
    private let handleQueue = DispatchQueue(label: "com.agentpulse.socket.handle", qos: .userInitiated, attributes: .concurrent)
    private var isRunning = false
    private var pendingConnections: [String: SocketConnection] = [:]

    func start() {
        acceptQueue.async { [weak self] in
            self?.startServer()
        }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            Darwin.close(serverSocket)
            serverSocket = -1
        }
        unlink(Self.socketPath)
        pendingConnections.values.forEach { $0.close() }
        pendingConnections.removeAll()
    }

    func holdConnection(id: String, connection: SocketConnection) {
        pendingConnections[id] = connection
    }

    func replyToConnection(id: String, response: [String: Any]) {
        guard let conn = pendingConnections.removeValue(forKey: id) else { return }
        conn.sendJSON(response)
        conn.close()
    }

    // MARK: - Private

    private func startServer() {
        // Remove existing socket
        unlink(Self.socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            DiagnosticLogger.shared.log("Failed to create socket: \(errno)")
            return
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Self.socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: min(buf.count, 104))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            DiagnosticLogger.shared.log("Failed to bind socket: \(errno)")
            Darwin.close(serverSocket)
            return
        }

        // Set permissions (readable/writable by user)
        chmod(Self.socketPath, 0o700)

        // Listen
        guard listen(serverSocket, 16) == 0 else {
            DiagnosticLogger.shared.log("Failed to listen: \(errno)")
            Darwin.close(serverSocket)
            return
        }

        isRunning = true
        DiagnosticLogger.shared.log("Socket server started at \(Self.socketPath)")

        // Accept loop
        while isRunning {
            let clientFd = accept(serverSocket, nil, nil)
            guard clientFd >= 0 else {
                if isRunning { DiagnosticLogger.shared.log("Accept failed: \(errno)") }
                continue
            }

            let connection = SocketConnection(fd: clientFd)

            handleQueue.async { [weak self] in
                self?.handleConnection(connection)
            }
        }
    }

    private func handleConnection(_ connection: SocketConnection) {
        let fd = connection.fd
        guard fd >= 0 else { return }

        var buffer = Data()
        var byte = [UInt8](repeating: 0, count: 1)
        while true {
            let n = recv(fd, &byte, 1, 0)
            if n <= 0 { break }
            if byte[0] == 0x0A { break }
            buffer.append(byte[0])
        }

        guard !buffer.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.socketServer(self, didReceiveEvent: json, connection: connection)
        }
    }
}
