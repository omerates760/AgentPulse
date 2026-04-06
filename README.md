# AgentPulse

A **Dynamic Island** for your AI coding tools on macOS. Monitor all your AI agent sessions from the notch — approve permissions, answer questions, and jump to terminals without context switching.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.8-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## What is AgentPulse?

AgentPulse lives in your macOS notch area and tracks every AI coding agent running on your machine. It shows real-time session status, handles permission approvals, and lets you answer Claude's questions — all without leaving your current window.

### Supported Agents
| Agent | Status |
|-------|--------|
| Claude Code | Full support (hooks + approvals + questions) |
| Cursor | Full support (hooks + approvals) |
| Codex | Full support (hooks + approvals) |
| Gemini CLI | Full support (hooks + approvals) |

### Supported Terminals & IDEs
iTerm2, Apple Terminal, VS Code, Cursor, Warp, Ghostty, Kitty

---

## Features

### Dynamic Island Pill
- Sits at the macOS notch, expands on hover
- Shows live session count, active tool, and status
- Animated glow border: cyan (active), orange (permission), purple (question)
- Dynamic width — grows when sessions are active

### Session Monitoring
- Real-time session tracking with live duration timer
- Tool activity animation (pulsing dots when running)
- Context usage / rate limit progress bar
- Project grouping for multi-session workflows
- Completion glow effect when sessions finish

### Permission Approvals
- **Allow Once / Always Allow / Deny** directly from the notch
- Bash command preview for tool approvals
- No need to switch to the terminal

### Question Answering
- Single-select (radio buttons) and multi-select (checkboxes)
- Multi-question batches with **Submit All** button
- Answers sent directly to Claude Code via hook protocol
- Option descriptions shown inline

### Smart Features
- **Smart Suppression** — mutes sounds when terminal is in focus
- **Terminal Jump** — click to jump to the exact terminal tab via AppleScript
- **Auto Hook Installation** — configures Claude/Cursor/Codex/Gemini hooks automatically
- **Global Hotkey** — Cmd+Shift+V to toggle the panel

### Settings & Customization
- Layout modes: Clean / Detailed
- Modifier key selection (Control / Option / Command)
- Sound effects with smart suppression
- Feedback system with community links
- Diagnostic export for troubleshooting

### Onboarding
- Beautiful 4-page animated onboarding flow
- Environment detection (installed agents & terminals)
- Zero-config setup

---

## Installation

### Build from Source

**Requirements:** macOS 13.0+, Xcode Command Line Tools

```bash
git clone https://github.com/omerates760/AgentPulse.git
cd AgentPulse
bash build.sh
cp -r AgentPulse.app /Applications/
open /Applications/AgentPulse.app
```

### What Happens on First Launch
1. Onboarding flow introduces you to AgentPulse
2. Bridge binary is installed to `~/.agent-pulse/bin/`
3. Hooks are automatically configured for detected AI tools
4. AgentPulse appears in your notch — ready to go

---

## Architecture

```
AgentPulse/
├── Sources/AgentPulse/
│   ├── main.swift                     # Entry point + crash handlers
│   ├── AppDelegate.swift              # Status bar, lifecycle, hotkeys
│   ├── Models/Models.swift            # Core data types
│   ├── ViewModels/NotchViewModel.swift
│   ├── Views/
│   │   ├── NotchContentView.swift     # Main panel UI
│   │   ├── SessionCardView.swift      # Session cards with live timers
│   │   ├── ApprovalViews.swift        # Permission & question UI
│   │   ├── SettingsView.swift         # Settings panel
│   │   ├── OnboardingViews.swift      # Onboarding flow
│   │   └── LicenseView.swift         
│   ├── Windows/
│   │   ├── NotchPanel.swift           # NSPanel with glow effects
│   │   └── NotchWindowController.swift
│   └── Services/
│       ├── SocketServer.swift         # Unix domain socket
│       ├── SessionStore.swift         # Session state management
│       ├── HookConfigurator.swift     # Auto hook installation
│       ├── SoundManager.swift         # Smart suppression
│       ├── TerminalJumper.swift       # AppleScript terminal jump
│       ├── KeyboardShortcutManager.swift  # Carbon hotkeys
│       ├── ScreenSelector.swift       # Notch display detection
│       └── ...
├── Sources/AgentPulseBridge/
│   └── main.swift                     # Hook binary for AI tools
├── Package.swift
└── build.sh
```

### How It Works

```
AI Tool (Claude Code) → Hook fires → AgentPulseBridge (stdin)
    → Unix Socket (/tmp/agent-pulse.sock) → AgentPulse App
    → SwiftUI Panel (notch) → User interacts
    → Response flows back through socket → Bridge stdout → AI Tool continues
```

---

## Tech Stack

- **Swift 5.8** + **SwiftUI** for the UI
- **AppKit** (NSPanel) for the notch window
- **Carbon** Hot Key API for global shortcuts
- **Unix Domain Sockets** for IPC
- **Combine** for reactive state management
- **AppleScript** for terminal navigation

---

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
