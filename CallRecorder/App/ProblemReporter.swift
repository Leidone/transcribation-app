import AppKit
import AudioCapture
import CallLibrary
import Localization
import Observation
import os
import UniformTypeIdentifiers

private let reportLog = Logger(subsystem: "app.callrecorder.dev", category: "problem-report")

/// Puts what is needed to understand a problem into one zip file the person can send: a summary (nothing that
/// was said, no titles, names or keys), the app's own log for the last day and its crash reports of the last week.
@Observable
@MainActor
final class ProblemReporter {
    private(set) var isCollecting = false

    private let model: AppModel
    private let settings: AISettings
    private let preferences: AppPreferences

    init(model: AppModel, settings: AISettings, preferences: AppPreferences) {
        self.model = model
        self.settings = settings
        self.preferences = preferences
    }

    enum ReportError: LocalizedError {
        case toolFailed(String, Int32)

        var errorDescription: String? {
            switch self {
            case .toolFailed(let tool, let status):
                tr("Команда \(tool) завершилась с кодом \(status).", "The \(tool) command ended with code \(status).")
            }
        }
    }

    /// Asks where to save the report, then collects it in the background and shows it in Finder.
    func collect() {
        guard !isCollecting, let destination = askWhereToSave() else { return }
        isCollecting = true
        let summary = DiagnosticSummary.text(
            machine: Self.machine(), recordings: model.recordings, settings: settingLines(),
            recentProblems: model.recentProblems, generatedAt: .now
        )
        Task {
            defer { isCollecting = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Self.writeReport(summary: summary, to: destination)
                }.value
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                model.announce(tr("Отчёт сохранён — отправьте этот файл разработчику", "Report saved — send this file to the developer"))
            } catch {
                reportLog.error("report failed: \(error.localizedDescription, privacy: .public)")
                model.report(error, doing: tr("Не удалось собрать отчёт", "Could not collect the report"))
            }
        }
    }

    private func askWhereToSave() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = URL.desktopDirectory
        panel.nameFieldStringValue = tr("Transcribation — отчёт", "Transcribation — report")
            + " \(Date().formatted(.iso8601.year().month().day())).zip"
        panel.message = tr("Журнал приложения и сведения о Mac. Записей, текстов разговоров и ключей в нём нет.", "The app's log and details about the Mac. No recordings, conversation text or keys.")
        panel.prompt = tr("Сохранить отчёт", "Save Report")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// In Russian whatever the interface language: the report is read by the developer.
    private func settingLines() -> [(String, String)] {
        let yesNo = { (value: Bool) in value ? Self.forDeveloper("да") : Self.forDeveloper("нет") }
        return [
            (Self.forDeveloper("ИИ"), settings.provider.kind.rawValue),
            (Self.forDeveloper("Модель"), settings.selectedModel ?? Self.forDeveloper("по умолчанию")),
            (Self.forDeveloper("Тип встречи"), settings.defaultTemplate.title),
            (Self.forDeveloper("Предлагать запись при звонке"), yesNo(preferences.suggestsRecordingOnCalls)),
            (Self.forDeveloper("Сочетание клавиш"), preferences.usesGlobalHotKey ? preferences.recordShortcut.display : Self.forDeveloper("выключено")),
            (Self.forDeveloper("Останавливать запись после звонка"), yesNo(preferences.stopsWhenCallEnds)),
            (Self.forDeveloper("Сжимать звук"), yesNo(preferences.compressesAudio)),
            (Self.forDeveloper("Идёт запись"), yesNo(model.isRecording)),
        ]
    }

    /// Marks a text that stays Russian in any interface language, because only the developer reads it.
    private static func forDeveloper(_ text: String) -> String {
        text
    }

    // MARK: Collecting (off the main actor)

    private nonisolated static func writeReport(summary: String, to destination: URL) throws {
        let workspace = FileManager.default.temporaryDirectory.appending(path: "report-\(UUID().uuidString)")
        let folder = workspace.appending(path: destination.deletingPathExtension().lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        try summary.write(to: folder.appending(path: "summary.txt"), atomically: true, encoding: .utf8)
        try run("/usr/bin/log", [
            "show", "--last", "1d", "--style", "compact", "--predicate",
            "subsystem == \"app.callrecorder.dev\" OR (process == \"Transcribation\" AND (messageType == error OR messageType == fault))",
        ], output: folder.appending(path: "log.txt"))
        copyCrashReports(into: folder.appending(path: "crashes"))

        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        // --norsrc: no "._" metadata files, which only confuse whoever opens the archive on another system.
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--keepParent", folder.path, destination.path])
    }

    /// The app's crash reports from the last week; none is fine.
    private nonisolated static func copyCrashReports(into folder: URL) {
        let reports = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3_600)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: reports, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let recent = files.filter { file in
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return file.lastPathComponent.hasPrefix("Transcribation") && (modified ?? .distantPast) > weekAgo
        }
        guard !recent.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in recent { try FileManager.default.copyItem(at: file, to: folder.appending(path: file.lastPathComponent)) }
        } catch {
            reportLog.error("cannot copy crash reports: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String], output: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        var handle: FileHandle?
        if let output {
            FileManager.default.createFile(atPath: output.path, contents: nil)
            handle = try FileHandle(forWritingTo: output)
            process.standardOutput = handle
        }
        defer { try? handle?.close() }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ReportError.toolFailed(tool, process.terminationStatus) }
    }

    // MARK: The Mac

    private static func machine() -> DiagnosticSummary.Machine {
        let info = Bundle.main.infoDictionary
        return DiagnosticSummary.Machine(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            model: systemValue("hw.model"),
            chip: systemValue("machdep.cpu.brand_string"),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            freeDiskBytes: DiskBudget.availableBytes(at: AppModel.recordingsDirectory)
        )
    }

    private static func systemValue(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "?" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
