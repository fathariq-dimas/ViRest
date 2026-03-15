import Foundation

@MainActor
final class SportSwitchOrchestrator: SportSwitchOrchestrating {
    private let firestoreUserRepository: FirestoreUserRepository
    private let recommendationEngine: RecommendationProviding
    private let notificationService: NotificationScheduling
    private let cooldownWindow: TimeInterval = 7 * 24 * 60 * 60

    init(
        firestoreUserRepository: FirestoreUserRepository,
        recommendationEngine: RecommendationProviding,
        notificationService: NotificationScheduling
    ) {
        self.firestoreUserRepository = firestoreUserRepository
        self.recommendationEngine = recommendationEngine
        self.notificationService = notificationService
    }

    func cooldownRemaining(
        for plan: FirestoreSportPlan,
        origin: SwitchOrigin,
        now: Date = Date()
    ) -> TimeInterval? {
        guard !origin.bypassesCooldown else { return nil }
        guard let lastSwitchAt = plan.lastSwitchAt else { return nil }

        let elapsed = now.timeIntervalSince(lastSwitchAt)
        let remaining = cooldownWindow - elapsed
        return remaining > 0 ? remaining : nil
    }

    func requestSportSwitch(
        userId: String,
        currentPlan: FirestoreSportPlan,
        requestedSportId: String?,
        reason: SwitchReason,
        origin: SwitchOrigin,
        userProfile: UserProfileInput?,
        healthSnapshot: HealthSnapshot?,
        preferredReminderTime: DateComponents
    ) async throws -> SportSwitchOutcome {
        if let remaining = cooldownRemaining(for: currentPlan, origin: origin, now: Date()) {
            throw SportSwitchError.cooldownActive(remaining)
        }

        guard let selectedSportId = currentPlan.resolvedSelectedSportId else {
            throw SportSwitchError.invalidPlanState
        }

        let suitabilityFlags = try await firestoreUserRepository.registerSportSwitchFeedback(
            userId: userId,
            sportId: selectedSportId,
            reason: reason,
            origin: origin
        )
        let notSuitableSportIds = Set(
            suitabilityFlags.compactMap { key, value in
                value.isNotSuitable ? key : nil
            }
        )
        if let requestedSportId, notSuitableSportIds.contains(requestedSportId) {
            throw SportSwitchError.sportMarkedNotSuitable
        }

        var plan = currentPlan
        var sports = plan.sports

        let resolvedTarget = resolveTargetCandidate(
            selectedSportId: selectedSportId,
            requestedSportId: requestedSportId,
            sports: sports,
            notSuitableSportIds: notSuitableSportIds,
            userProfile: userProfile,
            healthSnapshot: healthSnapshot
        )

        guard var targetSport = resolvedTarget.target else {
            throw SportSwitchError.noCandidateAvailable
        }

        sports = resolvedTarget.updatedSports
        let phaseStart = Date()
        for index in sports.indices where sports[index].id == targetSport.id {
            sports[index].completedThisWeek = 0
            sports[index].weekResetDate = phaseStart
            sports[index].phaseStartDate = phaseStart
            sports[index].pendingDeloadSessions = 0
            targetSport = sports[index]
        }

        plan.sports = sports
        plan.selectSport(id: targetSport.id)
        plan.lastSwitchAt = Date()
        plan.lastSwitchReason = reason

        try await firestoreUserRepository.saveSportPlan(userId: userId, plan: plan)

        let reminderSports = reminderSports(for: plan)
        notificationService.scheduleFirestorePlanReminder(
            sports: reminderSports,
            preferredTime: preferredReminderTime
        )

        return SportSwitchOutcome(updatedPlan: plan, selectedSport: targetSport)
    }

    private func reminderSports(for plan: FirestoreSportPlan) -> [FirestoreSportEntry] {
        let resolvedSports = plan.resolvedSports(at: Date())
        guard let selectedSportId = plan.resolvedSelectedSportId else { return resolvedSports }
        let active = resolvedSports.filter { $0.id == selectedSportId }
        return active.isEmpty ? resolvedSports : active
    }

