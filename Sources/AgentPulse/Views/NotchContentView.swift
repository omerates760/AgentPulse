// NotchContentView.swift — AgentPulse
// Main content view embedded in the notch panel

import SwiftUI

struct NotchContentView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        ZStack {
            if viewModel.isExpanded {
                expandedContent
                    .transition(.blurFade)
            } else {
                collapsedContent
                    .transition(.blurFade)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isExpanded)
    }

    // MARK: - Collapsed (pill in notch)

    @State private var idlePulse: Bool = false

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            if viewModel.sessionCount > 0 {
                // Left: agent icon + status dot
                HStack(spacing: 6) {
                    // First session's agent icon
                    if let first = viewModel.activeSessions.first {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: first.agentType.iconName)
                                .font(.system(size: 9))
                                .foregroundColor(Color(first.agentType.color))
                            Circle()
                                .fill(Color(first.status.statusColor))
                                .frame(width: 5, height: 5)
                                .offset(x: 3, y: 2)
                        }
                    }

                    // Separator
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 14)

                    // Center: primary info
                    collapsedInfoText

                    // Right: additional session dots
                    if viewModel.activeSessions.count > 1 {
                        HStack(spacing: 3) {
                            ForEach(viewModel.activeSessions.dropFirst().prefix(3)) { s in
                                Circle()
                                    .fill(Color(s.status.statusColor))
                                    .frame(width: 4, height: 4)
                            }
                            if viewModel.activeSessions.count > 4 {
                                Text("+\(viewModel.activeSessions.count - 4)")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                }
            } else {
                // Idle
                HStack(spacing: 5) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan.opacity(idlePulse ? 0.7 : 0.3), .purple.opacity(idlePulse ? 0.5 : 0.2)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    Text("VI")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(idlePulse ? 0.45 : 0.25))
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        idlePulse = true
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(height: 26)
        .background(
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.92))
                if viewModel.needsAttentionCount > 0 {
                    Capsule()
                        .stroke(Color(viewModel.collapsedStatusColor).opacity(0.4), lineWidth: 1)
                        .shadow(color: Color(viewModel.collapsedStatusColor).opacity(0.2), radius: 4)
                } else if viewModel.sessionCount > 0 {
                    Capsule()
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                }
            }
        )
    }

    @ViewBuilder
    private var collapsedInfoText: some View {
        if !viewModel.activePermissions.isEmpty {
            // Permission waiting
            HStack(spacing: 3) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.orange)
                Text("Approve")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.orange)
            }
        } else if !viewModel.activeQuestions.isEmpty {
            // Question waiting
            HStack(spacing: 3) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.purple)
                Text("Question")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.purple)
            }
        } else if let first = viewModel.activeSessions.first {
            // Active session info — single MorphText so it persists across state changes
            HStack(spacing: 4) {
                MorphText(
                    text: pillStatusText(for: first),
                    font: .system(size: 9, weight: .medium, design: .monospaced),
                    color: pillStatusColor(for: first)
                )

                if viewModel.sessionCount > 1 {
                    Text("·\(viewModel.sessionCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
    }

    private func pillStatusText(for session: Session) -> String {
        if session.status == .runningTool, let tool = session.currentTool {
            return shortToolName(tool)
        }
        switch session.status {
        case .waitingForInput: return "Ready"
        case .thinking:        return "Thinking"
        case .processing:      return "Processing"
        case .compacting:      return "Compacting"
        default:               return session.projectName
        }
    }

    private func pillStatusColor(for session: Session) -> Color {
        if session.status == .runningTool { return .green.opacity(0.8) }
        switch session.status {
        case .waitingForInput: return .cyan.opacity(0.7)
        case .thinking:        return .white.opacity(0.5)
        case .processing:      return .white.opacity(0.5)
        default:               return .white.opacity(0.5)
        }
    }

    private func shortToolName(_ tool: String) -> String {
        switch tool {
        case "Bash": return "$ run"
        case "Edit": return "editing"
        case "Read": return "reading"
        case "Write": return "writing"
        case "Grep": return "search"
        case "Glob": return "find"
        case "Agent": return "agent"
        default: return tool.lowercased()
        }
    }

    // MARK: - Expanded Panel

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Top bar: branding + tabs
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            // Session info + rate limit
            if viewModel.selectedTab == .sessions {
                sessionInfoBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Thin separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.08), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    switch viewModel.selectedTab {
                    case .sessions:
                        sessionsTab
                            .transition(.blurFade)
                    case .settings:
                        SettingsView(viewModel: viewModel)
                            .transition(.blurFade)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.selectedTab)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Branding
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("AgentPulse")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Tab switcher
            HStack(spacing: 1) {
                tabButton("Sessions", icon: "square.stack.3d.up", tab: .sessions)
                tabButton("Settings", icon: "gearshape", tab: .settings)
            }
            .padding(2)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
        }
    }

    private func tabButton(_ title: String, icon: String, tab: NotchViewModel.PanelTab) -> some View {
        let isActive = viewModel.selectedTab == tab
        return Button(action: { viewModel.selectedTab = tab }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.35))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.white.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session Info Bar

    private var sessionInfoBar: some View {
        HStack(spacing: 8) {
            // Session count
            HStack(spacing: 4) {
                Text("\(viewModel.sessionCount)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Text(viewModel.sessionCount == 1 ? "session" : "sessions")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            // Attention badge
            if viewModel.needsAttentionCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(viewModel.collapsedStatusColor))
                        .frame(width: 6, height: 6)
                    Text("\(viewModel.needsAttentionCount) waiting")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(viewModel.collapsedStatusColor))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(viewModel.collapsedStatusColor).opacity(0.12))
                .cornerRadius(5)
            }

            Spacer()

            // Rate limit indicator
            if let rl = viewModel.activeSessions.first?.rateLimits {
                rateLimitCompact(rl)
            }
        }
    }

    private func rateLimitCompact(_ rl: RateLimits) -> some View {
        let pct = rl.primaryUsedPercent
        let color: Color = pct > 80 ? .red : pct > 50 ? .orange : .green
        return HStack(spacing: 5) {
            // Mini bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(pct, 100) / 100))
                }
            }
            .frame(width: 40, height: 4)

            Text("\(Int(pct))%")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Rate Limit Bar

    @ViewBuilder
    private var rateLimitBar: some View {
        if let rl = viewModel.activeSessions.first?.rateLimits {
            let pct = min(max(rl.primaryUsedPercent, 0), 100)
            let barColor: Color = pct > 80 ? .red : pct > 50 ? .orange : .green

            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)

                        // Fill
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                LinearGradient(
                                    colors: [barColor.opacity(0.7), barColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(pct / 100), height: 3)
                            .animation(.easeInOut(duration: 0.5), value: pct)
                    }
                }
                .frame(height: 3)

                // Reset time label
                if let resetTime = rl.primaryResetsAt {
                    HStack {
                        Spacer()
                        Text("resets \(resetTime)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                    }
                }
            }
        }
    }

    private func rateLimitBadge(_ rl: RateLimits) -> some View {
        let pct = rl.primaryUsedPercent
        let color: Color = pct > 80 ? .red : pct > 50 ? .orange : .green
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(Int(pct))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }

    // MARK: - Sessions Tab

    private var sessionsTab: some View {
        VStack(spacing: 6) {
            // Pending permissions
            ForEach(Array(viewModel.activePermissions), id: \.id) { perm in
                PermissionApprovalView(permission: perm, viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            // Pending questions — grouped by session
            ForEach(questionSessionIds, id: \.self) { sessionId in
                let sessionQuestions = viewModel.activeQuestions.filter { $0.sessionId == sessionId }
                if !sessionQuestions.isEmpty {
                    QuestionGroupView(
                        sessionId: sessionId,
                        questions: sessionQuestions,
                        viewModel: viewModel
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }

            // Active sessions — grouped by project
            if viewModel.activeSessions.isEmpty && viewModel.activePermissions.isEmpty && viewModel.activeQuestions.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                ForEach(projectGroups, id: \.path) { group in
                    ProjectGroupSection(
                        group: group,
                        viewModel: viewModel
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }

            // Ended sessions
            if !viewModel.endedSessions.isEmpty {
                endedSessionsSection
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.activeSessions.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.activePermissions.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.activeQuestions.count)
    }

    // Unique session IDs that have active questions
    private var questionSessionIds: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for q in viewModel.activeQuestions {
            if seen.insert(q.sessionId).inserted {
                result.append(q.sessionId)
            }
        }
        return result
    }

    // MARK: - Project Grouping

    private var projectGroups: [ProjectGroup] {
        var groups: [String: [Session]] = [:]
        for session in viewModel.activeSessions {
            let key = session.cwd ?? "Unknown"
            groups[key, default: []].append(session)
        }
        return groups.map { ProjectGroup(path: $0.key, sessions: $0.value) }
            .sorted { $0.sessions.count > $1.sessions.count }
    }

    // MARK: - Ended Sessions

    private var endedSessionsSection: some View {
        DisclosureGroup {
            ForEach(viewModel.endedSessions.suffix(5)) { session in
                SessionCardView(session: session, viewModel: viewModel)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                Text("\(viewModel.endedSessions.count) ended")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .tint(.white.opacity(0.4))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        WaveformEmptyState()
    }
}

// MARK: - Project Group Model

private struct ProjectGroup: Identifiable {
    let path: String
    var sessions: [Session]

    var id: String { path }

    var projectName: String {
        path.split(separator: "/").last.map(String.init) ?? "Unknown"
    }
}

// MARK: - Project Group Section

private struct ProjectGroupSection: View {
    let group: ProjectGroup
    @ObservedObject var viewModel: NotchViewModel

    private var showHeader: Bool {
        group.sessions.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Project header — only if there are multiple sessions in this group
            if showHeader {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))

                    Text(group.projectName)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    Text("\(group.sessions.count)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(3)

                    Spacer()

                    // Truncated path
                    Text(truncatedPath(group.path))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.03))
                )
            }

            // Sessions within this group
            ForEach(group.sessions) { session in
                SessionCardView(session: session, viewModel: viewModel)
            }
        }
    }

    private func truncatedPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 3 { return path }
        return "~/" + components.suffix(2).joined(separator: "/")
    }
}

