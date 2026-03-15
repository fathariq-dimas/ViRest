import Foundation

enum BadgeType: String, Codable, CaseIterable, Identifiable {
    case firstCheckIn = "first_check_in"
    case streakThree = "streak_three"
    case consistencyTen = "consistency_ten"
    case activitySeven = "activity_seven"
    case activityTwenty = "activity_twenty"
    case streakSeven = "streak_seven"
    case painFreeFive = "pain_free_five"
    case varietyThree = "variety_three"
    case varietySix = "variety_six"
    case activityFifty = "activity_fifty"
    case streakFourteen = "streak_fourteen"
    case painFreeFifteen = "pain_free_fifteen"
    case varietyTen = "variety_ten"
    case activityHundred = "activity_hundred"
    case streakThirty = "streak_thirty"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstCheckIn: return "First Move"
        case .streakThree: return "3-Day Streak"
        case .consistencyTen: return "Consistency Builder"
        case .activitySeven: return "Activity Explorer"
        case .activityTwenty: return "Momentum Driver"
        case .streakSeven: return "7-Day Streak"
        case .painFreeFive: return "Smooth Sessions"
        case .varietyThree: return "Variety Seeker"
        case .varietySix: return "Variety Master"
        case .activityFifty: return "Half-Century"
        case .streakFourteen: return "14-Day Streak"
        case .painFreeFifteen: return "Pain-Free Hero"
        case .varietyTen: return "Activity Collector"
        case .activityHundred: return "Century Club"
        case .streakThirty: return "30-Day Streak"
        }
    }

    var iconName: String {
        switch self {
        case .firstCheckIn:
            return "sparkles"
        case .streakThree:
            return "flame.fill"
        case .consistencyTen:
            return "target"
        case .activitySeven:
            return "figure.walk"
        case .activityTwenty:
            return "bolt.heart.fill"
        case .streakSeven:
            return "flame.circle.fill"
        case .painFreeFive:
            return "cross.case.fill"
        case .varietyThree:
            return "circle.grid.3x3.fill"
        case .varietySix:
            return "app.badge.fill"
        case .activityFifty:
            return "figure.run"
        case .streakFourteen:
            return "calendar"
        case .painFreeFifteen:
            return "heart.text.square.fill"
        case .varietyTen:
            return "square.grid.2x2.fill"
        case .activityHundred:
            return "rosette"
        case .streakThirty:
            return "trophy.fill"
        }
    }
}

struct BadgeEarned: Codable, Identifiable, Equatable {
    var id: UUID
    var type: BadgeType
    var earnedAt: Date

    init(id: UUID = UUID(), type: BadgeType, earnedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.earnedAt = earnedAt
    }
}

enum BadgeCriterionKind: String, Codable, CaseIterable {
    case totalActivities = "total_activities"
    case streakDays = "streak_days"
    case painFreeSessions = "pain_free_sessions"
    case uniqueActivities = "unique_activities"
    // Legacy compatibility only. New criteria generation no longer uses time-based goals.
    case longestSessionMinutes = "longest_session_minutes"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = BadgeCriterionKind(rawValue: raw) ?? .totalActivities
    }

    var title: String {
        switch self {
        case .totalActivities:
            return "Total Activities"
        case .streakDays:
            return "Activity Streak"
        case .painFreeSessions:
            return "Pain-Free Activities"
        case .uniqueActivities:
            return "Activity Variety"
        case .longestSessionMinutes:
            return "Activity Milestone"
        }
    }

    func progressText(current: Int, target: Int) -> String {
        switch self {
        case .streakDays:
            return "\(current)/\(target) days"
        default:
            return "\(current)/\(target) activities"
        }
    }

    var isLegacyTimeBased: Bool {
        self == .longestSessionMinutes
    }
}

