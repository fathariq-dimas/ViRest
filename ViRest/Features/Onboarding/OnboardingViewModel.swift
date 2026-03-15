import Foundation
import Combine

@MainActor
final class OnboardingViewModel: ObservableObject {
    private static let healthKitSynchronizedDefaultsKey = "onboarding.healthkit.synchronized"

    struct RecommendationSummary: Equatable {
        struct SportFactor: Equatable, Identifiable {
            let sportId: String
            var id: String { sportId }
            let sportName: String
            let compatibilityPercent: Int
            let hasProgression: Bool
            let weekOneFrequency: Int
            let weekTwoPlusFrequency: Int
            let weekOneSessionMinutes: Int
            let weekTwoPlusSessionMinutes: Int
            let cautions: [String]
        }

        let primaryActivityName: String
        let sports: [SportFactor]
        var selectedSportId: String?
    }

    enum HealthImportState: Equatable {
        case idle
        case requestingConsent
        case imported
        case noData
        case denied
    }

    
    private let firestoreUserRepository: FirestoreUserRepository
    private let authService: AuthProviding
    
    @Published var fullName: String = ""
    @Published var ageText: String = ""
    @Published var gender: Gender?

    @Published var questionnaireCurrentRHRBand: CurrentRHRBandQuestion = .from61To75
    @Published var questionnaireTargetRHRGoal: TargetRHRGoalQuestion = .from60To69

    @Published var heightCmText: String = ""
    @Published var weightKgText: String = ""

    @Published var healthConcerns: Set<HealthConcernOption> = [.none]

    @Published var sessionDuration: SessionDurationOption = .tenToTwenty
    @Published var daysPerWeek: DaysPerWeekAvailability = .twoToThree
    @Published var preferredTime: PreferredTime = .flexible

    @Published var environment: SportEnvironment = .both
    @Published var accessOptions: Set<ExerciseAccessOptionQuestion> = [.none]

    @Published var enjoyableActivities: Set<ActivityType> = []
    @Published var intensityPreference: IntensityPreference = .light
    @Published var socialPreference: SocialPreference = .either
    @Published var consistency: ConsistencyLevel = .somewhatConsistent
    @Published var cardioExperienceLevel: CardioExperienceLevel?

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var importedHealthSnapshot: HealthSnapshot?
    @Published var recommendationSummary: RecommendationSummary?
    @Published private(set) var healthImportState: HealthImportState = .idle
    @Published private(set) var isHealthKitSynchronized = false

    private let userProfileRepository: UserProfileRepository
    private let planRepository: PlanRepository
    private let healthService: HealthDataProviding
    private let recommendationEngine: RecommendationProviding
    private let notificationService: NotificationScheduling
    private let onCompleted: () -> Void
    private var didAttemptAutoImport = false
    private var pendingGuestProfile: UserProfileInput?
    private var pendingGuestSportPlan: FirestoreSportPlan?
    private var latestGeneratedSportPlan: FirestoreSportPlan?
    private var latestRecommendationResult: RecommendationResult?
    private var latestGeneratedHealthSnapshot: HealthSnapshot?

    init(
        userProfileRepository: UserProfileRepository,
        planRepository: PlanRepository,
        healthService: HealthDataProviding,
        recommendationEngine: RecommendationProviding,
        notificationService: NotificationScheduling,
        firestoreUserRepository: FirestoreUserRepository,
        authService: AuthProviding,
        onCompleted: @escaping () -> Void
    ) {
        self.userProfileRepository = userProfileRepository
        self.planRepository = planRepository
        self.healthService = healthService
        self.recommendationEngine = recommendationEngine
        self.notificationService = notificationService
        self.firestoreUserRepository = firestoreUserRepository
        self.authService = authService
        self.onCompleted = onCompleted
        self.isHealthKitSynchronized = false
    }

    func autoImportHealthDataIfNeeded() {
        guard !didAttemptAutoImport else { return }
        didAttemptAutoImport = true
        importHealthData()
    }

