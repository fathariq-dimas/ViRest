import Foundation

struct RuleBasedRecommendationEngine: RecommendationProviding {
    private enum HardFilterMode {
        case strict
        case relaxedBMI
        case relaxedRHRAndBMI
    }

    private struct AccessSelection {
        let noneOnly: Bool
        let equipment: Set<String>
    }

    private struct Candidate {
        let exercise: ExerciseSeedExercise
        let rhrBandRule: ExerciseSeedRHRBandRule
        let bmiRule: ExerciseSeedBMIRule
        let hardFilterMode: HardFilterMode
        let safetyConflicts: [String]
    }

    private struct ScoredCandidate {
        let recommendation: SportRecommendation
        let hardQuality: Double
    }

    private let catalog: ExerciseSeedCatalog

    init(catalog: ExerciseSeedCatalog? = ExerciseSeedLoader.loadCatalog()) {
        self.catalog = catalog ?? ExerciseSeedCatalog(
            rhrBands: [],
            bmiCategories: [],
            environmentOptions: [],
            healthConcernContraindicationOptions: [],
            exercises: []
        )
    }

    func recommend(request: RecommendationRequest) throws -> RecommendationResult {
        guard !catalog.exercises.isEmpty else {
            throw RecommendationError.catalogUnavailable
        }

        let profile = request.userProfile
        let currentRHR = resolvedCurrentRHR(profile: profile, snapshot: request.healthSnapshot)
        let bmiValue = resolvedBMI(profile: profile, snapshot: request.healthSnapshot)
        let bmiCategory = resolvedBMICategory(for: bmiValue)
        let userDuration = durationRange(for: profile.sessionDuration)
        let userDurationOption = profile.sessionDuration
        let userFrequency = frequencyRange(for: profile.daysPerWeek)
        let accessSelection = mappedAccessSelection(profile: profile)
        let concernTags = mappedConcernTags(profile: profile)

        let strictHard = applyHardFilters(
            currentRHR: currentRHR,
            bmiCategory: bmiCategory,
            environment: profile.environment,
            concernTags: concernTags,
            hardFilterMode: .strict
        )

        let hardCandidates: [Candidate]
        let hardMode: HardFilterMode

        if !strictHard.isEmpty {
            hardCandidates = strictHard
            hardMode = .strict
        } else {
            let relaxedBMI = applyHardFilters(
                currentRHR: currentRHR,
                bmiCategory: bmiCategory,
                environment: profile.environment,
                concernTags: concernTags,
                hardFilterMode: .relaxedBMI
            )
            if !relaxedBMI.isEmpty {
                hardCandidates = relaxedBMI
                hardMode = .relaxedBMI
            } else {
                hardCandidates = applyHardFilters(
                    currentRHR: currentRHR,
                    bmiCategory: bmiCategory,
                    environment: profile.environment,
                    concernTags: concernTags,
                    hardFilterMode: .relaxedRHRAndBMI
                )
                hardMode = .relaxedRHRAndBMI
            }
        }

        let strictEquipmentCandidates = hardCandidates.filter {
            let equipmentRequired = Set($0.exercise.equipment.map(normalizedToken))
            return isStrictEquipmentCompatible(
                accessSelection: accessSelection,
                equipmentRequired: equipmentRequired
            )
        }
        let usedEquipmentRelaxation = strictEquipmentCandidates.isEmpty && !hardCandidates.isEmpty
        let equipmentPhaseCandidates = usedEquipmentRelaxation ? hardCandidates : strictEquipmentCandidates

        let safeCandidates = equipmentPhaseCandidates.filter { $0.safetyConflicts.isEmpty }
        guard !safeCandidates.isEmpty else {
            throw RecommendationError.noSafeRecommendation
        }

        let rankingPool = safeCandidates

        let scored = rankingPool
            .map {
                score(
                    candidate: $0,
                    currentRHR: currentRHR,
                    bmiCategory: bmiCategory,
                    preferredDuration: userDuration,
                    userDurationOption: userDurationOption,
                    preferredFrequency: userFrequency,
                    accessSelection: accessSelection,
                    preferredTime: profile.preferredTime
                )
            }
            .sorted { lhs, rhs in
                if lhs.hardQuality != rhs.hardQuality {
                    return lhs.hardQuality > rhs.hardQuality
                }
                if lhs.recommendation.score != rhs.recommendation.score {
                    return lhs.recommendation.score > rhs.recommendation.score
                }
                return normalizedToken(lhs.recommendation.displayName) < normalizedToken(rhs.recommendation.displayName)
            }

        var rankedRecommendations = Array(scored.prefix(3)).map(\.recommendation)
        if rankedRecommendations.count < 3 {
            let existingNames = Set(rankedRecommendations.map { normalizedToken($0.displayName) })
            let supplemental = supplementalRecommendations(
                excluding: existingNames,
                count: 3 - rankedRecommendations.count,
                currentRHR: currentRHR,
                plannedDurationMinutes: profile.sessionDuration.recommendedMinutes,
                candidates: safeCandidates
            )
            rankedRecommendations.append(contentsOf: supplemental)
        }

        guard let primary = rankedRecommendations.first else {
            throw RecommendationError.noSafeRecommendation
        }
        let alternatives = Array(rankedRecommendations.dropFirst().prefix(2))

        let weeklyPlan = WeeklyPlan(
            weekStartDate: request.weekStartDate.startOfWeek(),
            goalFrequency: request.goalFrequency,
            primaryRecommendation: primary,
            alternatives: alternatives,
            sessions: generateSessions(primary: primary, request: request),
            notes: buildPlanNotes(
                profile: profile,
                hardFilterMode: hardMode,
                usedEquipmentRelaxation: usedEquipmentRelaxation
            )
        )

        return RecommendationResult(
            generatedAt: Date(),
            primary: primary,
            alternatives: alternatives,
            weeklyPlan: weeklyPlan
        )
    }

