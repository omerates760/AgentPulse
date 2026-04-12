// TelegramAdapter.swift — AgentPulse
// RemoteControlAdapter that bridges AgentPulse events to a Telegram bot.
//
// Responsibilities
//   • Read bot token (Keychain) and paired chat id (UserDefaults)
//   • Send permission/question messages with inline keyboards
//   • Long-poll getUpdates for callback_query and inbound messages
//   • Route user responses back to RemoteControlService via onResponse
//   • Edit/remove keyboards when requests resolve via any channel
//
// Threading
//   Regular class (not an actor) to match the protocol's synchronous property
//   requirements. Internal state is protected by a serial dispatch queue;
//   network I/O happens inside async Tasks on URLSession's own queues. The
//   onResponse closure is always invoked on the main thread via a
//   DispatchQueue.main.async hop inside RemoteControlService.

import Foundation

final class TelegramAdapter: RemoteControlAdapter {
    let identifier = "telegram"

    var isEnabled: Bool {
        RemoteControlSettings.telegramEnabled
            && RemoteControlSecretsStore.telegramToken() != nil
            && RemoteControlSettings.telegramChatId != nil
    }

    var onResponse: ((RemoteControlResponse) -> Void)?

    // MARK: - State (protected by stateQueue)

    private struct PostedMessage {
        let chatId: Int64
        let messageId: Int64
    }

    private let stateQueue = DispatchQueue(label: "com.agentpulse.telegram.state")
    private var _api: TelegramAPI?
    private var _pollTask: Task<Void, Never>?
    private var _postedMessages: [String: PostedMessage] = [:]
    private var _pendingQuestions: [String: QuestionRequest] = [:]
    private var _multiSelectState: [String: Set<Int>] = [:]

    private var api: TelegramAPI? {
        stateQueue.sync { _api }
    }

    private func setAPI(_ value: TelegramAPI?) {
        stateQueue.sync { _api = value }
    }

    private func setPollTask(_ task: Task<Void, Never>?) {
        stateQueue.sync {
            _pollTask?.cancel()
            _pollTask = task
        }
    }

    private func cancelPollTask() {
        stateQueue.sync {
            _pollTask?.cancel()
            _pollTask = nil
        }
    }

    private func recordPosted(requestId: String, chatId: Int64, messageId: Int64) {
        stateQueue.sync {
            _postedMessages[requestId] = PostedMessage(chatId: chatId, messageId: messageId)
        }
    }

    private func takePosted(requestId: String) -> PostedMessage? {
        stateQueue.sync {
            _postedMessages.removeValue(forKey: requestId)
        }
    }

    private func postedMessage(requestId: String) -> PostedMessage? {
        stateQueue.sync { _postedMessages[requestId] }
    }

    private func cacheQuestion(_ q: QuestionRequest) {
        stateQueue.sync { _pendingQuestions[q.id] = q }
    }

    private func pendingQuestion(id: String) -> QuestionRequest? {
        stateQueue.sync { _pendingQuestions[id] }
    }

    private func clearQuestion(id: String) {
        stateQueue.sync {
            _pendingQuestions.removeValue(forKey: id)
            _multiSelectState.removeValue(forKey: id)
        }
    }

    private func toggleMultiSelection(id: String, index: Int) -> Set<Int> {
        stateQueue.sync {
            var set = _multiSelectState[id] ?? []
            if set.contains(index) { set.remove(index) } else { set.insert(index) }
            _multiSelectState[id] = set
            return set
        }
    }

    private func multiSelection(id: String) -> Set<Int> {
        stateQueue.sync { _multiSelectState[id] ?? [] }
    }

    /// Find a free-text question whose posted messageId matches `replyTo`.
    private func freeTextQuestionId(forReplyTo messageId: Int64) -> String? {
        stateQueue.sync {
            for (qid, q) in _pendingQuestions where (q.options?.isEmpty ?? true) {
                if let posted = _postedMessages[qid], posted.messageId == messageId {
                    return qid
                }
            }
            return nil
        }
    }

    /// All pending free-text question ids (for fallback matching when the
    /// user replies with plain text instead of a quoted reply).
    private func allFreeTextQuestionIds() -> [String] {
        stateQueue.sync {
            _pendingQuestions.compactMap { (id, q) in
                (q.options?.isEmpty ?? true) ? id : nil
            }
        }
    }

    // MARK: - Lifecycle

    init() {}

