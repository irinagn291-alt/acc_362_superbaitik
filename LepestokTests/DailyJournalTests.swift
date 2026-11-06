import XCTest
@testable import Lepestok

@MainActor
final class DailyJournalTests: XCTestCase {
    private func journalURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appending(path: "check-ins.json")
    }

    func testOneCheckInPerDaySurvivesEditingAndDeleting() throws {
        let url = journalURL()
        let journal = DailyJournal(fileURL: url)
        let today = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        try journal.save(DailyCheckIn(date: today, energy: .usual, note: "  Walked outside  "))
        try journal.save(DailyCheckIn(date: yesterday, cramps: CrampLevel.none))

        XCTAssertEqual(journal.entries.count, 2)
        XCTAssertEqual(journal.entries.first?.note, "Walked outside")
        var edited = try XCTUnwrap(journal.entry(on: today))
        edited.energy = .high
        try journal.save(edited)
        let reopened = DailyJournal(fileURL: url)
        XCTAssertEqual(reopened.entries.count, 2)
        XCTAssertEqual(reopened.entry(on: today)?.energy, .high)
        XCTAssertEqual(reopened.entry(on: yesterday)?.cramps, CrampLevel.none)
        try reopened.delete(edited)
        XCTAssertEqual(DailyJournal(fileURL: url).entries.map(\.date), [JournalDay(yesterday).date])
    }

    func testRejectsBlankAndFutureCheckIns() throws {
        let journal = DailyJournal(fileURL: journalURL())
        XCTAssertThrowsError(try journal.save(DailyCheckIn(date: .now, note: "   ")))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertThrowsError(try journal.save(DailyCheckIn(date: tomorrow, note: "Future")))
        XCTAssertTrue(journal.entries.isEmpty)
    }

    func testReadFailurePreservesJournal() throws {
        let url = journalURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("unreadable".utf8)
        try original.write(to: url)
        let journal = DailyJournal(fileURL: url)
        let entry = DailyCheckIn(date: .now, note: "Changed")
        XCTAssertNotNil(journal.loadError)
        XCTAssertThrowsError(try journal.save(entry))
        XCTAssertThrowsError(try journal.delete(entry))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
