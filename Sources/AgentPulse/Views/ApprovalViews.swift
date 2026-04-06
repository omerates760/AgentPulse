// ApprovalViews.swift — AgentPulse
// Permission approval, question, and exit plan views

import SwiftUI

// MARK: - Permission Approval View

struct PermissionApprovalView: View {
    @ObservedObject var permission: PermissionRequest
    let viewModel: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with session info
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)

                Text("Needs approval")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)

                Spacer()

                sessionBadge(for: permission.sessionId)
            }

            // Tool info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: toolIconName(permission.toolName))
                        .font(.system(size: 10))
                        .foregroundColor(.orange.opacity(0.8))
                    Text(permission.toolName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }

                if let cmd = permission.displayCommand {
                    BashCommandView(command: cmd)
                } else if let path = permission.displayFilePath {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }

            // Action buttons
            HStack(spacing: 6) {
                Button(action: { viewModel.denyPermission(permission) }) {
                    Text("Deny")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.approvePermission(permission) }) {
                    Text("Allow Once")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.alwaysAllowPermission(permission) }) {
                    Text("Always")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func toolIconName(_ tool: String) -> String {
        switch tool {
        case "Bash", "run_in_terminal": return "terminal"
        case "Edit", "search_replace": return "pencil"
        case "Write", "create_file": return "doc.badge.plus"
        case "Read", "read_file": return "doc.text"
        case "Grep", "grep_code": return "magnifyingglass"
        case "WebFetch": return "globe"
        default: return "wrench"
        }
    }
}

// MARK: - Bash Command View

struct BashCommandView: View {
    let command: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("$")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.5))

            Text(command)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .cornerRadius(6)
    }
}

// MARK: - Question Group View (groups all questions for one session)

