import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(TimerManager.self) private var timerManager

    @Query(sort: \Entry.timestamp, order: .reverse) private var entries: [Entry]
    @Query(sort: \Category.title) private var categories: [Category]
    @Query(sort: \BadgeAward.dateAwarded, order: .reverse) private var badgeAwards: [BadgeAward]

    @State private var viewModel = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                balanceCard
                dailyLedgerChangeCard
                dailyActivitiesCard
                streakHighlightCard
                activeSessionCard
                badgeCard
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    private var balanceCard: some View {
        let balance = viewModel.balance(entries: entries)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Ledger Balance")
                .font(.headline)
            Text(balance.formatted(.currency(code: "USD")))
                .font(.largeTitle.bold())
                .foregroundStyle(balance < .zeroValue ? .red : .green)
            Text("Positive balance means you've banked more grind than chill.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if balance < .zeroValue {
                Text("You're in the red. Prioritize Grind sessions to recover.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var dailyLedgerChangeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Ledger Change")
                .font(.headline)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let dailyChange = viewModel.dailyLedgerChange(entries: entries, on: context.date)
                let dailyBreakdown = viewModel.dailyLedgerBreakdown(entries: entries, on: context.date)
                let chillAbsolute = viewModel.absolute(dailyBreakdown.chill)

                VStack(alignment: .leading, spacing: 10) {
                    Text(dailyChange.formatted(.currency(code: "USD")))
                        .font(.title.bold())
                        .foregroundStyle(Self.amountColor(for: dailyChange))

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Grind")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(dailyBreakdown.grind.formatted(.currency(code: "USD")))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Self.amountColor(for: dailyBreakdown.grind))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(chillAbsolute.formatted(.currency(code: "USD")))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(dailyBreakdown.chill < .zeroValue ? .red : .secondary)
                        }
                    }

                    Text("\(dailyBreakdown.entryCount) \(Self.entryLabel(for: dailyBreakdown.entryCount)) today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var dailyActivitiesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Activities")
                .font(.headline)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let activities = viewModel.dailyActivities(entries: entries, on: context.date)

                if activities.isEmpty {
                    Text("No activity logged today. Start a session or add a manual entry.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(activities.prefix(5))) { activity in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: activity.symbolName)
                                    .foregroundStyle(activity.iconColor.swiftUIColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(activity.entryCount) \(Self.entryLabel(for: activity.entryCount)) • \(viewModel.activityQuantityText(for: activity))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(activity.totalAmountUSD.formatted(.currency(code: "USD")))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Self.amountColor(for: activity.totalAmountUSD))
                            }
                        }

                        if activities.count > 5 {
                            Text("+\(activities.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var activeSessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Session")
                .font(.headline)

            if let runningCategoryID = timerManager.activeCategoryID,
               let runningCategory = categories.first(where: { $0.id == runningCategoryID }) {
                Text(runningCategory.title)
                    .font(.title3.weight(.semibold))

                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    let elapsed = timerManager.elapsedSeconds(at: context.date)
                    Text(Self.formatDuration(elapsed))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            } else {
                Text("No active timer.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var streakHighlightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streak Highlight")
                .font(.headline)

            if categories.isEmpty {
                Text("Create your first category to begin tracking streaks.")
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let highlight = viewModel.streakHighlight(
                        categories: categories,
                        entries: entries,
                        now: context.date
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: highlight.symbolName)
                                .foregroundStyle(highlight.iconColor.swiftUIColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(highlight.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Self.typeLabel(for: highlight.type)) • \(highlight.progressText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(highlight.streakDays)d")
                                .font(.title3.weight(.bold))
                        }
                    } else {
                        Text("No active streak yet. Hit your Grind target or keep Chill below the threshold today.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var badgeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Badges")
                .font(.headline)

            if badgeAwards.isEmpty {
                Text("No badges yet. Hit a streak milestone (3, 7, 30 days).")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(badgeAwards.prefix(5), id: \.awardKey) { award in
                    HStack {
                        Image(systemName: "rosette")
                            .foregroundStyle(.yellow)
                        Text(Self.badgeLabel(from: award.awardKey))
                            .font(.subheadline)
                        Spacer()
                        Text(award.dateAwarded, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func badgeLabel(from key: String) -> String {
        let parts = key.split(separator: ":")

        guard parts.count >= 4, let milestone = Int(parts[2]) else {
            return key
        }

        return "\(milestone)-day streak"
    }

    private static func amountColor(for amount: Decimal) -> Color {
        if amount > .zeroValue {
            return .green
        }
        if amount < .zeroValue {
            return .red
        }
        return .secondary
    }

    private static func entryLabel(for count: Int) -> String {
        count == 1 ? "entry" : "entries"
    }

    private static func typeLabel(for type: CategoryType) -> String {
        switch type {
        case .goodHabit:
            return "Grind"
        case .quitHabit:
            return "Chill"
        }
    }
}
