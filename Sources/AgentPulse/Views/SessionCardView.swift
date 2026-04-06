// SessionCardView.swift — AgentPulse
// Individual session card in the notch panel

import SwiftUI
import AppKit
import Combine

struct SessionCardView: View {
    @ObservedObject var session: Session
    @ObservedObject var viewModel: NotchViewModel

    // MARK: - State

    @State private var isEventHistoryExpanded = false
    @State private var isHovered = false
    @State private var now = Date()
    @State private var toolAnimPhase = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var completionGlow = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            contextUsageBar
            if isEventHistoryExpanded {
                eventHistory
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !session.tasks.isEmpty {
                taskList
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(completionGlowOverlay)
        .onReceive(timer) { tick in
            now = tick
            if session.status == .runningTool {
                toolAnimPhase = (toolAnimPhase + 1) % 3
            }
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: session.needsAttention) { _ in startPulseIfNeeded() }
        .onChange(of: session.status) { newStatus in
            if newStatus == .ended { triggerCompletionGlow() }
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 8) {
            agentBadge
            sessionInfo
            Spacer(minLength: 4)
            rightColumn
            actionButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if viewModel.isModifierHeld {
                viewModel.jumpToSession(session)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEventHistoryExpanded.toggle()
                }
            }
        }
        .contextMenu { cardContextMenu }
    }

    // MARK: - Agent Badge

