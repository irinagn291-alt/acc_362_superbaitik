import Combine
import Foundation

private var localCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    return calendar
}

// A journal entry belongs to a civil day even when the person changes time zones.
struct JournalDay: Codable, Equatable {
    private var reference: Date

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    init(_ date: Date) {
        let parts = localCalendar.dateComponents([.year, .month, .day], from: date)
        reference = Self.utc.date(from: parts)!
    }

    var date: Date {
        let parts = Self.utc.dateComponents([.year, .month, .day], from: reference)
        return localCalendar.date(from: parts)!
    }
}

struct PeriodEntry: Codable, Equatable, Identifiable {
    var id: UUID
    private var startDay: JournalDay
    private var endDay: JournalDay?
    var note: String

    var start: Date {
        get { startDay.date }
        set { startDay = JournalDay(newValue) }
    }

    var end: Date? {
        get { endDay?.date }
        set { endDay = newValue.map(JournalDay.init) }
    }

    init(id: UUID = UUID(), start: Date, end: Date? = nil, note: String = "") {
        self.id = id
        startDay = JournalDay(start)
        endDay = end.map(JournalDay.init)
        self.note = note
    }
}

struct PeriodForecast: Equatable {
    let date: Date
    let isPast: Bool
}

private enum JournalError: LocalizedError {
    case future, reversed, overlap, unreadable, writeFailed

    var errorDescription: String? {
        switch self {
        case .future: "Choose today or a date in the past."
        case .reversed: "The end date must be on or after the start date."
        case .overlap: "These dates overlap another period. Check the start and end dates."
        case .unreadable: "Your diary could not be opened. Unlock your device and reopen the app."
        case .writeFailed: "Your changes could not be saved on this device. Try again."
        }
    }
}

@MainActor
final class CycleStore: ObservableObject {
    @Published private(set) var entries: [PeriodEntry] = []
    @Published private(set) var loadError: String?
    private let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory
        .appendingPathComponent("CycleJournal", isDirectory: true)
        .appendingPathComponent("periods.json")) {
        self.fileURL = fileURL
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([PeriodEntry].self, from: data)
                .sorted { $0.start > $1.start }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // First launch.
        } catch {
            loadError = JournalError.unreadable.localizedDescription
        }
    }

    var averageCycleLength: Int? {
        let recent = entries.prefix(7)
        guard recent.count >= 2 else { return nil }
        let gaps = zip(recent, recent.dropFirst()).map { later, earlier in
            localCalendar.dateComponents([.day], from: earlier.start, to: later.start).day!
        }
        return Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }

    var nextStart: Date? {
        guard let latest = entries.first, let length = averageCycleLength else { return nil }
        return localCalendar.date(byAdding: .day, value: length, to: latest.start)
    }

    func forecast(asOf day: Date) -> PeriodForecast? {
        guard let date = nextStart else { return nil }
        return PeriodForecast(date: date, isPast: date < localCalendar.startOfDay(for: day))
    }

    func save(_ entry: PeriodEntry) throws {
        guard loadError == nil else { throw JournalError.unreadable }
        let today = localCalendar.startOfDay(for: Date())
        let end = entry.end ?? today
        guard entry.start <= today, end <= today else { throw JournalError.future }
        guard end >= entry.start else { throw JournalError.reversed }

        var revised = entries.filter { $0.id != entry.id }
        guard !revised.contains(where: { $0.start <= end && ($0.end ?? today) >= entry.start }) else {
            throw JournalError.overlap
        }
        revised.append(entry)
        try persist(revised.sorted { $0.start > $1.start })
    }

    func delete(_ entry: PeriodEntry) throws {
        guard loadError == nil else { throw JournalError.unreadable }
        try persist(entries.filter { $0.id != entry.id })
    }

    private func persist(_ revised: [PeriodEntry]) throws {
        do {
            var directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(revised).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw JournalError.writeFailed
        }
        entries = revised
    }
}
