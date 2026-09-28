import CallLibrary
import CodexClient
import Localization
import SwiftUI
import Transcription

struct RecordingDetailView: View {
    @Bindable var model: AppModel
    let recording: RecordingItem
    @State private var tab: ResultTab = .summary
    @State private var showsDeleteConfirmation = false
    @State private var player = PlaybackController()

    /// The transcript line to bring into view once it is laid out.
    @State private var scrollTarget: TranscriptLine.ID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if recording.isSample {
                        SampleBanner { withAnimation(Motion.smooth) { model.hideSamples() } }
                    }
                    if recording.audio != nil, !recording.transcript.isEmpty {
                        PlayerBar(player: player)
                    }
                    if let analysis = recording.analysis, recording.status == .ready {
                        if recording.isAnalysisOutdated {
                            OutdatedBanner(model: model, recording: recording)
                        }
                        GlassTabBar(
                            tabs: [
                                (ResultTab.summary, tr("Итоги", "Summary")),
                                (ResultTab.transcript, tr("Транскрипт", "Transcript")),
                                (ResultTab.tasks, tr("Задачи", "Tasks") + " · \(analysis.tasks.filter { !$0.isDone }.count)"),
                                (ResultTab.questions, tr("Вопросы", "Ask")),
                            ],
                            selection: $tab
                        )

                        content(analysis: analysis)
                            .id(tab)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if recording.status == .transcribed {
                        TranscribedView(model: model, recording: recording, player: player)
                    } else {
                        AwaitingCard(model: model, recording: recording)
                    }
                }
                .padding(36)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                Task {
                    // The transcript tab has to be on screen before its line can be scrolled to.
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(Motion.smooth) { proxy.scrollTo(target, anchor: .center) }
                    scrollTarget = nil
                }
            }
        }
        .animation(Motion.smooth, value: tab)
        .task(id: recording.audio) {
            await player.load(recording.audio, duration: recording.duration)
            showPendingMoment()
        }
        .onChange(of: model.pendingMoment) { showPendingMoment() }
        .onDisappear { player.stop() }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.arrive, value: model.notice)
    }

    /// Goes to the moment another page asked for: the transcript, scrolled to the line, with the player there.
    private func showPendingMoment() {
        guard let moment = model.pendingMoment, moment.recordingID == recording.id else { return }
        model.pendingMoment = nil
        if recording.status == .ready { tab = .transcript }
        player.seek(to: moment.time)
        scrollTarget = recording.line(at: moment.time)?.id
    }

    private var seek: (TimeInterval) -> Void {
        { player.seek(to: $0, startsPlaying: true) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            AppIconView(bundleID: recording.appBundleID, size: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(recording.title)
                    .font(.system(size: 34, weight: .semibold))
                Text(RecordingExport.subtitle(of: recording))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if recording.directory != nil {
                    TagsRow(model: model, recording: recording)
                }
                let series = MeetingSeries.members(of: recording, in: model.recordings)
                if let previous = MeetingSeries.previous(of: recording, in: model.recordings) {
                    Button {
                        model.open(previous.id)
                    } label: {
                        Label(
                            tr("Серия: ", "Series: ")
                                + plural(series.count, "встреча", "встречи", "встреч", "meeting", "meetings")
                                + tr(" · прошлая ", " · previous ")
                                + previous.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Language.current.locale)),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(tr("Открыть прошлую встречу этой серии", "Open the previous meeting of this series"))
                }
                if let attendees = recording.meeting?.attendees, !attendees.isEmpty {
                    Label(tr("Приглашены: ", "Invited: ") + attendees.joined(separator: ", "), systemImage: "person.2")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let stats = recording.processingStats, let speed = stats.speedFactor {
                    let seconds = stats.processingSeconds.formatted(.number.precision(.fractionLength(0...1)))
                    let factor = Int(speed.rounded())
                    Text(tr(
                        "Расшифровано на этом Mac за \(seconds) с · в \(factor)× быстрее реального времени",
                        "Transcribed on this Mac in \(seconds) s · \(factor)× faster than real time"
                    ))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if !recording.transcript.isEmpty {
                ShareMenu(model: model, recording: recording)
            }
            if recording.directory != nil, model.preferences.usesCalendar {
                MeetingPicker(model: model, recording: recording)
            }
            if recording.directory != nil {
                Button {
                    model.revealInFinder(recording)
                } label: {
                    Label(tr("Показать в Finder", "Show in Finder"), systemImage: "folder")
                }
                .buttonStyle(.glass)
                .help(tr("Показать в Finder", "Show in Finder"))
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label(tr("Удалить", "Delete"), systemImage: "trash")
                }
                .buttonStyle(.glass)
                .help(tr("Удалить запись", "Delete the recording"))
            }
        }
        .labelStyle(.iconOnly)
        .alert(tr("Удалить «\(recording.title)»?", "Delete “\(recording.title)”?"), isPresented: $showsDeleteConfirmation) {
            Button(tr("Удалить", "Delete"), role: .destructive) { model.delete(recording.id) }
            Button(tr("Отмена", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Аудио и расшифровка переместятся в Корзину. Это можно отменить оттуда.", "The audio and transcript go to the Trash. You can restore them from there."))
        }
    }

    @ViewBuilder
    private func content(analysis: AnalysisResult) -> some View {
        switch tab {
        case .summary:
            VStack(alignment: .leading, spacing: 18) {
                SummaryTab(analysis: analysis)
                let shares = TalkTime.shares(of: recording)
                if shares.count > 1 {
                    TalkTimeCard(shares: shares)
                }
                if !recording.marks.isEmpty {
                    ImportantMomentsCard(recording: recording, onSeek: recording.audio == nil ? nil : seek)
                }
            }
        case .transcript:
            TranscriptTab(
                recording: recording,
                currentLineID: player.isReady ? recording.line(at: player.currentTime)?.id : nil,
                onRename: { model.renameSpeaker($0, to: $1, in: recording.id) },
                onSeek: recording.audio == nil ? nil : seek,
                onEdit: recording.isSample ? nil : { model.editLine($0, to: $1, in: recording.id) },
                onToggleMark: recording.isSample ? nil : { model.toggleMark(on: $0, in: recording.id) }
            )
        case .tasks:
            TasksTab(
                tasks: analysis.tasks, displayName: recording.displayName,
                onToggle: { taskID in withAnimation(.smooth) { model.toggleTask(taskID, in: recording.id) } },
                onSeek: recording.audio == nil ? nil : seek,
                onRemind: { tasks in Task { await model.addToReminders(tasks, from: recording) } }
            )
        case .questions:
            QuestionsView(model: model, scope: .recording(recording.id), isEmbedded: true)
        }
    }
}

/// Copy, save as Markdown or PDF, send the tasks to Reminders, or run the summary again.
private struct ShareMenu: View {
    @Bindable var model: AppModel
    let recording: RecordingItem
    @Environment(CodexAccountModel.self) private var account
    @AppStorage("export.includesTranscript") private var includesTranscript = true

    var body: some View {
        Menu {
            if recording.analysis != nil {
                Button(tr("Скопировать итоги", "Copy the summary"), systemImage: "doc.on.doc") { model.copySummary(of: recording) }
                Button(tr("Письмо участникам…", "Email the attendees…"), systemImage: "envelope") {
                    model.composeFollowUp(for: recording)
                }
                ForEach(model.configuredChats, id: \.self) { service in
                    Button(tr("Отправить в \(service.name)", "Send to \(service.name)"), systemImage: "paperplane") {
                        Task { await model.sendSummary(of: recording, to: service) }
                    }
                }
            }
            ShareLink(
                item: RecordingExport.markdown(of: recording, options: .init(includesTranscript: includesTranscript)),
                subject: Text(recording.title)
            ) {
                Label(tr("Поделиться…", "Share…"), systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(tr("Сохранить как Markdown…", "Save as Markdown…"), systemImage: "doc.text") {
                model.saveMarkdown(of: recording, includesTranscript: includesTranscript)
            }
            Button(tr("Сохранить как PDF…", "Save as PDF…"), systemImage: "doc.richtext") {
                model.savePDF(of: recording, includesTranscript: includesTranscript)
            }
            Toggle(tr("Вместе с расшифровкой", "Include the transcript"), isOn: $includesTranscript)
            if let tasks = recording.analysis?.tasks, !tasks.isEmpty {
                Divider()
                Button(tr("Задачи — в Напоминания", "Tasks to Reminders"), systemImage: "checklist") {
                    Task { await model.addToReminders(tasks, from: recording) }
                }
            }
            if !recording.isSample, recording.analysis != nil {
                Divider()
                Menu(tr("Пересчитать итоги как…", "Summarise again as…"), systemImage: "arrow.clockwise") {
                    TemplateButtons { template in
                        Task { await model.analyze(recording.id, using: account, template: template) }
                    }
                }
                .disabled(!account.isSignedIn || model.analyzingIDs.contains(recording.id))
            }
        } label: {
            Label(tr("Поделиться и экспорт", "Share and export"), systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help(tr("Поделиться, экспорт, Напоминания", "Share, export, Reminders"))
    }
}

/// One button per meeting template; the chosen one decides what the summary focuses on.
struct TemplateButtons: View {
    let action: (AnalysisTemplate) -> Void

    var body: some View {
        ForEach(AnalysisTemplate.allCases) { template in
            Button(template.title, systemImage: template.systemImage) { action(template) }
        }
    }
}

private struct OutdatedBanner: View {
    @Bindable var model: AppModel
    let recording: RecordingItem
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.circlepath")
                .foregroundStyle(.orange)
            Text(tr("Расшифровку исправили после того, как были готовы итоги.", "The transcript was corrected after the summary was made."))
                .font(.callout)
            Spacer()
            if model.analyzingIDs.contains(recording.id) {
                ProgressView().controlSize(.small)
            } else {
                Button(tr("Пересчитать", "Summarise again")) {
                    let template = recording.analysis?.template ?? account.settings.defaultTemplate
                    Task { await model.analyze(recording.id, using: account, template: template) }
                }
                .buttonStyle(.glass)
                .disabled(!account.isSignedIn)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .capsule)
        .transition(.blurReplace)
    }
}

private struct SampleBanner: View {
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(tr("Пример: так будет выглядеть результат после обработки записи", "Example: this is how a processed recording looks"), systemImage: "sparkles")
                .foregroundStyle(.secondary)
            Button(tr("Скрыть примеры", "Hide examples"), action: onHide)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(tr("Примеры можно вернуть в Настройки → «Общие»", "Examples can be brought back in Settings → General"))
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct AwaitingCard: View {
    @Bindable var model: AppModel
    let recording: RecordingItem

    private var isImported: Bool {
        if case .single = recording.audio { true } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let stage = model.processingStages[recording.id] {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    Text(stage.title)
                        .font(.title3.weight(.semibold))
                }
                Text(tr("Расшифровка идёт на этом Mac, звук никуда не отправляется.", "Transcribing on this Mac; the sound goes nowhere."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                let failure = model.processingErrors[recording.id]
                Image(systemName: failure == nil ? "text.bubble" : "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(failure == nil ? Color.accentColor : Color.orange)
                Text(failure == nil ? tr("Запись сохранена", "Recording saved") : tr("Не удалось расшифровать", "Could not transcribe"))
                    .font(.title2.weight(.semibold))
                Text(failure ?? (isImported
                    ? tr("Аудио добавлено. Расшифруем его локально и различим голоса.", "Audio added. It will be transcribed on this Mac, with the voices told apart.")
                    : tr("Аудио на диске. Расшифруем его локально: голоса собеседников и ваш микрофон по отдельности.", "Audio is on disk. It will be transcribed on this Mac: the other voices and your microphone separately.")))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        Task { await model.process(recording.id) }
                    } label: {
                        Label(failure == nil ? tr("Расшифровать", "Transcribe") : tr("Повторить", "Try again"), systemImage: "text.bubble")
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        model.revealInFinder(recording)
                    } label: {
                        Label(tr("Показать файлы", "Show files"), systemImage: "folder")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 28)
    }
}

/// A recording whose transcript exists; the summary and tasks come from the analysis step.
private struct TranscribedView: View {
    @Bindable var model: AppModel
    let recording: RecordingItem
    let player: PlaybackController
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if recording.transcript.isEmpty {
                Text(tr("В этой записи не нашлось речи.", "No speech was found in this recording."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 26)
            } else {
                analysisCard
                VStack(alignment: .leading, spacing: 12) {
                    Label(tr("Вопросы к записи", "Ask this recording"), systemImage: "bubble.left.and.text.bubble.right")
                        .font(.headline)
                    QuestionsView(model: model, scope: .recording(recording.id), isEmbedded: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 24)
                TranscriptTab(
                    recording: recording,
                    currentLineID: player.isReady ? recording.line(at: player.currentTime)?.id : nil,
                    onRename: { model.renameSpeaker($0, to: $1, in: recording.id) },
                    onSeek: { player.seek(to: $0, startsPlaying: true) },
                    onEdit: { model.editLine($0, to: $1, in: recording.id) },
                    onToggleMark: { model.toggleMark(on: $0, in: recording.id) }
                )
            }
        }
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.analyzingIDs.contains(recording.id) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    Text(tr("ИИ готовит итоги и задачи…", "The AI is preparing the summary and tasks…"))
                        .font(.headline)
                }
                Text(tr("Обычно это занимает до минуты.", "This usually takes up to a minute."))
                    .foregroundStyle(.secondary)
            } else {
                Label(tr("Итоги и задачи", "Summary and tasks"), systemImage: "sparkles")
                    .font(.headline)
                if account.isSignedIn {
                    Text(tr("ИИ прочитает расшифровку и составит краткие итоги, решения и задачи с исполнителями. Тип встречи подскажет, на что обратить внимание.", "The AI reads the transcript and writes a short summary, the decisions and the tasks with their owners. The meeting type says what to focus on."))
                        .foregroundStyle(.secondary)
                    AnalyzeButton(model: model, recording: recording)
                    Text(tr("В ИИ уйдёт только текст расшифровки, аудио остаётся на этом Mac.", "Only the transcript text goes to the AI; audio stays on this Mac."))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(tr("Чтобы получить итоги и задачи, подключите ИИ: кнопка слева внизу.", "To get a summary and tasks, connect an AI: the button at the bottom left."))
                        .foregroundStyle(.secondary)
                }
                if let failure = model.analysisErrors[recording.id] {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 24)
    }
}

/// "Get the summary" with the default meeting template, or any other one from the menu next to it.
private struct AnalyzeButton: View {
    @Bindable var model: AppModel
    let recording: RecordingItem
    @Environment(CodexAccountModel.self) private var account

    var body: some View {
        let template = account.settings.defaultTemplate
        Menu {
            TemplateButtons { chosen in
                Task { await model.analyze(recording.id, using: account, template: chosen) }
            }
        } label: {
            Label(tr("Получить итоги", "Get the summary") + " · " + template.title, systemImage: "wand.and.stars")
        } primaryAction: {
            Task { await model.analyze(recording.id, using: account, template: template) }
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .fixedSize()
    }
}

extension PipelineStage {
    var title: String {
        switch self {
        case .loadingModels: tr("Готовим модели распознавания…", "Preparing the recognition models…")
        case .recognizingOthers: tr("Расшифровываем собеседников…", "Transcribing the other participants…")
        case .identifyingSpeakers: tr("Различаем голоса…", "Telling the voices apart…")
        case .recognizingMe: tr("Расшифровываем ваш голос…", "Transcribing your voice…")
        case .finishing: tr("Собираем транскрипт…", "Putting the transcript together…")
        }
    }
}

/// The recording's own labels: a click searches for the tag, the cross takes it off, "+" adds one.
private struct TagsRow: View {
    @Bindable var model: AppModel
    let recording: RecordingItem
    @State private var isAdding = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(recording.tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Button("#" + tag) { model.searchText = tag }
                        .buttonStyle(.plain)
                        .help(tr("Показать записи с этим тегом", "Show recordings with this tag"))
                    Button {
                        model.removeTag(tag, from: recording.id)
                    } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(tr("Убрать тег", "Remove the tag"))
                }
                .font(.callout)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.quaternary, in: .capsule)
            }
            Button {
                draft = ""
                isAdding = true
            } label: {
                Label(tr("Тег", "Tag"), systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .popover(isPresented: $isAdding, arrowEdge: .bottom) { editor }
        }
    }

    private var suggestions: [String] {
        TagStore.allTags(in: model.recordings).filter { !recording.tags.contains($0) }.prefix(8).map { $0 }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(tr("Например, проект Альфа", "For example, Project Alpha"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button("#" + tag) {
                            draft = tag
                            add()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.callout)
            }
            HStack {
                Spacer()
                Button(tr("Добавить", "Add"), action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func add() {
        model.addTag(draft, to: recording.id)
        isAdding = false
    }
}

/// Which calendar meeting the recording belongs to: the one found automatically can be replaced by another of
/// that time, or taken away when the recording was not a meeting at all.
private struct MeetingPicker: View {
    @Bindable var model: AppModel
    let recording: RecordingItem
    @State private var isShown = false
    @State private var choices: [CalendarEvent]?

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Label(tr("Встреча из Календаря", "Calendar meeting"), systemImage: recording.meeting == nil ? "calendar.badge.plus" : "calendar")
        }
        .buttonStyle(.glass)
        .help(recording.meeting.map { tr("Встреча: ", "Meeting: ") + $0.title } ?? tr("Связать с встречей из Календаря", "Link to a Calendar meeting"))
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            list
                .frame(width: 360)
                .padding(14)
                .task { choices = await model.meetingChoices(for: recording) }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Встреча этой записи", "This recording’s meeting")).font(.headline)
            if let choices {
                if choices.isEmpty {
                    Text(tr("В Календаре нет встреч рядом со временем записи.", "Calendar has no meetings near the time of the recording."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(choices, id: \.self) { event in
                    Button {
                        isShown = false
                        Task { await model.link(event, to: recording.id) }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: event.title == recording.meeting?.title ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(event.title == recording.meeting?.title ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).lineLimit(2)
                                Text(Self.time(of: event)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if recording.meeting != nil {
                Divider()
                Button(tr("Не связывать с встречей", "Not a meeting"), systemImage: "calendar.badge.minus", role: .destructive) {
                    isShown = false
                    Task { await model.unlinkMeeting(from: recording.id) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
    }

    static func time(of event: CalendarEvent) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened).locale(Language.current.locale)
        let people = event.attendees.isEmpty ? "" : " · " + plural(event.attendees.count, "участник", "участника", "участников", "attendee", "attendees")
        return event.start.formatted(style) + "–" + event.end.formatted(style) + people
    }
}

