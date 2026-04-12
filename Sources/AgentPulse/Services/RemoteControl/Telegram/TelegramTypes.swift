// TelegramTypes.swift — AgentPulse
// Codable wire types for the Telegram Bot API.
// Encoding uses convertToSnakeCase (chatId → chat_id) and decoding uses
// convertFromSnakeCase (update_id → updateId), so all Swift-side names
// stay in camelCase.

import Foundation

// MARK: - Incoming

struct TGUpdate: Decodable {
    let updateId: Int64
    let message: TGMessage?
    let callbackQuery: TGCallbackQuery?
}

struct TGMessage: Decodable {
    let messageId: Int64
    let chat: TGChat
    let from: TGUser?
    let text: String?
    let replyToMessage: TGReplyStub?
}

/// Minimal stub for `reply_to_message` — we only need the message id to
/// correlate free-text replies with outstanding questions.
struct TGReplyStub: Decodable {
    let messageId: Int64
}

struct TGChat: Decodable {
    let id: Int64
    let type: String
    let title: String?
}

struct TGUser: Decodable {
    let id: Int64
    let firstName: String?
    let username: String?
    let isBot: Bool?
}

struct TGCallbackQuery: Decodable {
    let id: String
    let from: TGUser
    let message: TGMessage?
    let data: String?
}

// MARK: - Outgoing

struct TGInlineKeyboardButton: Encodable {
    let text: String
    let callbackData: String
}

struct TGInlineKeyboardMarkup: Encodable {
    let inlineKeyboard: [[TGInlineKeyboardButton]]
}

struct TGSendMessageRequest: Encodable {
    let chatId: Int64
    let text: String
    let parseMode: String
    let replyMarkup: TGInlineKeyboardMarkup?

    init(chatId: Int64,
         text: String,
         parseMode: String = "HTML",
         replyMarkup: TGInlineKeyboardMarkup? = nil) {
        self.chatId = chatId
        self.text = text
        self.parseMode = parseMode
        self.replyMarkup = replyMarkup
    }
}

struct TGEditMessageTextRequest: Encodable {
    let chatId: Int64
    let messageId: Int64
    let text: String
    let parseMode: String
    let replyMarkup: TGInlineKeyboardMarkup?
}

struct TGEditMessageReplyMarkupRequest: Encodable {
    let chatId: Int64
    let messageId: Int64
    let replyMarkup: TGInlineKeyboardMarkup?
}

struct TGAnswerCallbackQueryRequest: Encodable {
    let callbackQueryId: String
    let text: String?
    let showAlert: Bool?

    init(callbackQueryId: String, text: String? = nil, showAlert: Bool? = nil) {
        self.callbackQueryId = callbackQueryId
        self.text = text
        self.showAlert = showAlert
    }
}

// MARK: - Response envelope

struct TGResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let errorCode: Int?
    let description: String?
    let parameters: TGResponseParameters?
}

struct TGResponseParameters: Decodable {
    let retryAfter: Int?
}
