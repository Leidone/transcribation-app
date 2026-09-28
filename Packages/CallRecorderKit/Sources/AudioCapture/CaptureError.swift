import Foundation
import Localization

public enum CaptureError: LocalizedError, Equatable {
    case screenRecordingDenied
    case sourceUnavailable(bundleID: String)
    case noDisplay
    case alreadyRecording
    case notRecording
    case noAudioReceived(stream: String)
    case streamStopped(String)

    public var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            tr(
                "Приложению не разрешена запись экрана и системного звука. Разрешите её в Системных настройках → Конфиденциальность и безопасность.",
                "Screen & System Audio Recording is not allowed for this app. Enable it in System Settings → Privacy & Security."
            )
        case .sourceUnavailable(let bundleID):
            tr("\(bundleID) не запущено, поэтому его звук записать нельзя.", "\(bundleID) is not running, so its audio cannot be recorded.")
        case .noDisplay:
            tr("Не найден дисплей, к которому можно подключить запись звука.", "No display was found to attach the audio capture to.")
        case .alreadyRecording:
            tr("Запись уже идёт.", "A recording is already in progress.")
        case .notRecording:
            tr("Сейчас ничего не записывается.", "There is no recording in progress.")
        case .noAudioReceived(let stream):
            stream == "app"
                ? tr("От приложения звонка не пришло ни звука.", "No sound arrived from the call app.")
                : tr("С микрофона не пришло ни звука.", "No sound arrived from the microphone.")
        case .streamStopped(let detail):
            tr("Запись неожиданно остановилась: \(detail)", "Capture stopped unexpectedly: \(detail)")
        }
    }
}
