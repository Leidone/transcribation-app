import CallLibrary
import CodexClient
import SwiftUI
import Transcription
import UIKit

/// Transcript, summary, decisions and tasks for one recording, with a player that follows the transcript.
struct RecordingDetailView: View {
    @Bindable var model: AppModel
    let item: RecordingItem
    @Environment(AIAccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirmation = false
    @State private var player = PlaybackController()
    @State private var shareFile: ShareFile?
    @AppStorage("export.includesTranscript") private var includesTranscript = true

    private var current: RecordingItem { model.recordings.first(where: { $0.id == item.id }) ?? item }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                        .staggeredAppear(0)
                    if current.audio != nil, !current.transcript.isEmpty {
                        MobilePlayer(player: player)
                            .staggeredAppear(1)
                    }
                    if let stage = model.processingStages[item.id] {
                        ProcessingCard(stage: stage)
                            .transition(.blurReplace)
                    } else if let error = model.processingErrors[item.id] {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error).font(.callout).foregroundStyle(.red)
                            Button("Повторить") { Task { await model.process(item.id) } }
                                .buttonStyle(.glass)
                        }
                    } else if current.status == .awaitingProcessing {
                        Button("Расшифровать") { Task { await model.process(item.id) } }
                            .buttonStyle(.glassProminent)
                            .staggeredAppear(1)
                    } else {
                        if current.isAnalysisOutdated {
                            OutdatedBanner(model: model, item: current)
                        }
                        if let analysis = current.analysis {
                            AnalysisCard(model: model, item: current, analysis: analysis, onSeek: seek)
                                .staggeredAppear(2)
                                .transition(.blurReplace)
                        } else if !current.transcript.isEmpty {
                            AnalyzeButton(model: model, item: current, account: account)
                                .staggeredAppear(2)
                        }
                        TranscriptCard(
                            item: current,
                            currentLineID: player.isReady ? current.line(at: player.currentTime)?.id : nil,
                            onRename: { label, name in model.renameSpeaker(label, to: name, in: item.id) },
                            onSeek: current.audio == nil ? nil : seek,
                            onEdit: current.isSample ? nil : { lineID, text in model.editLine(lineID, to: text, in: item.id) }
                        )
                        .staggeredAppear(3)
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .animation(Motion.smooth, value: model.processingStages[item.id])
                .animation(Motion.smooth, value: current.analysis)
            }
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !current.transcript.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { shareMenu }
            }
            if !current.isSample {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .task(id: current.audio) { await player.load(current.audio, duration: current.duration) }
        .onDisappear { player.stop() }
        .sheet(item: $shareFile) { file in
            ActivitySheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
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
        .alert("Удалить «\(current.title)»?", isPresented: $showsDeleteConfirmation) {
            Button("Удалить", role: .destructive) {
                player.stop()
                model.delete(item.id)
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Аудио и расшифровка удалятся без возможности восстановить — на iPhone нет Корзины для приложений.")
        }
    }

    private var seek: (TimeInterval) -> Void {
        { player.seek(to: $0, startsPlaying: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(RecordingExport.subtitle(of: current))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let stats = current.processingStats, let speed = stats.speedFactor {
                Text("Расшифровано на этом iPhone за \(stats.processingSeconds.formatted(.number.precision(.fractionLength(0...1)))) с · в \(Int(speed.rounded()))× быстрее реального времени")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var shareMenu: some View {
        Menu {
            if let analysis = current.analysis {
                Button("Скопировать итоги", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = "# \(current.title)\n\n"
                        + RecordingExport.summaryMarkdown(of: analysis, displayName: current.displayName)
                    model.announce("Итоги скопированы")
                }
            }
            ShareLink(
                item: RecordingExport.markdown(of: current, options: .init(includesTranscript: includesTranscript)),
                subject: Text(current.title)
            ) {
                Label("Поделиться текстом", systemImage: "square.and.arrow.up")
            }
            Button("Файл PDF", systemImage: "doc.richtext") {
                shareFile = model.exportFile(of: current, asPDF: true, includesTranscript: includesTranscript).map(ShareFile.init)
            }
            Button("Файл Markdown", systemImage: "doc.text") {
                shareFile = model.exportFile(of: current, asPDF: false, includesTranscript: includesTranscript).map(ShareFile.init)
            }
            Toggle("Вместе с расшифровкой", isOn: $includesTranscript)
            if let tasks = current.analysis?.tasks, !tasks.isEmpty {
                Button("Задачи — в Напоминания", systemImage: "checklist") {
                    Task { await model.addToReminders(tasks, from: current) }
                }
            }
            if !current.isSample, current.analysis != nil {
                Menu("Пересчитать итоги как…", systemImage: "arrow.clockwise") {
                    TemplateButtons { template in
                        Task { await model.analyze(item.id, using: account, template: template) }
                    }
                }
                .disabled(!account.isSignedIn || model.analyzingIDs.contains(item.id))
            }
        } label: {
            Label("Поделиться", systemImage: "square.and.arrow.up")
        }
    }
}

/// An exported file waiting for the share sheet.
private struct ShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet for a file.
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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

private struct MobilePlayer: View {
    @Bindable var player: PlaybackController
    @State private var scrubbing: TimeInterval?

    var body: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                in: 0...max(player.duration, 1)
            ) { editing in
                if !editing, let target = scrubbing {
                    player.seek(to: target)
                    scrubbing = nil
                }
            }
            HStack {
                Text((scrubbing ?? player.currentTime).clockString).monospacedDigit()
                Spacer()
                Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44)
                }
                Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }
                Spacer()
                Menu {
                    ForEach(PlaybackController.rates, id: \.self) { rate in
                        Button(rateTitle(rate)) { player.setRate(rate) }
                    }
                } label: {
                    Text(rateTitle(player.rate)).monospacedDigit()
                }
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
            if let error = player.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .glassCard(cornerRadius: 22, padding: 16)
        .disabled(!player.isReady)
    }

    private func rateTitle(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate.formatted(.number.precision(.fractionLength(2))))×"
    }
}

