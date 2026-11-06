import SwiftUI

enum Petal {
    static let ink = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let rose = Color(red: 0.86, green: 0.10, blue: 0.18)
    static let pale = Color(red: 1.00, green: 0.95, blue: 0.95)
    static let muted = Color(red: 0.40, green: 0.42, blue: 0.46)
    static let line = Color(red: 0.89, green: 0.90, blue: 0.91)
    static let radius: CGFloat = 18
}

struct PetalCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white, in: RoundedRectangle(cornerRadius: Petal.radius))
            .overlay {
                RoundedRectangle(cornerRadius: Petal.radius)
                    .strokeBorder(Petal.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct PetalPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(Petal.ink, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct PetalSectionLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Petal.rose).frame(width: 4, height: 14)
            Text(title.uppercased()).font(.caption.weight(.heavy)).tracking(1.4)
        }
        .foregroundStyle(Petal.muted)
        .accessibilityAddTraits(.isHeader)
    }
}

struct PetalIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(Petal.rose)
            .frame(width: 48, height: 48)
            .background(Petal.pale, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

private enum TrackerTab { case today, calendar, journal, insights }

#if DEBUG && targetEnvironment(simulator)
enum ScreenshotScreen: String, CaseIterable {
    case today, calendar
    case dailyCheckIn = "daily-check-in"
    case journal
    case periodEditor = "period-editor"
    case insights
    case cycleRecap = "cycle-recap"

    static var requested: Self? {
        let process = ProcessInfo.processInfo
        let arguments = process.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if arguments.contains("-ReviewScreen") {
            return value(after: "-ReviewScreen").flatMap(Self.init(rawValue:))
        }
        let environmentFlag = process.environment["APPSTORE_SCREENSHOTS"]?.lowercased()
        guard arguments.contains("-AppStoreScreenshots") ||
                (environmentFlag != nil && !["", "0", "false", "no"].contains(environmentFlag!)) else { return nil }
        let index = Int(value(after: "-AppStoreScreenshotScreen") ?? process.environment["APPSTORE_SCREENSHOT_SCREEN"] ?? "0")
        guard let index, Self.allCases.indices.contains(index) else { return nil }
        return Self.allCases[index]
    }

    static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))!
    }

    @MainActor static func seed(store: CycleStore, journal: DailyJournal) {
        do {
            try store.save(PeriodEntry(start: day(-57), end: day(-53)))
            try store.save(PeriodEntry(start: day(-29), end: day(-25), note: "Felt tired on the first day"))
            try store.save(PeriodEntry(start: day(-1)))
            try journal.save(DailyCheckIn(date: day(-25), energy: .low, cramps: .mild, note: "Took a gentle walk"))
            try journal.save(DailyCheckIn(date: day(-1), energy: .usual, cramps: .mild))
            try journal.save(DailyCheckIn(date: day(0), energy: .usual, cramps: .mild, note: "A quiet walk helped."))
        } catch {
            assertionFailure("Could not seed screenshot journal: \(error)")
        }
    }
}
#endif

private enum DiarySheet: Identifiable {
    case period(PeriodEntry?, Date)
    case checkIn(Date)
    case guide
    case privacy

    var id: String {
        switch self {
        case .period: "period"
        case .checkIn: "check-in"
        case .guide: "guide"
        case .privacy: "privacy"
        }
    }
}

@main
struct LepestokApp: App {
    @StateObject private var store: CycleStore
    @StateObject private var journal: DailyJournal

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotScreen.requested != nil {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenshotJournal", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let demoStore = CycleStore(fileURL: directory.appendingPathComponent("periods.json"))
            let demoJournal = DailyJournal(fileURL: directory.appendingPathComponent("check-ins.json"))
            ScreenshotScreen.seed(store: demoStore, journal: demoJournal)
            _store = StateObject(wrappedValue: demoStore)
            _journal = StateObject(wrappedValue: demoJournal)
            return
        }
        #endif
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["LEPESTOK_TEST_JOURNAL"],
           let id = UUID(uuidString: value) {
            let url = URL.applicationSupportDirectory.appending(path: "UITests/\(id)/journal.json")
            _store = StateObject(wrappedValue: CycleStore(fileURL: url))
            _journal = StateObject(wrappedValue: DailyJournal(fileURL: url.deletingLastPathComponent().appending(path: "check-ins.json")))
            return
        }
        #endif
        _store = StateObject(wrappedValue: CycleStore())
        _journal = StateObject(wrappedValue: DailyJournal())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ScreenshotScreen.requested != nil {
                    TrackerRoot(store: store, journal: journal)
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                } else {
                    TrackerRoot(store: store, journal: journal)
                }
                #else
                TrackerRoot(store: store, journal: journal)
                #endif
            }
                .environment(\.locale, Locale(identifier: "en_US"))
                .preferredColorScheme(.light)
                .tint(Petal.rose)
        }
    }
}