struct QuestionGroupView: View {
    let sessionId: String
    let questions: [QuestionRequest]
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header with session info
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 8, height: 8)

                Text("Claude's Question")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.purple)

                if questions.count > 1 {
                    Text("(\(questions.count) questions)")
                        .font(.system(size: 9))
                        .foregroundColor(.purple.opacity(0.5))
                }

                Spacer()

                sessionBadge(for: sessionId)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Individual questions
            VStack(spacing: 8) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    SingleQuestionCard(
                        question: question,
                        questionIndex: index,
                        totalQuestions: questions.count,
                        viewModel: viewModel
                    )
                    .id(question.id)
                }
            }
            .padding(.horizontal, 10)

            // Bottom: Submit All or Answer in Terminal
            HStack(spacing: 8) {
                if questions.count > 1 {
                    let answered = viewModel.answeredCount(sessionId: sessionId)
                    let allDone = viewModel.allQuestionsAnswered(sessionId: sessionId)

                    Button(action: { viewModel.submitAllAnswers(sessionId: sessionId) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9))
                            Text("Submit All (\(answered)/\(questions.count))")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(allDone ? .white : .white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(allDone ? Color.purple : Color.white.opacity(0.08))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                    .disabled(!allDone)
                }

                Button(action: {
                    if let q = questions.first {
                        viewModel.answerInTerminal(q)
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 9))
                        Text("Terminal")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

// MARK: - Single Question Card

struct SingleQuestionCard: View {
    @ObservedObject var question: QuestionRequest
    let questionIndex: Int
    let totalQuestions: Int
    @ObservedObject var viewModel: NotchViewModel

    @State private var selectedSingle: String? = nil
    @State private var selectedMulti: Set<String> = []
    @State private var freeformText: String = ""

    private var isMultiQuestion: Bool { totalQuestions > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Question header badge + text
            HStack(alignment: .top, spacing: 6) {
                if let header = question.header {
                    Text(header)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                }

                Text(question.question)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Options
            if let options = question.options, !options.isEmpty {
                if question.multiSelect {
                    multiSelectOptions(options)

                    // Confirm button ONLY for single-question + multiSelect
                    if !isMultiQuestion && !selectedMulti.isEmpty {
                        Button(action: {
                            let answer = question.options!.filter { selectedMulti.contains($0) }.joined(separator: ", ")
                            viewModel.answerQuestion(question, answer: answer)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("Confirm Selection (\(selectedMulti.count))")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.purple)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    singleSelectOptions(options)
                }
            } else {
                // Freeform text input
                freeformInput
            }

            // Answered indicator (for multi-question batches)
            if isMultiQuestion, let stored = viewModel.pendingAnswers[question.id] {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    Text(stored)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }

    // MARK: - Single Select

    private func singleSelectOptions(_ options: [String]) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(action: {
                    selectedSingle = option
                    if isMultiQuestion {
                        viewModel.pendingAnswers[question.id] = option
                        viewModel.objectWillChange.send()
                    } else {
                        viewModel.answerQuestion(question, answer: option)
                    }
                }) {
                    HStack(spacing: 8) {
                        // Radio button
                        ZStack {
                            Circle()
                                .stroke(selectedSingle == option ? Color.purple : Color.white.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                            if selectedSingle == option {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 8, height: 8)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(option)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(selectedSingle == option ? .white : .white.opacity(0.7))

                            if let descs = question.optionDescriptions, index < descs.count, !descs[index].isEmpty {
                                Text(descs[index])
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.35))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(selectedSingle == option ? Color.purple.opacity(0.15) : Color.white.opacity(0.03))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Multi Select (Checkbox)

    private func multiSelectOptions(_ options: [String]) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(action: {
                    if selectedMulti.contains(option) {
                        selectedMulti.remove(option)
                    } else {
                        selectedMulti.insert(option)
                    }
                    // Store as comma-separated
                    let answer = selectedMulti.isEmpty ? nil : options.filter { selectedMulti.contains($0) }.joined(separator: ", ")
                    if let answer = answer {
                        viewModel.pendingAnswers[question.id] = answer
                    } else {
                        viewModel.pendingAnswers.removeValue(forKey: question.id)
                    }
                    viewModel.objectWillChange.send()
                }) {
                    HStack(spacing: 8) {
                        // Checkbox
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(selectedMulti.contains(option) ? Color.purple : Color.white.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                            if selectedMulti.contains(option) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.purple)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(option)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(selectedMulti.contains(option) ? .white : .white.opacity(0.7))

                            if let descs = question.optionDescriptions, index < descs.count, !descs[index].isEmpty {
                                Text(descs[index])
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.35))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(selectedMulti.contains(option) ? Color.purple.opacity(0.12) : Color.white.opacity(0.03))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            if !selectedMulti.isEmpty {
                Text("\(selectedMulti.count) selected")
                    .font(.system(size: 9))
                    .foregroundColor(.purple.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Freeform Input

    private var freeformInput: some View {
        HStack(spacing: 6) {
            TextField("Type your answer...", text: $freeformText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .onSubmit {
                    guard !freeformText.isEmpty else { return }
                    if isMultiQuestion {
                        viewModel.pendingAnswers[question.id] = freeformText
                        viewModel.objectWillChange.send()
                    } else {
                        viewModel.answerQuestion(question, answer: freeformText)
                    }
                }

            if !isMultiQuestion {
                Button(action: {
                    guard !freeformText.isEmpty else { return }
                    viewModel.answerQuestion(question, answer: freeformText)
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(freeformText.isEmpty ? .white.opacity(0.2) : .purple)
                }
                .buttonStyle(.plain)
                .disabled(freeformText.isEmpty)
            }
        }
    }
}

// MARK: - Session Badge Helper

func sessionBadge(for sessionId: String) -> some View {
    let store = SessionStore.shared
    let session = store.sessions.first(where: { $0.id == sessionId })
    let name = session?.title ?? session?.projectName ?? "session"
    let agentType = session?.agentType ?? .unknown

    return HStack(spacing: 4) {
        Image(systemName: agentType.iconName)
            .font(.system(size: 8))
            .foregroundColor(Color(agentType.color))
        Text(name)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
            .lineLimit(1)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color(agentType.color).opacity(0.1))
    .cornerRadius(4)
}

// MARK: - Exit Plan Approval View

struct ExitPlanApprovalView: View {
    let sessionId: String
    let viewModel: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "map")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
                Text("Exit Plan Mode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                Spacer()
                Text("Plan")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
            }

            VStack(spacing: 4) {
                planOptionButton(title: "Bypass Permissions", desc: "Skip all permission prompts", icon: "bolt.fill")
                planOptionButton(title: "Auto-accept Edits", desc: "Auto-approve file edits only", icon: "pencil.circle")
                planOptionButton(title: "Manually Approve", desc: "Review each action", icon: "hand.raised")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func planOptionButton(title: String, desc: String, icon: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.7))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text(desc)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy QuestionApprovalView (no longer used, kept for compatibility)

struct QuestionApprovalView: View {
    @ObservedObject var question: QuestionRequest
    let viewModel: NotchViewModel

    var body: some View {
        EmptyView()
    }
}
