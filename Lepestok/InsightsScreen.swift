import SwiftUI

private enum InsightMetric: String, CaseIterable, Identifiable {
    case cycle = "Cycle length"
    case period = "Period length"

    var id: Self { self }

    var explanation: String {
        switch self {
        case .cycle: "Days from one recorded period start to the next."
        case .period: "Days from the first through the last day of a finished period."
        }
    }

    func sampleLabel(count: Int) -> String {
        switch self {
        case .cycle: count == 1 ? "1 recorded interval" : "\(count) recorded intervals"
        case .period: count == 1 ? "1 finished period" : "\(count) finished periods"
        }
    }
}

private struct InsightSample: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let length: Int

    var dateLabel: String {
        let style = Date.FormatStyle(locale: .init(identifier: "en_US")).month(.abbreviated).day().year()
        if start == end { return start.formatted(style) }
        let sameYear = Calendar.current.isDate(start, equalTo: end, toGranularity: .year)
        let shortStyle = Date.FormatStyle(locale: .init(identifier: "en_US")).month(.abbreviated).day()
        return "\(start.formatted(sameYear ? shortStyle : style)) – \(end.formatted(style))"
    }

    static func recent(_ entries: [PeriodEntry], metric: InsightMetric) -> [Self] {
        let calendar = Calendar(identifier: .gregorian)
        switch metric {
        case .cycle:
            let recent = entries.prefix(7)
            return zip(recent, recent.dropFirst()).compactMap { newer, older in
                guard let days = calendar.dateComponents([.day], from: older.start, to: newer.start).day else { return nil }
                return Self(id: older.id, start: older.start, end: newer.start, length: days)
            }
        case .period:
            return Array(entries.lazy.compactMap { entry -> Self? in
                guard let end = entry.end,
                      let days = calendar.dateComponents([.day], from: entry.start, to: end).day else { return nil }
                return Self(id: entry.id, start: entry.start, end: end, length: days + 1)
            }.prefix(6))
        }
    }
}

struct InsightsScreen: View {
    @ObservedObject var store: CycleStore
    @ObservedObject var journal: DailyJournal
    @State private var metric = InsightMetric.cycle
    @State private var editorVisible = false

    #if DEBUG && targetEnvironment(simulator)
    @ViewBuilder static func screenshotRecap(store: CycleStore, journal: DailyJournal, id: UUID) -> some View {
        if let sample = InsightSample.recent(store.entries, metric: .cycle).first(where: { $0.id == id }) {
            CycleRecap(sample: sample, periodEnd: store.entries.first { $0.id == sample.id }?.end,
                       journal: journal)
        }
    }
    #endif

    private var ongoing: PeriodEntry? { store.entries.first.flatMap { $0.end == nil ? $0 : nil } }
    private var editablePeriod: PeriodEntry? { metric == .period ? ongoing : nil }

