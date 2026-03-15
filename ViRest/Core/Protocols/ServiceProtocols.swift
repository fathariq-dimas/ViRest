import Foundation
import UserNotifications

protocol AuthProviding: AnyObject {
    var authState: AppAuthState { get }
    func restoreSession() async
    func signInWithApple() async throws -> AuthUser
    func signInWithGoogle() async throws -> AuthUser
    func signOut() throws
}

protocol HealthDataProviding: AnyObject {
    var authorizationState: HealthAuthorizationState { get }
    func shouldPresentAuthorizationPrompt() async -> Bool
    func requestAuthorization() async -> Bool
    func fetchLatestSnapshot(profile: UserProfileInput?) async -> HealthSnapshot
    func fetchRestingHeartRateTrend(
        range: RestingHeartRateTrendRange,
        profile: UserProfileInput?
    ) async -> [RestingHeartRateTrendBucket]
}

protocol HealthDataResolving: AnyObject {
    func resolveVitals(
        localProfile: UserProfileInput?,
        firestoreUser: FirestoreUser?
    ) async -> ResolvedHealthVitals
}

protocol RecommendationProviding {
    func recommend(request: RecommendationRequest) -> RecommendationResult
}

protocol PlanAdjusting {
    func evaluate(
        checkIn: SessionCheckIn,
        recentCheckIns: [SessionCheckIn],
        currentPlan: WeeklyPlan,
        alternatives: [SportRecommendation],
        latestHealthSnapshot: HealthSnapshot?
    ) -> PlanAdjustmentResult
}

protocol SuitabilityEvaluating {
    func evaluate(
        feedback: SuitabilityFeedbackInput,
        recentSameSportCheckIns: [CheckInHistoryEntry]
    ) -> SuitabilityAssessment
}

protocol SportSwitchOrchestrating: AnyObject {
    func cooldownRemaining(
        for plan: FirestoreSportPlan,
        origin: SwitchOrigin,
        now: Date
    ) -> TimeInterval?

    func requestSportSwitch(
        userId: String,
        currentPlan: FirestoreSportPlan,
        requestedSportId: String?,
        reason: SwitchReason,
        origin: SwitchOrigin,
        userProfile: UserProfileInput?,
        healthSnapshot: HealthSnapshot?,
        preferredReminderTime: DateComponents
    ) async throws -> SportSwitchOutcome
}

protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func isAuthorizationGranted() async -> Bool
    func schedulePlanReminders(for plan: WeeklyPlan)
    func scheduleFirestorePlanReminder(sports: [FirestoreSportEntry], preferredTime: DateComponents)
    func scheduleTargetAchievedNotification(for activity: ActivityType)
    func scheduleProgressionPhaseActivatedNotification(
        sportName: String,
        targetDurationMinutes: Int,
        targetWeeklyFrequency: Int
    )
    func clearPlanReminders()
}

extension NotificationScheduling {
    func scheduleProgressionPhaseActivatedNotification(
        sportName: String,
        targetDurationMinutes: Int,
        targetWeeklyFrequency: Int
    ) {}
}

protocol GamificationProviding {
    func evaluate(after checkIn: SessionCheckIn, current: BadgeState) -> GamificationResult
}
