import AudioCapture
import CodexClient
import Foundation
import Localization
import Transcription

extension TimeInterval {
    /// `m:ss`, or `h:mm:ss` from one hour up.
    public var clockString: String {
        let total = Int(Swift.max(0, rounded(.down)))
        let (hours, minutes, seconds) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

public struct TranscriptLine: Identifiable, Equatable, Sendable {
    /// The utterance's position in `transcript.json`, so an edit can be written back to the right place.
    public let id: Int
    public let time: TimeInterval
    public let speaker: String
    public let isMe: Bool
    public let text: String
    /// When the phrase ends; `nil` where it is not known (the built-in samples).
    public let end: TimeInterval?

    public init(id: Int, time: TimeInterval, speaker: String, isMe: Bool, text: String, end: TimeInterval? = nil) {
        self.id = id
        self.time = time
        self.speaker = speaker
        self.isMe = isMe
        self.text = text
        self.end = end
    }
}

public struct TaskItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let owner: String?
    public let due: String?
    public let quote: String?
    public let timestamp: TimeInterval?
    public let isDone: Bool

    public init(
        id: UUID, title: String, owner: String?, due: String?, quote: String?, timestamp: TimeInterval?, isDone: Bool
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.due = due
        self.quote = quote
        self.timestamp = timestamp
        self.isDone = isDone
    }

    public func togglingDone() -> TaskItem {
        TaskItem(id: id, title: title, owner: owner, due: due, quote: quote, timestamp: timestamp, isDone: !isDone)
    }
}

public struct AnalysisResult: Equatable, Sendable {
    public let summary: String
    public let decisions: [String]
    public let tasks: [TaskItem]
    /// `nil` for the built-in samples.
    public let createdAt: Date?
    /// The kind of meeting the summary was written for; `nil` means the general template.
    public let template: AnalysisTemplate?

    public init(
        summary: String, decisions: [String], tasks: [TaskItem], createdAt: Date? = nil,
        template: AnalysisTemplate? = nil
    ) {
        self.summary = summary
        self.decisions = decisions
        self.tasks = tasks
        self.createdAt = createdAt
        self.template = template
    }

    public init(stored: StoredAnalysis) {
        self.init(
            summary: stored.summary,
            decisions: stored.decisions,
            tasks: stored.tasks.map {
                TaskItem(
                    id: $0.id, title: $0.title, owner: $0.owner, due: $0.due, quote: $0.quote,
                    timestamp: $0.timestampSeconds, isDone: $0.isDone
                )
            },
            createdAt: stored.createdAt,
            template: stored.template.flatMap(AnalysisTemplate.init(rawValue:))
        )
    }

    /// The on-disk form.
    public var stored: StoredAnalysis {
        StoredAnalysis(
            createdAt: createdAt ?? Date(),
            summary: summary,
            decisions: decisions,
            tasks: tasks.map {
                StoredTask(
                    id: $0.id, title: $0.title, owner: $0.owner, due: $0.due, quote: $0.quote,
                    timestampSeconds: $0.timestamp, isDone: $0.isDone
                )
            },
            template: template?.rawValue
        )
    }

    public func togglingTask(_ taskID: TaskItem.ID) -> AnalysisResult {
        AnalysisResult(
            summary: summary, decisions: decisions,
            tasks: tasks.map { $0.id == taskID ? $0.togglingDone() : $0 },
            createdAt: createdAt, template: template
        )
    }
}

/// How long the local transcription of a recording took, to show real speed on the person's own Mac or iPhone.
public struct ProcessingStats: Equatable, Sendable {
    public let audioSeconds: TimeInterval
    public let processingSeconds: TimeInterval

    public init(audioSeconds: TimeInterval, processingSeconds: TimeInterval) {
        self.audioSeconds = audioSeconds
        self.processingSeconds = processingSeconds
    }

