import CallLibrary
import Localization
import SwiftUI

/// A conversation with the connected AI about one meeting or all of them. Answers name the places they rest on;
/// a click opens the recording there.
struct QuestionsView: View {
    @Bindable var model: AppModel
    let scope: ChatScope
    /// Inside a recording's page, without a title of its own and without its own scrolling.
    var isEmbedded = false

    @Environment(CodexAccountModel.self) private var account
    @State private var draft = ""
    @FocusState private var isTyping: Bool

    private var turns: [ChatTurn] { model.chat(scope) }

    var body: some View {
        if isEmbedded {
            conversation
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                            .staggeredAppear(0)
                        conversation
                            .staggeredAppear(1)
                    }
                    .padding(36)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: turns) { _, newTurns in
                    guard let last = newTurns.last else { return }
                    withAnimation(Motion.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Вопросы по встречам", "Ask your meetings"))
                .font(.system(size: 34, weight: .semibold))
            Text(tr(
                "Спросите, о чём договорились, кто что обещал или когда это обсуждали. ИИ ответит по расшифровкам и итогам и покажет, где это было сказано.",
                "Ask what was agreed, who promised what, or when something came up. The AI answers from the transcripts and summaries and shows where it was said."
            ))
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            if turns.isEmpty {
                suggestions
            }
            ForEach(turns) { turn in
                ChatTurnView(
                    turn: turn, showsMeetingTitles: scope == .library,
                    onOpen: { source in model.open(source.recordingID, at: source.time) },
                    onRetry: { Task { await model.retry(turn.id, in: scope, using: account) } }
                )
                .id(turn.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            inputBar
            footnote
        }
        .animation(Motion.smooth, value: turns)
    }

    private var suggestionTexts: [String] {
        switch scope {
        case .library:
            [
                tr("Итоги недели: что решили и что осталось?", "This week: what was decided and what is still open?"),
                tr("Что решили на последней встрече?", "What was decided at the last meeting?"),
                tr("Какие задачи на мне?", "Which tasks are mine?"),
                tr("Когда обсуждали бюджет?", "When did we discuss the budget?"),
            ]
        case .recording(let id):
            (hasPreviousInSeries(id) ? [tr("Что изменилось с прошлой встречи?", "What changed since the last meeting?")] : []) + [
                tr("О чём договорились?", "What was agreed?"),
                tr("Какие были возражения?", "What objections came up?"),
                tr("Что осталось нерешённым?", "What is still open?"),
            ]
        }
    }

    private func hasPreviousInSeries(_ id: UUID) -> Bool {
        guard let recording = model.recordings.first(where: { $0.id == id }) else { return false }
        return MeetingSeries.previous(of: recording, in: model.recordings) != nil
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Например:", "For example:"))
                .font(.callout)
                .foregroundStyle(.secondary)
            FlowingButtons(titles: suggestionTexts) { text in send(text) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(
                scope == .library ? tr("Спросите о своих встречах…", "Ask about your meetings…")
                                  : tr("Спросите об этой встрече…", "Ask about this meeting…"),
                text: $draft, axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .focused($isTyping)
            .onSubmit { send(draft) }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))

            Button {
                send(draft)
            } label: {
                if model.isWaiting(in: scope) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWaiting(in: scope))
            .keyboardShortcut(.return, modifiers: .command)
            .help(tr("Спросить (⌘↩)", "Ask (⌘↩)"))

            if !turns.isEmpty {
                Button {
                    withAnimation(Motion.smooth) { model.clearChat(scope) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(model.isWaiting(in: scope))
                .help(tr("Очистить разговор", "Clear the conversation"))
            }
        }
    }

    private var footnote: some View {
        Text(scope == .library
            ? tr("В ИИ уйдёт текст встреч, подходящих к вопросу (до ~40 тысяч токенов). Аудио остаётся на этом Mac. Разговор не сохраняется после выхода.",
                 "The text of the meetings related to the question goes to the AI (up to ~40 thousand tokens). Audio stays on this Mac. The conversation is not kept after quitting.")
            : tr("В ИИ уйдёт текст этой встречи. Аудио остаётся на этом Mac.",
                 "The text of this meeting goes to the AI. Audio stays on this Mac."))
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !model.isWaiting(in: scope) else { return }
        draft = ""
        Task { await model.ask(question, in: scope, using: account) }
    }
}

/// One question and its answer, with the places the answer rests on.
private struct ChatTurnView: View {
    let turn: ChatTurn
    let showsMeetingTitles: Bool
    let onOpen: (ChatSource) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 80)
                Text(turn.question)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.18), in: .rect(cornerRadius: 18))
            }

            Group {
                if let answer = turn.answer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(answer)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                        if !turn.sources.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(turn.sources) { source in
                                    SourceButton(source: source, showsTitle: showsMeetingTitles) { onOpen(source) }
                                }
                            }
                        }
                    }
                } else if let error = turn.error {
                    HStack(spacing: 10) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Повторить", "Try again"), action: onRetry)
                            .buttonStyle(.glass)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(tr("Ищем ответ в записях…", "Looking through the recordings…"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 20, padding: 18)
        }
    }
}

/// "Weekly · 12:34 «quote»" — opens the recording at that moment.
private struct SourceButton: View {
    let source: ChatSource
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: source.time == nil ? "doc.text" : "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(place)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                if let quote = source.quote, !quote.isEmpty {
                    Text("«\(quote)»")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .help(tr("Открыть запись на этом месте", "Open the recording at this moment"))
    }

    private var place: String {
        let time = source.time?.clockString
        guard showsTitle else { return time ?? tr("Итоги встречи", "Meeting summary") }
        return [source.title, time].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Buttons that wrap onto the next line when they do not fit.
private struct FlowingButtons: View {
    let titles: [String]
    let action: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(titles, id: \.self) { title in
                Button(title) { action(title) }
                    .buttonStyle(.glass)
            }
        }
    }
}

/// Lays children out left to right, starting a new row when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let current = rows.count - 1
            rows[current].width += (rows[current].indices.isEmpty ? 0 : spacing) + size.width
            rows[current].height = max(rows[current].height, size.height)
            rows[current].indices.append(index)
        }
        return rows
    }
}
