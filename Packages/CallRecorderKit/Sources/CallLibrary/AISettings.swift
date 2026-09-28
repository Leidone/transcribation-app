import CodexClient
import Foundation
import Localization
import Observation
import os
import Security

private let settingsLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.callrecorder", category: "settings")

/// The person's choices about which AI does the analysis and what it is told. Nothing secret is kept here: every
/// provider key lives in the Keychain (`ProviderKeychain`); on the Mac a ChatGPT account or an OpenAI key signed
/// in through Codex stays in Codex's own credential store.
@Observable
@MainActor
public final class AISettings {
    public var prompt: AnalysisPrompt {
        didSet { store(prompt, key: Self.promptKey) }
    }

    public var provider: ProviderSettings {
        didSet { store(provider, key: Self.providerKey) }
    }

    /// The kind of meeting a new summary is written for unless the person picks another one for that recording.
    public var defaultTemplate: AnalysisTemplate {
        didSet { store(defaultTemplate, key: Self.templateKey) }
    }

    private let defaults: UserDefaults
    private static let promptKey = "analysisPrompt.v1"
    private static let providerKey = "providerSettings.v1"
    private static let templateKey = "analysisTemplate.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prompt = Self.load(AnalysisPrompt.self, key: Self.promptKey, from: defaults) ?? .standard
        provider = Self.load(ProviderSettings.self, key: Self.providerKey, from: defaults) ?? Self.defaultProvider
        defaultTemplate = Self.load(AnalysisTemplate.self, key: Self.templateKey, from: defaults) ?? .general
    }

    /// A ChatGPT account needs the Codex process, which iOS cannot run, so the iPhone starts with Claude.
    private static var defaultProvider: ProviderSettings {
        #if os(iOS)
        ProviderSettings(kind: .anthropic, customName: "", customBaseURL: "")
        #else
        .default
        #endif
    }

    /// The model chosen for the active provider. Claude keeps its own, so a GPT model name never reaches Anthropic.
    public var selectedModel: String? {
        get { provider.kind == .anthropic ? provider.claudeModel : prompt.model }
        set {
            if provider.kind == .anthropic {
                provider.claudeModel = newValue
            } else {
                prompt.model = newValue
            }
        }
    }

    /// The prompt to send for one recording: the person's instructions with the meeting template applied.
    public func prompt(for template: AnalysisTemplate) -> AnalysisPrompt {
        template.applied(to: prompt)
    }

    public func resetPrompt() {
        prompt = .standard
    }

    private func store(_ value: some Encodable, key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            settingsLog.error("could not store a setting: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            settingsLog.error("stored setting is unreadable, using the default: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// App behaviour that is not about the AI: first-launch setup and the Mac's call helpers.
@Observable
@MainActor
public final class AppPreferences {
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    /// Offer to record when a call app starts using the microphone (Mac only).
    public var suggestsRecordingOnCalls: Bool {
        didSet { defaults.set(suggestsRecordingOnCalls, forKey: Self.suggestKey) }
    }

    /// A key combination starts and stops a recording from any app (Mac only).
    public var usesGlobalHotKey: Bool {
        didSet { defaults.set(usesGlobalHotKey, forKey: Self.hotKeyKey) }
    }

    /// The combination for `usesGlobalHotKey`; ⌃⌥⌘R until the person records another one.
    public var recordShortcut: KeyShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(recordShortcut) { defaults.set(data, forKey: Self.shortcutKey) }
        }
    }

    /// A folder where every summary is also kept as a Markdown note (Obsidian, iCloud Drive…); `nil` keeps none.
    public var notesFolder: String? {
        didSet { defaults.set(notesFolder, forKey: Self.notesFolderKey) }
    }

    /// Whether those notes carry the whole transcript too, not only the summary, decisions and tasks.
    public var notesIncludeTranscript: Bool {
        didSet { defaults.set(notesIncludeTranscript, forKey: Self.notesTranscriptKey) }
    }

    /// The Telegram chat summaries are sent to; the bot's token itself is kept in the Keychain.
    public var telegramChatID: String {
        didSet { defaults.set(telegramChatID, forKey: Self.telegramChatKey) }
    }

    /// The window and the menu bar ask for Touch ID before showing any recording (Mac only).
    public var locksWithTouchID: Bool {
        didSet { defaults.set(locksWithTouchID, forKey: Self.lockKey) }
    }

    /// Seconds away from the app before the lock comes back.
    public var lockTimeout: TimeInterval {
        didSet { defaults.set(lockTimeout, forKey: Self.lockTimeoutKey) }
    }

    public var lockPolicy: AppLockPolicy {
        AppLockPolicy(isEnabled: locksWithTouchID, timeout: lockTimeout)
    }

    /// Names and terms the recogniser mishears, fixed in every new transcript.
    public var vocabulary: Vocabulary {
        didSet {
            if let data = try? JSONEncoder().encode(vocabulary) { defaults.set(data, forKey: Self.vocabularyKey) }
        }
    }

    /// The illustrative sample recordings, shown only while the library has none of the person's own.
    public var showsSamples: Bool {
        didSet { defaults.set(showsSamples, forKey: Self.samplesKey) }
    }

    /// Once a recording is transcribed, its lossless audio is replaced by AAC, about twenty times smaller.
    public var compressesAudio: Bool {
        didSet { defaults.set(compressesAudio, forKey: Self.compressKey) }
    }

    /// A recording stops by itself when the call ends; otherwise the person is only reminded (Mac only).
    public var stopsWhenCallEnds: Bool {
        didSet { defaults.set(stopsWhenCallEnds, forKey: Self.autoStopKey) }
    }

    /// Recordings take their title and attendees from the calendar event they happen during. Off until the
    /// person turns it on and allows calendar access (Mac only).
    public var usesCalendar: Bool {
        didSet { defaults.set(usesCalendar, forKey: Self.calendarKey) }
    }

    /// A key combination marks the current moment of a recording as important (Mac only).
    public var usesMarkShortcut: Bool {
        didSet { defaults.set(usesMarkShortcut, forKey: Self.markKey) }
    }

    /// The combination for `usesMarkShortcut`; ⌃⌥⌘M until the person records another one.
    public var markShortcut: KeyShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(markShortcut) { defaults.set(data, forKey: Self.markShortcutKey) }
        }
    }

    /// Titles, summaries and transcripts can be found with Spotlight. The index stays on this device.
    public var indexesInSpotlight: Bool {
        didSet { defaults.set(indexesInSpotlight, forKey: Self.spotlightKey) }
    }

    /// The call is transcribed roughly while it goes on and shown on the recording screen. Off until the person
    /// turns it on: it keeps the recognition model busy during the call (Mac only).
    public var transcribesLive: Bool {
        didSet { defaults.set(transcribesLive, forKey: Self.liveKey) }
    }

    private let defaults: UserDefaults
    private static let onboardingKey = "preferences.onboardingDone.v1"
    private static let suggestKey = "preferences.suggestRecording.v1"
    private static let hotKeyKey = "preferences.globalHotKey.v1"
    private static let samplesKey = "preferences.showsSamples.v1"
    private static let vocabularyKey = "preferences.vocabulary.v1"
    private static let lockKey = "preferences.lock.v1"
    private static let lockTimeoutKey = "preferences.lockTimeout.v1"
    private static let telegramChatKey = "preferences.telegramChat.v1"
    private static let notesFolderKey = "preferences.notesFolder.v1"
    private static let notesTranscriptKey = "preferences.notesIncludeTranscript.v1"
    private static let shortcutKey = "preferences.recordShortcut.v1"
    private static let compressKey = "preferences.compressesAudio.v1"
    private static let autoStopKey = "preferences.stopsWhenCallEnds.v1"
    private static let calendarKey = "preferences.usesCalendar.v1"
    private static let markKey = "preferences.markShortcutOn.v1"
    private static let markShortcutKey = "preferences.markShortcut.v1"
    private static let spotlightKey = "preferences.spotlight.v1"
    private static let liveKey = "preferences.liveTranscript.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)
        suggestsRecordingOnCalls = defaults.object(forKey: Self.suggestKey) as? Bool ?? true
        usesGlobalHotKey = defaults.object(forKey: Self.hotKeyKey) as? Bool ?? true
        showsSamples = defaults.object(forKey: Self.samplesKey) as? Bool ?? true
        locksWithTouchID = defaults.bool(forKey: Self.lockKey)
        lockTimeout = defaults.object(forKey: Self.lockTimeoutKey) as? Double ?? 300
        notesFolder = defaults.string(forKey: Self.notesFolderKey)
        telegramChatID = defaults.string(forKey: Self.telegramChatKey) ?? ""
        notesIncludeTranscript = defaults.bool(forKey: Self.notesTranscriptKey)
        vocabulary = defaults.data(forKey: Self.vocabularyKey)
            .flatMap { try? JSONDecoder().decode(Vocabulary.self, from: $0) } ?? .empty
        compressesAudio = defaults.object(forKey: Self.compressKey) as? Bool ?? true
        stopsWhenCallEnds = defaults.object(forKey: Self.autoStopKey) as? Bool ?? true
        usesCalendar = defaults.bool(forKey: Self.calendarKey)
        recordShortcut = defaults.data(forKey: Self.shortcutKey)
            .flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) } ?? .defaultRecordToggle
        usesMarkShortcut = defaults.object(forKey: Self.markKey) as? Bool ?? true
        markShortcut = defaults.data(forKey: Self.markShortcutKey)
            .flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) } ?? .defaultMarkImportant
        indexesInSpotlight = defaults.object(forKey: Self.spotlightKey) as? Bool ?? true
        transcribesLive = defaults.bool(forKey: Self.liveKey)
    }
}

