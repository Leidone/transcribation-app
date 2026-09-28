import Foundation
import Localization

/// Where a summary can be sent besides Mail: a Telegram chat through the person's own bot, or a Slack channel
/// through an incoming webhook. Only the result goes — never the audio or the transcript — and only when the
/// person presses the button.
public enum ChatService: String, CaseIterable, Sendable {
    case telegram
    case slack

    public var name: String {
        switch self {
        case .telegram: "Telegram"
        case .slack: "Slack"
        }
    }
}

public enum ChatDeliveryError: LocalizedError, Equatable {
    case invalidToken
    case invalidChatID
    case invalidWebhook
    case notConfigured(ChatService)
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            tr("Токен бота не похож на настоящий — скопируйте его из @BotFather целиком.",
               "The bot token does not look right — copy the whole token from @BotFather.")
        case .invalidChatID:
            tr("Не указан чат для отправки.", "No chat to send to is set.")
        case .invalidWebhook:
            tr("Нужен адрес вебхука Slack вида https://hooks.slack.com/…", "A Slack webhook address like https://hooks.slack.com/… is needed.")
        case .notConfigured(let service):
            tr("\(service.name) ещё не настроен — это делается в настройках.", "\(service.name) is not set up yet — do it in Settings.")
        case .rejected(let reason):
            tr("Сервис отказал: \(reason)", "The service refused: \(reason)")
        }
    }
}

/// The text that goes to a chat: plain, so nothing in a summary can break a messenger's markup.
public enum ChatMessage {
    /// Telegram takes 4096 characters; Slack more. One limit for both keeps them the same.
    public static let limit = 4_000

    /// `nil` for a recording without a summary: there is nothing to send yet.
    public static func text(for recording: RecordingItem) -> String? {
        guard let analysis = recording.analysis else { return nil }
        var parts = [recording.title + "\n" + RecordingExport.subtitle(of: recording), analysis.summary]
        if !analysis.decisions.isEmpty {
            parts.append(tr("Решения:", "Decisions:") + "\n" + analysis.decisions.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !analysis.tasks.isEmpty {
            let lines = analysis.tasks.map { ($0.isDone ? "✅ " : "☐ ") + RecordingExport.describe($0, displayName: recording.displayName) }
            parts.append(tr("Задачи:", "Tasks:") + "\n" + lines.joined(separator: "\n"))
        }
        return fitting(parts.joined(separator: "\n\n"))
    }

    /// The text as is, or cut short with "…" when a chat would refuse it.
    public static func fitting(_ text: String) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}

public struct TelegramChat: Equatable, Sendable {
    public let id: String
    public let name: String
}

/// The person's own bot, made with @BotFather, and the chat it posts to.
public struct TelegramBot: Sendable {
    public let token: String
    public let chatID: String

    public init(token: String, chatID: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidToken(token) else { throw ChatDeliveryError.invalidToken }
        guard !chatID.isEmpty else { throw ChatDeliveryError.invalidChatID }
        self.token = token
        self.chatID = chatID
    }

    /// "123456789:AA…": the bot's number, a colon and the secret. Checked so the token is safe in a URL path.
    public static func isValidToken(_ token: String) -> Bool {
        token.wholeMatch(of: /[0-9]+:[A-Za-z0-9_-]+/) != nil
    }

    public func sendRequest(text: String) -> URLRequest {
        Self.post(Self.endpoint(token: token, method: "sendMessage"), json: [
            "chat_id": chatID,
            "text": text,
            "disable_web_page_preview": true,
        ])
    }

    /// What the bot was sent lately, to find the chat the person just wrote to it from.
    public static func updatesRequest(token: String) throws -> URLRequest {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidToken(token) else { throw ChatDeliveryError.invalidToken }
        return URLRequest(url: endpoint(token: token, method: "getUpdates"))
    }

    /// The chat of the most recent update — a message, a channel post, or the bot being added to a group.
    public static func latestChat(inUpdates data: Data) throws -> TelegramChat? {
        try check(data, status: 200)
        let decoded = try JSONDecoder().decode(Updates.self, from: data)
        return decoded.result.reversed().lazy.compactMap(\.chat).first.map {
            TelegramChat(id: String($0.id), name: $0.title ?? [$0.firstName, $0.lastName].compactMap { $0 }.joined(separator: " "))
        }
    }

    /// Telegram answers `{"ok": false, "description": …}` when it refuses.
    public static func check(_ data: Data, status: Int) throws {
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        if reply?.ok == true, (200..<300).contains(status) { return }
        throw ChatDeliveryError.rejected(reply?.description ?? "HTTP \(status)")
    }

    private static func endpoint(token: String, method: String) -> URL {
        // Safe to force: the token is checked to be only letters, digits, "_", "-" and ":".
        URL(string: "https://api.telegram.org/bot\(token)/\(method)")!
    }

    fileprivate static func post(_ url: URL, json: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        return request
    }

    private struct Reply: Decodable {
        let ok: Bool
        let description: String?
    }

    private struct Updates: Decodable {
        let result: [Update]
    }

    private struct Update: Decodable {
        struct Chat: Decodable {
            let id: Int64
            let title: String?
            let firstName: String?
            let lastName: String?

            enum CodingKeys: String, CodingKey {
                case id, title
                case firstName = "first_name"
                case lastName = "last_name"
            }
        }

        struct Carrier: Decodable {
            let chat: Chat
        }

        let message: Carrier?
        let channelPost: Carrier?
        let myChatMember: Carrier?

        var chat: Chat? { (message ?? channelPost ?? myChatMember)?.chat }

        enum CodingKeys: String, CodingKey {
            case message
            case channelPost = "channel_post"
            case myChatMember = "my_chat_member"
        }
    }
}

/// A Slack channel's incoming webhook: the address itself is the secret.
public struct SlackWebhook: Sendable {
    public let url: URL

    public init(address: String) throws {
        guard let url = Self.url(from: address) else { throw ChatDeliveryError.invalidWebhook }
        self.url = url
    }

    /// Only `https://hooks.slack.com/…`, so a summary is never posted anywhere else by a mistyped address.
    public static func url(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host() == "hooks.slack.com", url.path().count > 1 else {
            return nil
        }
        return url
    }

    public func sendRequest(text: String) -> URLRequest {
        TelegramBot.post(url, json: ["text": text])
    }

    /// Slack answers "ok", or a short reason such as "no_service" or "invalid_token".
    public static func check(_ data: Data, status: Int) throws {
        guard !(200..<300).contains(status) else { return }
        let reason = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw ChatDeliveryError.rejected(reason.isEmpty ? "HTTP \(status)" : String(reason.prefix(200)))
    }
}

/// Sends a prepared request and turns the service's refusal into a readable error.
public enum ChatDelivery {
    @discardableResult
    public static func perform(
        _ request: URLRequest, session: URLSession = .shared, check: (Data, Int) throws -> Void
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try check(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        return data
    }
}