    private func resolveTargetCandidate(
        selectedSportId: String,
        requestedSportId: String?,
        sports: [FirestoreSportEntry],
        notSuitableSportIds: Set<String>,
        userProfile: UserProfileInput?,
        healthSnapshot: HealthSnapshot?
    ) -> (target: FirestoreSportEntry?, updatedSports: [FirestoreSportEntry]) {
        if let requestedSportId,
           requestedSportId != selectedSportId,
           !notSuitableSportIds.contains(requestedSportId),
           let requested = sports.first(where: { $0.id == requestedSportId }) {
            return (requested, sports)
        }

        if let existingCandidate = sports.first(
            where: { $0.id != selectedSportId && !notSuitableSportIds.contains($0.id) }
        ) {
            return (existingCandidate, sports)
        }

        guard let userProfile else {
            return (nil, sports)
        }

        let rerun = recommendationEngine.recommend(
            request: RecommendationRequest(
                userProfile: userProfile,
                healthSnapshot: healthSnapshot,
                goalFrequency: resolvedGoalFrequency(from: userProfile),
                weekStartDate: Date()
            )
        )

        let rerunRecommendations = [rerun.primary] + rerun.alternatives
        let rerunEntries = buildFallbackSportEntries(
            recommendations: rerunRecommendations,
            userProfile: userProfile,
            healthSnapshot: healthSnapshot
        )

        guard let rerunCandidate = rerunEntries.first(
            where: { $0.id != selectedSportId && !notSuitableSportIds.contains($0.id) }
        ) else {
            return (nil, sports)
        }

        var updatedSports = sports
        if !updatedSports.contains(where: { $0.id == rerunCandidate.id }) {
            if let replaceIndex = updatedSports.indices.first(where: { updatedSports[$0].id != selectedSportId }) {
                updatedSports[replaceIndex] = rerunCandidate
            } else {
                updatedSports.append(rerunCandidate)
            }
        }

        if updatedSports.count > 3 {
            updatedSports = Array(updatedSports.prefix(3))
        }

        let target = updatedSports.first(where: { $0.id == rerunCandidate.id }) ?? rerunCandidate
        return (target, updatedSports)
    }

    private func buildFallbackSportEntries(
        recommendations: [SportRecommendation],
        userProfile: UserProfileInput,
        healthSnapshot: HealthSnapshot?
    ) -> [FirestoreSportEntry] {
        let weekReset = Date()
        let rhrBand = resolvedRHRBand(profile: userProfile, healthSnapshot: healthSnapshot)
        let height = userProfile.heightCm ?? healthSnapshot?.heightCm
        let weight = userProfile.weightKg ?? healthSnapshot?.weightKg
        let bmiCategory = BMICalculator.category(heightCm: height, weightKg: weight)

        var seen = Set<String>()
        var entries: [FirestoreSportEntry] = []

        for recommendation in recommendations {
            let id = normalizedToken(recommendation.displayName)
            guard !seen.contains(id) else { continue }
            seen.insert(id)

            let prescription =
                SportsCatalogLoader.shared.prescription(
                    for: recommendation.displayName,
                    rhrBand: rhrBand,
                    bmiCategory: bmiCategory
                )
                ?? SportsCatalogLoader.shared.prescription(
                    for: recommendation.displayName,
                    rhrBand: rhrBand,
                    bmiCategory: "Any BMI"
                )

            let initialDuration = prescription?.initial.durationMinutes ?? max(10, recommendation.plannedDurationMinutes)
            let targetDuration = prescription?.target.durationMinutes ?? initialDuration
            let initialWeekly = prescription?.initial.daysPerWeek ?? resolvedGoalFrequency(from: userProfile).sessionsPerWeek
            let targetWeekly = prescription?.target.daysPerWeek ?? initialWeekly
            let hasProgression = prescription?.hasProgression ?? (initialDuration != targetDuration || initialWeekly != targetWeekly)

            entries.append(
                FirestoreSportEntry(
                    id: id,
                    displayName: recommendation.displayName,
                    weeklyTargetCount: initialWeekly,
                    completedThisWeek: 0,
                    durationMinutes: initialDuration,
                    weekResetDate: weekReset,
                    phaseStartDate: weekReset,
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
        }

        return entries
    }

    private func resolvedRHRBand(profile: UserProfileInput, healthSnapshot: HealthSnapshot?) -> String {
        if healthSnapshot?.restingHeartRateSource == .healthKit,
           let bpm = healthSnapshot?.restingHeartRate {
            if bpm <= 60 { return CurrentRHRBandQuestion.upTo60.sportsJsonBand }
            if bpm <= 75 { return CurrentRHRBandQuestion.from61To75.sportsJsonBand }
            if bpm <= 90 { return CurrentRHRBandQuestion.from76To90.sportsJsonBand }
            return CurrentRHRBandQuestion.above90.sportsJsonBand
        }

        if let band = profile.questionnaireCurrentRHRBand?.sportsJsonBand {
            return band
        }

        if let bpm = healthSnapshot?.restingHeartRate {
            if bpm <= 60 { return CurrentRHRBandQuestion.upTo60.sportsJsonBand }
            if bpm <= 75 { return CurrentRHRBandQuestion.from61To75.sportsJsonBand }
            if bpm <= 90 { return CurrentRHRBandQuestion.from76To90.sportsJsonBand }
            return CurrentRHRBandQuestion.above90.sportsJsonBand
        }

        return CurrentRHRBandQuestion.from61To75.sportsJsonBand
    }

    private func resolvedGoalFrequency(from profile: UserProfileInput) -> WeeklyGoalFrequency {
        switch profile.daysPerWeek {
        case .twoToThree:
            return .twoTimesPerWeek
        case .threeToFour:
            return .threeTimesPerWeek
        case .fourToFive:
            return .fourPlusPerWeek
        case .fiveToSeven:
            return .fourPlusPerWeek
        }
    }

    private func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }
}
