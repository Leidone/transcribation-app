import AppKit
import CallLibrary
import Localization
import UniformTypeIdentifiers

/// Getting a recording's result out of the app: the clipboard, a Markdown or PDF file, Reminders.
extension AppModel {
    func copySummary(of recording: RecordingItem) {
        guard let analysis = recording.analysis else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "# \(recording.title)\n\n" + RecordingExport.summaryMarkdown(of: analysis, displayName: recording.displayName),
            forType: .string
        )
        announce(tr("Итоги скопированы", "Summary copied"))
    }

    /// Opens a letter to the meeting's people in the mail app, ready to be read and sent by the person. Without a
    /// mail app the text is copied instead.
    func composeFollowUp(for recording: RecordingItem) {
        guard let draft = FollowUpEmail.draft(for: recording) else { return }
        guard let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: [draft.body]) else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(draft.subject + "\n\n" + draft.body, forType: .string)
            announce(tr("Почта не настроена — текст письма скопирован", "Mail is not set up — the letter was copied"))
            return
        }
        mail.recipients = draft.recipients
        mail.subject = draft.subject
        mail.perform(withItems: [draft.body])
    }

    /// Keeps the meeting's note in the chosen notes folder up to date; nothing when no folder is chosen.
    func writeNote(of recording: RecordingItem) {
        guard let path = preferences.notesFolder, recording.analysis != nil else { return }
        do {
            try AutoExport.write(recording, to: URL(fileURLWithPath: path), includesTranscript: preferences.notesIncludeTranscript)
        } catch {
            report(error, doing: tr("Не удалось сохранить заметку в папку", "Could not save the note to the folder"))
        }
    }

    /// Writes the notes of every summarised meeting at once, for the ones made before the folder was chosen.
    func writeAllNotes() {
        let summarised = realRecordings.filter { $0.analysis != nil }
        summarised.forEach(writeNote(of:))
        announce(tr("Сохранено заметок: \(summarised.count)", "Notes saved: \(summarised.count)"))
    }

    /// Asks for the notes folder.
    func chooseNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Выбрать", "Choose")
        panel.message = tr("Сюда будут сохраняться итоги встреч в Markdown", "Meeting summaries will be saved here as Markdown")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.notesFolder = url.path
    }

    func saveMarkdown(of recording: RecordingItem, includesTranscript: Bool) {
        let text = RecordingExport.markdown(of: recording, options: .init(includesTranscript: includesTranscript))
        save(Data(text.utf8), as: RecordingExport.fileName(of: recording, extension: "md"), type: UTType(filenameExtension: "md") ?? .plainText)
    }

    func savePDF(of recording: RecordingItem, includesTranscript: Bool) {
        do {
            let data = try PDFRenderer.pdf(fromHTML: RecordingExport.html(of: recording, options: .init(includesTranscript: includesTranscript)))
            save(data, as: RecordingExport.fileName(of: recording, extension: "pdf"), type: .pdf)
        } catch {
            report(error, doing: tr("Не удалось создать PDF", "Could not create the PDF"))
        }
    }

    func addToReminders(_ tasks: [TaskItem], from recording: RecordingItem) async {
        do {
            let count = try await RemindersExporter().add(tasks, from: recording)
            announce(count == 0 ? tr("Все задачи уже выполнены", "All tasks are already done") : tr("Добавлено в Напоминания: \(count)", "Added to Reminders: \(count)"))
        } catch {
            report(error, doing: tr("Не удалось добавить в Напоминания", "Could not add to Reminders"))
        }
    }

    private func save(_ data: Data, as name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            announce(tr("Сохранено: ", "Saved: ") + url.lastPathComponent)
        } catch {
            report(error, doing: tr("Не удалось сохранить файл", "Could not save the file"))
        }
    }
}
