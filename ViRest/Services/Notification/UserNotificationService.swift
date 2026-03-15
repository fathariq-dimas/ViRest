import Foundation
@preconcurrency import UserNotifications

@MainActor
final class UserNotificationService: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func isAuthorizationGranted() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                    || settings.authorizationStatus == .ephemeral
                continuation.resume(returning: authorized)
            }
        }
    }

    func schedulePlanReminders(for plan: WeeklyPlan) {
        clearPlanReminders()

        let pendingCount = plan.sessions.filter { !$0.isCompleted }.count
        guard pendingCount > 0 else { return }

        let preferredTime = plan.sessions.first?.preferredTime ?? .flexible

        let content = UNMutableNotificationContent()
        content.title = "Weekly target pending"
        content.body = "You still have \(pendingCount) activity session(s) to complete this week."
        content.sound = .default

        var components = DateComponents()
        switch preferredTime {
        case .morning:
            components.hour = 6
            components.minute = 0
        case .midday:
            components.hour = 12
            components.minute = 0
        case .evening:
            components.hour = 17
            components.minute = 0
        case .flexible:
            components.hour = 17
            components.minute = 0
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "plan-reminder-weekly-target",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func scheduleTargetAchievedNotification(for activity: ActivityType) {
        let content = UNMutableNotificationContent()
        content.title = "Target achieved"
        content.body = "Great job finishing your \(activity.displayName) session."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "goal-achieved-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func scheduleProgressionPhaseActivatedNotification(
        sportName: String,
        targetDurationMinutes: Int,
        targetWeeklyFrequency: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Program phase updated"
        content.body =
            "\(sportName) is now in target phase: \(targetDurationMinutes) min/session, "
            + "\(targetWeeklyFrequency)x/week."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let identifier = "plan-reminder-target-phase-\(normalizedToken(sportName))"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func clearPlanReminders() {
        let notificationCenter = center
        notificationCenter.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("plan-reminder-") || $0 == "plan-reminder-weekly-target" }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
    
    func scheduleSportReminders(for sports: [FirestoreSportEntry]) {
        // Clear old sport reminders
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
                .filter { $0.hasPrefix("sport-reminder-") }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }

        for sport in sports {
            let remaining = sport.weeklyTargetCount - sport.completedThisWeek
            guard remaining > 0 else { continue }  // Already met — no reminder needed

            let content = UNMutableNotificationContent()
            content.title = "Weekly target pending"
            content.body = "You've done \(sport.completedThisWeek)/\(sport.weeklyTargetCount) "
                + "sessions of \(sport.displayName) this week. \(remaining) more to go!"
            content.sound = .default

            // Fire on Friday at 6:00 PM
            var components = DateComponents()
            components.weekday = 6  // Friday
            components.hour = 18
            components.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "sport-reminder-\(sport.id)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    
    func scheduleWednesdayNudge(for sports: [FirestoreSportEntry]) {
        center.removePendingNotificationRequests(withIdentifiers: ["mid-week-nudge"])

        let laggingSports = sports.filter { sport in
            let ratio = Double(sport.completedThisWeek) / Double(sport.weeklyTargetCount)
            return ratio < 0.4  // Less than 40% done by midweek
        }
        guard !laggingSports.isEmpty else { return }

        let names = laggingSports.map(\.displayName).joined(separator: ", ")
        let content = UNMutableNotificationContent()
        content.title = "Halfway through the week!"
        content.body = "Time to make progress on: \(names)."
        content.sound = .default

        var components = DateComponents()
        components.weekday = 4  // Wednesday
        components.hour = 12
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: "mid-week-nudge", content: content, trigger: trigger))
    }

    func scheduleFirestorePlanReminder(sports: [FirestoreSportEntry], preferredTime: DateComponents) {
        // Clear existing plan reminders first
        clearPlanReminders()

        // Check if all weekly targets are met
        let allMet = sports.allSatisfy { $0.completedThisWeek >= $0.weeklyTargetCount }
        guard !allMet else {
            print("🔔 All weekly targets met — no reminder scheduled")
            return
        }

        // Count how many sports still have remaining sessions
        let remaining = sports.filter { $0.completedThisWeek < $0.weeklyTargetCount }
        let sportNames = remaining.map { $0.displayName }.joined(separator: ", ")

        let content = UNMutableNotificationContent()
        content.title = "Weekly target pending 📋"
        content.body = remaining.count == 1
            ? "Don't forget your \(sportNames) session today!"
            : "You still have \(remaining.count) activities pending: \(sportNames)."
        content.sound = .default

        var components = DateComponents()
        components.hour = preferredTime.hour ?? 17
        components.minute = preferredTime.minute ?? 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "plan-reminder-weekly-target",
            content: content,
            trigger: trigger
        )
        center.add(request)
        print("🔔 Plan reminder scheduled for \(components.hour ?? 17):\(String(format: "%02d", components.minute ?? 0)) — pending: \(sportNames)")
    }

    private func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }
}