    private func applyHardFilters(
        currentRHR: Int,
        bmiCategory: String,
        environment: SportEnvironment,
        concernTags: Set<String>,
        hardFilterMode: HardFilterMode
    ) -> [Candidate] {
        var candidates: [Candidate] = []

        for exercise in catalog.exercises {
            guard isEnvironmentMatch(environment, exerciseEnvironment: exercise.environment) else {
                continue
            }

            let matchedRHRRules: [ExerciseSeedRHRBandRule]
            switch hardFilterMode {
            case .strict, .relaxedBMI:
                matchedRHRRules = exercise.rhrBands.filter { rhrBandContains($0.rhrBand, bpm: currentRHR) }
            case .relaxedRHRAndBMI:
                matchedRHRRules = exercise.rhrBands
            }

            guard !matchedRHRRules.isEmpty else {
                continue
            }

            for rhrRule in matchedRHRRules {
                guard let matchedBMIRule = matchedBMIRule(
                    from: rhrRule.bmiRules,
                    bmiCategory: bmiCategory,
                    hardFilterMode: hardFilterMode
                ) else {
                    continue
                }

                let safetyConflicts = matchedBMIRule.contraindications.filter {
                    concernTags.contains(normalizedToken($0))
                }
                candidates.append(
                    Candidate(
                        exercise: exercise,
                        rhrBandRule: rhrRule,
                        bmiRule: matchedBMIRule,
                        hardFilterMode: hardFilterMode,
                        safetyConflicts: safetyConflicts
                    )
                )
            }
        }

        let deduped = deduplicateByExercise(candidates)
        return deduped
    }

    private func deduplicateByExercise(_ candidates: [Candidate]) -> [Candidate] {
        var bestByExercise: [String: Candidate] = [:]

        for candidate in candidates {
            let key = candidate.exercise.id
            guard let existing = bestByExercise[key] else {
                bestByExercise[key] = candidate
                continue
            }

            let existingRank = hardModeRank(existing.hardFilterMode)
            let candidateRank = hardModeRank(candidate.hardFilterMode)
            if candidateRank < existingRank {
                bestByExercise[key] = candidate
            } else if candidateRank == existingRank,
                      candidate.safetyConflicts.count < existing.safetyConflicts.count {
                bestByExercise[key] = candidate
            }
        }

        return Array(bestByExercise.values)
    }

    private func hardModeRank(_ mode: HardFilterMode) -> Int {
        switch mode {
        case .strict: return 0
        case .relaxedBMI: return 1
        case .relaxedRHRAndBMI: return 2
        }
    }