private struct ProcessingCard: View {
    let stage: PipelineStage

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title).contentTransition(.opacity)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 14)
    }

    private var title: String {
        switch stage {
        case .loadingModels: "Загружаем модели…"
        case .recognizingOthers: "Распознаём собеседников…"
        case .identifyingSpeakers: "Разделяем голоса…"
        case .recognizingMe: "Распознаём ваш голос…"
        case .finishing: "Сохраняем…"
        }
    }
}

private struct OutdatedBanner: View {
    @Bindable var model: AppModel
    let item: RecordingItem
    @Environment(AIAccountModel.self) private var account

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(.orange)
            Text("Расшифровку исправили после итогов.").font(.callout)
            Spacer()
            if model.analyzingIDs.contains(item.id) {
                ProgressView()
            } else {
                Button("Пересчитать") {
                    let template = item.analysis?.template ?? account.settings.defaultTemplate
                    Task { await model.analyze(item.id, using: account, template: template) }
                }
                .buttonStyle(.glass)
                .disabled(!account.isSignedIn)
            }
        }
        .glassCard(cornerRadius: 18, padding: 12)
    }
}

/// "Get the summary" with the default meeting template, or any other one from its menu.
private struct AnalyzeButton: View {
    @Bindable var model: AppModel
    let item: RecordingItem
    let account: AIAccountModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let template = account.settings.defaultTemplate
            Menu {
                TemplateButtons { chosen in
                    Task { await model.analyze(item.id, using: account, template: chosen) }
                }
            } label: {
                if model.analyzingIDs.contains(item.id) {
                    ProgressView()
                } else {
                    Label("Получить итоги · \(template.title)", systemImage: "sparkles")
                }
            } primaryAction: {
                Task { await model.analyze(item.id, using: account, template: template) }
            }
            .buttonStyle(.glassProminent)
            .disabled(!account.isSignedIn || model.analyzingIDs.contains(item.id))

