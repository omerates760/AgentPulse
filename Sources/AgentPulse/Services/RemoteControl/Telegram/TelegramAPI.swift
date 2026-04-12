// TelegramAPI.swift — AgentPulse
// Thin URLSession wrapper around the Telegram Bot HTTP API.
// Uses JSON encoding with snake_case conversion in both directions.
// Long-poll friendly: URLSession.timeoutIntervalForRequest = 35 covers
// getUpdates with timeout=25 plus some headroom.

import Foundation

enum TelegramError: Error, LocalizedError {
    case invalidToken
    case transport(String)
    case api(code: Int, description: String, retryAfter: Int?)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Invalid or missing bot token"
        case .transport(let msg):
            return "Network error: \(msg)"
        case .api(let code, let desc, _):
            return "Telegram error \(code): \(desc)"
        case .decoding(let msg):
            return "Telegram response decode failed: \(msg)"
        case .cancelled:
            return "Cancelled"
        }
    }
}

final class TelegramAPI {
    private let token: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(token: String) {
        self.token = token

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 35   // long-poll timeout(25) + headroom
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = true
        cfg.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: cfg)

        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = e

        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = d
    }

    // MARK: - Methods

    func getMe() async throws -> TGUser {
        try await call("getMe", body: EmptyBody())
    }

    func getUpdates(offset: Int64, timeout: Int = 25) async throws -> [TGUpdate] {
        struct Req: Encodable {
            let offset: Int64
            let timeout: Int
            let allowedUpdates: [String]
        }
        return try await call(
            "getUpdates",
            body: Req(offset: offset,
                      timeout: timeout,
                      allowedUpdates: ["message", "callback_query"])
        )
    }

    func sendMessage(_ req: TGSendMessageRequest) async throws -> TGMessage {
        try await call("sendMessage", body: req)
    }

    func editMessageText(_ req: TGEditMessageTextRequest) async throws {
        let _: MessageOrBool = try await call("editMessageText", body: req)
    }

    func editMessageReplyMarkup(_ req: TGEditMessageReplyMarkupRequest) async throws {
        let _: MessageOrBool = try await call("editMessageReplyMarkup", body: req)
    }

    func answerCallbackQuery(_ req: TGAnswerCallbackQueryRequest) async throws {
        let _: Bool = try await call("answerCallbackQuery", body: req)
    }

    // MARK: - Transport

    private struct EmptyBody: Encodable {}

    /// Telegram's edit* methods return either a full Message (if editing a
    /// message sent by the bot) or just `true`. We accept both and ignore
    /// the payload.
    private enum MessageOrBool: Decodable {
        case message(TGMessage)
        case bool(Bool)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) {
                self = .bool(b)
            } else {
                self = .message(try c.decode(TGMessage.self))
            }
        }
    }

    private func call<Req: Encodable, Res: Decodable>(
        _ method: String,
        body: Req
    ) async throws -> Res {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
            throw TelegramError.invalidToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw TelegramError.decoding("encode \(method): \(error.localizedDescription)")
        }

        let data: Data
        do {
            let (d, _) = try await session.data(for: request)
            data = d
        } catch is CancellationError {
            throw TelegramError.cancelled
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw TelegramError.cancelled
        } catch {
            throw TelegramError.transport(error.localizedDescription)
        }

        let envelope: TGResponse<Res>
        do {
            envelope = try decoder.decode(TGResponse<Res>.self, from: data)
        } catch {
            throw TelegramError.decoding("\(method): \(error.localizedDescription)")
        }

        if envelope.ok, let result = envelope.result {
            return result
        }

        let code = envelope.errorCode ?? -1
        let desc = envelope.description ?? "unknown"
        if code == 401 { throw TelegramError.invalidToken }
        throw TelegramError.api(
            code: code,
            description: desc,
            retryAfter: envelope.parameters?.retryAfter
        )
    }
}