    /// How many times faster than real time; `nil` when the processing time was not measurable.
    public var speedFactor: Double? {
        processingSeconds > 0 ? audioSeconds / processingSeconds : nil
    }
}

public struct RecordingItem: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Audio is on disk and has not been transcribed yet.
        case awaitingProcessing
        /// The transcript exists; the summary and tasks come from the analysis step.
        case transcribed
        case ready
    }

    public let id: UUID
    public let title: String
    public let appName: String
    public let appBundleID: String?
    public let startedAt: Date
    public let duration: TimeInterval
    public let status: Status
    public let directory: URL?
    /// Built-in illustration of a finished result, not a real call.
    public let isSample: Bool
    public let transcript: [TranscriptLine]
    public let analysis: AnalysisResult?
    /// Where the sound is kept; `nil` for the built-in samples.
    public let audio: RecordingAudio?
    /// Names the person gave to the voices; the transcript keeps the original labels.
    public let speakerNames: SpeakerNames
    /// When the person last corrected the transcript by hand; `nil` if it is as recognised.
    public let transcriptEditedAt: Date?
    public let processingStats: ProcessingStats?
    /// The calendar event it was recorded during, when the person lets the app read the calendar.
    public let meeting: MeetingInfo?
    /// Moments marked important during the call, in seconds on the transcript's clock, sorted.
    public let marks: [TimeInterval]
    /// The person's own labels (`tags.json`).
    public let tags: [String]

    public init(
        id: UUID, title: String, appName: String, appBundleID: String?, startedAt: Date, duration: TimeInterval,
        status: Status, directory: URL?, isSample: Bool, transcript: [TranscriptLine], analysis: AnalysisResult?,
        audio: RecordingAudio? = nil, speakerNames: SpeakerNames = .empty, transcriptEditedAt: Date? = nil,
        processingStats: ProcessingStats? = nil, meeting: MeetingInfo? = nil, marks: [TimeInterval] = [],
        tags: [String] = []
    ) {
        self.tags = tags
        self.meeting = meeting
        self.marks = marks
        self.id = id
        self.title = title
        self.appName = appName
        self.appBundleID = appBundleID
        self.startedAt = startedAt
        self.duration = duration
        self.status = status
        self.directory = directory
        self.isSample = isSample
        self.transcript = transcript
        self.analysis = analysis
        self.audio = audio
        self.speakerNames = speakerNames
        self.transcriptEditedAt = transcriptEditedAt
        self.processingStats = processingStats
    }

    public init(
        stored: StoredRecording,
        transcript: StoredTranscript? = nil,
        analysis storedAnalysis: StoredAnalysis? = nil,
        speakerNames: SpeakerNames = .empty,
        meeting: MeetingInfo? = nil,
        marks: ImportantMarks = .empty,
        tags: [String] = []
    ) {
        self.init(
            id: stored.id,
            title: meeting?.title ?? stored.title
                ?? tr("Запись — \(stored.appName ?? "аудио")", "Recording — \(stored.appName ?? "audio")"),
            appName: stored.appName ?? tr("Импорт", "Import"),
            appBundleID: stored.appBundleID,
            startedAt: stored.startedAt,
            duration: stored.duration,
            status: storedAnalysis != nil ? .ready : (transcript == nil ? .awaitingProcessing : .transcribed),
            directory: stored.directory,
            isSample: false,
            transcript: (transcript?.utterances ?? []).enumerated().map { index, utterance in
                TranscriptLine(
                    id: index, time: utterance.start, speaker: utterance.speaker,
                    isMe: utterance.speaker == TranscriptionPipeline.myName, text: utterance.text, end: utterance.end
                )
            },
            analysis: storedAnalysis.map(AnalysisResult.init(stored:)),
            audio: stored.audio,
            speakerNames: speakerNames,
            transcriptEditedAt: transcript?.editedAt,
            processingStats: transcript?.processingSeconds.map {
                ProcessingStats(audioSeconds: stored.duration, processingSeconds: $0)
            },
            meeting: meeting,
            marks: marks.times,
            tags: tags
        )
    }

    /// Every stored field the same except the ones given, so each change reads as one line.
    func with(
        transcript: [TranscriptLine]? = nil, analysis: AnalysisResult?? = nil, speakerNames: SpeakerNames? = nil,
        transcriptEditedAt: Date?? = nil, meeting: MeetingInfo?? = nil, marks: [TimeInterval]? = nil,
        tags: [String]? = nil
    ) -> RecordingItem {
        let meeting = meeting ?? self.meeting
        return RecordingItem(
            id: id, title: meeting?.title ?? title, appName: appName, appBundleID: appBundleID, startedAt: startedAt,
            duration: duration, status: status, directory: directory, isSample: isSample,
            transcript: transcript ?? self.transcript, analysis: analysis ?? self.analysis, audio: audio,
            speakerNames: speakerNames ?? self.speakerNames,
            transcriptEditedAt: transcriptEditedAt ?? self.transcriptEditedAt, processingStats: processingStats,
            meeting: meeting, marks: marks ?? self.marks, tags: tags ?? self.tags
        )
    }

    /// A copy with one task's done flag flipped; the original is left untouched.
    public func togglingTask(_ taskID: TaskItem.ID) -> RecordingItem {
        guard let analysis else { return self }
        return with(analysis: .some(analysis.togglingTask(taskID)))
    }

    /// A copy with other labels; the original is left untouched.
    public func taggedWith(_ tags: [String]) -> RecordingItem {
        with(tags: tags)
    }

    /// A copy with one voice renamed; the original is left untouched.
    public func renamingSpeaker(_ label: String, to newName: String) -> RecordingItem {
        with(speakerNames: speakerNames.renaming(label, to: newName))
    }

    /// A copy with the text of one line replaced (surrounding spaces trimmed). An unknown line, an unchanged
    /// text or an empty one changes nothing.
    public func editingLine(_ lineID: TranscriptLine.ID, to newText: String, at date: Date = Date()) -> RecordingItem {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let current = transcript.first(where: { $0.id == lineID }), current.text != trimmed else {
            return self
        }
        let lines = transcript.map {
            $0.id == lineID
                ? TranscriptLine(id: $0.id, time: $0.time, speaker: $0.speaker, isMe: $0.isMe, text: trimmed, end: $0.end)
                : $0
        }
        return with(transcript: lines, transcriptEditedAt: .some(date))
    }
}