    func start() async {
        guard let token = RemoteControlSecretsStore.telegramToken() else {
            DiagnosticLogger.shared.log("[rc/telegram] start skipped — no token")
            return
        }
        setAPI(TelegramAPI(token: token))

        if RemoteControlSettings.telegramChatId != nil {
            let task = Task { [weak self] in
                guard let self = self else { return }
                await self.runPollLoop()
            }
            setPollTask(task)
        }

        DiagnosticLogger.shared.log("[rc/telegram] started")
    }

    func stop() async {
        cancelPollTask()
        setAPI(nil)
        DiagnosticLogger.shared.log("[rc/telegram] stopped")
    }

    // MARK: - Event handling (service → Telegram)

    func notify(_ event: RemoteControlEvent) async {
        switch event {
        case .permissionRequested(let perm, let title, let agent):
            await sendPermission(perm, sessionTitle: title, agent: agent)

        case .questionRequested(let q, let title, let agent):
            await sendQuestion(q, sessionTitle: title, agent: agent)

        case .permissionResolved(let id):
            await resolvePosted(requestId: id)

        case .questionResolved(let id):
            clearQuestion(id: id)
            await resolvePosted(requestId: id)

        case .sessionStarted, .sessionEnded:
            break  // Not forwarded to Telegram — too noisy.
        }
    }

    // MARK: - Permission rendering

    private func sendPermission(_ perm: PermissionRequest,
                                sessionTitle: String,
                                agent: AgentType) async {
        guard let api = api, let chatId = RemoteControlSettings.telegramChatId else { return }

        let text = Self.renderPermissionText(perm: perm, sessionTitle: sessionTitle, agent: agent)
        let markup = Self.permissionKeyboard(requestId: perm.id)
        let req = TGSendMessageRequest(chatId: chatId, text: text, replyMarkup: markup)

        do {
            let sent = try await api.sendMessage(req)
            recordPosted(requestId: perm.id, chatId: chatId, messageId: sent.messageId)
            DiagnosticLogger.shared.log("[rc/telegram] posted permission id=\(perm.id) msg=\(sent.messageId)")
        } catch {
            DiagnosticLogger.shared.log("[rc/telegram] sendPermission failed: \(error.localizedDescription)")
        }
    }

    private static func renderPermissionText(perm: PermissionRequest,
                                              sessionTitle: String,
                                              agent: AgentType) -> String {
        var lines: [String] = []
        lines.append("🟠 <b>Permission needed</b>")
        lines.append("<b>\(escapeHTML(agent.displayName))</b> — <i>\(escapeHTML(sessionTitle))</i>")
        lines.append("Tool: <code>\(escapeHTML(perm.toolName))</code>")
        lines.append("")

        if let cmd = perm.displayCommand {
            lines.append("<pre>\(escapeHTML(truncate(cmd, max: 1500)))</pre>")
        } else if let path = perm.displayFilePath {
            lines.append("📄 <code>\(escapeHTML(path))</code>")
        } else {
            lines.append(escapeHTML(perm.displayDescription))
        }

        return lines.joined(separator: "\n")
    }

    private static func permissionKeyboard(requestId: String) -> TGInlineKeyboardMarkup {
        TGInlineKeyboardMarkup(inlineKeyboard: [[
            TGInlineKeyboardButton(text: "✅ Allow",  callbackData: "p|allow|\(requestId)"),
            TGInlineKeyboardButton(text: "♾ Always", callbackData: "p|always|\(requestId)"),
            TGInlineKeyboardButton(text: "❌ Deny",   callbackData: "p|deny|\(requestId)"),
        ]])
    }

    // MARK: - Question rendering

    private func sendQuestion(_ q: QuestionRequest,
                              sessionTitle: String,
                              agent: AgentType) async {
        guard let api = api, let chatId = RemoteControlSettings.telegramChatId else { return }

        cacheQuestion(q)

        let options = q.options ?? []
        let text: String
        let markup: TGInlineKeyboardMarkup?

        if options.isEmpty {
            text = Self.renderFreeTextQuestion(q: q, sessionTitle: sessionTitle, agent: agent)
            markup = nil
        } else if q.multiSelect {
            text = Self.renderQuestionHeader(q: q, sessionTitle: sessionTitle, agent: agent)
            markup = Self.multiSelectKeyboard(questionId: q.id, options: options, selected: [])
        } else {
            text = Self.renderQuestionHeader(q: q, sessionTitle: sessionTitle, agent: agent)
            markup = Self.singleSelectKeyboard(questionId: q.id, options: options)
        }

        let req = TGSendMessageRequest(chatId: chatId, text: text, replyMarkup: markup)

        do {
            let sent = try await api.sendMessage(req)
            recordPosted(requestId: q.id, chatId: chatId, messageId: sent.messageId)
            DiagnosticLogger.shared.log("[rc/telegram] posted question id=\(q.id) msg=\(sent.messageId) kind=\(options.isEmpty ? "free" : (q.multiSelect ? "multi" : "single"))")
        } catch {
            DiagnosticLogger.shared.log("[rc/telegram] sendQuestion failed: \(error.localizedDescription)")
        }
    }