    private var agentBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: session.agentType.iconName)
                .font(.system(size: 13))
                .foregroundColor(Color(session.agentType.color))
                .frame(width: 26, height: 26)
                .background(Color(session.agentType.color).opacity(0.15))
                .cornerRadius(7)

            statusDot
                .offset(x: 2, y: 2)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(Color(session.status.statusColor))
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.6), lineWidth: 1)
            )
            .scaleEffect(session.needsAttention ? pulseScale : 1.0)
    }

    // MARK: - Session Info

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(session.title ?? session.projectName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                childAgentBadge
            }

            HStack(spacing: 4) {
                statusDetailText
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)

                if session.status == .runningTool {
                    toolActivityDots
                }
            }
        }
    }

    // MARK: - Child Agent Badge

    @ViewBuilder
    private var childAgentBadge: some View {
        if !session.childAgentIds.isEmpty {
            HStack(spacing: 2) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 6))
                Text("\(session.childAgentIds.count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.1))
            .cornerRadius(3)
        }
    }

    // MARK: - Tool Activity Dots

    private var toolActivityDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(toolAnimPhase == i ? 0.8 : 0.25))
                    .frame(width: 3, height: 3)
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            liveDuration
            if session.toolCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "wrench")
                        .font(.system(size: 7))
                    Text("\(session.toolCount)")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    private var liveDuration: some View {
        let interval = now.timeIntervalSince(session.startTime)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let text: String
        if interval < 3600 {
            text = "\(minutes)m \(String(format: "%02d", seconds))s"
        } else {
            let hours = Int(interval) / 3600
            let remainMins = (Int(interval) % 3600) / 60
            text = "\(hours)h \(remainMins)m \(String(format: "%02d", seconds))s"
        }
        return Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if isHovered || viewModel.isModifierHeld {
            HStack(spacing: 4) {
                Button(action: { viewModel.jumpToSession(session) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Jump to terminal")

                Button(action: { viewModel.hideSession(session) }) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Hide session")
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    // MARK: - Context Usage Bar

    @ViewBuilder
    private var contextUsageBar: some View {
        if let limits = session.rateLimits {
            let pct = min(limits.primaryUsedPercent / 100.0, 1.0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                    Rectangle()
                        .fill(usageBarColor(pct))
                        .frame(width: geo.size.width * CGFloat(pct))
                }
            }
            .frame(height: 2)
            .cornerRadius(1)
            .padding(.horizontal, 10)
            .padding(.top, 1)
            .padding(.bottom, 2)
        }
    }

    private func usageBarColor(_ pct: Double) -> Color {
        if pct < 0.6 { return .green.opacity(0.7) }
        if pct < 0.85 { return .orange.opacity(0.8) }
        return .red.opacity(0.9)
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
    }

    // MARK: - Completion Glow

    private var completionGlowOverlay: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.green.opacity(completionGlow ? 0.6 : 0.0), lineWidth: 1.5)
            .shadow(color: .green.opacity(completionGlow ? 0.4 : 0.0), radius: 6)
    }

    private func triggerCompletionGlow() {
        withAnimation(.easeIn(duration: 0.3)) {
            completionGlow = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.8)) {
                completionGlow = false
            }
        }
    }

    // MARK: - Pulse Animation

    private func startPulseIfNeeded() {
        if session.needsAttention {
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.5
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulseScale = 1.0
            }
        }
    }

    // MARK: - Status Detail

    @ViewBuilder
    private var statusDetailText: some View {
        switch session.status {
        case .runningTool:
            if let tool = session.currentTool {
                HStack(spacing: 3) {
                    toolIcon(tool)
                    Text(toolDisplayName(tool))
                }
            } else {
                Text("Running tool...")
            }
        case .thinking:
            Text("Thinking...")
        case .processing:
            if let prompt = session.lastPrompt {
                Text("You: \(prompt)")
            } else {
                Text("Processing...")
            }
        case .waitingForApproval:
            Text("Needs approval")
                .foregroundColor(Color.orange)
        case .question:
            Text("Waiting for answer")
                .foregroundColor(Color.purple)
        case .compacting:
            Text("Compacting context...")
        case .waitingForInput:
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    if let msg = session.lastAssistantMessage {
                        let preview = msg.count > 50 ? String(msg.prefix(50)) + "..." : msg
                        Text("Claude: \(preview)")
                            .foregroundColor(Color.cyan.opacity(0.7))
                    } else {
                        Text("Waiting for input")
                            .foregroundColor(Color.cyan.opacity(0.6))
                    }
                }
                Spacer()
                Button(action: { viewModel.jumpToSession(session) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.forward.square.fill")
                            .font(.system(size: 9))
                        Text("Reply")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        case .ended:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.green.opacity(0.6))
                Text("Done")
            }
        default:
            Text(session.status.displayName)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var cardContextMenu: some View {
        Button("Jump to Terminal") { viewModel.jumpToSession(session) }
        Button("Hide Session") { viewModel.hideSession(session) }
        Divider()
        if let cwd = session.cwd {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cwd, forType: .string)
            }
        }
        if let model = session.model {
            Button("Copy Model: \(model)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model, forType: .string)
            }
        }
    }

    // MARK: - Tool Helpers

    private func toolIcon(_ tool: String) -> some View {
        let icon: String
        switch tool {
        case "Bash", "run_in_terminal": icon = "terminal"
        case "Edit", "search_replace": icon = "pencil"
        case "Write", "create_file": icon = "doc.badge.plus"
        case "Read", "read_file": icon = "doc.text"
        case "Grep", "grep_code": icon = "magnifyingglass"
        case "Glob", "search_file", "list_dir": icon = "folder.badge.magnifyingglass"
        case "WebFetch", "fetch_content": icon = "globe"
        case "WebSearch", "search_web": icon = "magnifyingglass.circle"
        case "Agent": icon = "person.2"
        default: icon = "wrench"
        }
        return Image(systemName: icon)
            .font(.system(size: 8))
            .foregroundColor(.white.opacity(0.4))
    }

    private func toolDisplayName(_ tool: String) -> String {
        switch tool {
        case "Bash", "run_in_terminal": return "Running..."
        case "Edit", "search_replace": return "Editing"
        case "Write", "create_file": return "Writing"
        case "Read", "read_file": return "Reading"
        case "Grep", "grep_code": return "Searching"
        case "Glob", "search_file", "list_dir": return "Finding"
        case "WebFetch", "fetch_content": return "Fetching"
        case "WebSearch", "search_web": return "Searching web"
        case "Agent": return "Sub-agent"
        default: return tool
        }
    }

    // MARK: - Event History

    private var eventHistory: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(session.events.suffix(10).reversed()) { event in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)

                    if let tool = event.toolName {
                        Text(tool)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(event.eventType)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.35))

                    Spacer()

                    Text(timeAgo(event.timestamp))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .padding(.leading, 34)
    }

    // MARK: - Task List

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 2) {
            let done = session.tasks.filter { $0.status == .completed }.count
            let inProg = session.tasks.filter { $0.status == .inProgress }.count
            let open = session.tasks.filter { $0.status == .pending }.count

            Text("Tasks (\(done) done, \(inProg) in progress, \(open) open)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            ForEach(session.tasks.filter { $0.status != .completed }.prefix(3)) { task in
                HStack(spacing: 4) {
                    Image(systemName: task.status == .inProgress ? "circle.dotted" : "circle")
                        .font(.system(size: 7))
                        .foregroundColor(task.status == .inProgress ? .yellow.opacity(0.6) : .white.opacity(0.3))
                    Text(task.title)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .padding(.leading, 34)
    }

    // MARK: - Helpers

    private func timeAgo(_ date: Date) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h"
    }
}
