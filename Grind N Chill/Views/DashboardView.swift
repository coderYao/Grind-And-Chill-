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
                activeSessionCard
                streaksCard
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
                Text("You're in the red. Prioritize Good Habit sessions to recover.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
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

    private var streaksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streaks")
                .font(.headline)

            if categories.isEmpty {
                Text("Create your first category to begin tracking streaks.")
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 10) {
                        ForEach(categories) { category in
                            let streak = viewModel.streak(for: category, entries: entries, now: context.date)
                            let progress = viewModel.progressText(for: category, entries: entries, now: context.date)

                            HStack {
                                Image(systemName: category.resolvedSymbolName)
                                    .foregroundStyle(category.resolvedType == .goodHabit ? .green : .orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(progress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("\(streak)d")
                                    .font(.headline)
                            }
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
}
