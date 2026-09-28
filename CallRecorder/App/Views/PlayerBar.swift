import CallLibrary
import Localization
import SwiftUI

/// Play, pause, scrub and change speed; the transcript highlights the line being heard.
struct PlayerBar: View {
    @Bindable var player: PlaybackController
    @State private var scrubbing: TimeInterval?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                player.skip(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .buttonStyle(.plain)
            .help(tr("Назад на 15 секунд", "Back 15 seconds"))

            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(player.isPlaying ? tr("Пауза (пробел)", "Pause (Space)") : tr("Слушать (пробел)", "Play (Space)"))

            Button {
                player.skip(by: 15)
            } label: {
                Image(systemName: "goforward.15")
            }
            .buttonStyle(.plain)
            .help(tr("Вперёд на 15 секунд", "Forward 15 seconds"))

            Text((scrubbing ?? player.currentTime).clockString)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            Slider(
                value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                in: 0...max(player.duration, 1)
            ) { editing in
                if !editing, let target = scrubbing {
                    player.seek(to: target)
                    scrubbing = nil
                }
            }
            .controlSize(.small)

            Text(player.duration.clockString)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Menu {
                ForEach(PlaybackController.rates, id: \.self) { rate in
                    Button {
                        player.setRate(rate)
                    } label: {
                        if rate == player.rate { Label(rateTitle(rate), systemImage: "checkmark") } else { Text(rateTitle(rate)) }
                    }
                }
            } label: {
                Text(rateTitle(player.rate))
                    .monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .help(tr("Скорость", "Speed"))
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .disabled(!player.isReady)
        .overlay(alignment: .bottomLeading) {
            if let error = player.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).offset(y: 22)
            }
        }
    }

    private func rateTitle(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate.formatted(.number.precision(.fractionLength(2))))×"
    }
}