    func resetForNewOnboarding() {
        fullName = ""
        ageText = ""
        gender = nil

        questionnaireCurrentRHRBand = .from61To75
        questionnaireTargetRHRGoal = .from60To69
        heightCmText = ""
        weightKgText = ""

        healthConcerns = [.none]
        sessionDuration = .twentyToThirty
        daysPerWeek = .threeToFour
        preferredTime = .flexible
        environment = .both
        accessOptions = [.none]
        enjoyableActivities = []
        intensityPreference = .light
        socialPreference = .either
        consistency = .somewhatConsistent
        cardioExperienceLevel = nil

        isLoading = false
        errorMessage = nil
        importedHealthSnapshot = nil
        recommendationSummary = nil
        healthImportState = .idle
        isHealthKitSynchronized = false
        pendingGuestProfile = nil
        pendingGuestSportPlan = nil
        latestGeneratedSportPlan = nil
        latestRecommendationResult = nil
        latestGeneratedHealthSnapshot = nil
        didAttemptAutoImport = false
    }

    func prepareHealthDataOnEntry() async {
        healthImportState = .idle
        isHealthKitSynchronized = false

        if healthService.authorizationState == .authorized || hasPersistedHealthKitSyncState() {
            isHealthKitSynchronized = true
        }

        let snapshot = await healthService.fetchLatestSnapshot(profile: nil)
        guard containsImportedHealthMetrics(snapshot) else {
            return
        }

        applyImportedMetrics(from: snapshot)
    }

    func shouldPresentHealthKitPrompt() async -> Bool {
        await healthService.shouldPresentAuthorizationPrompt()
    }

    func importHealthData() {
        Task {
            isLoading = true
            errorMessage = nil
            healthImportState = .requestingConsent

            let granted: Bool
            if healthService.authorizationState == .authorized {
                granted = true
            } else {
                granted = await healthService.requestAuthorization()
            }
            if !granted {
                await MainActor.run {
                    self.healthImportState = .denied
                    self.isHealthKitSynchronized = false
                    self.persistHealthKitSyncState(false)
                    self.errorMessage = "Health access denied. You can enable permissions from iOS Settings > Health > Data Access."
                    self.isLoading = false
                }
                return
            }
            await MainActor.run {
                self.isHealthKitSynchronized = true
            }

            let snapshot = await healthService.fetchLatestSnapshot(profile: nil)
            await MainActor.run {
                if !self.containsImportedHealthMetrics(snapshot) {
                    self.healthImportState = .noData
                    self.isHealthKitSynchronized = true
                    self.persistHealthKitSyncState(true)
                    self.errorMessage = "No Health data available yet. If Apple Watch has data, make sure Health sync is complete."
                } else {
                    self.applyImportedMetrics(from: snapshot)
                }
                self.isLoading = false
            }
        }
    }

    func toggleHealthConcern(_ concern: HealthConcernOption) {
        if concern == .none {
            healthConcerns = [.none]
            return
        }

        if healthConcerns.contains(concern) {
            healthConcerns.remove(concern)
        } else {
            healthConcerns.insert(concern)
        }
        healthConcerns.remove(.none)

        if healthConcerns.isEmpty {
            healthConcerns = [.none]
        }
    }

    func toggleAccessOption(_ option: ExerciseAccessOptionQuestion) {
        if option == .none {
            accessOptions = [.none]
            return
        }

        if accessOptions.contains(option) {
            accessOptions.remove(option)
        } else {
            accessOptions.insert(option)
        }

        accessOptions.remove(.none)

        if accessOptions.isEmpty {
            accessOptions = [.none]
        }
    }

    func submit() {
        Task {
            await submitInternal()
        }
    }

    func continueAfterRecommendation() {
        Task {
            await continueAfterRecommendationInternal()
        }
    }

    func selectRecommendedSport(_ sportId: String) {
        guard var summary = recommendationSummary else { return }
        guard summary.sports.contains(where: { $0.sportId == sportId }) else { return }
        guard summary.selectedSportId != sportId else { return }

        summary.selectedSportId = sportId
        recommendationSummary = summary
        errorMessage = nil
        applySelectedSportSelectionToDraft(selectedSportId: sportId)
    }