private struct TrackerRoot: View {
    @ObservedObject var store: CycleStore
    @ObservedObject var journal: DailyJournal
    @State private var sheet: DiarySheet?
    #if DEBUG && targetEnvironment(simulator)
    @State private var screenshotInsightsPath: [UUID] = []
    #endif
    @State private var tab: TrackerTab = {
        #if DEBUG && targetEnvironment(simulator)
        switch ScreenshotScreen.requested {
        case .calendar: return .calendar
        case .journal, .periodEditor: return .journal
        case .insights, .cycleRecap: return .insights
        default: break
        }
        #endif
        return .today
    }()

    init(store: CycleStore, journal: DailyJournal) {
        self.store = store
        self.journal = journal
        #if DEBUG && targetEnvironment(simulator)
        switch ScreenshotScreen.requested {
        case .dailyCheckIn:
            _sheet = State(initialValue: .checkIn(ScreenshotScreen.day(0)))
        case .periodEditor:
            let date = ScreenshotScreen.day(-29)
            if let entry = store.entries.first(where: { $0.start == date }) {
                _sheet = State(initialValue: .period(entry, date))
            }
        case .cycleRecap:
            if let entry = store.entries.first(where: { $0.start == ScreenshotScreen.day(-29) }) {
                _screenshotInsightsPath = State(initialValue: [entry.id])
            }
        default: break
        }
        #endif
    }

    @ViewBuilder private var insightsNavigation: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotScreen.requested == .cycleRecap {
            NavigationStack(path: $screenshotInsightsPath) {
                InsightsScreen(store: store, journal: journal)
                    .navigationDestination(for: UUID.self) { id in
                        InsightsScreen.screenshotRecap(store: store, journal: journal, id: id)
                    }
            }
        } else {
            NavigationStack { InsightsScreen(store: store, journal: journal) }
        }
        #else
        NavigationStack { InsightsScreen(store: store, journal: journal) }
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    TodayView(store: store, now: context.date, checkInSaved: journal.entry(on: context.date) != nil, record: {
                        if let active = store.entries.first, active.end == nil { sheet = .period(active, context.date) }
                        else { add(context.date) }
                    }, showCalendar: { tab = .calendar }, checkIn: { sheet = .checkIn(context.date) },
                       guide: { sheet = .guide }, privacy: { sheet = .privacy })
                }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }.tag(TrackerTab.today)

            NavigationStack {
                CalendarScreen(store: store, journal: journal, add: add, edit: { sheet = .period($0, $1) }, checkIn: { sheet = .checkIn($0) })
            }
                .tabItem { Label("Calendar", systemImage: "calendar") }.tag(TrackerTab.calendar)

            NavigationStack { HistoryScreen(store: store, journal: journal, add: add, edit: edit, checkIn: { sheet = .checkIn($0) }) }
                .tabItem { Label("Journal", systemImage: "book.pages") }.tag(TrackerTab.journal)

            insightsNavigation
                .tabItem { Label("Insights", systemImage: "chart.bar") }.tag(TrackerTab.insights)
        }
        .toolbarBackground(.white, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $sheet) { destination in
            switch destination {
            case let .period(entry, date): PeriodEditor(store: store, entry: entry, date: date)
            case let .checkIn(date): CheckInScreen(journal: journal, date: date)
            case .guide: PetalGuide()
            case .privacy: PetalGuide(privacyOnly: true)
            }
        }
        .safeAreaInset(edge: .top) {
            if let error = store.loadError {
                Text(error).font(.callout).padding().frame(maxWidth: .infinity).background(Petal.pale)
            }
        }
    }

    private func add(_ date: Date) { sheet = .period(nil, date) }
    private func edit(_ entry: PeriodEntry) { sheet = .period(entry, entry.start) }
}

// Original contour flower, shared by the diary header and cycle card.
struct Bloom: View {
    var color: Color = .white
    var rings = 14

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for ring in 0..<rings {
                let scale = 1 - Double(ring) * (0.76 / Double(rings))
                var path = Path()
                for index in 0...240 {
                    let angle = Double(index) * .pi / 120
                    let r = radius * scale * (0.80 + 0.20 * cos(5 * (angle + .pi / 2)))
                    let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(color), lineWidth: ring.isMultiple(of: 4) ? 1.8 : 0.9)
            }
            let dot = CGRect(x: center.x - radius * 0.055, y: center.y - radius * 0.055,
                             width: radius * 0.11, height: radius * 0.11)
            context.fill(Path(ellipseIn: dot), with: .color(color))
        }
        .accessibilityHidden(true)
    }
}

