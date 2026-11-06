import XCTest
@testable import Lepestok

final class CycleRecapTests: XCTestCase {
    func testCheckInsBelongToOnlyOneCycleAndAppearNewestFirst() throws {
        let calendar = Calendar(identifier: .gregorian)
        func date(_ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: day)))
        }

        let entries = try [3, 2, 5, 4, 1].map { DailyCheckIn(date: try date($0), note: "Day \($0)") }
        let days = CycleRecapDay.recorded(in: entries, start: try date(2), nextStart: try date(5))

        XCTAssertEqual(days.map(\.number), [3, 2, 1])
        XCTAssertEqual(days.map(\.checkIn.note), ["Day 4", "Day 3", "Day 2"])
    }
}