    @discardableResult
    func finalizePendingGuestSubmissionIfNeeded() async -> Bool {
        guard case .signedIn(let user) = authService.authState else { return false }
        guard let pendingGuestProfile, let pendingGuestSportPlan else { return false }

        do {
            if let existingUser = try await firestoreUserRepository.loadUser(userId: user.id),
               existingUser.sportPlan != nil {
                // Returning account already has an onboarding plan.
                // Ignore guest onboarding draft to avoid overwriting existing cloud data.
                self.pendingGuestProfile = nil
                self.pendingGuestSportPlan = nil
                self.latestGeneratedSportPlan = nil
                self.latestRecommendationResult = nil
                self.latestGeneratedHealthSnapshot = nil
                return true
            }

            // Register flow: persist draft to local cache after auth succeeds.
            try userProfileRepository.saveProfile(pendingGuestProfile)

            try await firestoreUserRepository.saveProfile(userId: user.id, profile: pendingGuestProfile)
            try await firestoreUserRepository.saveSportPlan(userId: user.id, plan: pendingGuestSportPlan)
            if let snapshot = latestGeneratedHealthSnapshot {
                try await firestoreUserRepository.upsertRHRTracking(
                    userId: user.id,
                    bpm: snapshot.restingHeartRate,
                    source: snapshot.restingHeartRateSource,
                    collectedAt: snapshot.collectedAt
                )
            }
            if let weeklyPlan = latestRecommendationResult?.weeklyPlan {
                try planRepository.saveCurrentPlan(weeklyPlan)
                _ = await notificationService.requestAuthorization()
                notificationService.schedulePlanReminders(for: weeklyPlan)
            }

            self.pendingGuestProfile = nil
            self.pendingGuestSportPlan = nil
            self.latestGeneratedSportPlan = nil
            self.latestRecommendationResult = nil
            self.latestGeneratedHealthSnapshot = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func continueAfterRecommendationInternal() async {
        guard let summary = recommendationSummary else { return }
        guard let selectedSportId = summary.selectedSportId else {
            errorMessage = "Please choose one recommended sport to continue."
            return
        }

        isLoading = true
        applySelectedSportSelectionToDraft(selectedSportId: selectedSportId)
        let didPersist = await persistOnboardingDataIfNeeded()
        isLoading = false
        guard didPersist else { return }

        if case .signedIn = authService.authState {
            pendingGuestProfile = nil
            pendingGuestSportPlan = nil
            latestGeneratedSportPlan = nil
            latestRecommendationResult = nil
            latestGeneratedHealthSnapshot = nil
        }
        onCompleted()
    }

    private func submitInternal() async {
        isLoading = true
        errorMessage = nil
        recommendationSummary = nil

        normalizeSelections()
        guard validateMandatoryInputs() else {
            isLoading = false
            return
        }

        let profile = buildProfile()
        let goalFrequency = derivedGoalFrequency()

        do {
            // 1. Generate recommendations from sports catalog and keep result as draft first.
            let snapshot = await healthService.fetchLatestSnapshot(profile: profile)
            latestGeneratedHealthSnapshot = snapshot
            let request = RecommendationRequest(
                userProfile: profile, healthSnapshot: snapshot,
                goalFrequency: goalFrequency, weekStartDate: Date()
            )
            let result = recommendationEngine.recommend(request: request)
            latestRecommendationResult = result
            let rawRecommendedSports = [result.primary] + result.alternatives
            let notSuitableSportIds = await loadNotSuitableSportIdsForCurrentUser()
            let recommendedSports = rawRecommendedSports.filter {
                !notSuitableSportIds.contains(Self.normalizedToken($0.displayName))
            }

            if recommendedSports.isEmpty {
                errorMessage = "No suitable sports available because previous not suitable flags filtered your matches. Try adjusting your answers."
                isLoading = false
                return
            }
            let sportPlan = buildSportPlan(
                profile: profile,
                snapshot: snapshot,
                recommendedSports: recommendedSports,
                fallbackWeeklySessions: max(1, result.weeklyPlan.sessions.count)
            )
            latestGeneratedSportPlan = sportPlan
            pendingGuestProfile = profile
            pendingGuestSportPlan = sportPlan

            let maxScore = recommendedSports.map(\.score).max() ?? 1
            let planBySportName = Dictionary(
                uniqueKeysWithValues: sportPlan.sports.map {
                    (Self.normalizedToken($0.displayName), $0)
                }
            )

            recommendationSummary = RecommendationSummary(
                primaryActivityName: recommendedSports.first?.displayName ?? result.primary.displayName,
                sports: recommendedSports.map { recommendation in
                    let matchedPlan = planBySportName[Self.normalizedToken(recommendation.displayName)]
                    let initial = matchedPlan?.resolvedInitialPrescription
                    let target = matchedPlan?.resolvedTargetPrescription
                    let resolvedWeekOneFrequency = initial?.weeklyTargetCount ?? result.weeklyPlan.sessions.count
                    let resolvedWeekTwoPlusFrequency = target?.weeklyTargetCount ?? resolvedWeekOneFrequency
                    let resolvedWeekOneDuration = initial?.durationMinutes ?? recommendation.plannedDurationMinutes
                    let resolvedWeekTwoPlusDuration = target?.durationMinutes ?? resolvedWeekOneDuration
                    let resolvedProgression =
                        matchedPlan?.hasProgression
                        ?? (resolvedWeekOneFrequency != resolvedWeekTwoPlusFrequency || resolvedWeekOneDuration != resolvedWeekTwoPlusDuration)

                    return RecommendationSummary.SportFactor(
                        sportId: matchedPlan?.id ?? Self.normalizedToken(recommendation.displayName),
                        sportName: recommendation.displayName,
                        compatibilityPercent: Self.compatibilityPercent(
                            score: recommendation.score,
                            maxScore: maxScore
                        ),
                        hasProgression: resolvedProgression,
                        weekOneFrequency: resolvedWeekOneFrequency,
                        weekTwoPlusFrequency: resolvedWeekTwoPlusFrequency,
                        weekOneSessionMinutes: resolvedWeekOneDuration,
                        weekTwoPlusSessionMinutes: resolvedWeekTwoPlusDuration,
                        cautions: recommendation.cautions
                    )
                },
                selectedSportId: sportPlan.resolvedSelectedSportId
            )

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadNotSuitableSportIdsForCurrentUser() async -> Set<String> {
        guard case .signedIn(let user) = authService.authState else { return [] }
        return (try? await firestoreUserRepository.loadNotSuitableSportIds(userId: user.id)) ?? []
    }

    private func buildSportPlan(
        profile: UserProfileInput,
        snapshot: HealthSnapshot,
        recommendedSports: [SportRecommendation],
        fallbackWeeklySessions: Int
    ) -> FirestoreSportPlan {
        let loader = SportsCatalogLoader.shared
        let rhrBand = resolvedSportsJsonRHRBand(profile: profile, snapshot: snapshot)
        let bmiCategory = BMICalculator.category(
            heightCm: profile.heightCm, weightKg: profile.weightKg
        )
        let generatedAt = Date()
        var usedSportKeys = Set<String>()
        var sports: [FirestoreSportEntry] = []

        for recommendation in recommendedSports {
            let normalizedName = Self.normalizedToken(recommendation.displayName)
            guard !usedSportKeys.contains(normalizedName) else { continue }
            usedSportKeys.insert(normalizedName)

            let prescription =
                loader.prescription(
                    for: recommendation.displayName,
                    rhrBand: rhrBand,
                    bmiCategory: bmiCategory
                )
                ?? loader.prescription(
                    for: recommendation.displayName,
                    rhrBand: rhrBand,
                    bmiCategory: "Any BMI"
                )

            let initialDuration = prescription?.initial.durationMinutes ?? max(10, recommendation.plannedDurationMinutes)
            let targetDuration = prescription?.target.durationMinutes ?? initialDuration
            let initialWeekly = prescription?.initial.daysPerWeek ?? fallbackWeeklySessions
            let targetWeekly = prescription?.target.daysPerWeek ?? initialWeekly
            let hasProgression = prescription?.hasProgression ?? (initialDuration != targetDuration || initialWeekly != targetWeekly)

            sports.append(
                FirestoreSportEntry(
                    id: normalizedName,
                    displayName: recommendation.displayName,
                    weeklyTargetCount: initialWeekly,
                    completedThisWeek: 0,
                    durationMinutes: initialDuration,
                    weekResetDate: generatedAt,
                    phaseStartDate: generatedAt,
                    pendingDeloadSessions: 0,
                    hasProgression: hasProgression,
                    initialPrescription: FirestoreSportPrescription(
                        weeklyTargetCount: initialWeekly,
                        durationMinutes: initialDuration
                    ),
                    targetPrescription: FirestoreSportPrescription(
                        weeklyTargetCount: targetWeekly,
                        durationMinutes: targetDuration
                    )
                )
            )
            if sports.count >= 3 { break }
        }

        return FirestoreSportPlan(
            generatedAt: generatedAt,
            sports: sports,
            selectedSportId: sports.first?.id
        )
    }

    private func applySelectedSportSelectionToDraft(selectedSportId: String) {
        if var generatedPlan = latestGeneratedSportPlan {
            generatedPlan.selectSport(id: selectedSportId)
            latestGeneratedSportPlan = generatedPlan
            pendingGuestSportPlan = generatedPlan
        } else if var pendingPlan = pendingGuestSportPlan {
            pendingPlan.selectSport(id: selectedSportId)
            pendingGuestSportPlan = pendingPlan
            latestGeneratedSportPlan = pendingPlan
        }
    }

    private func persistOnboardingDataIfNeeded() async -> Bool {
        guard let profile = pendingGuestProfile else { return false }
        guard let draftedPlan = latestGeneratedSportPlan ?? pendingGuestSportPlan else { return false }
        
        guard case .signedIn(let user) = authService.authState else { return true }
        
        do {
            let existingPlan = try await firestoreUserRepository.loadUser(userId: user.id)?.sportPlan
            let planToPersist = mergedPlanPreservingProgress(
                newPlan: draftedPlan,
                existingPlan: existingPlan
            )
            latestGeneratedSportPlan = planToPersist
            pendingGuestSportPlan = planToPersist

            try userProfileRepository.saveProfile(profile)
            try await firestoreUserRepository.saveProfile(userId: user.id, profile: profile)
            try await firestoreUserRepository.saveSportPlan(userId: user.id, plan: planToPersist)
            if let snapshot = latestGeneratedHealthSnapshot {
                try await firestoreUserRepository.upsertRHRTracking(
                    userId: user.id,
                    bpm: snapshot.restingHeartRate,
                    source: snapshot.restingHeartRateSource,
                    collectedAt: snapshot.collectedAt
                )
            }
            if let weeklyPlan = latestRecommendationResult?.weeklyPlan {
                try planRepository.saveCurrentPlan(weeklyPlan)
                _ = await notificationService.requestAuthorization()
                notificationService.schedulePlanReminders(for: weeklyPlan)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func mergedPlanPreservingProgress(
        newPlan: FirestoreSportPlan,
        existingPlan: FirestoreSportPlan?
    ) -> FirestoreSportPlan {
        guard let existingPlan else { return newPlan }

        var merged = newPlan
        let existingBySportId = Dictionary(uniqueKeysWithValues: existingPlan.sports.map { ($0.id, $0) })

        for index in merged.sports.indices {
            let sportId = merged.sports[index].id
            guard let existingSport = existingBySportId[sportId] else { continue }

            // Preserve per-sport progress/history when the same sport is recommended again.
            merged.sports[index].completedThisWeek = existingSport.completedThisWeek
            merged.sports[index].weekResetDate = existingSport.weekResetDate
            merged.sports[index].phaseStartDate = existingSport.phaseStartDate ?? existingSport.weekResetDate
            merged.sports[index].pendingDeloadSessions = existingSport.pendingDeloadSessions
        }

        merged.lastSwitchAt = existingPlan.lastSwitchAt
        merged.lastSwitchReason = existingPlan.lastSwitchReason

        if merged.resolvedSelectedSportId == nil,
           let existingSelectedSportId = existingPlan.resolvedSelectedSportId,
           merged.sports.contains(where: { $0.id == existingSelectedSportId }) {
            merged.selectedSportId = existingSelectedSportId
        }

        return merged
    }


    private func buildProfile() -> UserProfileInput {
        let resolvedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Virest User" : fullName
        let resolvedActivities: [ActivityType] = enjoyableActivities.isEmpty ? [.walking] : Array(enjoyableActivities)
        return UserProfileInput(
            fullName: resolvedName,
            age: Int(ageText),
            gender: gender,
            questionnaireCurrentRHRBand: questionnaireCurrentRHRBand,
            questionnaireTargetRHRGoal: questionnaireTargetRHRGoal,
            heightCm: parsedNumericValue(from: heightCmText),
            weightKg: parsedNumericValue(from: weightKgText),
            questionnaireHealthConcerns: normalizedHealthConcerns(),
            sessionDuration: sessionDuration,
            daysPerWeek: daysPerWeek,
            preferredTime: preferredTime,
            environment: environment,
            questionnaireAccessOptions: normalizedAccessOptions(),
            enjoyableActivities: resolvedActivities,
            intensityPreference: intensityPreference,
            socialPreference: socialPreference,
            consistency: consistency,
            cardioExperienceLevel: cardioExperienceLevel,
            acceptedDisclaimer: true,
            updatedAt: Date()
        )
    }

    private func normalizeSelections() {
        if healthConcerns.contains(.none), healthConcerns.count > 1 {
            healthConcerns.remove(.none)
        }

        if healthConcerns.isEmpty {
            healthConcerns.insert(.none)
        }

        if accessOptions.isEmpty {
            accessOptions.insert(.none)
        }

        if accessOptions.contains(.none), accessOptions.count > 1 {
            accessOptions.remove(.none)
        }
    }

    private func validateMandatoryInputs() -> Bool {
        let trimmedHeight = heightCmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHeight.isEmpty else {
            errorMessage = "Height is required."
            return false
        }

        guard let height = parsedNumericValue(from: trimmedHeight), height > 0 else {
            errorMessage = "Please input a valid height in cm."
            return false
        }

        let trimmedWeight = weightKgText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWeight.isEmpty else {
            errorMessage = "Weight is required."
            return false
        }

        guard let weight = parsedNumericValue(from: trimmedWeight), weight > 0 else {
            errorMessage = "Please input a valid weight in kg."
            return false
        }

        if height < 80 || height > 250 {
            errorMessage = "Height seems out of range."
            return false
        }

        if weight < 20 || weight > 400 {
            errorMessage = "Weight seems out of range."
            return false
        }

        if healthConcerns.isEmpty {
            errorMessage = "Health condition is required."
            return false
        }

        if accessOptions.isEmpty {
            errorMessage = "At least one access option is required."
            return false
        }

        return true
    }

    private func parsedNumericValue(from rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func containsImportedHealthMetrics(_ snapshot: HealthSnapshot) -> Bool {
        snapshot.heightCm != nil ||
        snapshot.weightKg != nil ||
        snapshot.restingHeartRate != nil
    }

    private func applyImportedMetrics(from snapshot: HealthSnapshot) {
        importedHealthSnapshot = snapshot
        healthImportState = .imported
        isHealthKitSynchronized = true
        persistHealthKitSyncState(true)
        errorMessage = nil

        if let height = snapshot.heightCm {
            heightCmText = formatDecimalInput(height)
        }
        if let weight = snapshot.weightKg {
            weightKgText = formatDecimalInput(weight)
        }
        if let rhr = snapshot.restingHeartRate {
            questionnaireCurrentRHRBand = Self.questionBand(from: rhr)
        }
    }

    private func normalizedHealthConcerns() -> [HealthConcernOption] {
        var list = Array(healthConcerns)
        if list.contains(.none), list.count > 1 {
            list.removeAll { $0 == .none }
        }
        return list.sorted { $0.displayName < $1.displayName }
    }

    private func normalizedAccessOptions() -> [ExerciseAccessOptionQuestion] {
        Array(accessOptions).sorted { $0.displayName < $1.displayName }
    }

    private func derivedGoalFrequency() -> WeeklyGoalFrequency {
        switch daysPerWeek {
        case .twoToThree:
            return .twoTimesPerWeek
        case .threeToFour:
            return .threeTimesPerWeek
        case .fourToFive, .fiveToSeven:
            return .fourPlusPerWeek
        }
    }

    private static func questionBand(from restingHeartRate: Double) -> CurrentRHRBandQuestion {
        switch restingHeartRate {
        case ..<61:
            return .upTo60
        case 61..<76:
            return .from61To75
        case 76..<91:
            return .from76To90
        default:
            return .above90
        }
    }

    private func resolvedSportsJsonRHRBand(profile: UserProfileInput, snapshot: HealthSnapshot) -> String {
        if snapshot.restingHeartRateSource == .healthKit,
           let healthKitRHR = snapshot.restingHeartRate {
            return Self.questionBand(from: healthKitRHR).sportsJsonBand
        }

        if let profileBand = profile.questionnaireCurrentRHRBand?.sportsJsonBand {
            return profileBand
        }

        if let fallbackRHR = snapshot.restingHeartRate {
            return Self.questionBand(from: fallbackRHR).sportsJsonBand
        }

        return CurrentRHRBandQuestion.from61To75.sportsJsonBand
    }

    private func formatDecimalInput(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.01 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    private static func compatibilityPercent(score: Double, maxScore: Double) -> Int {
        guard maxScore > 0 else { return 0 }
        let raw = (score / maxScore) * 100
        let clamped = min(100, max(1, raw))
        return Int(clamped.rounded())
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }

    private func hasPersistedHealthKitSyncState() -> Bool {
        UserDefaults.standard.bool(forKey: Self.healthKitSynchronizedDefaultsKey)
    }

    private func persistHealthKitSyncState(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.healthKitSynchronizedDefaultsKey)
    }
}
