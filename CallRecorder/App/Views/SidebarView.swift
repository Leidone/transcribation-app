import CallLibrary
import Localization
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var showsAccount = false
    @State private var pendingDelete: RecordingItem?

    private struct DayGroup {
        let title: String
        let items: [RecordingItem]
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let visible = model.visibleRecordings
        let candidates = [
            DayGroup(title: tr("Сегодня", "Today"), items: visible.filter { calendar.isDateInToday($0.startedAt) }),
            DayGroup(title: tr("Вчера", "Yesterday"), items: visible.filter { calendar.isDateInYesterday($0.startedAt) }),
            DayGroup(title: tr("Ранее", "Earlier"), items: visible.filter {
                !calendar.isDateInToday($0.startedAt) && !calendar.isDateInYesterday($0.startedAt)
            }),
        ]
        return candidates.filter { !$0.items.isEmpty }
    }

    var body: some View {
        List(selection: $model.selectedID) {
            if model.isRecording {
                LiveRecordingRow(model: model)
            }
            if model.searchText.isEmpty {
                LibraryPageRow(
                    title: tr("Все задачи", "All tasks"), systemImage: "checklist",
                    badge: TaskOverview.openCount(in: model.recordings), isActive: model.libraryPage == .tasks
                ) { model.libraryPage = .tasks }
                LibraryPageRow(
                    title: tr("Вопросы по встречам", "Ask your meetings"), systemImage: "bubble.left.and.text.bubble.right",
                    badge: 0, isActive: model.libraryPage == .questions
                ) { model.libraryPage = .questions }
            }
            if groups.isEmpty, !model.searchText.isEmpty {
                Text(tr("Ничего не нашлось. Поиск идёт по названиям, именам, итогам, задачам и расшифровкам.", "Nothing found. The search covers titles, names, summaries, tasks and transcripts."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        RecordingRow(
                            item: item,
                            isProcessing: model.processingStages[item.id] != nil || model.analyzingIDs.contains(item.id),
                            hit: LibrarySearch.hits(in: item, query: model.searchText, limit: 1).first
                        )
                        .tag(item.id)
                        .contextMenu {
                            if item.isSample {
                                Button(tr("Скрыть примеры", "Hide examples")) { withAnimation(Motion.smooth) { model.hideSamples() } }
                            } else {
                                Button(tr("Удалить запись", "Delete the recording"), role: .destructive) { pendingDelete = item }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if item.isSample {
                                Button(tr("Скрыть", "Hide")) { withAnimation(Motion.smooth) { model.hideSamples() } }
                            } else {
                                Button(tr("Удалить", "Delete"), role: .destructive) { pendingDelete = item }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: tr("Поиск по записям", "Search recordings"))
        .animation(Motion.smooth, value: model.visibleRecordings.map(\.id))
        .onChange(of: model.selectedID) { _, selection in
            if selection != nil { model.showsRecorder = false }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                AccountRow(showsAccount: $showsAccount)
                Button {
                    model.chooseAudioToImport()
                } label: {
                    Label(tr("Импортировать аудио…", "Import Audio…"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .help(tr("WAV, MP3, M4A, AAC, FLAC, AIFF, CAF. Можно перетащить файлы в окно.", "WAV, MP3, M4A, AAC, FLAC, AIFF, CAF. You can also drop files into the window."))
                Button {
                    model.selectedID = nil
                    model.showsRecorder = true
                } label: {
                    Label(model.isRecording ? tr("Открыть запись", "Open the recording") : tr("Новая запись", "New Recording"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(12)
        }
        .sheet(isPresented: $showsAccount) {
            AccountSheet()
        }
        .alert(
            tr("Удалить «\(pendingDelete?.title ?? "")»?", "Delete “\(pendingDelete?.title ?? "")”?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button(tr("Удалить", "Delete"), role: .destructive) {
                if let id = pendingDelete?.id { model.delete(id) }
                pendingDelete = nil
            }
            Button(tr("Отмена", "Cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(tr("Аудио и расшифровка переместятся в Корзину. Это можно отменить оттуда.", "The audio and transcript go to the Trash. You can restore them from there."))
        }
        .navigationTitle(tr("Записи", "Recordings"))
    }
}

/// A page about the whole library, above the recordings; it looks selected while it is shown.
private struct LibraryPageRow: View {
    let title: String
    let systemImage: String
    let badge: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(isActive ? Color.white : Color.accentColor)
                    .frame(width: 22)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(isActive ? Color.white.opacity(0.25) : Color.secondary.opacity(0.18), in: .capsule)
                        .foregroundStyle(isActive ? Color.white : Color.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: isActive)
        .animation(Motion.quick, value: badge)
    }
}

/// One-line account status; a click opens the sign-in sheet.
private struct AccountRow: View {
    @Environment(CodexAccountModel.self) private var account
    @Binding var showsAccount: Bool

    var body: some View {
        Button {
            showsAccount = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(text)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(PressableStyle())
        .help(tr("ИИ для итогов и задач: аккаунт, ключ и промпт", "The AI for summaries and tasks: account, key and prompt"))
    }

    private var icon: String {
        switch account.state {
        case .signedIn: "checkmark.seal.fill"
        case .unavailable, .failed: "exclamationmark.triangle.fill"
        case .checking, .signingIn, .signedOut: "person.crop.circle"
        }
    }

    private var color: Color {
        switch account.state {
        case .signedIn: .green
        case .unavailable, .failed: .orange
        case .checking, .signingIn, .signedOut: .secondary
        }
    }

    private var text: String {
        switch account.state {
        case .checking: tr("Проверяем аккаунт…", "Checking the account…")
        case .unavailable: tr("Codex не найден", "Codex not found")
        case .signedOut: tr("Подключить ИИ", "Connect an AI")
        case .signingIn: tr("Ждём вход в браузере…", "Waiting for sign-in in the browser…")
        case .signedIn(let email, let plan): email ?? plan ?? tr("ИИ подключён", "AI connected")
        case .failed: tr("Ошибка входа", "Sign-in failed")
        }
    }
}

private struct RecordingRow: View {
    let item: RecordingItem
    let isProcessing: Bool
    /// Where the search query was found, shown under the title while searching.
    let hit: SearchHit?

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleID: item.appBundleID, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(item.startedAt.formatted(date: .omitted, time: .shortened)) · \(item.duration.clockString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let hit, hit.place != .title {
                    Text(hit.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            badge
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var badge: some View {
        if item.isSample {
            Text(tr("Пример", "Example"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: .capsule)
        } else if isProcessing {
            ProgressView()
                .controlSize(.small)
                .help(tr("Идёт расшифровка", "Transcribing"))
        } else if item.status == .awaitingProcessing {
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
                .help(tr("Ожидает расшифровки", "Waiting to be transcribed"))
        } else if item.status == .transcribed {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
                .help(tr("Расшифровано", "Transcribed"))
        } else if item.status == .ready {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help(tr("Итоги и задачи готовы", "Summary and tasks ready"))
        }
    }
}

private struct LiveRecordingRow: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            model.selectedID = nil
            model.showsRecorder = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .phaseAnimator([0.35, 1.0]) { view, opacity in view.opacity(opacity) } animation: { _ in
                        .easeInOut(duration: 0.9)
                    }
                Text(tr("Идёт запись", "Recording"))
                    .font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = model.recordedTime(at: context.date)
                    Text(max(0, elapsed).clockString)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
