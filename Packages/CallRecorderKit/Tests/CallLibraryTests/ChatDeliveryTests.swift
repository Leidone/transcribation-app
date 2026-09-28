import Foundation
import Testing
@testable import CallLibrary

struct ChatDeliveryTests {
    private var release: RecordingItem {
        SampleData.recordings[0]
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The message

    @Test("the message carries the title, the summary, the decisions and every task with its owner")
    func messageCarriesTheResult() throws {
        let recording = release
        let analysis = try #require(recording.analysis)

        let text = try #require(ChatMessage.text(for: recording))

        #expect(text.hasPrefix(recording.title))
        #expect(text.contains(analysis.summary))
        for decision in analysis.decisions {
            #expect(text.contains("• \(decision)"))
        }
        for task in analysis.tasks {
            #expect(text.contains(RecordingExport.describe(task, displayName: recording.displayName)))
        }
    }

    @Test("a recording without a summary has no message")
    func noSummaryNoMessage() {
        let sample = release
        let plain = RecordingItem(
            id: UUID(), title: "Звонок", appName: "Zoom", appBundleID: nil, startedAt: sample.startedAt,
            duration: 60, status: .ready, directory: nil, isSample: false, transcript: [], analysis: nil
        )

        #expect(ChatMessage.text(for: plain) == nil)
    }

    @Test("a long message is cut to what a chat accepts, and says so")
    func longMessageIsCut() {
        let long = String(repeating: "слово ", count: 2_000)

        let cut = ChatMessage.fitting(long)

        #expect(cut.count <= ChatMessage.limit)
        #expect(cut.hasSuffix("…"))
        #expect(ChatMessage.fitting("коротко") == "коротко")
    }

    // MARK: Telegram

    @Test("a bot token is digits, a colon and the secret; anything else is refused")
    func tokenFormat() {
        #expect(TelegramBot.isValidToken("123456789:AAH-abc_DEF123"))
        #expect(!TelegramBot.isValidToken("abc:def"))
        #expect(!TelegramBot.isValidToken("123456789"))
        #expect(!TelegramBot.isValidToken("123:abc/../x"))
        #expect(!TelegramBot.isValidToken(""))
    }

    @Test("the Telegram request posts the plain text to the chosen chat of the bot")
    func telegramRequest() throws {
        let bot = try TelegramBot(token: " 123456789:AAH-abc ", chatID: " -100200 ")

        let request = bot.sendRequest(text: "Итоги")

        #expect(request.url?.absoluteString == "https://api.telegram.org/bot123456789:AAH-abc/sendMessage")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try body(of: request)
        #expect(json["chat_id"] as? String == "-100200")
        #expect(json["text"] as? String == "Итоги")
        #expect(json["parse_mode"] == nil, "plain text: nothing in a summary can break the markup")
    }

    @Test("a bot without a valid token or chat is not made")
    func telegramRefusesBadSettings() {
        #expect(throws: ChatDeliveryError.invalidToken) { try TelegramBot(token: "nope", chatID: "1") }
        #expect(throws: ChatDeliveryError.invalidChatID) { try TelegramBot(token: "1:a", chatID: "  ") }
    }

    @Test("Telegram's refusal comes back with its own reason")
    func telegramRefusal() {
        let refusal = Data(#"{"ok":false,"error_code":403,"description":"Forbidden: bot was blocked by the user"}"#.utf8)

        #expect(throws: ChatDeliveryError.rejected("Forbidden: bot was blocked by the user")) {
            try TelegramBot.check(refusal, status: 403)
        }
        #expect(throws: Never.self) { try TelegramBot.check(Data(#"{"ok":true,"result":{}}"#.utf8), status: 200) }
    }

    @Test("the chat the bot was last written from is found in its updates")
    func latestChatFromUpdates() throws {
        let updates = Data("""
        {"ok":true,"result":[
          {"update_id":1,"message":{"chat":{"id":111,"type":"private","first_name":"Анна"}}},
          {"update_id":2,"my_chat_member":{"chat":{"id":-100222,"type":"supergroup","title":"Команда"}}},
          {"update_id":3,"channel_post":{"chat":{"id":-100333,"type":"channel","title":"Новости"}}}
        ]}
        """.utf8)

        let chat = try #require(try TelegramBot.latestChat(inUpdates: updates))

        #expect(chat == TelegramChat(id: "-100333", name: "Новости"))
        #expect(try TelegramBot.latestChat(inUpdates: Data(#"{"ok":true,"result":[]}"#.utf8)) == nil)
    }

    @Test("the updates request asks the bot only, with the token in the path")
    func updatesRequest() throws {
        let request = try TelegramBot.updatesRequest(token: "123:abc")

        #expect(request.url?.absoluteString == "https://api.telegram.org/bot123:abc/getUpdates")
        #expect(throws: ChatDeliveryError.invalidToken) { try TelegramBot.updatesRequest(token: "x") }
    }

    // MARK: Slack

    @Test("only an https Slack webhook is accepted")
    func webhookFormat() {
        #expect(SlackWebhook.url(from: " https://hooks.slack.com/services/T0/B0/xyz ") != nil)
        #expect(SlackWebhook.url(from: "http://hooks.slack.com/services/T0/B0/xyz") == nil)
        #expect(SlackWebhook.url(from: "https://example.com/services/T0/B0/xyz") == nil)
        #expect(SlackWebhook.url(from: "https://hooks.slack.com.evil.com/services/x") == nil)
        #expect(SlackWebhook.url(from: "") == nil)
    }

    @Test("the Slack request posts the text to the webhook")
    func slackRequest() throws {
        let hook = try SlackWebhook(address: "https://hooks.slack.com/services/T0/B0/xyz")

        let request = hook.sendRequest(text: "Итоги")

        #expect(request.url?.absoluteString == "https://hooks.slack.com/services/T0/B0/xyz")
        #expect(request.httpMethod == "POST")
        #expect(try body(of: request)["text"] as? String == "Итоги")
        #expect(throws: ChatDeliveryError.invalidWebhook) { try SlackWebhook(address: "https://example.com") }
    }

    @Test("Slack's refusal comes back with its reason; a success passes")
    func slackRefusal() {
        #expect(throws: ChatDeliveryError.rejected("no_service")) { try SlackWebhook.check(Data("no_service".utf8), status: 404) }
        #expect(throws: Never.self) { try SlackWebhook.check(Data("ok".utf8), status: 200) }
    }
}
