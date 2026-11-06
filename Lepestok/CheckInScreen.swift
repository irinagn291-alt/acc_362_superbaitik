import SwiftUI

struct CheckInScreen: View {
    private enum PendingAction {
        case choose(Date), close, delete
    }

    @ObservedObject private var journal: DailyJournal
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DailyCheckIn
    @State private var pending: PendingAction?
    @State private var confirming = false
    @State private var error: String?

    init(journal: DailyJournal, date: Date) {
        self.journal = journal
        _draft = State(initialValue: journal.entry(on: date) ?? DailyCheckIn(date: date))
    }

    private var saved: DailyCheckIn? { journal.entry(on: draft.date) }
    private var changed: Bool { draft != (saved ?? DailyCheckIn(date: draft.date)) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                Form {
                    Section {
                        DatePicker("Day", selection: Binding(get: { draft.date }, set: select),
                                   in: ...Date.now, displayedComponents: .date)
                            .id("checkin.top")
                        Picker("Energy", selection: $draft.energy) {
                            Text("Not recorded").tag(nil as EnergyLevel?)
                            ForEach(EnergyLevel.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(Optional(level))
                            }
                        }
                        .accessibilityIdentifier("checkin.energy")
                        Picker("Cramps", selection: $draft.cramps) {
                            Text("Not recorded").tag(nil as CrampLevel?)
                            ForEach(CrampLevel.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(Optional(level))
                            }
                        }
                        .accessibilityIdentifier("checkin.cramps")
                    } header: {
                        Text("How did you feel?").textCase(nil)
                            .font(.system(.title2, design: .default, weight: .bold)).foregroundStyle(Petal.ink)
                    } footer: {
                        Text("Record what you noticed on any day of your cycle. Each field is optional.")
                    }

                    Section("Personal note") {
                        TextField("What stood out today?", text: $draft.note, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityLabel("Personal note")
                            .accessibilityIdentifier("checkin.note")
                    }

                    if saved != nil {
                        Section {
                            Button("Delete this check-in", role: .destructive) {
                                confirm(.delete)
                            }
                        }
                    }

                    Section("Check-in history") {
                        if journal.entries.isEmpty {
                            Text(journal.loadError ?? "Your saved check-ins will appear here.")
                                .font(.subheadline).foregroundStyle(Petal.muted)
                        } else {
                            ForEach(journal.entries) { entry in
                                Button { select(entry.date) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "book.pages")
                                            .foregroundStyle(Petal.rose).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.date, format: .dateTime.month(.wide).day().year())
                                                .font(.headline)
                                            Text(summary(entry)).font(.subheadline)
                                                .foregroundStyle(Petal.muted).lineLimit(2)
                                        }
                                        Spacer()
                                        if entry.id == draft.id {
                                            Text("Selected").font(.caption.weight(.semibold))
                                                .foregroundStyle(Petal.rose)
                                        } else {
                                            Image(systemName: "arrow.up.left").font(.caption)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .foregroundStyle(Petal.ink)
                                    .contentShape(Rectangle())
                                }
                                .accessibilityHint("Open this day to edit it")
                            }
                        }
                    }
                }
                .onChange(of: draft.id) { _, _ in
                    reader.scrollTo("checkin.top", anchor: .top)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Petal.paper)
            .navigationTitle("Daily check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { if changed { confirm(.close) } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.hasContent || !changed || journal.loadError != nil)
                        .accessibilityIdentifier("checkin.save")
                }
            }
            .interactiveDismissDisabled(changed)
            .confirmationDialog(confirmationTitle, isPresented: $confirming, titleVisibility: .visible) {
                Button(confirmationButton, role: .destructive) { performPendingAction() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn’t update check-in", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
        .tint(Petal.rose)
    }

    private func summary(_ entry: DailyCheckIn) -> String {
        let readings = [
            entry.energy.map { "\($0.rawValue) energy" },
            entry.cramps.map { $0 == .none ? "No cramps" : "\($0.rawValue) cramps" }
        ].compactMap { $0 }
        return readings.isEmpty ? entry.note : readings.joined(separator: " · ")
    }

    private func select(_ date: Date) {
        let target = journal.entry(on: date) ?? DailyCheckIn(date: date)
        guard target.id != draft.id else { return }
        if changed { confirm(.choose(date)) } else { draft = target }
    }

    private func confirm(_ action: PendingAction) {
        pending = action
        confirming = true
    }

    private var confirmationTitle: String {
        if case .delete = pending { return "Delete this day’s check-in?" }
        return "Discard your unsaved changes?"
    }

    private var confirmationButton: String {
        if case .delete = pending { return "Delete check-in" }
        return "Discard changes"
    }

    private func performPendingAction() {
        switch pending {
        case .choose(let date): draft = journal.entry(on: date) ?? DailyCheckIn(date: date)
        case .close: dismiss()
        case .delete:
            do {
                try journal.delete(draft)
                draft = DailyCheckIn(date: draft.date)
            } catch { self.error = error.localizedDescription }
        case nil: break
        }
    }

    private func save() {
        do {
            try journal.save(draft)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
