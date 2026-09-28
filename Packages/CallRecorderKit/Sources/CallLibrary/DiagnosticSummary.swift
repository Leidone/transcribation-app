import AudioCapture
import Foundation

/// The readable part of a problem report: which app and Mac, and the library in numbers. It never holds what was
/// said, titles, people's names, keys or server addresses, because the report is meant to be sent to someone.
public enum DiagnosticSummary {
    public struct Machine: Equatable, Sendable {
        public let appVersion: String
        public let build: String
        public let system: String
        public let model: String
        public let chip: String
        public let memoryBytes: UInt64
        public let freeDiskBytes: Int64?

        public init(
            appVersion: String, build: String, system: String, model: String, chip: String,
            memoryBytes: UInt64, freeDiskBytes: Int64?
        ) {
            self.appVersion = appVersion
            self.build = build
            self.system = system
            self.model = model
            self.chip = chip
            self.memoryBytes = memoryBytes
            self.freeDiskBytes = freeDiskBytes
        }
    }

    private static let gibibyte: Double = 1_073_741_824

    public static func text(
        machine: Machine, recordings: [RecordingItem], settings: [(String, String)], recentProblems: [String],
        generatedAt: Date
    ) -> String {
        let sections = [
            header(machine, generatedAt: generatedAt),
            library(recordings.filter { !$0.isSample }),
            ["Настройки"] + settings.map { "\($0.0): \($0.1)" },
            ["Последние ошибки"] + (recentProblems.isEmpty ? ["нет"] : recentProblems.map { "- \($0)" }),
        ]
        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    }

    private static func header(_ machine: Machine, generatedAt: Date) -> [String] {
        let memory = Int((Double(machine.memoryBytes) / gibibyte).rounded())
        let free = machine.freeDiskBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [
            "Отчёт о проблеме · \(generatedAt.formatted(.iso8601))",
            "Transcribation \(machine.appVersion) (\(machine.build))",
            "macOS: \(machine.system)",
            "Mac: \(machine.model) · \(machine.chip) · \(memory) ГБ",
            "Свободно на диске: \(free ?? "неизвестно")",
        ]
    }

    private static func library(_ own: [RecordingItem]) -> [String] {
        let transcribed = own.filter { !$0.transcript.isEmpty }.count
        let analyzed = own.filter { $0.analysis != nil }.count
        let imported = own.filter { if case .single? = $0.audio { true } else { false } }.count
        let compressed = own.filter(isCompressed).count
        let hours = own.map(\.duration).reduce(0, +) / 3_600
        return [
            "Библиотека",
            "Записей: \(own.count) (расшифровано \(transcribed), с итогами \(analyzed), импортировано \(imported))",
            "Сжатых: \(compressed) из \(own.count - imported)",
            "Всего звука: \(hours.formatted(.number.precision(.fractionLength(1)))) ч",
        ]
    }

    private static func isCompressed(_ recording: RecordingItem) -> Bool {
        guard case .separated(let app, _, _)? = recording.audio else { return false }
        return app.pathExtension.lowercased() == "m4a"
    }
}
