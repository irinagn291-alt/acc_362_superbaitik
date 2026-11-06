import XCTest
@testable import Lepestok

@MainActor
final class CycleStoreTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func file() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("journal.json")
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date()))!
    }

    func testHistorySurvivesEditingFinishingAndDeleting() throws {
        let url = file()
        let store = CycleStore(fileURL: url)
        var entry = PeriodEntry(start: daysAgo(4), note: "Initial note")
        try store.save(entry)
        XCTAssertEqual(CycleStore(fileURL: url).entries, [entry])
        XCTAssertNil(store.nextStart)
        entry.end = daysAgo(1)
        entry.note = "Updated note"
        try store.save(entry)
        let reopened = CycleStore(fileURL: url)
        XCTAssertEqual(reopened.entries, [entry])
        try reopened.delete(entry)
        XCTAssertEqual(CycleStore(fileURL: url).entries, [])
    }

    func testOverlappingPeriodsAndInvalidDatesLeaveExistingRecordIntact() throws {
        let store = CycleStore(fileURL: file())
        let current = PeriodEntry(start: daysAgo(4))
        try store.save(current)
        XCTAssertThrowsError(try store.save(PeriodEntry(start: daysAgo(1))))
        XCTAssertThrowsError(try store.save(PeriodEntry(start: daysAgo(8), end: daysAgo(4))))
        XCTAssertThrowsError(try store.save(PeriodEntry(start: daysAgo(-1))))
        XCTAssertThrowsError(try store.save(PeriodEntry(start: daysAgo(10), end: daysAgo(11))))
        XCTAssertEqual(store.entries, [current])
    }

    func testForecastUsesOnlyTheSixMostRecentGapsAndUpdatesOnDelete() throws {
        let store = CycleStore(fileURL: file())
        for offset in [31, 201, 141, 61, 171, 1, 401, 111, 91] {
            try store.save(PeriodEntry(start: daysAgo(offset), end: daysAgo(offset)))
        }
        // Last seven starts: 1, 31, 61, 91, 111, 141, 171 days ago.
        XCTAssertEqual(store.averageCycleLength, 28)
        XCTAssertEqual(store.nextStart, daysAgo(-27))
        try store.delete(XCTUnwrap(store.entries.first))
        XCTAssertEqual(store.nextStart, daysAgo(3))
    }

    func testUnreadableJournalCannotBeOverwritten() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("interrupted".utf8)
        try corrupt.write(to: url)
        let store = CycleStore(fileURL: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.save(PeriodEntry(start: daysAgo(1))))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testEstimateBecomesHistoricalOnlyAfterItsCalendarDay() throws {
        let store = CycleStore(fileURL: file())
        XCTAssertNil(store.forecast(asOf: .now))
        for days in [60, 30] {
            try store.save(PeriodEntry(start: daysAgo(days), end: daysAgo(days - 3)))
        }

        let expectedDay = daysAgo(0)
        let expectedEvening = try XCTUnwrap(calendar.date(byAdding: .hour, value: 19, to: expectedDay))
        XCTAssertEqual(store.forecast(asOf: expectedEvening), PeriodForecast(date: expectedDay, isPast: false))
        XCTAssertEqual(store.forecast(asOf: daysAgo(-1)), PeriodForecast(date: expectedDay, isPast: true))
        XCTAssertEqual(store.nextStart, expectedDay)
        XCTAssertEqual(store.entries.count, 2)
    }
}
