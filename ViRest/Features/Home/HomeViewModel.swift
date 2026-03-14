import Foundation
import Combine
import UserNotifications

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var firestoreUser: FirestoreUser?
    @Published var currentTitle: String = ""
    @Published var profileName: String = "ViRest User"
    @Published var currentRestingHRText: String = "-"
    @Published var currentWeightText: String = "-"
    @Published var currentHeightText: String = "-"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var checkInSuccess: String?

    // Sheet state
    @Published var selectedSport: FirestoreSportEntry?
    @Published var showCheckInSheet = false

    private let firestoreUserRepository: FirestoreUserRepository
    private let userProfileRepository: UserProfileRepository
    private let authService: AuthProviding
    private let healthService: HealthDataProviding
    private let notificationService: NotificationScheduling
    private let gamificationService: GamificationProviding
    private let badgeRepository: BadgeStateRepository
    private let planAdjustmentService: PlanAdjusting

    init(
        firestoreUserRepository: FirestoreUserRepository,
        userProfileRepository: UserProfileRepository,
        authService: AuthProviding,
        healthService: HealthDataProviding,
        notificationService: NotificationScheduling,
        gamificationService: GamificationProviding,
        badgeRepository: BadgeStateRepository,
        planAdjustmentService: PlanAdjusting
    ) {
        self.firestoreUserRepository = firestoreUserRepository
        self.userProfileRepository = userProfileRepository
        self.authService = authService
        self.healthService = healthService
        self.notificationService = notificationService
        self.gamificationService = gamificationService
        self.badgeRepository = badgeRepository
        self.planAdjustmentService = planAdjustmentService
    }

    var sports: [FirestoreSportEntry] {
        firestoreUser?.sportPlan?.resolvedSports(at: Date()) ?? []
    }

    func load() {
        Task { await loadInternal() }
    }

    // Called when user taps '+' on a sport card
    func tapCheckIn(sport: FirestoreSportEntry) {
        selectedSport = sport
        showCheckInSheet = true
    }

    // Called by sheet's onCompleted closure to reload data
    func reloadAfterCheckIn() {
        Task {
            await loadInternal()

            // Reschedule reminder based on current progress
            let sports = firestoreUser?.sportPlan?.sports ?? []
            notificationService.scheduleFirestorePlanReminder(sports: sports, preferredHour: 19)

            checkInSuccess = "Session logged!"
        }
    }

    func makeCheckInSheetViewModel(for sport: FirestoreSportEntry) -> CheckInSheetViewModel {
        let vm = CheckInSheetViewModel(
            sport: sport,
            firestoreUserRepository: firestoreUserRepository,
            authService: authService,
            badgeRepository: badgeRepository,
            gamificationService: gamificationService,
            notificationService: notificationService,
            planAdjustmentService: planAdjustmentService
        )
        vm.onCompleted = { [weak self] in
            self?.reloadAfterCheckIn()
        }
        return vm
    }

    private func loadInternal() async {
        isLoading = true
        guard case .signedIn(let user) = authService.authState else {
            // Reschedule reminder reflecting current weekly progress
            let sports = firestoreUser?.sportPlan?.sports ?? []
            notificationService.scheduleFirestorePlanReminder(sports: sports, preferredHour: 19)
            isLoading = false; return
        }
        do {
            var loadedBadgeState = try badgeRepository.loadState()
            let didChangeBadgeState = loadedBadgeState.normalizeRandomCriteriaIfNeeded()
            if didChangeBadgeState {
                try badgeRepository.saveState(loadedBadgeState)
            }

            firestoreUser = try await firestoreUserRepository.loadUser(userId: user.id)
            let localProfile = try userProfileRepository.loadProfile()
            currentTitle = loadedBadgeState.level.title
            updateProfileName(localProfile: localProfile)
            await updateVitals(localProfile: localProfile)
            try await resetWeeklyCountersIfNeeded(userId: user.id)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func updateProfileName(localProfile: UserProfileInput?) {
        let localName = localProfile?.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localName, !localName.isEmpty {
            profileName = localName
            return
        }

        let remoteName = firestoreUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remoteName, !remoteName.isEmpty {
            profileName = remoteName
            return
        }

        profileName = "ViRest User"
    }

    private func updateVitals(localProfile: UserProfileInput?) async {
        let snapshot = await healthService.fetchLatestSnapshot(profile: localProfile)

        let resolvedHeight = snapshot.heightCm ?? localProfile?.heightCm
        let resolvedWeight = snapshot.weightKg ?? localProfile?.weightKg
        let resolvedRHR = snapshot.restingHeartRate.map { Int($0.rounded()) }
            ?? localProfile?.questionnaireCurrentRHRBand?.representativeBPM
            ?? firestoreUser?.restingHeartRate

        if let resolvedRHR {
            currentRestingHRText = "\(resolvedRHR) bpm"
        } else {
            currentRestingHRText = "-"
        }

        if let resolvedWeight {
            currentWeightText = formatWeight(resolvedWeight)
        } else {
            currentWeightText = "-"
        }

        if let resolvedHeight {
            currentHeightText = String(format: "%.0f cm", resolvedHeight)
        } else {
            currentHeightText = "-"
        }
    }

    private func formatWeight(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.01 {
            return String(format: "%.0f kg", rounded)
        }
        return String(format: "%.1f kg", rounded)
    }

    private func resetWeeklyCountersIfNeeded(userId: String) async throws {
        guard var plan = firestoreUser?.sportPlan else { return }
        let weekStart = Date().startOfWeek()
        guard plan.sports.contains(where: { $0.weekResetDate < weekStart }) else { return }

        for i in plan.sports.indices {
            plan.sports[i].completedThisWeek = 0
            plan.sports[i].weekResetDate = weekStart
        }
        firestoreUser?.sportPlan = plan
        try await firestoreUserRepository.saveSportPlan(userId: userId, plan: plan)
    }
    
    // DEBUG ONLY — remove before release
    func debugSimulateNextWeek() async {
        guard case .signedIn(let user) = authService.authState,
              var plan = firestoreUser?.sportPlan else { return }

        // Backdate weekResetDate by 8 days so it's older than current week start
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date()
        for i in plan.sports.indices {
            plan.sports[i].weekResetDate = eightDaysAgo
        }

        do {
            try await firestoreUserRepository.saveSportPlan(userId: user.id, plan: plan)
            firestoreUser?.sportPlan = plan
            // Now trigger the reset logic
            try await resetWeeklyCountersIfNeeded(userId: user.id)
            await loadInternal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // DEBUG ONLY — remove before release
    func debugFireTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let sports = firestoreUser?.sportPlan?.sports ?? []
        let allMet = sports.allSatisfy { $0.completedThisWeek >= $0.weeklyTargetCount }

        // 1. Test "target achieved" style — fires in 3 seconds
        let achievedContent = UNMutableNotificationContent()
        achievedContent.title = "Target achieved 🎯"
        achievedContent.body = "Great job finishing your session!"
        achievedContent.sound = .default
        let achievedRequest = UNNotificationRequest(
            identifier: "debug-achieved-\(UUID().uuidString)",
            content: achievedContent,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        try? await center.add(achievedRequest)

        // 2. Test "plan reminder" style — fires in 8 seconds
        //    Content reflects actual current progress
        let reminderContent = UNMutableNotificationContent()
        if allMet {
            reminderContent.title = "All targets met this week! 🎉"
            reminderContent.body = "Amazing consistency — keep it up next week!"
        } else {
            let remaining = sports.filter { $0.completedThisWeek < $0.weeklyTargetCount }
            let sportNames = remaining.map { $0.displayName }.joined(separator: ", ")
            reminderContent.title = "Weekly target pending 📋"
            reminderContent.body = remaining.count == 1
                ? "Don't forget your \(sportNames) session today!"
                : "You still have \(remaining.count) activities pending: \(sportNames)."
        }
        reminderContent.sound = .default
        let reminderRequest = UNNotificationRequest(
            identifier: "debug-reminder-\(UUID().uuidString)",
            content: reminderContent,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 8, repeats: false)
        )
        try? await center.add(reminderRequest)

        print("🔔 Debug notifications scheduled — all targets met: \(allMet) — background the app now!")
    }
    
    // DEBUG ONLY — remove before release
    func debugPrintPendingNotifications() {
        Task {
            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            if requests.isEmpty {
                print("🔔 No pending notifications")
            } else {
                print("🔔 Pending notifications (\(requests.count)):")
                for req in requests {
                    let trigger = req.trigger
                    if let calendarTrigger = trigger as? UNCalendarNotificationTrigger {
                        print("  • \(req.identifier) — fires at \(calendarTrigger.dateComponents) repeats: \(calendarTrigger.repeats)")
                    } else if let intervalTrigger = trigger as? UNTimeIntervalNotificationTrigger {
                        print("  • \(req.identifier) — fires in \(intervalTrigger.timeInterval)s repeats: \(intervalTrigger.repeats)")
                    }
                }
            }
        }
    }
}