    private func matchedBMIRule(
        from rules: [ExerciseSeedBMIRule],
        bmiCategory: String,
        hardFilterMode: HardFilterMode
    ) -> ExerciseSeedBMIRule? {
        if let exact = rules.first(where: { normalizedToken($0.bmiCategory) == normalizedToken(bmiCategory) }) {
            return exact
        }

        if let any = rules.first(where: { normalizedToken($0.bmiCategory) == normalizedToken("Any BMI") }) {
            return any
        }

        switch hardFilterMode {
        case .strict:
            return nil
        case .relaxedBMI, .relaxedRHRAndBMI:
            return rules.first
        }
    }

    private func score(
        candidate: Candidate,
        currentRHR: Int,
        bmiCategory: String,
        preferredDuration: ClosedRange<Int>,
        userDurationOption: SessionDurationOption,
        preferredFrequency: ClosedRange<Int>,
        accessSelection: AccessSelection,
        preferredTime: PreferredTime
    ) -> ScoredCandidate {
        let durationRange = candidate.bmiRule.durationPrescription.entryRange ?? preferredDuration
        let frequencyRange = candidate.bmiRule.weeklyFrequencyPrescription.entryRange ?? preferredFrequency

        let durationScore = rangeSimilarity(preferredDuration, durationRange, maxGap: 80)
        let frequencyScore = rangeSimilarity(preferredFrequency, frequencyRange, maxGap: 6)

        let equipmentRequired = Set(candidate.exercise.equipment.map(normalizedToken))
        let equipmentScore = equipmentFit(
            accessSelection: accessSelection,
            equipmentRequired: equipmentRequired
        )
        let preferredTimeScore = preferredTimeFit(
            preferredTime: preferredTime,
            exerciseEnvironment: candidate.exercise.environment
        )
        let rhrMatchScore = rhrFit(rhrBand: candidate.rhrBandRule.rhrBand, currentRHR: currentRHR)
        let bmiMatchScore = bmiFit(ruleCategory: candidate.bmiRule.bmiCategory, userCategory: bmiCategory)

        let strictEquipmentCompatible = isStrictEquipmentCompatible(
            accessSelection: accessSelection,
            equipmentRequired: equipmentRequired
        )

        var hardQuality = baseHardQuality(for: candidate.hardFilterMode)
        if !strictEquipmentCompatible {
            hardQuality -= 0.03
        }
        hardQuality = max(0.05, min(1.0, hardQuality))

        let score =
            hardQuality * 50 +
            rhrMatchScore * 12 +
            bmiMatchScore * 8 +
            durationScore * 16 +
            frequencyScore * 10 +
            equipmentScore * 2 +
            preferredTimeScore * 2

        let reasons = buildReasons(
            candidate: candidate,
            currentRHR: currentRHR,
            bmiCategory: bmiCategory,
            preferredDuration: preferredDuration,
            recommendedDuration: durationRange,
            preferredFrequency: preferredFrequency,
            recommendedFrequency: frequencyRange,
            equipmentScore: equipmentScore,
            strictEquipmentCompatible: strictEquipmentCompatible,
            preferredTime: preferredTime
        )

        let plannedDurationOption = compromiseDurationOption(
            userOption: userDurationOption,
            recommendationRange: durationRange
        )
        let plannedDuration = plannedDurationOption.recommendedMinutes
        let recommendation = SportRecommendation(
            activity: activityType(forExerciseName: candidate.exercise.exercise),
            displayName: candidate.exercise.exercise,
            score: score,
            plannedDurationMinutes: plannedDuration,
            targetRPE: targetRPE(for: currentRHR),
            reasons: reasons,
            cautions: candidate.bmiRule.keyCautions
        )

        return ScoredCandidate(recommendation: recommendation, hardQuality: hardQuality)
    }

    private func buildReasons(
        candidate: Candidate,
        currentRHR: Int,
        bmiCategory: String,
        preferredDuration: ClosedRange<Int>,
        recommendedDuration: ClosedRange<Int>,
        preferredFrequency: ClosedRange<Int>,
        recommendedFrequency: ClosedRange<Int>,
        equipmentScore: Double,
        strictEquipmentCompatible: Bool,
        preferredTime: PreferredTime
    ) -> [String] {
        var reasons: [String] = []

        reasons.append("RHR fit: \(candidate.rhrBandRule.rhrBand) (current \(currentRHR) bpm).")
        reasons.append("BMI fit: \(candidate.bmiRule.bmiCategory) rule (you: \(bmiCategory)).")
        reasons.append("Environment fit: \(candidate.exercise.environment).")

        if strictEquipmentCompatible {
            reasons.append("Equipment fit: all required access is available.")
        } else if equipmentScore >= 0.6 {
            reasons.append("Equipment fit: partial match, still feasible with your current access.")
        } else {
            reasons.append("Equipment fit: limited match, shown as an available option.")
        }

        reasons.append("Safety fit: no contraindication overlap detected.")

        reasons.append("Duration fit: \(minutesDescription(recommendedDuration)) vs your \(minutesDescription(preferredDuration)).")
        reasons.append("Frequency fit: \(sessionsDescription(recommendedFrequency)) vs your \(sessionsDescription(preferredFrequency)).")

        if let caution = candidate.bmiRule.keyCautions.first {
            reasons.append("Key caution: \(caution).")
        }

        reasons.append("Preferred time (\(preferredTime.displayName)) is used for scheduling only.")
        return reasons
    }

