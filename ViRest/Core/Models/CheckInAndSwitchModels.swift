import Foundation

enum SwitchReason: String, Codable, CaseIterable, Identifiable {
    case notSuitable = "not_suitable"
    case bored
    case scheduleMismatch = "schedule_mismatch"
    case equipmentMismatch = "equipment_mismatch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notSuitable:
            return "Not suitable"
        case .bored:
            return "Bored"
        case .scheduleMismatch:
            return "Schedule mismatch"
        case .equipmentMismatch:
            return "Equipment mismatch"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = SwitchReason(rawValue: raw) ?? .notSuitable
    }
}

enum SwitchOrigin: String, Codable {
    case manualProfile = "manual_profile"
    case feedbackRed = "feedback_red"
    case feedbackYellowPattern = "feedback_yellow_pattern"

    var bypassesCooldown: Bool {
        self == .feedbackRed
    }
}

struct SuitabilityFeedbackInput: Equatable {
    var difficulty: ActivityDifficulty
    var fatigue: FatigueLevel
    var painLevel: PainLevel
    var discomfortAreas: [DiscomfortArea]
}

struct CheckInHistoryEntry: Codable, Identifiable, Equatable {
    var id: String?
    var sportId: String
    var sportName: String
    var createdAt: Date
    var durationMinutes: Int
    var difficulty: ActivityDifficulty?
    var fatigue: FatigueLevel?
    var painLevel: PainLevel?
    var discomfortAreas: [DiscomfortArea]
    var zone: SuitabilityZone?
    var decision: ProgressionDecision?

    var date: Date { createdAt }

    init(
        id: String? = nil,
        sportId: String,
        sportName: String,
        createdAt: Date = Date(),
        durationMinutes: Int,
        difficulty: ActivityDifficulty? = nil,
        fatigue: FatigueLevel? = nil,
        painLevel: PainLevel? = nil,
        discomfortAreas: [DiscomfortArea] = [],
        zone: SuitabilityZone? = nil,
        decision: ProgressionDecision? = nil
    ) {
        self.id = id
        self.sportId = sportId
        self.sportName = sportName
        self.createdAt = createdAt
        self.durationMinutes = durationMinutes
        self.difficulty = difficulty
        self.fatigue = fatigue
        self.painLevel = painLevel
        self.discomfortAreas = discomfortAreas
        self.zone = zone
        self.decision = decision
    }

}

enum SportSwitchError: LocalizedError {
    case reasonRequired
    case cooldownActive(TimeInterval)
    case noCandidateAvailable
    case sportMarkedNotSuitable
    case invalidPlanState

    var errorDescription: String? {
        switch self {
        case .reasonRequired:
            return "Switch reason is required."
        case .cooldownActive(let remaining):
            let days = Int(ceil(remaining / 86_400))
            return "You can switch again in \(max(days, 1)) day(s)."
        case .noCandidateAvailable:
            return "No safe switch candidate is available right now."
        case .sportMarkedNotSuitable:
            return "This sport is marked as not suitable from your previous feedback."
        case .invalidPlanState:
            return "No active sport plan found."
        }
    }
}

struct SportSwitchOutcome {
    var updatedPlan: FirestoreSportPlan
    var selectedSport: FirestoreSportEntry
}
