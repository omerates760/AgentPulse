// main.swift — AgentPulse
// Application entry point

import AppKit
import Foundation

// Crash handler — log crash reason
func crashHandler(_ signal: Int32) {
    let msg = "CRASH: signal=\(signal)\n"
    let fd = Darwin.open("/tmp/agent-pulse-crash.log", O_WRONLY | O_CREAT | O_APPEND, 0o644)
    if fd >= 0 {
        _ = msg.withCString { Darwin.write(fd, $0, Int(strlen($0))) }

        // Get thread backtrace
        let symbols = Thread.callStackSymbols
        for s in symbols {
            let line = s + "\n"
            _ = line.withCString { Darwin.write(fd, $0, Int(strlen($0))) }
        }
        Darwin.close(fd)
    }
    exit(1)
}

signal(SIGSEGV, crashHandler)
signal(SIGBUS, crashHandler)
signal(SIGABRT, crashHandler)
signal(SIGTRAP, crashHandler)
signal(SIGILL, crashHandler)

// Uncaught NSException handler
NSSetUncaughtExceptionHandler { exception in
    let msg = """
    UNCAUGHT EXCEPTION: \(exception.name.rawValue)
    Reason: \(exception.reason ?? "nil")
    Stack: \(exception.callStackSymbols.joined(separator: "\n"))
    """
    try? msg.write(toFile: "/tmp/agent-pulse-crash.log", atomically: true, encoding: .utf8)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu bar only app (no dock icon)
app.setActivationPolicy(.accessory)

app.run()
