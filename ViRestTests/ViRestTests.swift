import Foundation
import Testing
@testable import ViRest

struct ViRestTests {
    @Test("Progression levels use the documented session thresholds")
    func progressionThresholds() {
        #expect(ProgressionLevel.from(completedSessions: 0) == .level1)
        #expect(ProgressionLevel.from(completedSessions: 9) == .level1)
        #expect(ProgressionLevel.from(completedSessions: 10) == .level2)
        #expect(ProgressionLevel.from(completedSessions: 230) == .level10)
    }

    @Test("Widget snapshots preserve health and plan values")
    func widgetSnapshotRoundTrip() throws {
        let snapshot = ViRestWidgetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_000),
            latestRestingHR: 64,
            targetRestingHR: 60,
            activeSportName: "Walking",
            completedSessions: 1,
            targetSessions: 3
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ViRestWidgetSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test("Recommendation engine refuses a catalog with only contraindicated options")
    func contraindicatedCatalogDoesNotFallback() {
        let durationPhase = ExerciseSeedDurationPhase(minMinutes: 20, maxMinutes: 30)
        let duration = ExerciseSeedDurationPrescription(
            isProgression: false,
            standardPhase: durationPhase,
            startPhase: nil,
            targetPhase: nil
        )
        let frequencyPhase = ExerciseSeedWeeklyFrequencyPhase(minDaysPerWeek: 2, maxDaysPerWeek: 3)
        let frequency = ExerciseSeedWeeklyFrequencyPrescription(
            isProgression: false,
            standardPhase: frequencyPhase,
            startPhase: nil,
            targetPhase: nil
        )
        let bmiRule = ExerciseSeedBMIRule(
            bmiCategory: "Any BMI",
            keyCautions: [],
            contraindications: ["Chest pain during activity"],
            durationPrescription: duration,
            weeklyFrequencyPrescription: frequency
        )
        let catalog = ExerciseSeedCatalog(
            rhrBands: ["61-75"],
            bmiCategories: ["Any BMI"],
            environmentOptions: ["both"],
            healthConcernContraindicationOptions: ["Chest pain during activity"],
            exercises: [
                ExerciseSeedExercise(
                    exercise: "Unsafe exercise",
                    environment: "both",
                    impactLevel: "low",
                    equipment: [],
                    rhrBands: [ExerciseSeedRHRBandRule(rhrBand: "61-75", bmiRules: [bmiRule])]
                )
            ]
        )
        let profile = UserProfileInput(
            questionnaireCurrentRHRBand: .from61To75,
            questionnaireHealthConcerns: [.chestPainDuringActivity],
            environment: .both,
            questionnaireAccessOptions: [.none]
        )
        let request = RecommendationRequest(
            userProfile: profile,
            healthSnapshot: nil,
            goalFrequency: .twoTimesPerWeek,
            weekStartDate: Date(timeIntervalSince1970: 0)
        )

        #expect(throws: RecommendationError.noSafeRecommendation) {
            try RuleBasedRecommendationEngine(catalog: catalog).recommend(request: request)
        }
    }

    @Test("Firestore check-in DTO round-trips through the domain model")
    func firestoreCheckInDTOMapsWithoutFirebaseInTheDomainModel() {
        let entry = CheckInHistoryEntry(
            id: nil,
            sportId: "walking",
            sportName: "Walking",
            createdAt: Date(timeIntervalSince1970: 1_000),
            durationMinutes: 25,
            difficulty: .moderate,
            fatigue: .slightlyTired,
            painLevel: .noPain,
            discomfortAreas: [],
            zone: .green,
            decision: .keep
        )

        #expect(FirestoreCheckInDTO(entry: entry).toDomain() == entry)
    }
}
