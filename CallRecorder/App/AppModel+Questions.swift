import CallLibrary
import CodexClient
import Foundation
import Localization

/// Questions to one meeting or to all of them, answered by the connected AI from the transcripts and summaries.
extension AppModel {
    /// How many earlier questions and answers go with a new one, so a follow-up can refer to them.
    private static let rememberedTurns = 4

    func chat(_ scope: ChatScope) -> [ChatTurn] {
        chats[scope] ?? []
    }

    func isWaiting(in scope: ChatScope) -> Bool {
        chat(scope).contains(where: \.isWaiting)
    }

    /// Asks the AI; the question shows at once, the answer or the reason there is none replaces the wait.
    func ask(_ text: String, in scope: ChatScope, using account: CodexAccountModel) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isWaiting(in: scope) else { return }
        let earlier = chat(scope).suffix(Self.rememberedTurns).compactMap { turn in
            turn.answer.map { MeetingQuestion.Turn(question: turn.question, answer: $0) }
        }
        let turn = ChatTurn(question: question)
        chats[scope, default: []].append(turn)

        guard account.isSignedIn else {
            updateTurn(turn.id, in: scope) { $0.error = ChatTurn.notConnectedMessage() }
            return
        }
        let context: MeetingContext
        switch scope {
        case .library:
            context = MeetingContext.library(recordings, question: question)
        case .recording(let id):
            guard let recording = recordings.first(where: { $0.id == id }) else { return }
            context = MeetingContext.single(recording, previous: MeetingSeries.previous(of: recording, in: realRecordings))
        }
        guard !context.references.isEmpty else {
            updateTurn(turn.id, in: scope) {
                $0.error = tr(
                    "В записях пока нет текста: сначала их нужно расшифровать.",
                    "There is no text in the recordings yet: transcribe them first."
                )
            }
            return
        }
        do {
            let outcome = try await account.answer(
                MeetingQuestion(question: question, meetings: context.text, earlier: Array(earlier))
            )
            let sources = context.sources(of: outcome.answer, in: recordings)
            updateTurn(turn.id, in: scope) {
                $0.answer = outcome.answer.answer
                $0.sources = sources
            }
        } catch {
            updateTurn(turn.id, in: scope) { $0.error = error.localizedDescription }
        }
    }

    /// Asks a question that failed once more, in its place at the end of the conversation.
    func retry(_ turnID: ChatTurn.ID, in scope: ChatScope, using account: CodexAccountModel) async {
        guard let turn = chat(scope).first(where: { $0.id == turnID }) else { return }
        chats[scope]?.removeAll { $0.id == turnID }
        await ask(turn.question, in: scope, using: account)
    }

    func clearChat(_ scope: ChatScope) {
        chats[scope] = nil
    }

    private func updateTurn(_ id: ChatTurn.ID, in scope: ChatScope, _ change: (inout ChatTurn) -> Void) {
        guard var turns = chats[scope], let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
        chats[scope] = turns
    }
}
