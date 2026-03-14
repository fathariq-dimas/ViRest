import Foundation

@MainActor
enum PreviewSupport {
    static func makeSeededContainer() -> AppContainer {
        let container = AppContainer(inMemory: true)
        seed(container: container)
        return container
    }

    static func makeAuthViewModel() -> AuthViewModel {
        let container = AppContainer(inMemory: true)
        return AuthViewModel(
            authService: PreviewAuthService(),
            onAuthenticated: { },
            firestoreUserRepository: container.firestoreUserRepository
        )
    }

    static func makeOnboardingViewModel() -> OnboardingViewModel {
        let container = AppContainer(inMemory: true)
        return OnboardingViewModel(
            userProfileRepository: container.userProfileRepository,
            planRepository: container.planRepository,
            healthService: PreviewHealthDataService(),
            recommendationEngine: container.recommendationEngine,
            notificationService: PreviewNotificationService(),
            firestoreUserRepository: container.firestoreUserRepository,
            authService: PreviewAuthService(),
            onCompleted: { }
        )
    }

    private static func seed(container: AppContainer) {
        let profile = UserProfileInput(
            fullName: "Preview User",
            age: 29,
            gender: .male,
            questionnaireCurrentRHRBand: .from76To90,
            questionnaireTargetRHRGoal: .from60To69,
            heightCm: 171,
            weightKg: 76,
            questionnaireHealthConcerns: [.none],
            sessionDuration: .twentyToThirty,
            daysPerWeek: .threeToFour,
            preferredTime: .evening,
            environment: .both,
            questionnaireAccessOptions: [.walkingShoes, .yogaMat, .stableChair],
            enjoyableActivities: [.walking, .yoga],
            intensityPreference: .light,
            socialPreference: .either,
            consistency: .somewhatConsistent,
            cardioExperienceLevel: .lightlyActive,
            acceptedDisclaimer: true
        )

        let goal: WeeklyGoalFrequency = .threeTimesPerWeek

        let primary = SportRecommendation(
            activity: .walking,
            displayName: "Brisk walking",
            score: 92,
            plannedDurationMinutes: 28,
            targetRPE: RPERange(min: 3, max: 4),
            reasons: [
                "Fits your current RHR band and beginner-safe progression.",
                "Matches your available equipment and preferred environment.",
                "Session duration aligns with your weekly routine."
            ],
            cautions: ["Stop and rest if chest discomfort appears."]
        )

        let alternativeA = SportRecommendation(
            activity: .indoorCycling,
            displayName: "Indoor cycling",
            score: 86,
            plannedDurationMinutes: 25,
            targetRPE: RPERange(min: 3, max: 4),
            reasons: ["Low-impact cardio alternative when weather is not ideal."]
        )

        let alternativeB = SportRecommendation(
            activity: .taiChi,
            displayName: "Tai chi",
            score: 78,
            plannedDurationMinutes: 20,
            targetRPE: RPERange(min: 2, max: 3),
            reasons: ["Recovery-friendly option for lighter days."]
        )

        let sessions = (1...goal.sessionsPerWeek).map { index in
            SessionPlan(
                sessionNumber: index,
                activity: .walking,
                preferredTime: profile.preferredTime,
                plannedDurationMinutes: 28,
                targetRPE: RPERange(min: 3, max: 4)
            )
        }

        let plan = WeeklyPlan(
            weekStartDate: Date().startOfWeek(),
            goalFrequency: goal,
            primaryRecommendation: primary,
            alternatives: [alternativeA, alternativeB],
            sessions: sessions,
            notes: ["Preview data only"]
        )

        let badges = BadgeState(
            completedSessions: 12,
            currentStreak: 4,
            lastCheckInDate: Date().addingTimeInterval(-86_400),
            level: .level2,
            earnedBadges: [BadgeEarned(type: .firstCheckIn)]
        )

        do {
            try container.userProfileRepository.saveProfile(profile)
            try container.planRepository.saveGoal(goal)
            try container.planRepository.saveCurrentPlan(plan)
            try container.badgeStateRepository.saveState(badges)
        } catch {
            // Keep preview resilient if seeding fails.
        }
    }
}

@MainActor
final class PreviewAuthService: AuthProviding {
    private(set) var authState: AppAuthState = .signedOut

    func restoreSession() async { }

    func signInWithApple() async throws -> AuthUser {
        let user = AuthUser(
            id: "preview-apple-user",
            email: "preview.apple@virest.app",
            displayName: "Preview Apple User",
            provider: .apple
        )
        authState = .signedIn(user)
        return user
    }

    func signInWithGoogle() async throws -> AuthUser {
        let user = AuthUser(
            id: "preview-google-user",
            email: "preview.google@virest.app",
            displayName: "Preview Google User",
            provider: .google
        )
        authState = .signedIn(user)
        return user
    }

    func signOut() throws {
        authState = .signedOut
    }
}

@MainActor
final class PreviewHealthDataService: HealthDataProviding {
    var authorizationState: HealthAuthorizationState = .authorized

    func shouldPresentAuthorizationPrompt() async -> Bool { false }

    func requestAuthorization() async -> Bool { true }

    func fetchLatestSnapshot(profile: UserProfileInput?) async -> HealthSnapshot {
        let resolvedProfile = profile ?? UserProfileInput(
            fullName: "Preview User",
            age: 29,
            gender: .male,
            questionnaireCurrentRHRBand: .from61To75,
            heightCm: 171,
            weightKg: 76
        )

        let heightCm = resolvedProfile.heightCm ?? 171
        let weightKg = resolvedProfile.weightKg ?? 76
        let heightMeters = max(0.1, heightCm / 100)
        let bmi = weightKg / (heightMeters * heightMeters)

        return HealthSnapshot(
            collectedAt: Date(),
            source: .healthKit,
            ageYears: resolvedProfile.age ?? 29,
            biologicalGender: resolvedProfile.gender ?? .male,
            stepCount: 8_420,
            activeEnergyKCal: 1_980,
            heightCm: heightCm,
            weightKg: weightKg,
            bmi: bmi,
            restingHeartRate: Double(resolvedProfile.questionnaireCurrentRHRBand?.representativeBPM ?? 68),
            walkingHeartRateAverage: 96,
            peakHeartRate: 141,
            heartRateRecovery: 19,
            vo2Max: 33.4,
            dataFreshnessHours: 2
        )
    }
}

@MainActor
final class PreviewNotificationService: NotificationScheduling {
    func requestAuthorization() async -> Bool { true }
    func schedulePlanReminders(for plan: WeeklyPlan) { }
    func scheduleFirestorePlanReminder(sports: [FirestoreSportEntry], preferredHour: Int) { }
    func scheduleTargetAchievedNotification(for activity: ActivityType) { }
    func clearPlanReminders() { }
}
