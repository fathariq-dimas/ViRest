import Foundation
import Combine

@MainActor
final class CheckInViewModel: ObservableObject {
    @Published var currentPlan: WeeklyPlan?
    @Published var pendingSessions: [SessionPlan] = []
    @Published var selectedSessionId: UUID?

    @Published var difficulty: ActivityDifficulty = .moderate
    @Published var fatigue: FatigueLevel = .moderatelyTired
    @Published var painLevel: PainLevel = .noPain
    @Published var discomfortAreas: Set<DiscomfortArea> = []
    @Published var notes: String = ""

    @Published var assessment: SuitabilityAssessment?
    @Published var appreciationText: String?
    @Published var newBadges: [BadgeEarned] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let userProfileRepository: UserProfileRepository
    private let planRepository: PlanRepository
    private let checkInRepository: CheckInRepository
    private let badgeRepository: BadgeStateRepository
    private let healthService: HealthDataProviding
    private let planAdjustmentService: PlanAdjusting
    private let gamificationService: GamificationProviding
    private let notificationService: NotificationScheduling
    private let firestoreUserRepository: FirestoreUserRepository?
    private let authService: AuthProviding?

    init(
        userProfileRepository: UserProfileRepository,
        planRepository: PlanRepository,
        checkInRepository: CheckInRepository,
        badgeRepository: BadgeStateRepository,
        healthService: HealthDataProviding,
        planAdjustmentService: PlanAdjusting,
        gamificationService: GamificationProviding,
        notificationService: NotificationScheduling,
        firestoreUserRepository: FirestoreUserRepository? = nil,
        authService: AuthProviding? = nil
    ) {
        self.userProfileRepository = userProfileRepository
        self.planRepository = planRepository
        self.checkInRepository = checkInRepository
        self.badgeRepository = badgeRepository
        self.healthService = healthService
        self.planAdjustmentService = planAdjustmentService
        self.gamificationService = gamificationService
        self.notificationService = notificationService
        self.firestoreUserRepository = firestoreUserRepository
        self.authService = authService
    }

    func load() {
        Task {
            await loadInternal()
        }
    }

    func submitCheckIn() {
        Task {
            await submitInternal()
        }
    }

    private func loadInternal() async {
        do {
            let plan = try planRepository.loadCurrentPlan()
            self.currentPlan = plan
            self.pendingSessions = plan?.sessions.filter { !$0.isCompleted } ?? []

            if selectedSessionId == nil {
                selectedSessionId = pendingSessions.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitInternal() async {
        isLoading = true
        errorMessage = nil

        do {
            guard var plan = try planRepository.loadCurrentPlan() else {
                throw AppError.invalidState("No active plan found.")
            }

            guard let sessionId = selectedSessionId,
                  let sessionIndex = plan.sessions.firstIndex(where: { $0.id == sessionId }) else {
                throw AppError.invalidState("Please select a session.")
            }

            let selectedSession = plan.sessions[sessionIndex]
            let resolvedDiscomfortAreas: [DiscomfortArea] =
                painLevel == .noPain ? [] : Array(discomfortAreas)

            let checkIn = SessionCheckIn(
                sessionId: selectedSession.id,
                checkInDate: Date(),
                activity: selectedSession.activity,
                actualDurationMinutes: selectedSession.plannedDurationMinutes,
                activityDifficulty: difficulty,
                fatigueLevel: fatigue,
                painLevel: painLevel,
                discomfortAreas: resolvedDiscomfortAreas,
                notes: notes
            )

            plan.sessions[sessionIndex].completedAt = checkIn.checkInDate
            try checkInRepository.addCheckIn(checkIn)

            let allCheckIns = try checkInRepository.loadCheckIns()
            let profile = try userProfileRepository.loadProfile()
            let snapshot = await healthService.fetchLatestSnapshot(profile: profile)

            let adjustment = planAdjustmentService.evaluate(
                checkIn: checkIn,
                recentCheckIns: allCheckIns,
                currentPlan: plan,
                alternatives: plan.alternatives,
                latestHealthSnapshot: snapshot
            )

            try planRepository.saveCurrentPlan(adjustment.updatedPlan)
            assessment = adjustment.assessment

            let existingState = try badgeRepository.loadState()
            let gamification = gamificationService.evaluate(after: checkIn, current: existingState)
            try badgeRepository.saveState(gamification.updatedState)
            if let firestoreUserRepository,
               case .signedIn(let user) = authService?.authState {
                try? await firestoreUserRepository.saveBadgeState(
                    userId: user.id,
                    state: gamification.updatedState
                )
            }

            appreciationText = gamification.appreciationMessage
            newBadges = gamification.newlyEarnedBadges

            notificationService.scheduleTargetAchievedNotification(for: checkIn.activity)
            notificationService.schedulePlanReminders(for: adjustment.updatedPlan)

            currentPlan = adjustment.updatedPlan
            pendingSessions = adjustment.updatedPlan.sessions.filter { !$0.isCompleted }
            selectedSessionId = pendingSessions.first?.id

            notes = ""
            discomfortAreas.removeAll()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