    private func buildPlanNotes(
        profile: UserProfileInput,
        hardFilterMode: HardFilterMode,
        usedEquipmentRelaxation: Bool
    ) -> [String] {
        var notes: [String] = [
            "Recommendations are generated from sports.json.",
            "Target RHR (\(profile.questionnaireTargetRHRGoal?.displayName ?? "-")) is for tracking only and is not used as a recommendation filter.",
            "Preferred exercise time (\(profile.preferredTime.displayName)) is metadata only."
        ]

        switch hardFilterMode {
        case .strict:
            break
        case .relaxedBMI:
            notes.append("Strict BMI rule produced limited results; BMI matching was relaxed while keeping RHR and environment filters.")
        case .relaxedRHRAndBMI:
            notes.append("Strict hard filters produced limited results; RHR/BMI matching was relaxed to avoid empty recommendations.")
        }

        if usedEquipmentRelaxation {
            notes.append("No exact equipment match found; equipment was treated as soft-fit for best available options.")
        }

        return notes
    }

    private func baseHardQuality(for mode: HardFilterMode) -> Double {
        switch mode {
        case .strict:
            return 1.0
        case .relaxedBMI:
            return 0.92
        case .relaxedRHRAndBMI:
            return 0.84
        }
    }

    private func durationRange(for option: SessionDurationOption) -> ClosedRange<Int> {
        switch option {
        case .tenToTwenty:
            return 10...20
        case .twentyToThirty:
            return 20...30
        case .thirtyToFortyFive:
            return 30...45
        case .fortyFiveToSixty:
            return 45...60
        case .sixtyMinutes:
            return 60...60
        }
    }

    private func frequencyRange(for option: DaysPerWeekAvailability) -> ClosedRange<Int> {
        switch option {
        case .twoToThree:
            return 2...3
        case .threeToFour:
            return 3...4
        case .fourToFive:
            return 4...5
        case .fiveToSeven:
            return 5...7
        }
    }

    private func resolvedCurrentRHR(profile: UserProfileInput, snapshot: HealthSnapshot?) -> Int {
        if snapshot?.restingHeartRateSource == .healthKit,
           let healthKitRHR = snapshot?.restingHeartRate {
            return Int(healthKitRHR.rounded())
        }
        if let questionBand = profile.questionnaireCurrentRHRBand {
            return questionBand.representativeBPM
        }
        if let fallbackRHR = snapshot?.restingHeartRate {
            return Int(fallbackRHR.rounded())
        }
        return 75
    }

    private func resolvedBMI(profile: UserProfileInput, snapshot: HealthSnapshot?) -> Double? {
        let weight = profile.weightKg ?? snapshot?.weightKg
        let heightCm = profile.heightCm ?? snapshot?.heightCm

        if let weight, let heightCm, heightCm > 0 {
            let meters = heightCm / 100
            return weight / (meters * meters)
        }

        if let bmi = snapshot?.bmi, bmi > 0 {
            return bmi
        }

        return nil
    }

    private func resolvedBMICategory(for bmi: Double?) -> String {
        guard let bmi else { return "Any BMI" }
        if bmi < 25 {
            return "Normal"
        }
        if bmi < 30 {
            return "Overweight"
        }
        return "Obese"
    }

    private func isEnvironmentMatch(_ userEnvironment: SportEnvironment, exerciseEnvironment: String) -> Bool {
        let normalizedEnvironment = normalizedToken(exerciseEnvironment)
        switch userEnvironment {
        case .both:
            return true
        case .indoor:
            return normalizedEnvironment == "indoor" || normalizedEnvironment == "both"
        case .outdoor:
            return normalizedEnvironment == "outdoor" || normalizedEnvironment == "both"
        }
    }

