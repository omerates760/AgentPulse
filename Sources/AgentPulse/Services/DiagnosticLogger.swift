// DiagnosticLogger.swift — AgentPulse
// Thread-safe diagnostic logger with file and in-memory log storage

import Foundation

class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    private let queue = DispatchQueue(label: "com.agentpulse.logger", qos: .utility)
    private var entries: [String] = []
    private let maxEntries = 1000

    private let tmpLogPath = "/tmp/agent-pulse.log"
    private let logDirectory: String

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        logDirectory = "\(home)/Library/Logs/AgentPulse"

        // Create log directory if needed
        try? FileManager.default.createDirectory(
            atPath: logDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"

        queue.async { [weak self] in
            guard let self = self else { return }

            // Add to in-memory buffer
            self.entries.append(line)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }

            // Append to /tmp log
            self.appendToFile(line, path: self.tmpLogPath)

            // Append to ~/Library/Logs/AgentPulse/agent-pulse.log
            let libLogPath = "\(self.logDirectory)/agent-pulse.log"
            self.appendToFile(line, path: libLogPath)
        }
    }

    func export() -> URL {
        var snapshot: [String] = []
        queue.sync {
            snapshot = self.entries
        }

        let tempDir = FileManager.default.temporaryDirectory
        let reportDir = tempDir.appendingPathComponent("AgentPulse-Diagnostic-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)

        // Write log entries
        let logContent = snapshot.joined(separator: "\n")
        let logFile = reportDir.appendingPathComponent("agent-pulse.log")
        try? logContent.write(to: logFile, atomically: true, encoding: .utf8)

        // Write system info
        let systemInfo = """
        AgentPulse Diagnostic Report
        Date: \(dateFormatter.string(from: Date()))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Entries: \(snapshot.count)
        """
        let infoFile = reportDir.appendingPathComponent("system-info.txt")
        try? systemInfo.write(to: infoFile, atomically: true, encoding: .utf8)

        // Create zip
        let zipURL = tempDir.appendingPathComponent("AgentPulse-Diagnostic.zip")
        try? FileManager.default.removeItem(at: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-j", zipURL.path, reportDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        // Clean up report directory
        try? FileManager.default.removeItem(at: reportDir)

        return zipURL
    }

    // MARK: - Private

    private func appendToFile(_ line: String, path: String) {
        let lineWithNewline = line + "\n"
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                if let data = lineWithNewline.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? lineWithNewline.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