extension RecordingItem {
    /// The chosen name of a voice, or its original label.
    public func displayName(_ label: String) -> String {
        speakerNames.displayName(for: label)
    }

    /// The transcript in the compact form sent to the model, with the names the person gave.
    public var transcriptText: String {
        CompactTranscript.make(transcript.map {
            CompactLine(time: $0.time, speaker: displayName($0.speaker), text: $0.text)
        })
    }

    /// What is sent for a summary: the meeting's title and who was invited, when known, and the moments marked
    /// important, then the transcript. The names help the model tell who promised what; the marks say what the
    /// person cared about most.
    public var analysisText: String {
        var header: [String] = []
        if let meeting {
            header.append("Встреча: \(meeting.title)")
            if !meeting.attendees.isEmpty { header.append("Приглашены: \(meeting.attendees.joined(separator: ", "))") }
        }
        if !marks.isEmpty {
            let moments = marks.map { CompactTranscript.clock($0) }.joined(separator: ", ")
            header.append("Marked important during the call (give what was said there weight in the summary): \(moments)")
        }
        guard !header.isEmpty else { return transcriptText }
        return header.joined(separator: "\n") + "\n\n" + transcriptText
    }

    /// How far back from a mark the words it is about may have started: people press after hearing something.
    public static let markLead: TimeInterval = 10

    /// The transcript lines a mark points at: the line being said at the mark, and those that began up to
    /// `markLead` seconds before it.
    public func lineIDs(markedAt mark: TimeInterval) -> Set<TranscriptLine.ID> {
        var ids = Set(transcript.filter { $0.time <= mark && $0.time >= mark - Self.markLead }.map(\.id))
        if let current = line(at: mark) { ids.insert(current.id) }
        return ids
    }

    /// Every line some mark points at, to highlight in the transcript.
    public var importantLineIDs: Set<TranscriptLine.ID> {
        marks.reduce(into: Set<TranscriptLine.ID>()) { ids, mark in ids.formUnion(lineIDs(markedAt: mark)) }
    }

    /// A copy with a mark on `lineID`, or without the marks pointing at it if it has some.
    public func togglingMark(on lineID: TranscriptLine.ID) -> RecordingItem {
        guard let line = transcript.first(where: { $0.id == lineID }) else { return self }
        let pointing = marks.filter { lineIDs(markedAt: $0).contains(lineID) }
        guard pointing.isEmpty else { return with(marks: marks.filter { !pointing.contains($0) }) }
        return with(marks: ImportantMarks(times: marks).adding(line.time).times)
    }

    /// Each voice once, in order of first appearance.
    public var speakers: [(label: String, isMe: Bool)] {
        var seen: Set<String> = []
        return transcript.compactMap { line in
            seen.insert(line.speaker).inserted ? (line.speaker, line.isMe) : nil
        }
    }

    /// The summary was written before the latest hand correction of the transcript, so it may be out of date.
    public var isAnalysisOutdated: Bool {
        guard let edited = transcriptEditedAt, let created = analysis?.createdAt else { return false }
        return edited > created
    }

    /// The line being spoken at `time`: the last one that started at or before it.
    public func line(at time: TimeInterval) -> TranscriptLine? {
        transcript.last { $0.time <= time }
    }
}
