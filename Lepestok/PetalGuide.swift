import SwiftUI

struct PetalGuide: View {
    var privacyOnly = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if privacyOnly {
                    PrivacyDetails()
                } else {
                    List {
                        Section("Getting started") {
                            tip("1. Record a start", "Choose Log a period on Today. You can enter a past start date, even if you’re opening SuperBaitik for the first time.")
                            tip("2. Finish the entry", "Open the period in Journal, turn on Period has ended, and choose its last day. Both the first and last day count toward period length.")
                            tip("3. Check in between periods", "Open Daily check-in on Today or choose a past day in Calendar. You can record energy, cramps, or just a note on any day.")
                        }
                        Section("Reading your history") {
                            tip("Look back at one cycle", "In Insights, tap a recorded interval under Cycle length. Its recap places your observations on the days you wrote them, from one period start up to the next.")
                        }
                        Section("Where the estimate comes from") {
                            tip("Count from start to start", "SuperBaitik takes the average of up to six recent gaps between recorded start dates, rounds it to a whole day, and adds it to the latest start. Your first estimate appears after two starts.")
                            tip("An example", "Starts on April 1 and April 30 are 29 days apart. With those two entries, SuperBaitik would mark May 29 as the estimated next start.")
                            tip("Interpret your dates", "An unlogged period can make the estimate less useful. A dotted circle marks the estimate. Your next period may start on a different day.")
                            Text("Use these estimates for personal planning. They cannot determine ovulation or safe days for contraception. Speak with a healthcare professional before making medical decisions.")
                                .font(.footnote).foregroundStyle(Petal.muted)
                        }
                        Section {
                            NavigationLink { PrivacyDetails() } label: {
                                Label("Privacy policy", systemImage: "lock")
                            }
                        }
                    }
                    .scrollContentBackground(.hidden).background(Petal.paper)
                    .navigationTitle("Journal guide")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Petal.muted)
        }.padding(.vertical, 4)
    }
}

private struct PrivacyDetails: View {
    // The same plain-text policy can be hosted at the publisher's public privacy URL.
    private static let sections: [String] = {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Array(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n").dropFirst())
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Self.sections, id: \.self) { section in
                    let parts = section.split(separator: "\n", maxSplits: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(parts[0])).font(parts.count == 1 ? .subheadline : .headline)
                        if parts.count == 2 { Text(String(parts[1])).foregroundStyle(Petal.muted) }
                    }
                }
            }.frame(maxWidth: 560, alignment: .leading).padding(20).frame(maxWidth: .infinity)
        }.background(Petal.paper).navigationTitle("Privacy policy").navigationBarTitleDisplayMode(.inline)
    }
}