struct BadgeCriterion: Codable, Identifiable, Equatable {
    var id: UUID
    var badgeType: BadgeType
    var kind: BadgeCriterionKind
    var targetValue: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        badgeType: BadgeType,
        kind: BadgeCriterionKind,
        targetValue: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.badgeType = badgeType
        self.kind = kind
        self.targetValue = targetValue
        self.createdAt = createdAt
    }

    var summary: String {
        switch kind {
        case .totalActivities:
            return "Complete \(targetValue) activities."
        case .streakDays:
            return "Maintain a \(targetValue)-day active streak."
        case .painFreeSessions:
            return "Log \(targetValue) pain-free activities."
        case .uniqueActivities:
            return "Complete \(targetValue) different activity types."
        case .longestSessionMinutes:
            return "Complete \(targetValue) activities."
        }
    }

    static func random(for badgeType: BadgeType) -> BadgeCriterion {
        let options = allowedCriteria(for: badgeType)
        let selectedKind = options.randomElement() ?? .totalActivities
        let target = randomTargetValue(for: badgeType, kind: selectedKind)
        return BadgeCriterion(
            badgeType: badgeType,
            kind: selectedKind,
            targetValue: target
        )
    }

    private static func allowedCriteria(for badgeType: BadgeType) -> [BadgeCriterionKind] {
        switch badgeType {
        case .firstCheckIn:
            return [.totalActivities, .painFreeSessions]
        case .streakThree:
            return [.streakDays]
        case .consistencyTen:
            return [.totalActivities, .painFreeSessions]
        case .activitySeven:
            return [.totalActivities, .painFreeSessions]
        case .activityTwenty:
            return [.totalActivities, .painFreeSessions]
        case .streakSeven:
            return [.streakDays, .uniqueActivities]
        case .painFreeFive:
            return [.painFreeSessions, .totalActivities]
        case .varietyThree:
            return [.uniqueActivities, .totalActivities]
        case .varietySix:
            return [.uniqueActivities, .streakDays]
        case .activityFifty:
            return [.totalActivities, .painFreeSessions]
        case .streakFourteen:
            return [.streakDays]
        case .painFreeFifteen:
            return [.painFreeSessions]
        case .varietyTen:
            return [.uniqueActivities, .totalActivities]
        case .activityHundred:
            return [.totalActivities]
        case .streakThirty:
            return [.streakDays]
        }
    }

    private static func randomTargetValue(for badgeType: BadgeType, kind: BadgeCriterionKind) -> Int {
        switch (badgeType, kind) {
        case (.firstCheckIn, .totalActivities):
            return Int.random(in: 1...3)
        case (.firstCheckIn, .painFreeSessions):
            return Int.random(in: 1...3)

        case (.streakThree, .streakDays):
            return Int.random(in: 3...5)

        case (.consistencyTen, .totalActivities):
            return Int.random(in: 10...16)
        case (.consistencyTen, .painFreeSessions):
            return Int.random(in: 8...14)

        case (.activitySeven, .totalActivities):
            return Int.random(in: 7...10)
        case (.activitySeven, .painFreeSessions):
            return Int.random(in: 6...9)

        case (.activityTwenty, .totalActivities):
            return Int.random(in: 20...28)
        case (.activityTwenty, .painFreeSessions):
            return Int.random(in: 15...24)

        case (.streakSeven, .streakDays):
            return Int.random(in: 6...10)
        case (.streakSeven, .uniqueActivities):
            return Int.random(in: 3...5)

        case (.painFreeFive, .painFreeSessions):
            return Int.random(in: 4...7)
        case (.painFreeFive, .totalActivities):
            return Int.random(in: 6...10)

        case (.varietyThree, .uniqueActivities):
            return Int.random(in: 2...4)
        case (.varietyThree, .totalActivities):
            return Int.random(in: 8...14)

        case (.varietySix, .uniqueActivities):
            return Int.random(in: 5...8)
        case (.varietySix, .streakDays):
            return Int.random(in: 4...7)

        case (.activityFifty, .totalActivities):
            return Int.random(in: 45...60)
        case (.activityFifty, .painFreeSessions):
            return Int.random(in: 32...48)

        case (.streakFourteen, .streakDays):
            return Int.random(in: 12...16)

        case (.painFreeFifteen, .painFreeSessions):
            return Int.random(in: 12...18)

        case (.varietyTen, .uniqueActivities):
            return Int.random(in: 8...12)
        case (.varietyTen, .totalActivities):
            return Int.random(in: 24...36)

        case (.activityHundred, .totalActivities):
            return Int.random(in: 95...120)

        case (.streakThirty, .streakDays):
            return Int.random(in: 25...35)

        default:
            return Int.random(in: 2...10)
        }
    }
}

enum ProgressionLevel: Int, Codable, CaseIterable {
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4
    case level5 = 5
    case level6 = 6
    case level7 = 7
    case level8 = 8
    case level9 = 9
    case level10 = 10

    var title: String {
        switch self {
        case .level1: return "Starter"
        case .level2: return "Rhythm Rookie"
        case .level3: return "Cardio Climber"
        case .level4: return "Heart Defender"
        case .level5: return "Resting HR Hunter"
        case .level6: return "Pulse Master"
        case .level7: return "Endurance Ranger"
        case .level8: return "Consistency Captain"
        case .level9: return "Performance Pro"
        case .level10: return "Virest Legend"
        }
    }

    var minSessions: Int {
        switch self {
        case .level1: return 0
        case .level2: return 10
        case .level3: return 20
        case .level4: return 35
        case .level5: return 55
        case .level6: return 80
        case .level7: return 110
        case .level8: return 145
        case .level9: return 185
        case .level10: return 230
        }
    }

    var nextTargetSessions: Int? {
        switch self {
        case .level1: return 10
        case .level2: return 20
        case .level3: return 35
        case .level4: return 55
        case .level5: return 80
        case .level6: return 110
        case .level7: return 145
        case .level8: return 185
        case .level9: return 230
        case .level10: return nil
        }
    }

