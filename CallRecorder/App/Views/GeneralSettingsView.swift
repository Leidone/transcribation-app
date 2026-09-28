import AppKit
import CallLibrary
import Carbon.HIToolbox
import CodexClient
import Localization
import SwiftUI

/// Everything that is not the AI account: the default meeting template, the call helpers and the voices the app
/// has learned.
struct GeneralSettingsView: View {
    @Environment(CodexAccountModel.self) private var account
    @Environment(AppModel.self) private var model
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var settings = account.settings
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Тип встречи по умолчанию", "Default meeting type")).font(.headline)
                Picker(tr("Тип встречи", "Meeting type"), selection: $settings.defaultTemplate) {
                    ForEach(AnalysisTemplate.allCases) { template in
                        Label(template.title, systemImage: template.systemImage).tag(template)
                    }
                }
                .labelsHidden()
                Text(tr("Подсказывает ИИ, на что обратить внимание в итогах. Для отдельной записи можно выбрать другой.", "Tells the AI what to focus on in the summary. A single recording can use another one."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 20, padding: 18)
            .staggeredAppear(0)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $preferences.suggestsRecordingOnCalls) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Предлагать запись, когда начинается звонок", "Offer to record when a call starts")).font(.headline)
                        Text(tr("Когда Zoom, Teams, FaceTime, Telegram и похожие приложения включают микрофон, появится уведомление с кнопкой «Записать». Без нажатия ничего не записывается.", "When Zoom, Teams, FaceTime, Telegram and similar apps turn on the microphone, a notification with a Record button appears. Nothing is recorded unless you press it."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Toggle(isOn: $preferences.usesGlobalHotKey) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Сочетание клавиш для записи", "Recording shortcut")).font(.headline)
                        Text(tr("Начинает и останавливает запись из любого приложения; пишется приложение, выбранное в последний раз, или запущенное приложение звонка.", "Starts and stops a recording from any app; it records the app chosen last, or a running call app."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if preferences.usesGlobalHotKey {
                    ShortcutRecorder(role: .record)
                        .transition(.opacity)
                }
                Divider()
                Toggle(isOn: $preferences.usesMarkShortcut) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Сочетание клавиш «Важно»", "“Important” shortcut")).font(.headline)
                        Text(tr(
                            "Во время записи отмечает текущий момент как важный: в расшифровке он подсветится, а ИИ уделит ему внимание в итогах. Работает, только пока идёт запись.",
                            "While recording, marks the current moment as important: it is highlighted in the transcript and the AI gives it weight in the summary. Active only while recording."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if preferences.usesMarkShortcut {
                    ShortcutRecorder(role: .mark)
                        .transition(.opacity)
                }
            }
            .toggleStyle(.switch)
            .glassCard(cornerRadius: 20, padding: 18)
            .staggeredAppear(1)

            RecordingCard()
                .staggeredAppear(2)

            Toggle(isOn: $preferences.showsSamples) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Показывать примеры, пока нет своих записей", "Show examples while there are no recordings of your own")).font(.headline)
                    Text(tr("Две записи с готовыми итогами, чтобы было видно, как всё выглядит. С первой своей записью исчезают сами.", "Two recordings with finished summaries, to show how everything looks. They go away with your first own recording."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .glassCard(cornerRadius: 20, padding: 18)
            .staggeredAppear(3)

            SearchAndSiriCard()
                .staggeredAppear(4)

            VoicesCard()
                .staggeredAppear(5)

            VocabularyCard()
                .staggeredAppear(5)

            NotesFolderCard()
                .staggeredAppear(5)

            ChatsCard()
                .staggeredAppear(5)

            LockCard()
                .staggeredAppear(5)

            UpdatesCard()
                .staggeredAppear(6)

            ProblemReportCard()
                .staggeredAppear(7)

            AboutCard()
                .staggeredAppear(8)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}

/// How a recording ends and how it is kept.
private struct RecordingCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $preferences.stopsWhenCallEnds) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Останавливать запись, когда звонок закончился", "Stop recording when the call ends")).font(.headline)
                    Text(tr("Когда приложение звонка отпускает микрофон и собеседники замолкают, запись сохраняется сама — и после 15 минут полной тишины тоже. Если выключить, придёт только напоминание.", "When the call app lets go of the microphone and the others fall silent, the recording is saved by itself — and after 15 minutes of complete silence too. Turned off, you only get a reminder."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Toggle(isOn: $preferences.transcribesLive) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Расшифровка во время звонка (бета)", "Transcribe during the call (beta)")).font(.headline)
                    Text(tr(
                        "Текст появляется на экране записи через несколько секунд, ваши слова отдельно от собеседников. Mac распознаёт речь прямо во время звонка; если он не успевает, на экране будет предупреждение. Полная расшифровка по-прежнему делается после звонка. Включается со следующей записи.",
                        "Text appears on the recording screen a few seconds after it is said, your words apart from the others'. The Mac recognises speech during the call; if it cannot keep up, the screen says so. The full transcript is still made after the call. Takes effect from the next recording."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Toggle(isOn: calendarBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Брать название встречи из Календаря", "Take the meeting title from Calendar")).font(.headline)
                    Text(tr("Запись назовётся как событие, во время которого шла, а приглашённые будут подсказаны при подписи голосов и переданы ИИ для итогов. Календарь только читается.", "A recording is named after the event it was made during; the invited people are suggested when naming voices and passed to the AI for the summary. The calendar is only read."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Toggle(isOn: $preferences.compressesAudio) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Сжимать звук после расшифровки", "Compress audio after transcription")).font(.headline)
                    Text(tr("Час звонка займёт около 90 МБ вместо 1,7 ГБ. На слух разницы нет, время в расшифровке совпадает до доли секунды.", "An hour of a call takes about 90 MB instead of 1.7 GB. It sounds the same, and transcript times match to a fraction of a second."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toggleStyle(.switch)
        .glassCard(cornerRadius: 20, padding: 18)
        .onChange(of: preferences.compressesAudio) { _, isOn in
            if isOn { Task { await model.compressBacklog() } }
        }
    }

    /// Turning it on first asks macOS for calendar access.
    private var calendarBinding: Binding<Bool> {
        Binding(
            get: { preferences.usesCalendar },
            set: { isOn in
                if isOn {
                    Task { await model.enableCalendar() }
                } else {
                    preferences.usesCalendar = false
                }
            }
        )
    }
}

/// Spotlight search and what Siri and Shortcuts can do.
private struct SearchAndSiriCard: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $preferences.indexesInSpotlight) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Искать записи через Spotlight", "Find recordings with Spotlight")).font(.headline)
                    Text(tr(
                        "Названия, итоги и расшифровки находятся через ⌘Пробел; результат открывает запись. Индекс хранит macOS, только на этом Mac.",
                        "Titles, summaries and transcripts can be found with ⌘Space; a result opens the recording. macOS keeps the index on this Mac only."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Siri и «Команды»", "Siri and Shortcuts")).font(.headline)
                Text(tr(
                    "В приложении «Команды» есть действия Transcribation: «Начать запись», «Остановить запись», «Отметить важное» и «Итоги последней встречи». Их можно вызвать голосом через Siri или назначить на кнопку.",
                    "The Shortcuts app has Transcribation actions: Start Recording, Stop Recording, Mark Important Moment and Last Meeting Summary. Run them with Siri or put them on a button."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

/// The installed version and new ones.
private struct UpdatesCard: View {
    @Environment(Updater.self) private var updater

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var updater = updater

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Обновления", "Updates")).font(.headline)
                    Text(tr("Установлена версия \(version).", "Version \(version) is installed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(tr("Проверить сейчас", "Check Now")) { updater.checkForUpdates() }
                    .buttonStyle(.glass)
                    .disabled(!updater.isConfigured || !updater.canCheck)
            }
            if updater.isConfigured {
                Toggle(tr("Проверять обновления автоматически", "Check for updates automatically"), isOn: $updater.checksAutomatically)
                    .toggleStyle(.switch)
                Text(tr(
                    "Новая версия ставится только если подписана ключом разработчика. Приложение предложит обновиться и перезапустится само.",
                    "A new version is installed only if it is signed with the developer's key. The app offers the update and restarts by itself."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text(tr(
                    "Автообновление в этой сборке выключено: у неё не указан адрес, где публикуются обновления.",
                    "Automatic updates are off in this build: it names no address where updates are published."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

/// Touch ID before the recordings are shown.
private struct LockCard: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { preferences.locksWithTouchID }, set: { isOn in Task { await lock.setEnabled(isOn) } })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Защищать записи Touch ID", "Protect recordings with Touch ID")).font(.headline)
                    Text(tr("Окно и меню-бар показывают записи только после Touch ID или пароля Mac: при запуске, после сна и когда вы долго не заходили. Запись при этом не останавливается.",
                            "The window and the menu bar show recordings only after Touch ID or the Mac's password: at launch, after sleep and when you have been away. Recording carries on meanwhile."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            if preferences.locksWithTouchID {
                if preferences.indexesInSpotlight {
                    Text(tr("Поиск через Spotlight хранит тексты в индексе Mac и замком не закрывается — выключите его выше, если нужно.",
                            "Spotlight keeps the texts in the Mac's index, which the lock does not cover — turn it off above if needed."))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Picker(tr("Снова спрашивать после", "Ask again after"), selection: $preferences.lockTimeout) {
                    ForEach(AppLockPolicy.timeouts, id: \.self) { seconds in
                        Text(Self.label(for: seconds)).tag(seconds)
                    }
                }
                .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
    }

    private static func label(for seconds: TimeInterval) -> String {
        switch seconds {
        case 0: tr("каждого возврата", "every return")
        case ..<3_600: tr("\(Int(seconds / 60)) мин", "\(Int(seconds / 60)) min")
        default: tr("1 часа", "1 hour")
        }
    }
}

/// A folder where every summary is kept as a Markdown note.
private struct NotesFolderCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Итоги в папку", "Summaries to a folder")).font(.headline)
            Text(tr("Каждые итоги сохраняются ещё и файлом Markdown — удобно для Obsidian, iCloud Drive и любых заметок. Повторные итоги обновляют тот же файл.",
                    "Every summary is also saved as a Markdown file — handy for Obsidian, iCloud Drive or any notes app. A summary made again updates the same file."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let folder = preferences.notesFolder {
                Label(folder, systemImage: "folder")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Toggle(tr("Вместе с расшифровкой", "With the transcript"), isOn: $preferences.notesIncludeTranscript)
                    .toggleStyle(.switch)
                HStack {
                    Button(tr("Другая папка…", "Another folder…")) { model.chooseNotesFolder() }
                    Button(tr("Сохранить все итоги сейчас", "Save all summaries now")) { model.writeAllNotes() }
                    Spacer()
                    Button(tr("Не сохранять", "Stop saving"), role: .destructive) { preferences.notesFolder = nil }
                }
                .buttonStyle(.glass)
            } else {
                Button(tr("Выбрать папку…", "Choose a folder…"), systemImage: "folder.badge.plus") { model.chooseNotesFolder() }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

/// Where the "Send to Telegram / Slack" buttons of a recording post its summary.
private struct ChatsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppPreferences.self) private var preferences
    @State private var token = ""
    @State private var chatID = ""
    @State private var webhook = ""
    @State private var status: String?
    @State private var isFinding = false
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Отправка итогов в чаты", "Summaries to chats")).font(.headline)
            Text(tr("Кнопка «Отправить в Telegram / Slack» в меню записи. Уходят только итоги, решения и задачи — без звука и расшифровки, и только по нажатию. Токен и адрес хранятся в связке ключей.",
                    "A “Send to Telegram / Slack” button in a recording’s menu. Only the summary, decisions and tasks go — no audio or transcript, and only when pressed. The token and the address are kept in the Keychain."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            telegram
            Divider()
            slack
            if let status {
                Text(status).font(.footnote).foregroundStyle(.orange)
            }
        }
        .id(revision)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
        .onAppear { chatID = preferences.telegramChatID }
    }

    private var telegram: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.isConfigured(.telegram) ? tr("Telegram — настроен", "Telegram — set up") : "Telegram", systemImage: "paperplane")
                .font(.subheadline.weight(.semibold))
            Text(tr("Создайте бота у @BotFather, вставьте его токен, напишите боту что-нибудь (или добавьте его в группу) и нажмите «Найти чат».",
                    "Make a bot with @BotFather, paste its token, write anything to the bot (or add it to a group) and press “Find the chat”."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            SecureField(model.isConfigured(.telegram) ? tr("Токен сохранён — оставьте пустым", "Token saved — leave empty") : tr("Токен бота", "Bot token"), text: $token)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField(tr("Номер чата", "Chat number"), text: $chatID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button(tr("Найти чат", "Find the chat")) { Task { await findChat() } }
                    .disabled(isFinding)
            }
            HStack {
                Button(tr("Сохранить", "Save")) { save { try model.saveTelegram(token: token, chatID: chatID) } }
                if model.isConfigured(.telegram) {
                    Button(tr("Проверить", "Test")) { Task { await model.sendTestMessage(to: .telegram) } }
                    Spacer()
                    Button(tr("Отключить", "Disconnect"), role: .destructive) { forget(.telegram) }
                }
            }
            .buttonStyle(.glass)
        }
    }

    private var slack: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.isConfigured(.slack) ? tr("Slack — настроен", "Slack — set up") : "Slack", systemImage: "number")
                .font(.subheadline.weight(.semibold))
            Text(tr("В Slack: приложение Incoming Webhooks → канал → скопируйте адрес https://hooks.slack.com/…",
                    "In Slack: the Incoming Webhooks app → a channel → copy the https://hooks.slack.com/… address."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            SecureField(model.isConfigured(.slack) ? tr("Адрес сохранён — вставьте новый, чтобы заменить", "Address saved — paste a new one to replace it") : tr("Адрес вебхука", "Webhook address"), text: $webhook)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(tr("Сохранить", "Save")) { save { try model.saveSlack(webhook: webhook) } }
                    .disabled(webhook.isEmpty)
                if model.isConfigured(.slack) {
                    Button(tr("Проверить", "Test")) { Task { await model.sendTestMessage(to: .slack) } }
                    Spacer()
                    Button(tr("Отключить", "Disconnect"), role: .destructive) { forget(.slack) }
                }
            }
            .buttonStyle(.glass)
        }
    }

    private func save(_ action: () throws -> Void) {
        do {
            try action()
            token = ""
            webhook = ""
            status = nil
            model.announce(tr("Сохранено", "Saved"))
        } catch {
            status = error.localizedDescription
        }
        revision += 1
    }

    private func forget(_ service: ChatService) {
        model.forget(service)
        if service == .telegram { chatID = "" }
        revision += 1
    }

    private func findChat() async {
        isFinding = true
        defer { isFinding = false }
        do {
            if let chat = try await model.findTelegramChat(token: token) {
                chatID = chat.id
                status = tr("Найден чат «\(chat.name)». Нажмите «Сохранить».", "Found the chat “\(chat.name)”. Press “Save”.")
            } else {
                status = tr("Бот пока не получал сообщений — напишите ему и попробуйте ещё раз.", "The bot has no messages yet — write to it and try again.")
            }
        } catch {
            status = error.localizedDescription
        }
    }
}

/// Names and terms the recogniser mishears, and how to write them.
private struct VocabularyCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Свой словарь", "Your vocabulary")).font(.headline)
            Text(tr("Имена и термины, которые распознавание пишет неверно. Замены делаются в каждой новой расшифровке, только целыми словами, регистр не важен.",
                    "Names and terms that recognition gets wrong. They are fixed in every new transcript, whole words only, whatever the case."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach($preferences.vocabulary.rules) { $rule in
                HStack(spacing: 8) {
                    TextField(tr("Слышится", "Heard as"), text: $rule.heard)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    TextField(tr("Пишется", "Written as"), text: $rule.written)
                    Button {
                        let id = rule.id
                        preferences.vocabulary.rules.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help(tr("Удалить", "Remove"))
                }
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button(tr("Добавить", "Add"), systemImage: "plus") {
                    preferences.vocabulary.rules.append(.init(heard: "", written: ""))
                }
                Spacer()
                Button(tr("Применить к записям", "Apply to recordings")) {
                    Task { await model.applyVocabularyToLibrary() }
                }
                .disabled(preferences.vocabulary.rules.allSatisfy { $0.heard.trimmingCharacters(in: .whitespaces).isEmpty })
                .help(tr("Исправить эти слова и в уже расшифрованных записях", "Fix these words in transcripts made before, too"))
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

/// A way to send the developer what is needed to understand a problem.
private struct ProblemReportCard: View {
    @Environment(ProblemReporter.self) private var reporter

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Что-то работает не так?", "Something not working?")).font(.headline)
                Text(tr("Соберём журнал приложения и сведения о Mac в один файл, который можно отправить разработчику. Записей, текстов разговоров и ключей в нём нет.", "Collects the app's log and details about the Mac into one file you can send to the developer. It holds no recordings, no conversation text and no keys."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                reporter.collect()
            } label: {
                if reporter.isCollecting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(tr("Сообщить о проблеме…", "Report a Problem…"))
                }
            }
            .buttonStyle(.glass)
            .disabled(reporter.isCollecting)
        }
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

/// People whose voices were named once; each can be forgotten.
private struct VoicesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Запомненные голоса", "Remembered voices")).font(.headline)
            if model.voiceBook.profiles.isEmpty {
                Text(tr("Пока никого. Переименуйте собеседника в расшифровке, и его голос будет узнан в следующих звонках.", "Nobody yet. Rename a speaker in a transcript, and their voice will be recognised in later calls."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.voiceBook.profiles) { profile in
                    HStack {
                        Circle()
                            .fill(Theme.speakerColor(profile.name, isMe: false))
                            .frame(width: 9, height: 9)
                        Text(profile.name).font(.body.weight(.medium))
                        Text(tr("· записей: \(profile.samples)", "· recordings: \(profile.samples)"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(tr("Забыть", "Forget"), role: .destructive) {
                            withAnimation(Motion.smooth) { model.forgetVoice(profile.id) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    .transition(.opacity)
                }
            }
            Text(tr("Хранится только числовой «отпечаток» голоса, не аудио, и только на этом Mac.", "Only a numeric “fingerprint” of the voice is kept, not audio, and only on this Mac."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

/// Shows one of the two shortcuts; a click listens for the next key combination and saves it. Esc cancels.
private struct ShortcutRecorder: View {
    let role: HelperShortcut

    @Environment(AppPreferences.self) private var preferences
    @Environment(CallHelpers.self) private var helpers
    @State private var isListening = false
    @State private var monitor: Any?
    @State private var message: String?

    private var current: KeyShortcut {
        role == .record ? preferences.recordShortcut : preferences.markShortcut
    }

    private var standard: KeyShortcut {
        role == .record ? .defaultRecordToggle : .defaultMarkImportant
    }

    /// The other role's combination: the two must differ.
    private var other: KeyShortcut {
        role == .record ? preferences.markShortcut : preferences.recordShortcut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    if isListening { stopListening() } else { startListening() }
                } label: {
                    Text(isListening ? tr("Нажмите сочетание…", "Press a combination…") : current.display)
                        .font(.title3.weight(.semibold))
                        .contentTransition(.opacity)
                        .frame(minWidth: 170)
                }
                .buttonStyle(.glass)
                .help(tr("Нажмите и введите новое сочетание", "Click and type a new combination"))

                if isListening {
                    Text(tr("Esc — отмена", "Esc cancels")).font(.caption).foregroundStyle(.secondary)
                } else if current != standard {
                    Button(tr("Сбросить на \(standard.display)", "Reset to \(standard.display)")) { save(standard) }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(tr(
                "Подойдут короткие сочетания вроде ⌥R или ⌃R, или одна функциональная клавиша, например F5.",
                "Short combinations such as ⌥R or ⌃R work, or a single function key such as F5."
            ))
                .font(.footnote)
                .foregroundStyle(.tertiary)
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: isListening)
        .animation(Motion.quick, value: message)
        .onDisappear { if isListening { stopListening() } }
    }

    private func startListening() {
        message = nil
        isListening = true
        helpers.suspendShortcuts()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Key events are delivered on the main thread. Only a Bool crosses back: NSEvent is not Sendable.
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    /// Handles a key press while listening; `true` swallows it, so it does not also type or trigger a menu command.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if Int(event.keyCode) == kVK_Escape, flags.intersection([.command, .option, .control, .shift]).isEmpty {
            stopListening()
            return true
        }
        guard let candidate = KeyShortcut(event: event) else { return false }
        if let problem = candidate.problem {
            message = problem
            return true
        }
        if candidate == other {
            message = tr(
                "«\(candidate.display)» уже занято другим сочетанием приложения. Выберите другое.",
                "“\(candidate.display)” is already the app's other shortcut. Choose another one."
            )
            return true
        }
        save(candidate)
        return true
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isListening = false
        helpers.resumeShortcuts()
    }

    private func store(_ shortcut: KeyShortcut) {
        if role == .record {
            preferences.recordShortcut = shortcut
        } else {
            preferences.markShortcut = shortcut
        }
    }

    /// Saves the new combination and takes it at once; if the system refuses it, the old one stays. macOS does
    /// not report a combination that another app also listens for, so that case cannot be caught here. The mark
    /// shortcut is held only while recording, so outside a call it is only checked when the next call starts.
    private func save(_ shortcut: KeyShortcut) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isListening = false
        let previous = current
        store(shortcut)
        helpers.resumeShortcuts()
        if helpers.apply().contains(role) {
            store(previous)
            helpers.apply()
            message = tr(
                "macOS не дала занять «\(shortcut.display)» — осталось \(previous.display). Попробуйте другое сочетание.",
                "macOS did not allow “\(shortcut.display)” — \(previous.display) is kept. Try another combination."
            )
        } else {
            message = nil
        }
    }
}

/// Who made the app, and which version this is. The author line is the one the About window shows.
private struct AboutCard: View {
    private var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }
    private var version: String {
        let main = Bundle.main.infoDictionary
        return "\(main?["CFBundleShortVersionString"] as? String ?? "") (\(main?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Transcribation").font(.headline)
                Text(tr("Версия ", "Version ") + version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let author = copyright {
                    Text(author)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
    }
}
