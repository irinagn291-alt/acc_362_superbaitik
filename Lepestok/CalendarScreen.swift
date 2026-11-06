import SwiftUI

struct CalendarScreen: View {
    @ObservedObject var store: CycleStore
    @ObservedObject var journal: DailyJournal
    let add: (Date) -> Void
    let edit: (PeriodEntry, Date) -> Void
    let checkIn: (Date) -> Void

    @State private var selected: Date = {
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotScreen.requested == .calendar { return ScreenshotScreen.day(-1) }
        #endif
        return .now
    }()

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private static let monthLabel = formatter("LLLL yyyy")
    private static let selectedLabel = formatter("EEEE, MMMM d")
    private static let fullDateLabel = formatter("EEEE, MMMM d, yyyy")

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: selected)!.start
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: selected)!.count
    }

    private var leadingDays: Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PetalSectionLabel(title: "Your days, at a glance")
                monthCard
                selectedDayCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Petal.paper)
        .foregroundStyle(Petal.ink)
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { selected = .now }
                    .foregroundStyle(Petal.rose)
            }
        }
    }

    private var monthCard: some View {
        let checkInDays = Set(journal.entries.lazy.map(\.date).filter {
            calendar.isDate($0, equalTo: selected, toGranularity: .month)
        })
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(Self.monthLabel.string(from: selected))
                    .font(.system(.title2, design: .default, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                monthButton(offset: -1)
                monthButton(offset: 1)
            }

            VStack(spacing: 4) {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Petal.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(0..<leadingDays, id: \.self) { _ in
                        Color.clear.frame(height: 44).accessibilityHidden(true)
                    }
                    ForEach(0..<daysInMonth, id: \.self) { offset in
                        if let date = calendar.date(byAdding: .day, value: offset, to: monthStart) {
                            dayButton(date, hasCheckIn: checkInDays.contains(date))
                        }
                    }
                }
            }

            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { legend }
                VStack(alignment: .leading, spacing: 8) { legend }
            }
            if store.entries.isEmpty {
                Text("Choose the day your period started, then tap Log a period.")
                    .font(.footnote).foregroundStyle(Petal.muted)
            }
        }
        .padding(16)
        .modifier(PetalCard())
    }

    @ViewBuilder private var legend: some View {
        Label("Logged period", systemImage: "drop.fill")
            .foregroundStyle(Petal.rose)
            .font(.caption.weight(.semibold))
        if store.entries.first?.end == nil, !store.entries.isEmpty {
            Label("Open period", systemImage: "drop")
                .foregroundStyle(Petal.rose)
                .font(.caption.weight(.semibold))
        }
        if let forecast = store.forecast(asOf: .now) {
            Label(forecast.isPast ? "Past estimate" : "Estimated start", systemImage: "circle.dashed")
                .foregroundStyle(Petal.muted)
                .font(.caption.weight(.semibold))
        }
        if !journal.entries.isEmpty {
            Label("Check-in", systemImage: "diamond.fill")
                .foregroundStyle(Petal.ink)
                .font(.caption.weight(.semibold))
        }
    }

    private func monthButton(offset: Int) -> some View {
        Button {
            guard let target = calendar.date(byAdding: .month, value: offset, to: selected) else { return }
            selected = target
        } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, height: 44)
                .background(Petal.paper, in: RoundedRectangle(cornerRadius: 12).inset(by: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offset < 0 ? "Previous month" : "Next month")
    }

    private func dayButton(_ date: Date, hasCheckIn: Bool) -> some View {
        let period = entry(on: date)
        let logged = period != nil
        let openDay = period.map { $0.end == nil && !calendar.isDate($0.start, inSameDayAs: date) } ?? false
        let estimate = logged ? nil : forecast(on: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let today = calendar.isDateInToday(date)
        let description = [
            today ? "Today" : nil,
            openDay ? "Open period, no end date" : logged ? "Logged period" : nil,
            estimate.map { $0.isPast ? "Past estimate" : "Estimated period start" },
            hasCheckIn ? "Saved check-in" : nil
        ].compactMap { $0 }.joined(separator: ", ")
        return Button {
            selected = date
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? Petal.ink : logged && !openDay ? Petal.pale : Color.clear)
                if estimate != nil {
                    Circle().inset(by: 3)
                        .strokeBorder(isSelected ? .white : Petal.rose, style: StrokeStyle(lineWidth: 1.6, dash: [3, 2]))
                }
                Text(String(calendar.component(.day, from: date)))
                    .font(.body.weight(today || logged ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : logged ? Petal.rose : Petal.ink)
                    .accessibilityHidden(true)
                if logged || today || hasCheckIn {
                    VStack {
                        Spacer()
                        HStack(spacing: 3) {
                            if logged {
                                Image(systemName: openDay ? "drop" : "drop.fill").font(.system(size: 8, weight: .semibold))
                            } else if today {
                                Circle().frame(width: 3, height: 3)
                            }
                            if hasCheckIn {
                                Image(systemName: "diamond.fill").font(.system(size: 7))
                            }
                        }
                    }
                    .foregroundStyle(isSelected ? .white : logged ? Petal.rose : Petal.ink)
                    .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: 40, maxHeight: 40)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.fullDateLabel.string(from: date))
        .accessibilityValue(description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedDayCard: some View {
        let period = entry(on: selected)
        let future = calendar.startOfDay(for: selected) > calendar.startOfDay(for: .now)
        return VStack(alignment: .leading, spacing: 12) {
            PetalSectionLabel(title: "Selected day")
            Text(Self.selectedLabel.string(from: selected))
                .font(.system(.title3, design: .default, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            if let period {
                let index = calendar.dateComponents([.day], from: calendar.startOfDay(for: period.start),
                                                    to: calendar.startOfDay(for: selected)).day ?? 0
                Label("Period · Day \(index + 1)", systemImage: "drop.fill")
                    .foregroundStyle(Petal.rose)
                if period.end == nil {
                    Text("This period has a start date only. Add its last day when it ends.")
                        .foregroundStyle(Petal.muted)
                }
                if !period.note.isEmpty {
                    Text(period.note)
                }
                Button("Edit period") { edit(period, selected) }
                    .accessibilityIdentifier("calendar.edit")
            } else {
                if let estimate = forecast(on: selected) {
                    Text(estimate.isPast
                         ? "This was your estimated start date. You can log the actual start whenever you know it."
                         : "Estimated start based on your recorded cycles. Your period may start earlier or later.")
                        .foregroundStyle(Petal.muted)
                } else {
                    Text(future ? "You can log a period once this day arrives." : "No period logged for this day.")
                        .foregroundStyle(Petal.muted)
                }

                if !future {
                    Button("Log a period") { add(selected) }
                        .accessibilityIdentifier("calendar.add")
                }
            }
            if !future {
                Button(journal.entry(on: selected) == nil ? "Daily check-in" : "View check-in") { checkIn(selected) }
                    .accessibilityIdentifier("calendar.checkIn")
            }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .tint(Petal.rose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .modifier(PetalCard())
    }

    private func entry(on date: Date) -> PeriodEntry? {
        let day = calendar.startOfDay(for: date)
        return store.entries.first {
            calendar.startOfDay(for: $0.start) <= day && day <= calendar.startOfDay(for: $0.end ?? .now)
        }
    }

    private func forecast(on date: Date) -> PeriodForecast? {
        guard let estimate = store.forecast(asOf: .now), calendar.isDate(estimate.date, inSameDayAs: date) else { return nil }
        return estimate
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = pattern
        return formatter
    }
}
