import CallLibrary
import ReplayKit
import SwiftUI

/// Starts a recording via ReplayKit. Unlike the macOS recorder, iOS gives no way to start or stop a broadcast
/// from inside the app itself — only the system picker button below can, and only the person can tap it.
struct RecordView: View {
    @State private var isRecording = false

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 28) {
                Spacer()

                RecordingOrb(isRecording: isRecording)
                    .staggeredAppear(0)

                GradientTitle(text: isRecording ? "Идёт запись" : "Готов к записи", size: 30)
                    .staggeredAppear(1)

                BroadcastPickerRepresentable()
                    .frame(width: 64, height: 64)
                    .glassEffect(.regular.tint(isRecording ? .red : .accentColor).interactive(), in: .circle)
                    .staggeredAppear(2)

                VStack(spacing: 8) {
                    Text("iOS записывает звук всего экрана, а не одного приложения — так работает система вызовов, для звонка откройте нужное приложение и говорите на громкой связи или в наушниках.")
                    Text("Остановить запись: смахните вниз для Пункта управления и нажмите на красный индикатор записи, либо на «Остановить» в статус-баре.")
                    Text("Записывать разговор можно только с согласия собеседников — предупредите их в начале звонка.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .staggeredAppear(3)

                Spacer()
            }
            .padding()
            .animation(Motion.smooth, value: isRecording)
        }
        .task {
            while !Task.isCancelled {
                isRecording = RPScreenRecorder.shared().isRecording
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct RecordingOrb: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            if isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.55), lineWidth: 2)
                    .frame(width: 108, height: 108)
                    .phaseAnimator([false, true]) { view, expanded in
                        view.scaleEffect(expanded ? 1.6 : 1).opacity(expanded ? 0 : 1)
                    } animation: { _ in
                        .easeOut(duration: 1.8)
                    }
            }
            Image(systemName: isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative.reversing, isActive: isRecording)
                .frame(width: 108, height: 108)
                .glassEffect(.regular.tint(isRecording ? .red : .accentColor), in: .circle)
        }
        .frame(width: 108, height: 108)
    }
}
