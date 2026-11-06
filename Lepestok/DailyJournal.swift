import Combine
import Foundation

enum EnergyLevel: String, Codable, CaseIterable {
    case low = "Low", usual = "Usual", high = "High"
}

enum CrampLevel: String, Codable, CaseIterable {
    case none = "None", mild = "Mild", moderate = "Moderate", strong = "Strong"
}

struct DailyCheckIn: Identifiable, Equatable, Codable {
    private let day: JournalDay
    var energy: EnergyLevel?
    var cramps: CrampLevel?
    var note: String

    var date: Date { day.date }
    var id: Date { date }
    var hasContent: Bool {
        energy != nil || cramps != nil || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(date: Date, energy: EnergyLevel? = nil, cramps: CrampLevel? = nil, note: String = "") {
        day = JournalDay(date)
        self.energy = energy
        self.cramps = cramps
        self.note = note
    }
}

private enum CheckInError: LocalizedError {
    case future, empty, unreadable, writeFailed

    var errorDescription: String? {
        switch self {
        case .future: "Choose today or an earlier date."
        case .empty: "Choose an energy or cramp level, or add a note."
        case .unreadable: "Your check-ins could not be opened. Unlock your device and reopen SuperBaitik."
        case .writeFailed: "Your check-in changes could not be saved. Try again."
        }
    }
}

@MainActor
final class DailyJournal: ObservableObject {
    @Published private(set) var entries: [DailyCheckIn] = []
    @Published private(set) var loadError: String?
    private let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory
        .appending(path: "CycleJournal/check-ins.json")) {
        self.fileURL = fileURL
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DailyCheckIn].self, from: data)
                .sorted { $0.date > $1.date }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A new journal starts empty.
        } catch {
            loadError = CheckInError.unreadable.localizedDescription
        }
    }

    func entry(on date: Date) -> DailyCheckIn? {
        let day = JournalDay(date).date
        return entries.first { $0.date == day }
    }

    func save(_ entry: DailyCheckIn) throws {
        guard loadError == nil else { throw CheckInError.unreadable }
        guard entry.date <= JournalDay(.now).date else { throw CheckInError.future }
        guard entry.hasContent else { throw CheckInError.empty }
        var clean = entry
        clean.note = clean.note.trimmingCharacters(in: .whitespacesAndNewlines)
        var revised = entries.filter { $0.id != clean.id }
        revised.append(clean)
        try persist(revised.sorted { $0.date > $1.date })
    }

    func delete(_ entry: DailyCheckIn) throws {
        guard loadError == nil else { throw CheckInError.unreadable }
        try persist(entries.filter { $0.id != entry.id })
    }

    private func persist(_ revised: [DailyCheckIn]) throws {
        do {
            var directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let data = try JSONEncoder().encode(revised)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            entries = revised
        } catch {
            throw CheckInError.writeFailed
        }
    }
}
