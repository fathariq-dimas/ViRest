import Foundation

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

protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func schedulePlanReminders(for plan: WeeklyPlan)
    func scheduleFirestorePlanReminder(sports: [FirestoreSportEntry], preferredHour: Int)
    func scheduleTargetAchievedNotification(for activity: ActivityType)
    func clearPlanReminders()
}

protocol GamificationProviding {
    func evaluate(after checkIn: SessionCheckIn, current: BadgeState) -> GamificationResult
}
