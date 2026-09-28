import Foundation
import Testing
@testable import AudioCapture

@Test func marksStaySortedAndCloseOnesMerge() {
    let marks = ImportantMarks.empty.adding(90).adding(30).adding(31.5).adding(-4)
    #expect(marks.times == [0, 30, 90])
}

@Test func aMarkCanBeTakenBack() {
    let marks = ImportantMarks(times: [10, 60]).removing(near: 61)
    #expect(marks.times == [10])
}

@Test func marksSurviveOnDiskAndNoneMeansNoFile() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "marks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(try ImportantMarksStore.load(from: folder) == .empty)
    try ImportantMarksStore.save(ImportantMarks(times: [12.5, 300]), in: folder)
    #expect(try ImportantMarksStore.load(from: folder).times == [12.5, 300])
    try ImportantMarksStore.save(.empty, in: folder)
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: ImportantMarksStore.fileName).path))
}
