import Foundation


enum WeeklyGoalFrequency: String, Codable, CaseIterable, Identifiable {
    
    case oncePerWeek = "once_per_week"
    case twoTimesPerWeek = "two_times_per_week"
    case threeTimesPerWeek = "three_times_per_week"
    case fourPlusPerWeek = "four_plus_per_week"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oncePerWeek: return "1 activity"
        case .twoTimesPerWeek: return "2 activities"
        case .threeTimesPerWeek: return "3 activities"
        case .fourPlusPerWeek: return "4+ activities"
        }
    }

    var sessionsPerWeek: Int {
        switch self {
        case .oncePerWeek: return 1
        case .twoTimesPerWeek: return 2
        case .threeTimesPerWeek: return 3
        case .fourPlusPerWeek: return 5
        }
    }

    var weeklySummary: String {
        "\(displayName) / week"
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }
}

struct RPERange: Codable, Equatable {
    var min: Int
    var max: Int

    init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }

    func clamped(maximum: Int) -> RPERange {
        RPERange(min: Swift.min(min, maximum), max: Swift.min(max, maximum))
    }
}

struct SessionPlan: Codable, Identifiable, Equatable {
    var id: UUID
    var sessionNumber: Int
    var activity: ActivityType
    // Legacy field kept for backward compatibility with older stored plans.
    var scheduledDay: Weekday?
    var preferredTime: PreferredTime
    var plannedDurationMinutes: Int
    var targetRPE: RPERange
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        sessionNumber: Int,
        activity: ActivityType,
        scheduledDay: Weekday? = nil,
        preferredTime: PreferredTime,
        plannedDurationMinutes: Int,
        targetRPE: RPERange,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.sessionNumber = sessionNumber
        self.activity = activity
        self.scheduledDay = scheduledDay
        self.preferredTime = preferredTime
        self.plannedDurationMinutes = plannedDurationMinutes
        self.targetRPE = targetRPE
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }

    var sessionTitle: String {
        "Session \(sessionNumber)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionNumber
        case activity
        case scheduledDay
        case preferredTime
        case plannedDurationMinutes
        case targetRPE
        case completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        activity = try container.decode(ActivityType.self, forKey: .activity)
        scheduledDay = try container.decodeIfPresent(Weekday.self, forKey: .scheduledDay)
        preferredTime = try container.decode(PreferredTime.self, forKey: .preferredTime)
        plannedDurationMinutes = try container.decode(Int.self, forKey: .plannedDurationMinutes)
        targetRPE = try container.decode(RPERange.self, forKey: .targetRPE)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)

        if let decoded = try container.decodeIfPresent(Int.self, forKey: .sessionNumber) {
            sessionNumber = decoded
        } else if let legacyDay = scheduledDay {
            sessionNumber = max(1, legacyDay.rawValue)
        } else {
            sessionNumber = 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionNumber, forKey: .sessionNumber)
        try container.encode(activity, forKey: .activity)
        try container.encodeIfPresent(scheduledDay, forKey: .scheduledDay)
        try container.encode(preferredTime, forKey: .preferredTime)
        try container.encode(plannedDurationMinutes, forKey: .plannedDurationMinutes)
        try container.encode(targetRPE, forKey: .targetRPE)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}

struct WeeklyPlan: Codable, Identifiable, Equatable {
    var id: UUID
    var generatedAt: Date
    var weekStartDate: Date
    var goalFrequency: WeeklyGoalFrequency
    var primaryRecommendation: SportRecommendation
    var alternatives: [SportRecommendation]
    var sessions: [SessionPlan]
    var notes: [String]

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        weekStartDate: Date,
        goalFrequency: WeeklyGoalFrequency,
        primaryRecommendation: SportRecommendation,
        alternatives: [SportRecommendation],
        sessions: [SessionPlan],
        notes: [String] = []
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.weekStartDate = weekStartDate
        self.goalFrequency = goalFrequency
        self.primaryRecommendation = primaryRecommendation
        self.alternatives = alternatives
        self.sessions = sessions
        self.notes = notes
    }
}