private struct TodayView: View {
    @ObservedObject var store: CycleStore
    let now: Date
    let checkInSaved: Bool
    let record: () -> Void
    let showCalendar: () -> Void
    let checkIn: () -> Void
    let guide: () -> Void
    let privacy: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 46
    @Environment(\.dynamicTypeSize) private var typeSize

    private var latest: PeriodEntry? { store.entries.first }
    private var isOngoing: Bool { latest != nil && latest?.end == nil }
    private var calendar: Calendar { .current }
    private let english = Locale(identifier: "en_US")

    private var cycleDay: Int? {
        guard let latest else { return nil }
        return (calendar.dateComponents([.day], from: calendar.startOfDay(for: latest.start), to: calendar.startOfDay(for: now)).day ?? 0) + 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brandHeader
                VStack(alignment: .leading, spacing: 5) {
                    Text("My cycle").font(.largeTitle.weight(.heavy)).tracking(-1.2)
                        .accessibilityAddTraits(.isHeader)
                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(english)).capitalizedFirst)
                        .font(.subheadline).foregroundStyle(Petal.muted)
                }
                cycleCard
                Button(action: record) {
                    HStack {
                        Label(isOngoing ? "Update period" : "Log a period", systemImage: isOngoing ? "pencil" : "plus")
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(PetalPrimaryButton())
                .accessibilityIdentifier("today.record")

                Button(action: checkIn) {
                    HStack(spacing: 14) {
                        PetalIcon(symbol: "leaf")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(checkInSaved ? "Today’s check-in" : "Daily check-in").font(.headline)
                            Text(checkInSaved ? "View or edit your observations" : "Energy, cramps, and a moment for you")
                                .font(.subheadline).foregroundStyle(Petal.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Petal.muted)
                    }.padding(18).frame(maxWidth: .infinity).modifier(PetalCard())
                }.buttonStyle(.plain).accessibilityIdentifier("today.checkIn")

                forecastCard
                Label("Stored on this device", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(Petal.muted).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 580).padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity)
        }
        .foregroundStyle(Petal.ink).background(Petal.paper)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Bloom(color: Petal.rose, rings: 5).frame(width: 32, height: 32)
            Text("SuperBaitik").font(.headline.weight(.heavy)).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: guide) {
                Image(systemName: "questionmark.circle").frame(width: 44, height: 44)
            }.accessibilityLabel("Guide").accessibilityIdentifier("today.guide")
            Button(action: privacy) {
                Image(systemName: "lock.shield").frame(width: 44, height: 44)
            }.accessibilityLabel("Privacy policy").accessibilityIdentifier("today.privacy")
        }
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(Petal.ink)
        .padding(.bottom, 2)
    }

    private var cycleCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TODAY").font(.caption.weight(.heavy)).tracking(1.8)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.14), in: Capsule())
            Spacer(minLength: 16)
            Text(cycleDay.map { "Day \($0)" } ?? "Your first\nentry")
                .font(.system(size: heroSize, weight: .heavy)).tracking(-1.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(cycleDay.map { "Day \($0)" } ?? "Your first entry")
            Text(latest == nil ? "Log the day your period started" : isOngoing ? "Period in progress" : "Since your period started")
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .padding(24)
        .background(alignment: .trailing) {
            GeometryReader { geo in
                Bloom(color: .white.opacity(typeSize.isAccessibilitySize ? 0.10 : 0.28))
                    .frame(width: geo.size.width * 0.66, height: geo.size.width * 0.66)
                    .rotationEffect(.degrees(-12))
                    .position(x: geo.size.width * 0.89, y: geo.size.height * 0.42)
            }
        }
        .foregroundStyle(.white).background(Petal.rose)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            let forecast = store.forecast(asOf: now)
            PetalSectionLabel(title: forecast?.isPast == true ? "Last estimate" : "Looking ahead")
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(Petal.rose)
                Text("Next period").font(.headline)
            }
            if let forecast {
                Text(forecast.date.formatted(.dateTime.day().month(.wide).year().locale(english)))
                    .font(.title2.weight(.bold)).tracking(-0.6)
                Text(forecast.isPast ? "This estimate has passed. Log your next start when it happens to update your calendar." : "Based on your recorded start dates. Your period may start earlier or later.")
                    .font(.subheadline).foregroundStyle(Petal.muted)
            } else {
                Text("Log two period start dates to see an estimate for your next period.")
                    .font(.subheadline).foregroundStyle(Petal.muted)
            }
            Divider().overlay(Petal.line)
            Button(action: showCalendar) {
                HStack { Text("Open calendar"); Spacer(); Image(systemName: "arrow.right") }
                    .font(.subheadline.bold()).frame(minHeight: 32).contentShape(Rectangle())
            }.foregroundStyle(Petal.rose)
        }.padding(20).modifier(PetalCard())
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