            Text(account.isSignedIn ? "Нажмите и удерживайте, чтобы выбрать тип встречи." : "Сначала подключите ИИ в настройках.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = model.analysisErrors[item.id] {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

private struct AnalysisCard: View {
    @Bindable var model: AppModel
    let item: RecordingItem
    let analysis: AnalysisResult
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Итоги").font(.headline)
                Spacer()
                if let template = analysis.template, template != .general {
                    Label(template.title, systemImage: template.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(analysis.summary).font(.callout).textSelection(.enabled)

            if !analysis.decisions.isEmpty {
                Text("Решения").font(.headline)
                ForEach(analysis.decisions, id: \.self) { decision in
                    Label(decision, systemImage: "checkmark.seal").font(.callout)
                }
            }

            if !analysis.tasks.isEmpty {
                HStack {
                    Text("Задачи").font(.headline)
                    Spacer()
                    if analysis.tasks.contains(where: { !$0.isDone }) {
                        Button {
                            Task { await model.addToReminders(analysis.tasks, from: item) }
                        } label: {
                            Label("В Напоминания", systemImage: "checklist").font(.caption)
                        }
                        .buttonStyle(.glass)
                    }
                }
                ForEach(analysis.tasks) { task in
                    MobileTaskRow(
                        task: task, displayName: item.displayName,
                        onToggle: { withAnimation(Motion.quick) { model.toggleTask(task.id, in: item.id) } },
                        onSeek: item.audio == nil ? nil : onSeek
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct MobileTaskRow: View {
    let task: TaskItem
    let displayName: (String) -> String
    let onToggle: () -> Void
    let onSeek: ((TimeInterval) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Отметить невыполненной" : "Отметить выполненной")

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.callout.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let owner = task.owner { chip("person.fill", displayName(owner)) }
                    if let due = task.due { chip("calendar", due) }
                }
                if let quote = task.quote {
                    HStack(spacing: 6) {
                        Text("«\(quote)»").font(.caption).foregroundStyle(.secondary)
                        if let time = task.timestamp, let onSeek {
                            Button { onSeek(time) } label: {
                                Label(time.clockString, systemImage: "play.circle").font(.caption.monospacedDigit())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
    }
}

private struct TranscriptCard: View {
    let item: RecordingItem
    let currentLineID: TranscriptLine.ID?
    let onRename: (String, String) -> Void
    let onSeek: ((TimeInterval) -> Void)?
    let onEdit: ((TranscriptLine.ID, String) -> Void)?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var editing: TranscriptLine?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Расшифровка").font(.headline)
            Text("Нажмите на имя, чтобы назвать голос — он запомнится для следующих записей. Удерживайте строку, чтобы исправить текст.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if item.transcriptEditedAt != nil {
                Label("Текст исправлен вручную", systemImage: "pencil.line").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(item.transcript) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Button(item.displayName(line.speaker)) {
                            renaming = line.speaker
                            newName = item.displayName(line.speaker) == line.speaker ? "" : item.displayName(line.speaker)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.speakerColor(line.speaker, isMe: line.isMe))
                        Spacer()
                        if let onSeek {
                            Button(line.time.clockString) { onSeek(line.time) }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(line.id == currentLineID ? Color.accentColor : Color.secondary)
                        }
                    }
                    Text(line.text).font(.callout)
                }
                .padding(8)
                .background(line.id == currentLineID ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
                .contextMenu {
                    if let onSeek { Button("Слушать отсюда", systemImage: "play") { onSeek(line.time) } }
                    if onEdit != nil {
                        Button("Исправить текст", systemImage: "pencil") {
                            draft = line.text
                            editing = line
                        }
                    }
                    Button("Скопировать", systemImage: "doc.on.doc") { UIPasteboard.general.string = line.text }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(Motion.quick, value: currentLineID)
        .alert("Имя собеседника", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Например, Анна", text: $newName)
            Button("Сохранить") {
                if let label = renaming { onRename(label, newName) }
                renaming = nil
            }
            Button("Сбросить", role: .destructive) {
                if let label = renaming { onRename(label, "") }
                renaming = nil
            }
            Button("Отмена", role: .cancel) { renaming = nil }
        }
        .sheet(item: $editing) { line in
            NavigationStack {
                TextEditor(text: $draft)
                    .padding()
                    .navigationTitle("Исправить текст")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { editing = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Сохранить") {
                                onEdit?(line.id, draft)
                                editing = nil
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}