// MARK: - Waveform Empty State

private struct WaveformEmptyState: View {
    @State private var wavePhase: CGFloat = 0

    private let dotCount = 12
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            // Animated waveform dots
            HStack(spacing: 5) {
                ForEach(0..<dotCount, id: \.self) { index in
                    let offset = sin(wavePhase + CGFloat(index) * 0.5) * 6
                    Circle()
                        .fill(dotColor(for: index))
                        .frame(width: 4, height: 4)
                        .offset(y: offset)
                }
            }
            .frame(height: 24)
            .onReceive(timer) { _ in
                wavePhase += 0.08
            }

            Text("The island awaits")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            Text("Start coding to light it up")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))

            VStack(alignment: .leading, spacing: 4) {
                supportedAgentRow("Claude Code", icon: "brain.head.profile")
                supportedAgentRow("Codex", icon: "terminal")
                supportedAgentRow("Gemini CLI", icon: "sparkles")
                supportedAgentRow("Cursor", icon: "cursorarrow.rays")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func dotColor(for index: Int) -> Color {
        let progress = sin(wavePhase + CGFloat(index) * 0.5)
        let brightness = 0.15 + (progress + 1) * 0.1  // range: 0.15 to 0.35
        return Color.white.opacity(brightness)
    }

    private func supportedAgentRow(_ name: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 14)
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}