enum ActivityDifficulty: String, Codable, CaseIterable, Identifiable, Hashable {
    case veryEasy = "very_easy"
    case easy
    case moderate
    case hard
    case veryHard = "very_hard"
    case tooExhausting = "too_exhausting"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .veryEasy: return "Very easy"
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .veryHard: return "Very hard"
        case .tooExhausting: return "Too exhausting"
        }
    }
}

enum FatigueLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case notTired = "not_tired"
    case slightlyTired = "slightly_tired"
    case moderatelyTired = "moderately_tired"
    case veryTired = "very_tired"
    case completelyExhausted = "completely_exhausted"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notTired: return "Not tired"
        case .slightlyTired: return "Slightly tired"
        case .moderatelyTired: return "Moderately tired"
        case .veryTired: return "Very tired"
        case .completelyExhausted: return "Completely exhausted"
        }
    }
}

enum PainLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case noPain = "no_pain"
    case mildDiscomfort = "mild_discomfort"
    case moderatePain = "moderate_pain"
    case strongPain = "strong_pain"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noPain: return "No pain"
        case .mildDiscomfort: return "Mild discomfort"
        case .moderatePain: return "Moderate pain"
        case .strongPain: return "Strong pain"
        }
    }
}

enum DiscomfortArea: String, Codable, CaseIterable, Identifiable {
    case arms
    case shoulders
    case back
    case legs
    case neck
    case joints
    case breathing
    case other

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

struct SessionCheckInInput: Codable, Equatable {
    var sessionId: UUID
    var checkInDate: Date
    var activityDifficulty: ActivityDifficulty
    var fatigueLevel: FatigueLevel
    var painLevel: PainLevel
    var discomfortAreas: [DiscomfortArea]
    var notes: String
}

struct SessionCheckIn: Codable, Identifiable, Equatable {
    var id: UUID
    var sessionId: UUID
    var checkInDate: Date
    var activity: ActivityType
    var actualDurationMinutes: Int
    var activityDifficulty: ActivityDifficulty
    var fatigueLevel: FatigueLevel
    var painLevel: PainLevel
    var discomfortAreas: [DiscomfortArea]
    var notes: String

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        checkInDate: Date,
        activity: ActivityType,
        actualDurationMinutes: Int,
        activityDifficulty: ActivityDifficulty,
        fatigueLevel: FatigueLevel,
        painLevel: PainLevel,
        discomfortAreas: [DiscomfortArea],
        notes: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.checkInDate = checkInDate
        self.activity = activity
        self.actualDurationMinutes = actualDurationMinutes
        self.activityDifficulty = activityDifficulty
        self.fatigueLevel = fatigueLevel
        self.painLevel = painLevel
        self.discomfortAreas = discomfortAreas
        self.notes = notes
    }
}

enum SuitabilityZone: String, Codable {
    case green
    case yellow
    case red
}

enum ProgressionDecision: String, Codable {
    case keep
    case keepAdjusted = "keep_adjusted"
    case offerSwitch = "offer_switch"
    case offerSwitchNow = "offer_switch_now"
    case deloadNextSession = "deload_next_session"
    case downgradeIntensity = "downgrade_intensity"
    case reduceVolume = "reduce_volume"
    case switchAlternative = "switch_alternative"
    case progress

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ProgressionDecision(rawValue: raw) ?? .keep
    }
}

struct SuitabilityAssessment: Codable, Equatable {
    var zone: SuitabilityZone
    var score: Double
    var reasons: [String]
    var decision: ProgressionDecision
    var recommendationText: String
}

struct PlanAdjustmentResult: Equatable {
    var assessment: SuitabilityAssessment
    var updatedPlan: WeeklyPlan
}
