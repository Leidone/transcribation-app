import AudioCapture
import CallLibrary
import CodexClient
import Localization
import SwiftUI

enum ResultTab: Hashable {
    case summary
    case transcript
    case tasks
    case questions
}

private struct CardLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct SummaryTab: View {
    let analysis: AnalysisResult

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CardLabel(text: tr("Кратко", "In short"))
                        Spacer()
                        if let template = analysis.template, template != .general {
                            Label(template.title, systemImage: template.systemImage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(analysis.summary)
                        .font(.system(size: 20, weight: .regular))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 26)
                .staggeredAppear(0)

                VStack(alignment: .leading, spacing: 14) {
                    CardLabel(text: tr("Решения", "Decisions"))
                    if analysis.decisions.isEmpty {
                        Text(tr("Явных решений не зафиксировано.", "No explicit decisions were made."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(analysis.decisions, id: \.self) { decision in
                            Label {
                                Text(decision).textSelection(.enabled)
                            } icon: {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                            }
                            .font(.title3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 26)
            }
        }
    }
}

/// The moments marked important during the call, each with what was being said, to jump to.
/// Who spoke how much in this meeting, the most talkative first.
struct TalkTimeCard: View {
    let shares: [TalkShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("Кто сколько говорил", "Who spoke how much"), systemImage: "chart.bar.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            ForEach(shares, id: \.name) { share in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(share.name).font(.callout.weight(share.isMe ? .semibold : .regular))
                        Spacer()
                        Text("\(Int((share.share * 100).rounded()))% · \(share.seconds.clockString)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Theme.speakerColor(share.name, isMe: share.isMe).gradient)
                            .frame(width: max(4, geometry.size.width * share.share))
                    }
                    .frame(height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 22)
    }
}

struct ImportantMomentsCard: View {
    let recording: RecordingItem
    var onSeek: ((TimeInterval) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("Отмечено важным", "Marked as important"), systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            ForEach(recording.marks, id: \.self) { mark in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        onSeek?(mark)
                    } label: {
                        Label(mark.clockString, systemImage: "play.circle")
                            .font(.callout.monospacedDigit())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(onSeek == nil)
                    .help(tr("Послушать это место", "Listen to this moment"))
                    Text(said(at: mark))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 22)
    }

    /// What was being said around the mark, as far as it is known yet.
    private func said(at mark: TimeInterval) -> String {
        let ids = recording.lineIDs(markedAt: mark)
        let lines = recording.transcript.filter { ids.contains($0.id) }.suffix(2)
        guard !lines.isEmpty else { return tr("Расшифровки этого места пока нет", "Not transcribed yet") }
        return lines.map { "\(recording.displayName($0.speaker)): \($0.text)" }.joined(separator: " ")
    }
}

struct TranscriptTab: View {
    let recording: RecordingItem
    /// The line being heard in the player, highlighted.
    var currentLineID: TranscriptLine.ID?
    /// Called with an original label and the name the person typed (empty takes the name back).
    let onRename: (String, String) -> Void
    var onSeek: ((TimeInterval) -> Void)?
    var onEdit: ((TranscriptLine.ID, String) -> Void)?
    /// Marks a line as important, or takes the mark back.
    var onToggleMark: ((TranscriptLine.ID) -> Void)?

    var body: some View {
        let important = recording.importantLineIDs
        LazyVStack(alignment: .leading, spacing: 6) {
            SpeakerLegend(
                speakers: recording.speakers, displayName: recording.displayName,
                suggestions: (recording.meeting?.attendees ?? []).filter { !recording.speakerNames.names.values.contains($0) },
                onRename: onRename
            )
                .padding(.bottom, 12)
            if recording.transcriptEditedAt != nil {
                Label(tr("Текст исправлен вручную", "Text corrected by hand"), systemImage: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
            if !recording.marks.isEmpty {
                Label(
                    tr("Отмеченные во время звонка места подсвечены", "Moments marked during the call are highlighted"),
                    systemImage: "star.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            }
            ForEach(recording.transcript) { line in
                TranscriptRow(
                    line: line, name: recording.displayName(line.speaker), isCurrent: line.id == currentLineID,
                    isImportant: important.contains(line.id), onSeek: onSeek, onEdit: onEdit, onToggleMark: onToggleMark
                )
                .id(line.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 20)
        .animation(Motion.smooth, value: recording.speakers.map { recording.displayName($0.label) })
        .animation(Motion.quick, value: currentLineID)
        .animation(Motion.quick, value: important)
    }
}

private struct TranscriptRow: View {
    let line: TranscriptLine
    let name: String
    let isCurrent: Bool
    let isImportant: Bool
    let onSeek: ((TimeInterval) -> Void)?
    let onEdit: ((TranscriptLine.ID, String) -> Void)?
    let onToggleMark: ((TranscriptLine.ID) -> Void)?

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                onSeek?(line.time)
            } label: {
                Text(line.time.clockString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(onSeek == nil)
            .help(tr("Слушать с этого места", "Listen from here"))
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.speakerColor(line.speaker, isMe: line.isMe))
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.opacity)
                        .foregroundStyle(Theme.speakerColor(line.speaker, isMe: line.isMe))
                    if isImportant {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .help(tr("Отмечено как важное", "Marked as important"))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    if isHovering, onEdit != nil {
                        Button {
                            draft = line.text
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(tr("Исправить текст", "Correct the text"))
                        .transition(.opacity)
                    }
                }
                Text(line.text)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(background, in: .rect(cornerRadius: 12))
        .onHover { hovering in withAnimation(Motion.quick) { isHovering = hovering } }
        .contextMenu {
            if let onSeek { Button(tr("Слушать с этого места", "Listen from here")) { onSeek(line.time) } }
            if onEdit != nil {
                Button(tr("Исправить текст…", "Correct the text…")) {
                    draft = line.text
                    isEditing = true
                }
            }
            if let onToggleMark {
                Button(isImportant ? tr("Снять отметку «Важно»", "Remove the “Important” mark")
                                   : tr("Отметить как важное", "Mark as important")) {
                    onToggleMark(line.id)
                }
            }
        }
        .popover(isPresented: $isEditing, arrowEdge: .trailing) { editor }
    }

    private var background: Color {
        if isCurrent { return Color.accentColor.opacity(0.12) }
        return isImportant ? Color.yellow.opacity(0.13) : .clear
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Исправить текст", "Correct the text")).font(.headline)
            TextEditor(text: $draft)
                .font(.body)
                .frame(width: 380, height: 120)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            Text(tr("Время и собеседник останутся прежними. Итоги можно будет пересчитать.", "The time and the speaker stay the same. The summary can be made again."))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(tr("Отмена", "Cancel")) { isEditing = false }
                Spacer()
                Button(tr("Сохранить", "Save")) {
                    onEdit?(line.id, draft)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
    }
}

/// The voices of a recording as chips; a click opens a small editor to give the voice a name.
private struct SpeakerLegend: View {
    let speakers: [(label: String, isMe: Bool)]
    let displayName: (String) -> String
    /// Invited people from the calendar who have no voice yet.
    let suggestions: [String]
    let onRename: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(speakers, id: \.label) { speaker in
                    SpeakerChip(
                        label: speaker.label, isMe: speaker.isMe, name: displayName(speaker.label),
                        suggestions: speaker.isMe ? [] : suggestions,
                        onRename: { onRename(speaker.label, $0) }
                    )
                }
            }
            Text(tr("Нажмите на имя, чтобы переименовать голос. Имя запомнится, и в следующих звонках этот голос подпишется сам.", "Click a name to rename the voice. The name is remembered, and this voice is named by itself in later calls."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SpeakerChip: View {
    let label: String
    let isMe: Bool
    let name: String
    let suggestions: [String]
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    /// How the voice is shown while nobody has named it.
    private var defaultName: String { SpeakerNames.defaultName(for: label) }

    var body: some View {
        Button {
            draft = name == defaultName ? "" : name
            isEditing = true
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.speakerColor(label, isMe: isMe))
                    .frame(width: 9, height: 9)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary, in: .capsule)
        }
        .buttonStyle(PressableStyle())
        .popover(isPresented: $isEditing, arrowEdge: .bottom) { editor }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Имя для «\(defaultName)»", "Name for “\(defaultName)”"))
                .font(.headline)
            TextField(tr("Например, Анна", "For example, Anna"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            if !suggestions.isEmpty {
                Text(tr("Приглашены на встречу:", "Invited to the meeting:"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suggestions, id: \.self) { person in
                        Button(person) {
                            draft = person
                            commit()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            HStack {
                Button(tr("Сбросить", "Reset")) {
                    onRename("")
                    isEditing = false
                }
                .disabled(name == defaultName)
                Spacer()
                Button(tr("Готово", "Done"), action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 280)
    }

    private func commit() {
        onRename(draft)
        isEditing = false
    }
}

struct TasksTab: View {
    let tasks: [TaskItem]
    /// Shows a task owner by the name the person gave, when they renamed that voice.
    let displayName: (String) -> String
    let onToggle: (TaskItem.ID) -> Void
    var onSeek: ((TimeInterval) -> Void)?
    var onRemind: (([TaskItem]) -> Void)?

    var body: some View {
        if tasks.isEmpty {
            Text(tr("В этом разговоре задач не было.", "There were no tasks in this conversation."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .glassCard(padding: 26)
        } else {
            VStack(alignment: .trailing, spacing: 14) {
                if let onRemind, tasks.contains(where: { !$0.isDone }) {
                    Button {
                        onRemind(tasks)
                    } label: {
                        Label(tr("Все открытые — в Напоминания", "All open ones to Reminders"), systemImage: "checklist")
                    }
                    .buttonStyle(.glass)
                }
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            TaskRow(
                                task: task, displayName: displayName, onToggle: { onToggle(task.id) }, onSeek: onSeek,
                                onRemind: onRemind.map { remind in { remind([task]) } }
                            )
                            .staggeredAppear(index)
                        }
                    }
                }
            }
        }
    }
}

/// One task: done mark, owner and deadline, the quote with a jump to where it was said.
struct TaskRow: View {
    let task: TaskItem
    let displayName: (String) -> String
    let onToggle: () -> Void
    let onSeek: ((TimeInterval) -> Void)?
    let onRemind: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                    .symbolEffect(.bounce, value: task.isDone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? tr("Отметить невыполненной", "Mark as not done") : tr("Отметить выполненной", "Mark as done"))

            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                HStack(spacing: 8) {
                    if let owner = task.owner { Chip(icon: "person.fill", text: displayName(owner)) }
                    if let due = task.due { Chip(icon: "calendar", text: due) }
                }
                if let quote = task.quote {
                    HStack(spacing: 6) {
                        Text("«\(quote)»")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let time = task.timestamp, let onSeek {
                            Button {
                                onSeek(time)
                            } label: {
                                Label(time.clockString, systemImage: "play.circle")
                                    .font(.callout.monospacedDigit())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .help(tr("Послушать, где это было сказано", "Listen to where it was said"))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let onRemind, !task.isDone {
                Button(action: onRemind) {
                    Image(systemName: "bell.badge")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("Добавить в Напоминания", "Add to Reminders"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20, padding: 18)
    }
}

private struct Chip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
    }
}
