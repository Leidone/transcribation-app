import AudioCapture
import Foundation
import Transcription

/// The changes both apps make to a recording on disk, in one place, so the Mac and the iPhone keep the files
/// exactly the same way.
public enum LibraryStore {
    /// Saves a fresh transcription next to the audio and names every voice the voice book recognises. Returns the
    /// names given, keyed by transcript label.
    @discardableResult
    public static func saveTranscription(
        _ result: TranscriptionResult, in recordingDirectory: URL, library libraryDirectory: URL
    ) throws -> [String: String] {
        try TranscriptStore.save(result.transcript, in: recordingDirectory)
        try VoiceprintStore.save(result.voiceprints, in: recordingDirectory)

        let recognised = try VoiceBookStore.load(from: libraryDirectory).names(for: result.voiceprints.voices)
        guard !recognised.isEmpty else { return [:] }
        let current = try SpeakerNamesStore.load(from: recordingDirectory)
        // A name the person already gave (a transcription run again) is never overwritten by a guess.
        let names = recognised.reduce(current) { names, pair in
            names.names[pair.key] == nil ? names.renaming(pair.key, to: pair.value) : names
        }
        try SpeakerNamesStore.save(names, in: recordingDirectory)
        return recognised
    }

    /// Fixes the person's own words throughout `transcript.json`. Returns whether anything changed; a changed
    /// transcript counts as corrected by hand, so an existing summary is flagged as possibly out of date.
    @discardableResult
    public static func applyVocabulary(_ vocabulary: Vocabulary, in recordingDirectory: URL, at date: Date = Date()) throws -> Bool {
        guard !vocabulary.rules.isEmpty, let transcript = try TranscriptStore.load(from: recordingDirectory) else { return false }
        var fixed = transcript
        for (index, utterance) in transcript.utterances.enumerated() {
            let text = vocabulary.apply(to: utterance.text)
            if text != utterance.text { fixed = fixed.replacingText(at: index, with: text, editedAt: date) }
        }
        guard fixed != transcript else { return false }
        try TranscriptStore.save(fixed, in: recordingDirectory)
        return true
    }

    /// Writes a corrected line into `transcript.json`; the timing and the speaker stay as recognised.
    public static func saveEdit(
        lineID: Int, text: String, in recordingDirectory: URL, at date: Date = Date()
    ) throws {
        guard let transcript = try TranscriptStore.load(from: recordingDirectory) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try TranscriptStore.save(transcript.replacingText(at: lineID, with: trimmed, editedAt: date), in: recordingDirectory)
    }

    /// Remembers the voice behind `label` under `name`, when the recording has a voiceprint for it. Returns the
    /// updated book, or `nil` when there was nothing to remember (no voiceprint, or the name was taken back).
    @discardableResult
    public static func rememberVoice(
        _ label: String, as name: String, from recordingDirectory: URL, library libraryDirectory: URL
    ) throws -> VoiceBook? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != label,
              let embedding = try VoiceprintStore.load(from: recordingDirectory).voices[label]
        else { return nil }
        let book = try VoiceBookStore.load(from: libraryDirectory).remembering(trimmed, embedding: embedding)
        try VoiceBookStore.save(book, in: libraryDirectory)
        return book
    }

    public static func forgetVoice(_ profileID: VoiceProfile.ID, library libraryDirectory: URL) throws -> VoiceBook {
        let book = try VoiceBookStore.load(from: libraryDirectory).forgetting(profileID)
        try VoiceBookStore.save(book, in: libraryDirectory)
        return book
    }
}
