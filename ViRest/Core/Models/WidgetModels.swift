import Foundation

enum ViRestWidgetShared {
    static let appGroupId = "group.halo-dek.virest.shared"
    static let snapshotStorageKey = "virest_widget_daily_snapshot"
}

struct ViRestWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var latestRestingHR: Int?
    var targetRestingHR: Int?
    var activeSportName: String?
    var completedSessions: Int
    var targetSessions: Int

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case latestRestingHR
        case dailyRestingHR
        case targetRestingHR
        case activeSportName
        case completedSessions
        case targetSessions
    }

    init(
        updatedAt: Date,
        latestRestingHR: Int?,
        targetRestingHR: Int?,
        activeSportName: String?,
        completedSessions: Int,
        targetSessions: Int
    ) {
        self.updatedAt = updatedAt
        self.latestRestingHR = latestRestingHR
        self.targetRestingHR = targetRestingHR
        self.activeSportName = activeSportName
        self.completedSessions = completedSessions
        self.targetSessions = targetSessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        latestRestingHR =
            try container.decodeIfPresent(Int.self, forKey: .latestRestingHR)
            ?? container.decodeIfPresent(Int.self, forKey: .dailyRestingHR)
        targetRestingHR = try container.decodeIfPresent(Int.self, forKey: .targetRestingHR)
        activeSportName = try container.decodeIfPresent(String.self, forKey: .activeSportName)
        completedSessions = try container.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        targetSessions = try container.decodeIfPresent(Int.self, forKey: .targetSessions) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(latestRestingHR, forKey: .latestRestingHR)
        try container.encodeIfPresent(targetRestingHR, forKey: .targetRestingHR)
        try container.encodeIfPresent(activeSportName, forKey: .activeSportName)
        try container.encode(completedSessions, forKey: .completedSessions)
        try container.encode(targetSessions, forKey: .targetSessions)
    }

    var pendingSessions: Int {
        max(0, targetSessions - completedSessions)
    }
}