public enum KeychainError: LocalizedError {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .status(let code): tr("Связка ключей вернула ошибку \(code).", "The Keychain returned error \(code).")
        }
    }
}

/// API keys of the providers the app calls itself, one Keychain item each, so switching providers never
/// overwrites another one's key. On the Mac an OpenAI key signed in through Codex is kept by Codex instead, so the
/// `openAIKey` slot is used on iOS only.
public enum ProviderKeychain {
    public enum Slot: String, Sendable {
        case anthropic
        case openAIKey = "openai-key"
        case custom = "custom-provider"
        /// Where summaries are sent (Mac): the Telegram bot's token and the Slack webhook address.
        case telegramBot = "telegram-bot"
        case slackWebhook = "slack-webhook"
    }

    /// `app.callrecorder.dev.provider-key` on the Mac, `app.callrecorder.dev.ios.provider-key` on the iPhone — the
    /// names each app used before this code was shared, so stored keys are still found.
    private static let service = (Bundle.main.bundleIdentifier ?? "app.callrecorder.dev") + ".provider-key"

    private static func query(_ slot: Slot) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: slot.rawValue]
    }

    public static func read(_ slot: Slot) -> String? {
        var lookup = query(slot)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func save(_ key: String, slot: Slot) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(slot) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.status(status) }

        var newItem = query(slot)
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let added = SecItemAdd(newItem as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.status(added) }
    }

    public static func delete(_ slot: Slot) {
        let status = SecItemDelete(query(slot) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            settingsLog.error("could not delete the \(slot.rawValue, privacy: .public) key, status \(status)")
        }
    }
}
