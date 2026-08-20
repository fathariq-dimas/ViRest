import Foundation

struct SportRecommendation: Codable, Identifiable, Equatable {
    var id: UUID
    var activity: ActivityType
    var displayName: String
    var score: Double
    var plannedDurationMinutes: Int
    var targetRPE: RPERange
    var reasons: [String]
    var cautions: [String]

    init(
        id: UUID = UUID(),
        activity: ActivityType,
        displayName: String,
        score: Double,
        plannedDurationMinutes: Int,
        targetRPE: RPERange,
        reasons: [String],
        cautions: [String] = []
    ) {
        self.id = id
        self.activity = activity
        self.displayName = displayName
        self.score = score
        self.plannedDurationMinutes = plannedDurationMinutes
        self.targetRPE = targetRPE
        self.reasons = reasons
        self.cautions = cautions
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case activity
        case displayName
        case score
        case plannedDurationMinutes
        case targetRPE
        case reasons
        case cautions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        activity = try container.decode(ActivityType.self, forKey: .activity)
        displayName = try container.decode(String.self, forKey: .displayName)
        score = try container.decode(Double.self, forKey: .score)
        plannedDurationMinutes = try container.decode(Int.self, forKey: .plannedDurationMinutes)
        targetRPE = try container.decode(RPERange.self, forKey: .targetRPE)
        reasons = try container.decode([String].self, forKey: .reasons)
        cautions = try container.decodeIfPresent([String].self, forKey: .cautions) ?? []
    }
}

struct RecommendationRequest {
    var userProfile: UserProfileInput
    var healthSnapshot: HealthSnapshot?
    var goalFrequency: WeeklyGoalFrequency
    var weekStartDate: Date
}

struct RecommendationResult: Equatable {
    var generatedAt: Date
    var primary: SportRecommendation
    var alternatives: [SportRecommendation]
    var weeklyPlan: WeeklyPlan
}

enum RecommendationError: LocalizedError, Equatable {
    case catalogUnavailable
    case noSafeRecommendation

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            "Exercise recommendations are temporarily unavailable. Please try again later."
        case .noSafeRecommendation:
            "No safe exercise match was found for your current answers. Please review your health information or seek professional guidance."
        }
    }
}
