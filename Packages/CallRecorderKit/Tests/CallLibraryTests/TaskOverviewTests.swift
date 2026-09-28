import AudioCapture
import Foundation
import Testing
@testable import CallLibrary

private func task(_ title: String, owner: String? = nil, done: Bool = false) -> TaskItem {
    TaskItem(id: UUID(), title: title, owner: owner, due: nil, quote: nil, timestamp: 12, isDone: done)
}

private func meeting(_ title: String, daysAgo: Double, tasks: [TaskItem], names: [String: String] = [:]) -> RecordingItem {
    RecordingItem(
        id: UUID(), title: title, appName: "Zoom", appBundleID: nil,
        startedAt: Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86_400), duration: 60, status: .ready,
        directory: nil, isSample: false, transcript: [],
        analysis: AnalysisResult(summary: "", decisions: [], tasks: tasks), speakerNames: SpeakerNames(names: names)
    )
}

@Test func openTasksAreGroupedByMeetingNewestFirst() {
    let old = meeting("Понедельник", daysAgo: 3, tasks: [task("Отчёт"), task("Сделано", done: true)])
    let new = meeting("Среда", daysAgo: 1, tasks: [task("Созвон с клиентом")])
    let empty = meeting("Без задач", daysAgo: 2, tasks: [task("Всё сделано", done: true)])

    let groups = TaskOverview.groups(in: [old, empty, new], filter: .open)
    #expect(groups.map(\.recording.title) == ["Среда", "Понедельник"])
    #expect(groups[1].tasks.map(\.title) == ["Отчёт"])
}

@Test func allTasksIncludeTheDoneOnes() {
    let groups = TaskOverview.groups(
        in: [meeting("Понедельник", daysAgo: 3, tasks: [task("Отчёт"), task("Сделано", done: true)])], filter: .all
    )
    #expect(groups.first?.tasks.count == 2)
}

@Test func myTasksFollowTheNameGivenToMyVoice() {
    let named = meeting("Планёрка", daysAgo: 1, tasks: [task("Моё", owner: "Саша"), task("Чужое", owner: "Анна")], names: ["Я": "Саша"])
    let plain = meeting("Созвон", daysAgo: 2, tasks: [task("Тоже моё", owner: "Я"), task("Ничьё")])

    let groups = TaskOverview.groups(in: [named, plain], filter: .open, mineOnly: true)
    #expect(groups.flatMap(\.tasks).map(\.title) == ["Моё", "Тоже моё"])
}

@Test func theBadgeCountsOpenTasksEverywhere() {
    let recordings = [
        meeting("А", daysAgo: 1, tasks: [task("1"), task("2", done: true)]),
        meeting("Б", daysAgo: 2, tasks: [task("3"), task("4")]),
    ]
    #expect(TaskOverview.openCount(in: recordings) == 3)
}