    private static func renderQuestionHeader(q: QuestionRequest,
                                              sessionTitle: String,
                                              agent: AgentType) -> String {
        var lines: [String] = []
        lines.append("🟣 <b>Question</b>")
        lines.append("<b>\(escapeHTML(agent.displayName))</b> — <i>\(escapeHTML(sessionTitle))</i>")
        lines.append("")
        if let header = q.header, !header.isEmpty {
            lines.append("<b>\(escapeHTML(header))</b>")
        }
        lines.append(escapeHTML(q.question))
        if q.multiSelect {
            lines.append("")
            lines.append("<i>Tap options to toggle, then Submit.</i>")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderFreeTextQuestion(q: QuestionRequest,
                                                sessionTitle: String,
                                                agent: AgentType) -> String {
        var lines: [String] = []
        lines.append("🟣 <b>Question</b>")
        lines.append("<b>\(escapeHTML(agent.displayName))</b> — <i>\(escapeHTML(sessionTitle))</i>")
        lines.append("")
        if let header = q.header, !header.isEmpty {
            lines.append("<b>\(escapeHTML(header))</b>")
        }
        lines.append(escapeHTML(q.question))
        lines.append("")
        lines.append("<i>Reply to this message with your answer.</i>")
        return lines.joined(separator: "\n")
    }

    private static func singleSelectKeyboard(questionId: String,
                                              options: [String]) -> TGInlineKeyboardMarkup {
        let rows = options.enumerated().map { (idx, label) in
            [TGInlineKeyboardButton(
                text: truncate(label, max: 60),
                callbackData: "q|opt|\(questionId)|\(idx)"
            )]
        }
        return TGInlineKeyboardMarkup(inlineKeyboard: rows)
    }

    private static func multiSelectKeyboard(questionId: String,
                                             options: [String],
                                             selected: Set<Int>) -> TGInlineKeyboardMarkup {
        var rows: [[TGInlineKeyboardButton]] = options.enumerated().map { (idx, label) in
            let marker = selected.contains(idx) ? "☑" : "☐"
            return [TGInlineKeyboardButton(
                text: "\(marker) \(truncate(label, max: 58))",
                callbackData: "q|mtg|\(questionId)|\(idx)"
            )]
        }
        let submitLabel = selected.isEmpty ? "✅ Submit" : "✅ Submit (\(selected.count))"
        rows.append([TGInlineKeyboardButton(
            text: submitLabel,
            callbackData: "q|msub|\(questionId)"
        )])
        return TGInlineKeyboardMarkup(inlineKeyboard: rows)
    }

    // MARK: - Resolution (message dismissal)

    private func resolvePosted(requestId: String) async {
        guard let posted = takePosted(requestId: requestId), let api = api else { return }
        let req = TGEditMessageReplyMarkupRequest(
            chatId: posted.chatId,
            messageId: posted.messageId,
            replyMarkup: nil
        )
        do {
            try await api.editMessageReplyMarkup(req)
        } catch {
            // Non-fatal: message may have been deleted by user, or another
            // edit already ran. Log and move on.
            DiagnosticLogger.shared.log("[rc/telegram] resolve edit failed id=\(requestId): \(error.localizedDescription)")
        }
    }

    // MARK: - Poll loop (Telegram → service)

    private func runPollLoop() async {
        DiagnosticLogger.shared.log("[rc/telegram] poll loop started")
        defer { DiagnosticLogger.shared.log("[rc/telegram] poll loop exited") }

        var offset: Int64 = 0
        var backoffSeconds: UInt64 = 1

        // Initial drain so we don't replay stale updates.
        if let api = api {
            if let initial = try? await api.getUpdates(offset: 0, timeout: 0) {
                for u in initial { offset = max(offset, u.updateId + 1) }
            }
        }

        while !Task.isCancelled {
            guard let api = api else { return }
            do {
                let updates = try await api.getUpdates(offset: offset, timeout: 25)
                backoffSeconds = 1
                for update in updates {
                    offset = max(offset, update.updateId + 1)
                    if Task.isCancelled { return }
                    await handleUpdate(update)
                }
            } catch TelegramError.cancelled {
                return
            } catch TelegramError.api(_, _, let retryAfter) where retryAfter != nil {
                let seconds = max(1, retryAfter ?? 1)
                DiagnosticLogger.shared.log("[rc/telegram] rate-limited, sleep \(seconds)s")
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            } catch {
                DiagnosticLogger.shared.log("[rc/telegram] poll error: \(error.localizedDescription) — backoff \(backoffSeconds)s")
                try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                backoffSeconds = min(backoffSeconds * 2, 60)
            }
        }
    }

    private func handleUpdate(_ update: TGUpdate) async {
        guard let pairedChatId = RemoteControlSettings.telegramChatId else { return }

        if let cb = update.callbackQuery {
            guard cb.message?.chat.id == pairedChatId else {
                DiagnosticLogger.shared.log("[rc/telegram] drop callback from chat=\(cb.message?.chat.id ?? -1)")
                return
            }
            await handleCallback(cb)
            return
        }

        if let msg = update.message {
            guard msg.chat.id == pairedChatId else {
                DiagnosticLogger.shared.log("[rc/telegram] drop message from chat=\(msg.chat.id)")
                return
            }
            await handleMessage(msg)
        }
    }

    // MARK: - Callback handling

    private enum ParsedCallback {
        case permissionAllow(id: String)
        case permissionAlways(id: String)
        case permissionDeny(id: String)
        case questionOption(id: String, index: Int)
        case questionMultiToggle(id: String, index: Int)
        case questionMultiSubmit(id: String)
    }

    private static func parseCallback(_ data: String) -> ParsedCallback? {
        let parts = data.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let kind = parts[0]
        let action = parts[1]
        let id = parts[2]
        let arg: Int? = parts.count > 3 ? Int(parts[3]) : nil

        switch (kind, action) {
        case ("p", "allow"):  return .permissionAllow(id: id)
        case ("p", "always"): return .permissionAlways(id: id)
        case ("p", "deny"):   return .permissionDeny(id: id)
        case ("q", "opt"):    return arg.map { .questionOption(id: id, index: $0) }
        case ("q", "mtg"):    return arg.map { .questionMultiToggle(id: id, index: $0) }
        case ("q", "msub"):   return .questionMultiSubmit(id: id)
        default:              return nil
        }
    }

    private func handleCallback(_ cb: TGCallbackQuery) async {
        // ACK immediately — Telegram hangs the button spinner if we miss the 10s deadline.
        let ack = TGAnswerCallbackQueryRequest(callbackQueryId: cb.id, text: nil, showAlert: nil)
        if let api = api {
            _ = try? await api.answerCallbackQuery(ack)
        }

        guard let data = cb.data, let parsed = Self.parseCallback(data) else {
            DiagnosticLogger.shared.log("[rc/telegram] unparseable callback_data")
            return
        }

        switch parsed {
        case .permissionAllow(let id):
            guard postedMessage(requestId: id) != nil else {
                await toast(cb: cb, text: "This request is no longer valid")
                return
            }
            onResponse?(.approvePermission(requestId: id))

        case .permissionAlways(let id):
            guard postedMessage(requestId: id) != nil else {
                await toast(cb: cb, text: "This request is no longer valid")
                return
            }
            onResponse?(.alwaysAllowPermission(requestId: id))

        case .permissionDeny(let id):
            guard postedMessage(requestId: id) != nil else {
                await toast(cb: cb, text: "This request is no longer valid")
                return
            }
            onResponse?(.denyPermission(requestId: id))

        case .questionOption(let id, let index):
            guard let q = pendingQuestion(id: id),
                  let options = q.options,
                  index >= 0, index < options.count else {
                await toast(cb: cb, text: "This question is no longer valid")
                return
            }
            onResponse?(.answerQuestion(requestId: id, answer: options[index]))

        case .questionMultiToggle(let id, let index):
            guard let q = pendingQuestion(id: id),
                  let options = q.options,
                  index >= 0, index < options.count else {
                await toast(cb: cb, text: "This question is no longer valid")
                return
            }
            let newSet = toggleMultiSelection(id: id, index: index)
            await redrawMultiSelect(questionId: id, options: options, selected: newSet)

        case .questionMultiSubmit(let id):
            guard let q = pendingQuestion(id: id), let options = q.options else {
                await toast(cb: cb, text: "This question is no longer valid")
                return
            }
            let selected = multiSelection(id: id).sorted()
            guard !selected.isEmpty else {
                await toast(cb: cb, text: "Select at least one option")
                return
            }
            let answer = selected.map { options[$0] }.joined(separator: ", ")
            onResponse?(.answerQuestion(requestId: id, answer: answer))
        }
    }

    private func redrawMultiSelect(questionId: String,
                                    options: [String],
                                    selected: Set<Int>) async {
        guard let posted = postedMessage(requestId: questionId), let api = api else { return }
        let markup = Self.multiSelectKeyboard(questionId: questionId,
                                              options: options,
                                              selected: selected)
        let req = TGEditMessageReplyMarkupRequest(
            chatId: posted.chatId,
            messageId: posted.messageId,
            replyMarkup: markup
        )
        do {
            try await api.editMessageReplyMarkup(req)
        } catch {
            DiagnosticLogger.shared.log("[rc/telegram] redraw multi-select failed: \(error.localizedDescription)")
        }
    }

    private func toast(cb: TGCallbackQuery, text: String) async {
        guard let api = api else { return }
        let req = TGAnswerCallbackQueryRequest(callbackQueryId: cb.id, text: text, showAlert: false)
        _ = try? await api.answerCallbackQuery(req)
    }

    // MARK: - Message handling (free-text replies)

    private func handleMessage(_ msg: TGMessage) async {
        guard let text = msg.text, !text.isEmpty else { return }
        // Ignore commands — we only care about free-text answers.
        if text.hasPrefix("/") { return }

        // Preferred path: user used Telegram's reply-to-message on a posted question.
        if let replyTo = msg.replyToMessage?.messageId,
           let qid = freeTextQuestionId(forReplyTo: replyTo) {
            onResponse?(.answerQuestion(requestId: qid, answer: text))
            return
        }

        // Fallback: exactly one outstanding free-text question → treat plain
        // text as the answer. Avoids making users hunt for the reply gesture.
        let pending = allFreeTextQuestionIds()
        if pending.count == 1 {
            onResponse?(.answerQuestion(requestId: pending[0], answer: text))
        }
    }

    // MARK: - Helpers

    private static func escapeHTML(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        return out
    }

    private static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    // MARK: - Settings API

    /// Validates the stored token by calling getMe. Returns the bot's username
    /// (or first name as fallback).
    func testConnection() async throws -> String {
        guard let token = RemoteControlSecretsStore.telegramToken(), !token.isEmpty else {
            throw TelegramError.invalidToken
        }
        let api = TelegramAPI(token: token)
        let me = try await api.getMe()
        return me.username ?? me.firstName ?? "bot"
    }

    /// Waits for the user to send `/start` to the bot. Runs a short-poll
    /// getUpdates loop for up to 60 seconds. Returns the paired chat id, or
    /// nil if timed out. Also catches a /start that was already pending when
    /// the user pressed Connect.
    func discoverChatId() async throws -> Int64? {
        guard let token = RemoteControlSecretsStore.telegramToken() else {
            throw TelegramError.invalidToken
        }
        let api = TelegramAPI(token: token)

        var offset: Int64 = 0
        let deadline = Date().addingTimeInterval(60)

        // Initial peek: drain any stale updates and pick up a pre-existing /start.
        if let initial = try? await api.getUpdates(offset: 0, timeout: 0) {
            for update in initial {
                offset = max(offset, update.updateId + 1)
                if let msg = update.message, msg.text == "/start" {
                    return try await confirmPairing(api: api, chatId: msg.chat.id)
                }
            }
        }

        while Date() < deadline {
            if Task.isCancelled { throw TelegramError.cancelled }
            do {
                let updates = try await api.getUpdates(offset: offset, timeout: 15)
                for update in updates {
                    offset = max(offset, update.updateId + 1)
                    if let msg = update.message, msg.text == "/start" {
                        return try await confirmPairing(api: api, chatId: msg.chat.id)
                    }
                }
            } catch TelegramError.cancelled {
                throw TelegramError.cancelled
            } catch {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        return nil
    }

    private func confirmPairing(api: TelegramAPI, chatId: Int64) async throws -> Int64 {
        let req = TGSendMessageRequest(
            chatId: chatId,
            text: "✅ <b>AgentPulse paired!</b>\nYou will receive permission prompts and questions here.",
            replyMarkup: nil
        )
        _ = try? await api.sendMessage(req)
        return chatId
    }
}