    private func rhrBandContains(_ band: String, bpm: Int) -> Bool {
        let lower = band.lowercased()
        let numbers = lower
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }

        if lower.contains("<=") || lower.contains("≤") {
            guard let limit = numbers.first else { return false }
            return bpm <= limit
        }

        if lower.contains(">") {
            guard let limit = numbers.first else { return false }
            return bpm > limit
        }

        if numbers.count >= 2 {
            return bpm >= numbers[0] && bpm <= numbers[1]
        }

        if let single = numbers.first {
            return bpm == single
        }

        return false
    }

    private func mappedAccessSelection(profile: UserProfileInput) -> AccessSelection {
        guard
            let rawOptions = profile.questionnaireAccessOptions,
            !rawOptions.isEmpty
        else {
            return AccessSelection(noneOnly: true, equipment: [])
        }

        let hasNone = rawOptions.contains(.none)
        let nonNone = rawOptions.filter { $0 != .none }

        if hasNone && nonNone.isEmpty {
            return AccessSelection(noneOnly: true, equipment: [])
        }

        let mapped = Set(nonNone.map { accessToken(for: $0) })
        return AccessSelection(noneOnly: false, equipment: mapped)
    }

    private func accessToken(for option: ExerciseAccessOptionQuestion) -> String {
        switch option {
        case .none: return ""
        case .treadmill: return normalizedToken("Treadmill")
        case .walkingShoes: return normalizedToken("Walking shoes")
        case .runningShoes: return normalizedToken("Running shoes")
        case .bicycle: return normalizedToken("Bicycle")
        case .helmet: return normalizedToken("Helmet")
        case .stationaryBike: return normalizedToken("Stationary bike")
        case .recumbentBike: return normalizedToken("Recumbent bike")
        case .ellipticalTrainer: return normalizedToken("Elliptical trainer")
        case .rowingMachine: return normalizedToken("Rowing machine")
        case .swimmingPool: return normalizedToken("Swimming pool")
        case .flotationBelt: return normalizedToken("Flotation belt")
        case .stairClimberMachine: return normalizedToken("Stair climber machine")
        case .stairs: return normalizedToken("Stairs")
        case .nordicWalkingPoles: return normalizedToken("Nordic walking poles")
        case .yogaMat: return normalizedToken("Yoga mat")
        case .stableChair: return normalizedToken("Stable chair")
        case .hikingShoes: return normalizedToken("Hiking shoes")
        }
    }

    private func mappedConcernTags(profile: UserProfileInput) -> Set<String> {
        guard
            let concerns = profile.questionnaireHealthConcerns,
            !concerns.isEmpty
        else {
            return []
        }

        let nonNone = concerns.filter { $0 != .none }
        return Set(nonNone.map { normalizedToken($0.displayName) })
    }

    private func isStrictEquipmentCompatible(
        accessSelection: AccessSelection,
        equipmentRequired: Set<String>
    ) -> Bool {
        if accessSelection.noneOnly {
            return equipmentRequired.isEmpty
        }

        if equipmentRequired.isEmpty {
            return true
        }

        return equipmentRequired.isSubset(of: accessSelection.equipment)
    }

    private func equipmentFit(
        accessSelection: AccessSelection,
        equipmentRequired: Set<String>
    ) -> Double {
        if accessSelection.noneOnly {
            return equipmentRequired.isEmpty ? 1.0 : 0.1
        }

        if equipmentRequired.isEmpty {
            return 0.95
        }

        let matched = accessSelection.equipment.intersection(equipmentRequired)
        if matched.count == equipmentRequired.count {
            return 1.0
        }

        if !matched.isEmpty {
            let ratio = Double(matched.count) / Double(equipmentRequired.count)
            return 0.55 + ratio * 0.35
        }

        return 0.2
    }

    private func preferredTimeFit(preferredTime: PreferredTime, exerciseEnvironment: String) -> Double {
        let env = normalizedToken(exerciseEnvironment)
        switch preferredTime {
        case .morning:
            return env == "outdoor" || env == "both" ? 1.0 : 0.85
        case .midday:
            return env == "indoor" || env == "both" ? 1.0 : 0.85
        case .evening:
            return env == "indoor" || env == "both" ? 0.95 : 0.85
        case .flexible:
            return 0.9
        }
    }

    private func rangeSimilarity(
        _ lhs: ClosedRange<Int>,
        _ rhs: ClosedRange<Int>,
        maxGap: Int
    ) -> Double {
        let overlapLower = max(lhs.lowerBound, rhs.lowerBound)
        let overlapUpper = min(lhs.upperBound, rhs.upperBound)

        if overlapLower <= overlapUpper {
            let overlap = overlapUpper - overlapLower + 1
            let lhsLength = lhs.upperBound - lhs.lowerBound + 1
            let rhsLength = rhs.upperBound - rhs.lowerBound + 1
            let denom = max(lhsLength, rhsLength)
            let overlapRatio = Double(overlap) / Double(denom)
            return 0.75 + overlapRatio * 0.25
        }

        let gap = min(abs(lhs.lowerBound - rhs.upperBound), abs(rhs.lowerBound - lhs.upperBound))
        let gapRatio = min(1.0, Double(gap) / Double(max(1, maxGap)))
        return max(0.2, 0.7 - gapRatio * 0.5)
    }

    private func targetRPE(for currentRHR: Int) -> RPERange {
        switch currentRHR {
        case ..<61:
            return RPERange(min: 4, max: 6)
        case 61..<76:
            return RPERange(min: 3, max: 5)
        case 76..<91:
            return RPERange(min: 3, max: 4)
        default:
            return RPERange(min: 2, max: 3)
        }
    }

    private func compromiseDurationOption(
        userOption: SessionDurationOption,
        recommendationRange: ClosedRange<Int>
    ) -> SessionDurationOption {
        let recommendationOption = nearestDurationOption(for: recommendationRange)
        let userIndex = durationOptionIndex(userOption)
        let recommendationIndex = durationOptionIndex(recommendationOption)
        let diff = abs(userIndex - recommendationIndex)

        if diff <= 1 {
            return recommendationOption
        }

        let midpointIndex = Int(round(Double(userIndex + recommendationIndex) / 2.0))
        return durationOption(at: midpointIndex)
    }

    private func nearestDurationOption(for range: ClosedRange<Int>) -> SessionDurationOption {
        let options = SessionDurationOption.allCases
        var best = options.first ?? .twentyToThirty
        var bestScore = -1.0

        for option in options {
            let optionRange = durationRange(for: option)
            let score = rangeSimilarity(range, optionRange, maxGap: 80)
            if score > bestScore {
                bestScore = score
                best = option
            }
        }

        return best
    }

    private func durationOptionIndex(_ option: SessionDurationOption) -> Int {
        SessionDurationOption.allCases.firstIndex(of: option) ?? 0
    }

    private func durationOption(at index: Int) -> SessionDurationOption {
        let options = SessionDurationOption.allCases
        guard !options.isEmpty else { return .twentyToThirty }
        let safeIndex = min(max(index, 0), options.count - 1)
        return options[safeIndex]
    }

    private func generateSessions(primary: SportRecommendation, request: RecommendationRequest) -> [SessionPlan] {
        let capByUserAvailability = request.userProfile.daysPerWeek.targetSessions
        let requested = request.goalFrequency.sessionsPerWeek
        let totalSessions = max(1, min(requested, capByUserAvailability))

        return (1...totalSessions).map { number in
            SessionPlan(
                sessionNumber: number,
                activity: primary.activity,
                preferredTime: request.userProfile.preferredTime,
                plannedDurationMinutes: primary.plannedDurationMinutes,
                targetRPE: primary.targetRPE
            )
        }
    }

    private func supplementalRecommendations(
        excluding existingNames: Set<String>,
        count: Int,
        currentRHR: Int,
        plannedDurationMinutes: Int,
        candidates: [Candidate]
    ) -> [SportRecommendation] {
        guard count > 0 else { return [] }

        var usedNames = existingNames
        var results: [SportRecommendation] = []

        let prioritized = candidates.sorted { lhs, rhs in
            let lhsRHR = rhrBandContains(lhs.rhrBandRule.rhrBand, bpm: currentRHR)
            let rhsRHR = rhrBandContains(rhs.rhrBandRule.rhrBand, bpm: currentRHR)
            if lhsRHR != rhsRHR {
                return lhsRHR && !rhsRHR
            }
            return normalizedToken(lhs.exercise.exercise) < normalizedToken(rhs.exercise.exercise)
        }

        for candidate in prioritized {
            let key = normalizedToken(candidate.exercise.exercise)
            guard !usedNames.contains(key) else { continue }
            usedNames.insert(key)

            let fallbackScore = max(18, 35 - (results.count * 5))
            results.append(
                SportRecommendation(
                    activity: activityType(forExerciseName: candidate.exercise.exercise),
                    displayName: candidate.exercise.exercise,
                    score: Double(fallbackScore),
                    plannedDurationMinutes: plannedDurationMinutes,
                    targetRPE: targetRPE(for: currentRHR),
                    reasons: [
                        "Added as additional option to provide multiple matches.",
                        "Ranked below your highest-fit recommendations."
                    ],
                    cautions: candidate.bmiRule.keyCautions
                )
            )

            if results.count >= count {
                break
            }
        }

        return results
    }

    private func rhrFit(rhrBand: String, currentRHR: Int) -> Double {
        if rhrBandContains(rhrBand, bpm: currentRHR) {
            return 1.0
        }

        guard let parsedRange = parsedRHRRange(from: rhrBand) else {
            return 0.65
        }

        let gap: Int
        if currentRHR < parsedRange.lowerBound {
            gap = parsedRange.lowerBound - currentRHR
        } else if currentRHR > parsedRange.upperBound {
            gap = currentRHR - parsedRange.upperBound
        } else {
            gap = 0
        }

        let normalizedGap = min(1.0, Double(gap) / 40.0)
        return max(0.3, 1.0 - normalizedGap)
    }

    private func bmiFit(ruleCategory: String, userCategory: String) -> Double {
        let normalizedRule = normalizedToken(ruleCategory)
        let normalizedUser = normalizedToken(userCategory)
        if normalizedRule == normalizedUser {
            return 1.0
        }
        if normalizedRule == normalizedToken("Any BMI") {
            return 0.82
        }
        return 0.6
    }

    private func parsedRHRRange(from band: String) -> ClosedRange<Int>? {
        let lower = band.lowercased()
        let numbers = lower
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }

        if lower.contains("<=") || lower.contains("≤") {
            guard let upper = numbers.first else { return nil }
            return 0...upper
        }

        if lower.contains(">") {
            guard let lowerBound = numbers.first else { return nil }
            return (lowerBound + 1)...220
        }

        if numbers.count >= 2 {
            return numbers[0]...numbers[1]
        }

        if let value = numbers.first {
            return value...value
        }

        return nil
    }

    private func activityType(forExerciseName name: String) -> ActivityType {
        switch normalizedToken(name) {
        case normalizedToken("Brisk walking"): return .briskWalking
        case normalizedToken("Trail walking"): return .trailWalking
        case normalizedToken("Nordic walking"): return .nordicWalking
        case normalizedToken("Flat walking"): return .flatWalking
        case normalizedToken("Walking"): return .walkingGeneral
        case normalizedToken("Interval walking"): return .intervalWalking
        case normalizedToken("Jogging"): return .jogging
        case normalizedToken("Run-walk intervals"): return .runWalkIntervals
        case normalizedToken("Road cycling"): return .roadCycling
        case normalizedToken("Stationary cycling"): return .stationaryCycling
        case normalizedToken("Recumbent cycling"): return .recumbentCycling
        case normalizedToken("Elliptical trainer"): return .ellipticalTrainer
        case normalizedToken("Rowing machine"): return .rowingMachineCardio
        case normalizedToken("Lap swimming"): return .lapSwimming
        case normalizedToken("Dance cardio"): return .danceCardio
        case normalizedToken("Stair climber"): return .stairClimber
        case normalizedToken("Stair walking"): return .stairWalking
        case normalizedToken("Pool walking"): return .poolWalking
        case normalizedToken("Aqua jogging"): return .aquaJogging
        case normalizedToken("Vinyasa yoga"): return .vinyasaYoga
        case normalizedToken("Yoga"): return .yoga
        case normalizedToken("Restorative yoga"): return .restorativeYoga
        case normalizedToken("Chair marching"): return .chairMarching
        case normalizedToken("Chair aerobics"): return .chairAerobics
        case normalizedToken("Tai chi"): return .taiChi
        default: return .walking
        }
    }

    private func minutesDescription(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)-\(range.upperBound) min/session"
    }

    private func sessionsDescription(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)-\(range.upperBound) days/week"
    }

    private func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }
}
