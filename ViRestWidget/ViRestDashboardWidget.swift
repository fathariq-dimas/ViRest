import SwiftUI
import WidgetKit

struct ViRestWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ViRestWidgetSnapshot?
}

struct ViRestWidgetProvider: TimelineProvider {
    private let decoder = JSONDecoder()

    private var signedOutSnapshot: ViRestWidgetSnapshot {
        ViRestWidgetSnapshot(
            updatedAt: Date(),
            latestRestingHR: nil,
            targetRestingHR: nil,
            activeSportName: "Sign in to sync your plan",
            completedSessions: 0,
            targetSessions: 0
        )
    }

    func placeholder(in context: Context) -> ViRestWidgetEntry {
        ViRestWidgetEntry(
            date: Date(),
            snapshot: signedOutSnapshot
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ViRestWidgetEntry) -> Void) {
        let snapshot = loadSnapshot() ?? signedOutSnapshot
        completion(ViRestWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ViRestWidgetEntry>) -> Void) {
        let entry = ViRestWidgetEntry(date: Date(), snapshot: loadSnapshot() ?? signedOutSnapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> ViRestWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: ViRestWidgetShared.appGroupId) else { return nil }
        guard let data = defaults.data(forKey: ViRestWidgetShared.snapshotStorageKey) else { return nil }
        return try? decoder.decode(ViRestWidgetSnapshot.self, from: data)
    }
}

struct ViRestDashboardWidgetEntryView: View {
    let entry: ViRestWidgetProvider.Entry

    private let vibrantGreen = Color(.sRGB, red: 0.133, green: 0.773, blue: 0.369, opacity: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = entry.snapshot {
                rhrSummary(snapshot)
                progressSection(snapshot)
            } else {
                emptyState
            }
        }
        .environment(\.redactionReasons, [])
        .unredacted()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Virest")
                .font(.headline)
            Text("Login to sync your health and training progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }

    private func rhrSummary(_ snapshot: ViRestWidgetSnapshot) -> some View {
        HStack(spacing: 10) {
            metric(title: "Latest RHR", value: valueText(snapshot.latestRestingHR), valueColor: .primary)
            metric(title: "Goal RHR", value: valueText(snapshot.targetRestingHR), valueColor: vibrantGreen)
        }
    }

    private func metric(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func progressSection(_ snapshot: ViRestWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.activeSportName ?? "No active sport selected")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text("Weekly Progress")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(progressSubtitle(snapshot))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                progressCircle(
                    progress: completionProgress(snapshot),
                    completed: snapshot.completedSessions,
                    target: snapshot.targetSessions
                )
            }

            if let checkInURL = URL(string: "virest://checkin") {
                Link(destination: checkInURL) {
                    Text("Check In Sport")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(vibrantGreen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
            }
        }
    }

    private func progressCircle(progress: Double, completed: Int, target: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 8)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    vibrantGreen,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(progressText(completed: completed, target: target))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text("done")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
    }

    private func progressText(completed: Int, target: Int) -> String {
        guard target > 0 else { return "--" }
        let percentage = Int((min(1.0, Double(completed) / Double(target)) * 100).rounded())
        return "\(percentage)%"
    }

    private func progressSubtitle(_ snapshot: ViRestWidgetSnapshot) -> String {
        guard snapshot.targetSessions > 0 else { return "No active plan" }
        return "\(snapshot.completedSessions)/\(snapshot.targetSessions) sessions"
    }

    private func valueText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) bpm"
    }

    private func completionProgress(_ snapshot: ViRestWidgetSnapshot) -> Double {
        guard snapshot.targetSessions > 0 else { return 0 }
        return min(1.0, Double(snapshot.completedSessions) / Double(snapshot.targetSessions))
    }
}

struct ViRestDashboardWidget: Widget {
    let kind: String = "ViRestDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ViRestWidgetProvider()) { entry in
            ViRestDashboardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Virest Daily")
        .description("Latest RHR, goal RHR, and check-in progress.")
        .supportedFamilies([.systemMedium])
    }
}
