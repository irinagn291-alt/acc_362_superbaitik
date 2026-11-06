import SwiftUI

private let journalLocale = Locale(identifier: "en_US")

private func journalDate(_ day: Date, includeYear: Bool = false) -> String {
    let style = Date.FormatStyle(locale: journalLocale).day().month(.wide)
    return day.formatted(includeYear ? style.year() : style)
}

struct PeriodEditor: View {
    @ObservedObject var store: CycleStore
    @Environment(\.dismiss) private var dismiss
    let entry: PeriodEntry?
    @State private var start: Date
    @State private var end: Date
    @State private var hasEnd: Bool
    @State private var note: String
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(store: CycleStore, entry: PeriodEntry?, date: Date) {
        self.store = store
        self.entry = entry
        let selectedDay = Calendar.current.startOfDay(for: date)
        let firstDay = entry?.start ?? selectedDay
        _start = State(initialValue: firstDay)
        _end = State(initialValue: entry?.end ?? max(selectedDay, firstDay))
        _hasEnd = State(initialValue: entry?.end != nil)
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("First day", selection: $start, in: ...Date.now, displayedComponents: .date)
                        .onChange(of: start) { _, value in
                            if end < value || (entry == nil && !hasEnd) { end = value }
                        }
                    Toggle("Period has ended", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Last day", selection: $end, in: min(start, Date.now)...Date.now, displayedComponents: .date)
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text(hasEnd
                         ? "Count the first and last days you had bleeding. For a one-day period, use the same date twice."
                         : "Pick the first day of bleeding. Leave the switch off for an ongoing period, or turn it on to record the last day.")
                }
                Section("Note (optional)") {
                    TextField("Anything you want to remember?", text: $note, axis: .vertical)
                        .lineLimit(3...7)
                        .accessibilityLabel("Note")
                }
                if entry != nil {
                    Section {
                        Button("Delete entry", role: .destructive) { confirmDelete = true }
                            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                                Button("Delete", role: .destructive, action: remove)
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This will remove these dates and your note from the journal.")
                            }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Petal.paper)
            .navigationTitle(entry == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .alert("Couldn’t update your journal", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(Petal.rose)
        .environment(\.locale, journalLocale)
    }

    private func save() {
        let record = PeriodEntry(id: entry?.id ?? UUID(), start: start, end: hasEnd ? end : nil,
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try store.save(record)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        guard let entry else { return }
        do {
            try store.delete(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HistoryScreen: View {
    @ObservedObject var store: CycleStore
    @ObservedObject var journal: DailyJournal
    let add: (Date) -> Void
    let edit: (PeriodEntry) -> Void
    let checkIn: (Date) -> Void

    private func monthHeading(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: journalLocale).month(.wide).year()).capitalized(with: journalLocale)
    }

    var body: some View {
        let entries = store.entries
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                PetalSectionLabel(title: "A little more in tune")
                Button { checkIn(journal.entries.first?.date ?? .now) } label: {
                    HStack(spacing: 14) {
                        PetalIcon(symbol: "square.and.pencil")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Daily check-ins").font(.headline).foregroundStyle(Petal.ink)
                            Text(journal.entries.isEmpty
                                 ? "Add your first check-in"
                                 : "\(journal.entries.count) saved · View history")
                                .font(.subheadline).foregroundStyle(Petal.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).accessibilityHidden(true)
                    }
                    .padding(16)
                    .modifier(PetalCard())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.checkIns")
                Text("Periods").font(.title2.weight(.bold)).foregroundStyle(Petal.ink)
                    .accessibilityAddTraits(.isHeader)
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        PetalIcon(symbol: "book.pages")
                        Text("Your first entry")
                            .font(.system(.title, design: .default, weight: .bold)).foregroundStyle(Petal.ink)
                        Text("Add the first day of your most recent period. You can also enter earlier periods from memory or another calendar.")
                            .foregroundStyle(Petal.muted)
                        Button { add(.now) } label: {
                            Label("Log a period", systemImage: "plus")
                        }
                        .buttonStyle(PetalPrimaryButton())
                    }
                    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Petal.pale, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index == 0 || !Calendar.current.isDate(entry.start, equalTo: entries[index - 1].start, toGranularity: .month) {
                            Text(monthHeading(entry.start))
                                .font(.system(.title3, design: .default, weight: .bold)).foregroundStyle(Petal.ink)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Button { edit(entry) } label: { HistoryRow(entry: entry) }
                            .buttonStyle(.plain).accessibilityHint("Edit this entry")
                            .accessibilityIdentifier("history.entry")
                    }
                }
            }
            .frame(maxWidth: 600)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Petal.paper)
        .navigationTitle("Journal")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { add(.now) } label: { Label("Log a period", systemImage: "plus") }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: PeriodEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(entry.start, format: .dateTime.day())
                    .font(.title2.weight(.heavy))
                Text(entry.start, format: .dateTime.month(.abbreviated))
                    .font(.caption2.weight(.bold)).textCase(.uppercase)
            }
            .foregroundStyle(Petal.rose).frame(minWidth: 54, minHeight: 62)
            .background(Petal.pale, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(dateRange).font(.headline).foregroundStyle(Petal.ink)
                if entry.end == nil { Text("Ongoing").font(.subheadline).foregroundStyle(Petal.rose) }
                if !entry.note.isEmpty { Text(entry.note).lineLimit(2).font(.subheadline).foregroundStyle(Petal.muted) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Petal.muted).accessibilityHidden(true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PetalCard())
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }

    private var dateRange: String {
        let calendar = Calendar.current
        guard let end = entry.end, !calendar.isDate(end, inSameDayAs: entry.start) else { return journalDate(entry.start) }
        let spansYears = !calendar.isDate(entry.start, equalTo: end, toGranularity: .year)
        return journalDate(entry.start, includeYear: spansYears) + " — " + journalDate(end, includeYear: spansYears)
    }
}