    var body: some View {
        let samples = InsightSample.recent(store.entries, metric: metric)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PetalSectionLabel(title: "Understand your rhythm")
                Picker("Measure", selection: $metric) {
                    ForEach(InsightMetric.allCases) { option in Text(option.rawValue).tag(option) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("insights.measure")

                if samples.isEmpty {
                    emptyCard
                } else {
                    summaryCard(samples)
                    recordsCard(samples)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Insights")
        .foregroundStyle(Petal.ink)
        .background(Petal.paper)
        .sheet(isPresented: $editorVisible) {
            PeriodEditor(store: store, entry: editablePeriod, date: editablePeriod?.start ?? .now)
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PetalIcon(symbol: metric == .cycle ? "calendar" : "drop")
            Text(metric == .cycle ? "How long is my cycle?" : "How long is my period?")
                .font(.system(.title2, design: .default, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(metric.explanation).font(.body)
            Text(emptyPrompt).foregroundStyle(Petal.muted).font(.subheadline)
            if metric == .period || store.entries.isEmpty || ongoing == nil {
                Button {
                    editorVisible = true
                } label: {
                    Label(editablePeriod == nil ? "Log a period" : "Update period",
                          systemImage: editablePeriod == nil ? "plus" : "pencil")
                }
                .buttonStyle(PetalPrimaryButton())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .background(Petal.pale, in: RoundedRectangle(cornerRadius: 22))
    }

    private var emptyPrompt: String {
        if metric == .period {
            return ongoing == nil
                ? "Add a period with a first and last day to see its length here."
                : "When your period ends, add its last day to see the length here."
        }
        return store.entries.isEmpty
            ? "Log two start dates to see your first interval. You can add past periods from the calendar."
            : "You have one start date. Add a previous period from the calendar or record your next period when it begins."
    }

    private func summaryCard(_ samples: [InsightSample]) -> some View {
        let lengths = samples.map(\.length)
        let average = Double(lengths.reduce(0, +)) / Double(samples.count)
        return VStack(alignment: .leading, spacing: 12) {
            Text("AVERAGE " + metric.rawValue.uppercased())
                .font(.caption.bold()).tracking(1.4).accessibilityAddTraits(.isHeader)
            Text("\(average.formatted(.number.precision(.fractionLength(0...1)))) \(average == 1 ? "day" : "days")")
                .font(.system(.largeTitle, design: .default, weight: .heavy)).tracking(-1)
            Text("Based on \(metric.sampleLabel(count: samples.count)).").font(.subheadline)
            if samples.count > 1, let min = lengths.min(), let max = lengths.max() {
                Divider().overlay(.white.opacity(0.4))
                Text(min == max
                     ? "All \(samples.count) were \(days(min)) long."
                     : "\(days(min)) shortest   ·   \(days(max)) longest")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .foregroundStyle(.white)
        .background(Petal.rose, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("insights.summary")
    }

    private func recordsCard(_ samples: [InsightSample]) -> some View {
        let longest = samples.map(\.length).max() ?? 1
        return VStack(alignment: .leading, spacing: 16) {
            Text(metric == .cycle ? "Recent cycles" : "Recent periods")
                .font(.system(.title2, design: .default, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(metric.explanation + " Includes up to six recent records.")
                .font(.subheadline).foregroundStyle(Petal.muted)
            ForEach(samples) { sample in
                if metric == .cycle {
                    NavigationLink {
                        CycleRecap(sample: sample, periodEnd: store.entries.first { $0.id == sample.id }?.end,
                                   journal: journal)
                    } label: {
                        HStack(spacing: 12) {
                            recordRow(sample, longest: longest)
                            Image(systemName: "chevron.right").font(.footnote.bold())
                                .foregroundStyle(Petal.rose).accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open cycle recap")
                } else {
                    recordRow(sample, longest: longest)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .modifier(PetalCard())
    }

    private func recordRow(_ sample: InsightSample, longest: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(sample.dateLabel)
                    Spacer(minLength: 8)
                    Text(days(sample.length)).bold()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample.dateLabel)
                    Text(days(sample.length)).bold()
                }
            }
            .font(.subheadline)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Petal.pale)
                    Capsule().fill(Petal.rose)
                        .frame(width: geometry.size.width * CGFloat(sample.length) / CGFloat(longest))
                }
            }
            .frame(height: 8).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }
}

struct CycleRecapDay: Identifiable {
    let checkIn: DailyCheckIn
    let number: Int
    var id: Date { checkIn.id }

    static func recorded(in entries: [DailyCheckIn], start: Date, nextStart: Date) -> [Self] {
        let calendar = Calendar(identifier: .gregorian)
        return entries.filter { start <= $0.date && $0.date < nextStart }
            .sorted { $0.date > $1.date }
            .compactMap { entry in
                calendar.dateComponents([.day], from: start, to: entry.date).day.map {
                    Self(checkIn: entry, number: $0 + 1)
                }
            }
    }
}

private struct CycleRecap: View {
    let sample: InsightSample
    let periodEnd: Date?
    @ObservedObject var journal: DailyJournal

    var body: some View {
        let days = CycleRecapDay.recorded(in: journal.entries, start: sample.start, nextStart: sample.end)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Cycle dates")
                        .font(.system(.title2, design: .default, weight: .bold)).accessibilityAddTraits(.isHeader)
                    LabeledContent("First day", value: dateText(sample.start))
                    LabeledContent("Next period started", value: dateText(sample.end))
                    Divider()
                    LabeledContent("Cycle length", value: duration(sample.length))
                    if let periodEnd,
                       let length = Calendar(identifier: .gregorian).dateComponents([.day], from: sample.start, to: periodEnd).day {
                        LabeledContent("Period length", value: duration(length + 1))
                    }
                }
                .padding(20)
                .background(Petal.pale, in: RoundedRectangle(cornerRadius: 22))

                Text("Check-ins this cycle")
                    .font(.system(.title2, design: .default, weight: .bold)).accessibilityAddTraits(.isHeader)
                if days.isEmpty {
                    Text("No check-ins were recorded during this cycle. You can add one by selecting a past day in Calendar.")
                        .foregroundStyle(Petal.muted)
                } else {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Day \(day.number)").font(.headline).foregroundStyle(Petal.rose)
                            Text(dateText(day.checkIn.date)).font(.subheadline)
                            if let energy = day.checkIn.energy { LabeledContent("Energy", value: energy.rawValue) }
                            if let cramps = day.checkIn.cramps { LabeledContent("Cramps", value: cramps.rawValue) }
                            if !day.checkIn.note.isEmpty {
                                Text(verbatim: day.checkIn.note)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .modifier(PetalCard())
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(20).frame(maxWidth: 580).frame(maxWidth: .infinity)
        }
        .foregroundStyle(Petal.ink)
        .background(Petal.paper)
        .navigationTitle("Cycle recap")
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
    }

    private func duration(_ days: Int) -> String { days == 1 ? "1 day" : "\(days) days" }
}
