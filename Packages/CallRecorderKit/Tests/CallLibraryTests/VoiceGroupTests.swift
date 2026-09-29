import Foundation
import Testing
import AudioCapture
@testable import CallLibrary

struct VoiceGroupTests {
    private func recording(names: [String: String] = [:]) -> RecordingItem {
        let lines = [
            TranscriptLine(id: 0, time: 0, speaker: "Я", isMe: true, text: "a", end: 2),
            TranscriptLine(id: 1, time: 2, speaker: "Собеседник 1", isMe: false, text: "b", end: 4),
            TranscriptLine(id: 2, time: 4, speaker: "Собеседник 2", isMe: false, text: "c", end: 6),
            TranscriptLine(id: 3, time: 6, speaker: "Собеседник 5", isMe: false, text: "d", end: 8),
        ]
        return RecordingItem(
            id: UUID(), title: "Звонок", appName: "Zoom", appBundleID: nil, startedAt: Date(), duration: 8,
            status: .transcribed, directory: nil, isSample: false, transcript: lines, analysis: nil,
            speakerNames: SpeakerNames(names: names)
        )
    }

    @Test("every voice is its own person until the person names two of them the same")
    func oneGroupPerVoice() {
        let voices = recording().voices

        #expect(voices.map(\.name) == ["Я", "Собеседник 1", "Собеседник 2", "Собеседник 5"])
        #expect(voices.map(\.labels) == [["Я"], ["Собеседник 1"], ["Собеседник 2"], ["Собеседник 5"]])
        #expect(voices.first?.isMe == true)
    }

    @Test("voices given the same name are one person, in the order they were first heard")
    func sameNameMerges() {
        let voices = recording(names: ["Собеседник 1": "Митрофанов", "Собеседник 5": "Митрофанов"]).voices

        #expect(voices.map(\.name) == ["Я", "Митрофанов", "Собеседник 2"])
        #expect(voices[1].labels == ["Собеседник 1", "Собеседник 5"])
    }

    @Test("renaming a person renames every voice of it; an empty name gives them their own labels back")
    func renamingAGroup() {
        let merged = recording(names: ["Собеседник 1": "Митрофанов", "Собеседник 5": "Митрофанов"])
        let group = merged.voices[1]

        let renamed = merged.renamingVoices(group.labels, to: "Иван Митрофанов")
        let reset = renamed.renamingVoices(group.labels, to: "")

        #expect(renamed.voices.map(\.name) == ["Я", "Иван Митрофанов", "Собеседник 2"])
        #expect(reset.voices.map(\.name) == ["Я", "Собеседник 1", "Собеседник 2", "Собеседник 5"])
    }
}
