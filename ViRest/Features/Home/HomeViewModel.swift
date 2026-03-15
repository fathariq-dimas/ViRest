import Foundation
import Combine
import UserNotifications

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var firestoreUser: FirestoreUser?
    @Published var currentTitle: String = ""
    @Published var profileName: String = "Virest User"
    @Published var currentRestingHRText: String = "-"
    @Published var currentRestingHRValue: Int?
    @Published var currentWeightText: String = "-"
    @Published var currentHeightText: String = "-"
    @Published private(set) var restingHeartRateTrend: [RestingHeartRateTrendRange: [RestingHeartRateTrendBucket]] = [:]
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
    private let healthDataResolver: HealthDataResolving
    private let notificationService: NotificationScheduling
    private let gamificationService: GamificationProviding
    private let badgeRepository: BadgeStateRepository
    private let suitabilityEvaluator: SuitabilityEvaluating
    private let sportSwitchOrchestrator: SportSwitchOrchestrating
    private let widgetSyncService: WidgetSyncService
    private var preferredReminderTime: DateComponents = PreferredTime.flexible.reminderDateComponents

    private struct TargetPhaseTransitionInfo {
        let sportName: String
        let targetDurationMinutes: Int
        let targetWeeklyFrequency: Int
    }

    init(
        firestoreUserRepository: FirestoreUserRepository,
        userProfileRepository: UserProfileRepository,
        authService: AuthProviding,
        healthService: HealthDataProviding,
        healthDataResolver: HealthDataResolving,
        notificationService: NotificationScheduling,
        gamificationService: GamificationProviding,
        badgeRepository: BadgeStateRepository,
        suitabilityEvaluator: SuitabilityEvaluating,
        sportSwitchOrchestrator: SportSwitchOrchestrating,
        widgetSyncService: WidgetSyncService
    ) {
        self.firestoreUserRepository = firestoreUserRepository
        self.userProfileRepository = userProfileRepository
        self.authService = authService
        self.healthService = healthService
        self.healthDataResolver = healthDataResolver
        self.notificationService = notificationService
        self.gamificationService = gamificationService
        self.badgeRepository = badgeRepository
        self.suitabilityEvaluator = suitabilityEvaluator
        self.sportSwitchOrchestrator = sportSwitchOrchestrator
        self.widgetSyncService = widgetSyncService
    }

    var sports: [FirestoreSportEntry] {
        firestoreUser?.sportPlan?.resolvedSports(at: Date()) ?? []
    }

    var selectedSportId: String? {
        firestoreUser?.sportPlan?.resolvedSelectedSportId
    }

    func isSportLocked(_ sport: FirestoreSportEntry) -> Bool {
        firestoreUser?.sportPlan?.isSportLocked(sport) ?? false
    }

    func preferredSportForCheckIn() -> FirestoreSportEntry? {
        let resolvedSports = sports
        if let selectedSportId,
           let selectedSport = resolvedSports.first(where: { $0.id == selectedSportId }),
           !isSportLocked(selectedSport) {
            return selectedSport
        }

        return resolvedSports.first(where: { !isSportLocked($0) })
    }

    func restingHeartRateTrendBuckets(for range: RestingHeartRateTrendRange) -> [RestingHeartRateTrendBucket] {
        restingHeartRateTrend[range] ?? []
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
            let reminderSports = reminderSportsForNotification()
            notificationService.scheduleFirestorePlanReminder(
                sports: reminderSports,
                preferredTime: preferredReminderTime
            )

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
            userProfileRepository: userProfileRepository,
            healthService: healthService,
            suitabilityEvaluator: suitabilityEvaluator,
            sportSwitchOrchestrator: sportSwitchOrchestrator
        )
        vm.onCompleted = { [weak self] in
            self?.reloadAfterCheckIn()
        }
        return vm
    }

    private func loadInternal() async {
        isLoading = true
        errorMessage = nil
        guard case .signedIn(let user) = authService.authState else {
            widgetSyncService.clear()
            // Reschedule reminder reflecting current weekly progress
            let reminderSports = reminderSportsForNotification()
            notificationService.scheduleFirestorePlanReminder(
                sports: reminderSports,
                preferredTime: preferredReminderTime
            )
            isLoading = false; return
        }
        var localBadgeState = (try? badgeRepository.loadState()) ?? .default
        let didChangeLocalBadgeState = localBadgeState.normalizeRandomCriteriaIfNeeded()
        if didChangeLocalBadgeState {
            try? badgeRepository.saveState(localBadgeState)
        }

        firestoreUser = try? await firestoreUserRepository.loadUser(userId: user.id)
        let resolvedBadgeState: BadgeState
        if var remoteBadgeState = firestoreUser?.badgeState {
            let remoteChanged = remoteBadgeState.normalizeRandomCriteriaIfNeeded()
            resolvedBadgeState = remoteBadgeState
            try? badgeRepository.saveState(remoteBadgeState)
            if remoteChanged {
                try? await firestoreUserRepository.saveBadgeState(userId: user.id, state: remoteBadgeState)
            }
        } else {
            resolvedBadgeState = localBadgeState
            try? await firestoreUserRepository.saveBadgeState(userId: user.id, state: localBadgeState)
        }

        let localProfile = try? userProfileRepository.loadProfile()
        currentTitle = resolvedBadgeState.level.title
        updateProfileName(localProfile: localProfile)
        await updateVitals(localProfile: localProfile)
        await updateRestingHeartRateTrend(localProfile: localProfile)
        preferredReminderTime = localProfile?.resolvedReminderDateComponents ?? PreferredTime.flexible.reminderDateComponents

        do {
            try await resetWeeklyCountersIfNeeded(userId: user.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        await publishWidgetSnapshot(localProfile: localProfile)
        let reminderSports = reminderSportsForNotification()
        notificationService.scheduleFirestorePlanReminder(
            sports: reminderSports,
            preferredTime: preferredReminderTime
        )
        isLoading = false
    }

    private func updateRestingHeartRateTrend(localProfile: UserProfileInput?) async {
        async let dayTrend = healthService.fetchRestingHeartRateTrend(range: .day, profile: localProfile)
        async let weekTrend = healthService.fetchRestingHeartRateTrend(range: .week, profile: localProfile)
        async let monthTrend = healthService.fetchRestingHeartRateTrend(range: .month, profile: localProfile)

        restingHeartRateTrend = [
            .day: await dayTrend,
            .week: await weekTrend,
            .month: await monthTrend
        ]
    }

    private func updateProfileName(localProfile: UserProfileInput?) {
        let localName = localProfile?.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localName, !localName.isEmpty {
            profileName = localName
            return
        }

        if case .signedIn(let authUser) = authService.authState {
            let authName = authUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !authName.isEmpty {
                profileName = authName
                return
            }
        }

        let remoteName = firestoreUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remoteName, !remoteName.isEmpty {
            profileName = remoteName
            return
        }

        profileName = "Virest User"
    }

    private func updateVitals(localProfile: UserProfileInput?) async {
        let resolvedVitals = await healthDataResolver.resolveVitals(
            localProfile: localProfile,
            firestoreUser: firestoreUser
        )
        let resolvedRHR = resolvedVitals.latestRestingHeartRate

        if let resolvedRHR {
            currentRestingHRValue = resolvedRHR
            currentRestingHRText = "\(resolvedRHR) bpm"
        } else {
            currentRestingHRValue = nil
            currentRestingHRText = "-"
        }

        if let resolvedWeight = resolvedVitals.weightKg {
            currentWeightText = formatWeight(resolvedWeight)
        } else {
            currentWeightText = "-"
        }

        if let resolvedHeight = resolvedVitals.heightCm {
            currentHeightText = formatHeight(resolvedHeight)
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

    private func formatHeight(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.01 {
            return String(format: "%.0f cm", rounded)
        }
        return String(format: "%.1f cm", rounded)
    }

    private func resetWeeklyCountersIfNeeded(userId: String) async throws {
        guard var plan = firestoreUser?.sportPlan else { return }
        let now = Date()
        let selectedSportId = plan.resolvedSelectedSportId
        var didResetAnyCycle = false
        var targetPhaseTransition: TargetPhaseTransitionInfo?

        for i in plan.sports.indices {
            let sport = plan.sports[i]
            let nextCycleStart = sport.currentCycleStart(at: now, defaultStart: plan.generatedAt)
            guard sport.weekResetDate < nextCycleStart else { continue }

            if targetPhaseTransition == nil,
               sport.id == selectedSportId {
                targetPhaseTransition = detectTargetPhaseTransition(
                    sport: sport,
                    nextCycleStart: nextCycleStart,
                    planGeneratedAt: plan.generatedAt
                )
            }

            plan.sports[i].completedThisWeek = 0
            plan.sports[i].weekResetDate = nextCycleStart
            didResetAnyCycle = true
        }
        guard didResetAnyCycle else { return }

        firestoreUser?.sportPlan = plan
        try await firestoreUserRepository.saveSportPlan(userId: userId, plan: plan)

        if let transition = targetPhaseTransition {
            notificationService.scheduleProgressionPhaseActivatedNotification(
                sportName: transition.sportName,
                targetDurationMinutes: transition.targetDurationMinutes,
                targetWeeklyFrequency: transition.targetWeeklyFrequency
            )
        }
    }

    private func detectTargetPhaseTransition(
        sport: FirestoreSportEntry,
        nextCycleStart: Date,
        planGeneratedAt: Date
    ) -> TargetPhaseTransitionInfo? {
        guard sport.hasProgression else { return nil }

        let previousWeekIndex = sport.programWeekIndex(
            at: sport.weekResetDate,
            defaultStart: planGeneratedAt
        )
        let currentWeekIndex = sport.programWeekIndex(
            at: nextCycleStart,
            defaultStart: planGeneratedAt
        )
        guard previousWeekIndex <= 1, currentWeekIndex >= 2 else { return nil }

        let target = sport.resolvedTargetPrescription
        return TargetPhaseTransitionInfo(
            sportName: sport.displayName,
            targetDurationMinutes: target.durationMinutes,
            targetWeeklyFrequency: target.weeklyTargetCount
        )
    }

    private func reminderSportsForNotification() -> [FirestoreSportEntry] {
        guard let plan = firestoreUser?.sportPlan else { return [] }
        let resolvedSports = plan.resolvedSports(at: Date())
        guard let selectedSportId = plan.resolvedSelectedSportId else { return resolvedSports }
        let activeSports = resolvedSports.filter { $0.id == selectedSportId }
        return activeSports.isEmpty ? resolvedSports : activeSports
    }

    private func publishWidgetSnapshot(localProfile: UserProfileInput?) async {
        let resolvedSports = firestoreUser?.sportPlan?.resolvedSports(at: Date()) ?? []
        let selectedSportId = firestoreUser?.sportPlan?.resolvedSelectedSportId
        let activeSport = resolvedSports.first(where: { $0.id == selectedSportId }) ?? resolvedSports.first
        let resolvedVitals = await healthDataResolver.resolveVitals(
            localProfile: localProfile,
            firestoreUser: firestoreUser
        )

        let snapshot = ViRestWidgetSnapshot(
            updatedAt: Date(),
            latestRestingHR: resolvedVitals.latestRestingHeartRate,
            targetRestingHR: resolvedVitals.targetRestingHeartRate,
            activeSportName: activeSport?.displayName,
            completedSessions: activeSport?.completedThisWeek ?? 0,
            targetSessions: activeSport?.weeklyTargetCount ?? 0
        )
        widgetSyncService.publish(snapshot: snapshot)
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