    static func from(completedSessions: Int) -> ProgressionLevel {
        switch completedSessions {
        case 0..<10:
            return .level1
        case 10..<20:
            return .level2
        case 20..<35:
            return .level3
        case 35..<55:
            return .level4
        case 55..<80:
            return .level5
        case 80..<110:
            return .level6
        case 110..<145:
            return .level7
        case 145..<185:
            return .level8
        case 185..<230:
            return .level9
        default:
            return .level10
        }
    }
}

struct BadgeState: Codable, Equatable {
    var completedSessions: Int
    var currentStreak: Int
    var lastCheckInDate: Date?
    var level: ProgressionLevel
    var earnedBadges: [BadgeEarned]
    var painFreeSessions: Int
    var longestSessionMinutes: Int
    var uniqueActivityTokens: [String]
    var randomCriteria: [BadgeCriterion]

    init(
        completedSessions: Int,
        currentStreak: Int,
        lastCheckInDate: Date?,
        level: ProgressionLevel,
        earnedBadges: [BadgeEarned],
        painFreeSessions: Int = 0,
        longestSessionMinutes: Int = 0,
        uniqueActivityTokens: [String] = [],
        randomCriteria: [BadgeCriterion] = []
    ) {
        self.completedSessions = completedSessions
        self.currentStreak = currentStreak
        self.lastCheckInDate = lastCheckInDate
        self.level = level
        self.earnedBadges = earnedBadges
        self.painFreeSessions = painFreeSessions
        self.longestSessionMinutes = longestSessionMinutes
        self.uniqueActivityTokens = Array(Set(uniqueActivityTokens)).sorted()
        self.randomCriteria = randomCriteria
    }

    static var `default`: BadgeState {
        var value = BadgeState(
            completedSessions: 0,
            currentStreak: 0,
            lastCheckInDate: nil,
            level: .level1,
            earnedBadges: []
        )
        _ = value.normalizeRandomCriteriaIfNeeded()
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case completedSessions
        case currentStreak
        case lastCheckInDate
        case level
        case earnedBadges
        case painFreeSessions
        case longestSessionMinutes
        case uniqueActivityTokens
        case randomCriteria
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.completedSessions = try container.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        self.currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        self.lastCheckInDate = try container.decodeIfPresent(Date.self, forKey: .lastCheckInDate)
        self.level = try container.decodeIfPresent(ProgressionLevel.self, forKey: .level)
            ?? ProgressionLevel.from(completedSessions: completedSessions)
        self.earnedBadges = try container.decodeIfPresent([BadgeEarned].self, forKey: .earnedBadges) ?? []
        self.painFreeSessions = try container.decodeIfPresent(Int.self, forKey: .painFreeSessions) ?? 0
        self.longestSessionMinutes = try container.decodeIfPresent(Int.self, forKey: .longestSessionMinutes) ?? 0
        self.uniqueActivityTokens =
            Array(Set(try container.decodeIfPresent([String].self, forKey: .uniqueActivityTokens) ?? [])).sorted()
        self.randomCriteria = try container.decodeIfPresent([BadgeCriterion].self, forKey: .randomCriteria) ?? []

        _ = normalizeRandomCriteriaIfNeeded()
    }

    mutating func normalizeRandomCriteriaIfNeeded() -> Bool {
        var changed = false
        var byType: [BadgeType: BadgeCriterion] = [:]

        for criterion in randomCriteria {
            var normalizedCriterion = criterion
            if criterion.kind.isLegacyTimeBased {
                normalizedCriterion = BadgeCriterion.random(for: criterion.badgeType)
                changed = true
            }

            if byType[normalizedCriterion.badgeType] == nil {
                byType[normalizedCriterion.badgeType] = normalizedCriterion
            }
        }

        for badgeType in BadgeType.allCases {
            guard byType[badgeType] == nil else { continue }
            byType[badgeType] = BadgeCriterion.random(for: badgeType)
            changed = true
        }

        let normalizedCriteria = BadgeType.allCases.compactMap { byType[$0] }
        if normalizedCriteria != randomCriteria {
            randomCriteria = normalizedCriteria
            changed = true
        }

        let dedupedTokens = Array(Set(uniqueActivityTokens)).sorted()
        if dedupedTokens != uniqueActivityTokens {
            uniqueActivityTokens = dedupedTokens
            changed = true
        }

        return changed
    }

    func metricValue(for kind: BadgeCriterionKind) -> Int {
        switch kind {
        case .totalActivities:
            return completedSessions
        case .streakDays:
            return currentStreak
        case .painFreeSessions:
            return painFreeSessions
        case .longestSessionMinutes:
            // Legacy fallback: mapped to activity count to avoid minute-based rewards.
            return completedSessions
        case .uniqueActivities:
            return uniqueActivityTokens.count
        }
    }

    func criterion(for badgeType: BadgeType) -> BadgeCriterion? {
        randomCriteria.first { $0.badgeType == badgeType }
    }
}

struct GamificationResult: Equatable {
    var updatedState: BadgeState
    var newlyEarnedBadges: [BadgeEarned]
    var appreciationMessage: String
}
