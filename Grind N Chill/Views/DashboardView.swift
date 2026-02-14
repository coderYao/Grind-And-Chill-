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
                trendInsightsCard
                streakHighlightCard
                streakRiskAlertsCard
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
                                CategoryIconView(
                                    iconName: activity.symbolName,
                                    color: activity.iconColor.swiftUIColor
                                )

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
                            CategoryIconView(
                                iconName: highlight.symbolName,
                                color: highlight.iconColor.swiftUIColor
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(highlight.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Self.typeLabel(for: highlight.type)) • \(highlight.progressText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(highlight.streakDays)\(highlight.cadence.shortSuffix)")
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

    private var trendInsightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trend Insights")
                .font(.headline)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let trend = viewModel.weeklyTrend(entries: entries, now: context.date)
                let leaders = viewModel.topWeeklyCategories(entries: entries, now: context.date)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last 7 Days Net")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(trend.currentNet.formatted(.currency(code: "USD")))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Self.amountColor(for: trend.currentNet))
                    }

                    HStack(spacing: 6) {
                        Text("vs previous 7 days:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(trend.delta.formatted(.currency(code: "USD")))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Self.amountColor(for: trend.delta))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        insightRow(
                            title: "Top Grind",
                            insight: leaders.grind,
                            amountSign: .positive
                        )
                        insightRow(
                            title: "Top Chill",
                            insight: leaders.chill,
                            amountSign: .negative
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var streakRiskAlertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Streak Risk Alerts")
                .font(.headline)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let alerts = viewModel.streakRiskAlerts(
                    categories: categories,
                    entries: entries,
                    now: context.date
                )

                if alerts.isEmpty {
                    Text("No streaks at risk right now.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(alerts.prefix(3))) { alert in
                            HStack(alignment: .top, spacing: 10) {
                                CategoryIconView(
                                    iconName: alert.symbolName,
                                    color: alert.iconColor.swiftUIColor
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(alert.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(Self.typeLabel(for: alert.type))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.tertiarySystemFill), in: Capsule())
                                    }
                                    Text(alert.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(Self.severityLabel(for: alert.severity))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(alert.severity >= 3 ? .red : .orange)
                            }
                        }

                        if alerts.count > 3 {
                            Text("+\(alerts.count - 3) more risk alerts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                Text("No badges yet. Hit a streak milestone (3, 7, 30).")
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

        let periodKey = String(parts[3])
        let unit: String
        if periodKey.hasPrefix("w") {
            unit = "week"
        } else if periodKey.hasPrefix("m") {
            unit = "month"
        } else {
            unit = "day"
        }

        return "\(milestone)-\(unit) streak"
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

    private static func severityLabel(for severity: Int) -> String {
        severity >= 3 ? "High" : "Watch"
    }

    private enum AmountSign {
        case positive
        case negative
    }

    private func insightRow(
        title: String,
        insight: DashboardViewModel.WeeklyCategoryInsight?,
        amountSign: AmountSign
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let insight {
                CategoryIconView(
                    iconName: insight.symbolName,
                    color: insight.iconColor.swiftUIColor
                )
                Text(insight.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                let amount = amountSign == .negative ? (insight.totalAmountUSD * Decimal(-1)) : insight.totalAmountUSD
                Text(amount.formatted(.currency(code: "USD")))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(amountSign == .negative ? .red : .green)
            } else {
                Spacer()
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
