import CallLibrary
import Foundation
import Localization

/// Sending a summary to a Telegram chat or a Slack channel. The bot token and the webhook address are secrets and
/// live in the Keychain; the chat number is not and lives in the preferences.
extension AppModel {
    func isConfigured(_ service: ChatService) -> Bool {
        switch service {
        case .telegram: ProviderKeychain.read(.telegramBot) != nil && !preferences.telegramChatID.isEmpty
        case .slack: ProviderKeychain.read(.slackWebhook) != nil
        }
    }

    var configuredChats: [ChatService] {
        ChatService.allCases.filter(isConfigured)
    }

    func sendSummary(of recording: RecordingItem, to service: ChatService) async {
        guard let text = ChatMessage.text(for: recording) else { return }
        do {
            try await send(text, to: service)
            announce(tr("Итоги отправлены в \(service.name)", "Summary sent to \(service.name)"))
        } catch {
            report(error, doing: tr("Не удалось отправить в \(service.name)", "Could not send to \(service.name)"))
        }
    }

    /// Checks the settings with a real short message, so a wrong chat shows up now and not after a meeting.
    func sendTestMessage(to service: ChatService) async {
        do {
            try await send(tr("Transcribation: проверка связи ✅", "Transcribation: connection check ✅"), to: service)
            announce(tr("Проверочное сообщение отправлено в \(service.name)", "Test message sent to \(service.name)"))
        } catch {
            report(error, doing: tr("\(service.name) не отвечает как надо", "\(service.name) did not answer as expected"))
        }
    }

    /// Stores the bot (an empty token keeps the stored one) after checking its format.
    func saveTelegram(token: String, chatID: String) throws {
        let bot = try TelegramBot(token: effectiveToken(token), chatID: chatID)
        try ProviderKeychain.save(bot.token, slot: .telegramBot)
        preferences.telegramChatID = bot.chatID
    }

    func saveSlack(webhook: String) throws {
        let hook = try SlackWebhook(address: webhook)
        try ProviderKeychain.save(hook.url.absoluteString, slot: .slackWebhook)
    }

    func forget(_ service: ChatService) {
        switch service {
        case .telegram:
            ProviderKeychain.delete(.telegramBot)
            preferences.telegramChatID = ""
        case .slack:
            ProviderKeychain.delete(.slackWebhook)
        }
    }

    /// The chat the person last wrote to the bot from (or added it to): no need to look up chat numbers by hand.
    func findTelegramChat(token: String) async throws -> TelegramChat? {
        let request = try TelegramBot.updatesRequest(token: effectiveToken(token))
        let data = try await ChatDelivery.perform(request, check: TelegramBot.check)
        return try TelegramBot.latestChat(inUpdates: data)
    }

    /// The token just typed, or the stored one when the field is left empty.
    private func effectiveToken(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (ProviderKeychain.read(.telegramBot) ?? "") : trimmed
    }

    private func send(_ text: String, to service: ChatService) async throws {
        switch service {
        case .telegram:
            guard let token = ProviderKeychain.read(.telegramBot) else { throw ChatDeliveryError.notConfigured(.telegram) }
            let bot = try TelegramBot(token: token, chatID: preferences.telegramChatID)
            try await ChatDelivery.perform(bot.sendRequest(text: text), check: TelegramBot.check)
        case .slack:
            guard let address = ProviderKeychain.read(.slackWebhook) else { throw ChatDeliveryError.notConfigured(.slack) }
            try await ChatDelivery.perform(try SlackWebhook(address: address).sendRequest(text: text), check: SlackWebhook.check)
        }
    }
}
