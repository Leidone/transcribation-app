import AudioCapture
import CallLibrary
import Localization
import SwiftUI
import Transcription

/// The call as it is being said, in its own panel: the person's own words on the right, the others' on the left,
/// each phrase arriving softly out of a blur, the newest one in focus.
struct LiveTranscriptPanel: View {
    /// The panel's width beside the recorder, and the detail width from which it fits there.
    static let width: CGFloat = 380
    static let besideMinimumWidth: CGFloat = 860

    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if model.liveLines.isEmpty {
                            ListeningPlaceholder(warning: model.soundWarning)
                                .transition(.opacity)
                        }
                        ForEach(model.liveLines) { line in
                            LiveBubble(line: line, isNewest: line.id == model.liveLines.last?.id, isInRoom: isInRoom)
                                .id(line.id)
                                .transition(.phraseArrival)
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(Motion.arrive, value: model.liveLines.count)
                }
                .scrollIndicators(.hidden)
                .mask(fadedEdges)
                .onChange(of: model.liveLines.last?.id) { _, last in
                    guard let last else { return }
                    withAnimation(Motion.smooth) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            Text(tr(
                "Черновик: полная расшифровка с разделением собеседников будет готова после звонка.",
                "A draft: the full transcript, with the voices told apart, is made after the call."
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(cornerRadius: 24, padding: 18)
    }

    private var header: some View {
        HStack(spacing: 8) {
            LiveDot(isActive: !model.isPaused)
            Text(tr("Расшифровка на лету", "Live transcript"))
                .font(.headline)
            Spacer()
            Text(speedCaption)
                .font(.caption)
                .foregroundStyle(isFallingBehind ? Color.orange : Color.secondary)
                .contentTransition(.numericText())
                .animation(Motion.quick, value: speedCaption)
        }
    }

    /// Lines slide under a soft fade at the top and the bottom instead of being cut by the edge.
    private var fadedEdges: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var isFallingBehind: Bool {
        model.liveStats.skippedPhrases > 0
    }

    /// A meeting in a room: every voice comes through the one microphone, so no line is "mine".
    private var isInRoom: Bool {
        model.selectedBundleID == SourceApp.inPersonBundleID
    }

    /// How the Mac keeps up, so the person can judge whether their Mac manages it.
    private var speedCaption: String {
        if isFallingBehind {
            return tr(
                "не успевает: пропущено \(model.liveStats.skippedPhrases)",
                "falling behind: \(model.liveStats.skippedPhrases) skipped"
            )
        }
        guard let speed = model.liveStats.speedFactor else { return "" }
        let factor = Int(speed.rounded())
        return tr("в \(factor)× быстрее речи", "\(factor)× faster than speech")
    }
}

/// One phrase as a chat bubble: "Me" on the right in the accent colour, the others on the left.
private struct LiveBubble: View {
    let line: LiveLine
    let isNewest: Bool
    let isInRoom: Bool

    private var isMine: Bool { line.isMe && !isInRoom }

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 36) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isInRoom ? tr("В комнате", "In the room") : line.isMe ? tr("Я", "Me") : tr("Собеседники", "Others"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(line.time.clockString)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(line.text)
                    .textSelection(.enabled)
                    .multilineTextAlignment(isMine ? .trailing : .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(tint.opacity(isNewest ? 0.2 : 0.1), in: .rect(cornerRadius: 14))
            }
            .opacity(isNewest ? 1 : 0.78)
            .animation(Motion.smooth, value: isNewest)
            if !isMine { Spacer(minLength: 36) }
        }
    }

    private var tint: Color {
        isInRoom ? .teal : line.isMe ? .accentColor : .orange
    }
}

/// Shown until the first phrase is heard: a breathing waveform instead of a static note.
private struct ListeningPlaceholder: View {
    /// Why nothing can be heard, when the sound check knows (a muted microphone): said here instead of "Listening".
    let warning: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: warning == nil ? "waveform" : "mic.slash")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(warning == nil ? Color.secondary : Color.orange)
                .symbolEffect(.variableColor.iterative.reversing, isActive: warning == nil)
                .contentTransition(.symbolEffect(.replace))
            Text(warning ?? tr(
                "Слушаю… Текст появится через несколько секунд после того, как прозвучит фраза.",
                "Listening… Text appears a few seconds after each phrase is said."
            ))
            .font(.callout)
            .foregroundStyle(warning == nil ? Color.secondary : Color.orange)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// A red dot that pulses while the call is being heard, and rests grey during a pause.
private struct LiveDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.red : Color.secondary)
            .frame(width: 8, height: 8)
            .phaseAnimator([false, true]) { dot, bright in
                dot.opacity(isActive && !bright ? 0.35 : 1)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .animation(Motion.quick, value: isActive)
    }
}

/// A new phrase rises a little, sharpens out of a blur and fades in.
private struct PhraseArrival: ViewModifier {
    let isPending: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPending ? 0 : 1)
            .blur(radius: isPending ? 8 : 0)
            .offset(y: isPending ? 14 : 0)
            .scaleEffect(isPending ? 0.97 : 1, anchor: .bottom)
    }
}

extension AnyTransition {
    static var phraseArrival: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PhraseArrival(isPending: true), identity: PhraseArrival(isPending: false)),
            removal: .opacity
        )
    }
}
