//
//  FirestoreModels.swift
//  ViRest
//
//  Created by Joshua Valentine Manik on 13/03/26.
//

import Foundation
import FirebaseFirestore

// Maps to the 'users' Firestore collection
struct FirestoreUser: Codable {
    @DocumentID var documentId: String?
    var id: String
    var email: String?
    var displayName: String?
    var age: Int?
    var restingHeartRate: Int?
    var targetRestingHeartRate: Int?
    var heightCm: Double?
    var weightKg: Double?
    var currentTitleId: String
    var totalActionsCompleted: Int
    var recommendationParameters: [String: String]
    var createdAt: Date
    var lastActiveAt: Date
    var badgeState: BadgeState?
    var badgeStateUpdatedAt: Date?
    var rhrTracking: FirestoreRHRTracking?
    var sportSuitabilityFlags: [String: FirestoreSportSuitabilityFlag]?

    // Nested sport plan — stored as subcollection or embedded
    // For simplicity we embed as a field
    var sportPlan: FirestoreSportPlan?

    init(from authUser: AuthUser) {
        self.id = authUser.id
        self.email = authUser.email
        self.displayName = authUser.displayName
        self.currentTitleId = ""
        self.totalActionsCompleted = 0
        self.recommendationParameters = [:]
        self.createdAt = Date()
        self.lastActiveAt = Date()
        self.badgeState = nil
        self.badgeStateUpdatedAt = nil
        self.rhrTracking = nil
        self.sportSuitabilityFlags = nil
    }
}

struct FirestoreSportSuitabilityFlag: Codable, Equatable {
    var isNotSuitable: Bool
    var reasonCounts: [String: Int]
    var lastReason: SwitchReason?
    var lastOrigin: SwitchOrigin?
    var lastUpdatedAt: Date
    var notSuitableAt: Date?

    init(
        isNotSuitable: Bool = false,
        reasonCounts: [String: Int] = [:],
        lastReason: SwitchReason? = nil,
        lastOrigin: SwitchOrigin? = nil,
        lastUpdatedAt: Date = Date(),
        notSuitableAt: Date? = nil
    ) {
        self.isNotSuitable = isNotSuitable
        self.reasonCounts = reasonCounts
        self.lastReason = lastReason
        self.lastOrigin = lastOrigin
        self.lastUpdatedAt = lastUpdatedAt
        self.notSuitableAt = notSuitableAt
    }

    mutating func register(reason: SwitchReason, origin: SwitchOrigin, at date: Date = Date()) {
        reasonCounts[reason.rawValue, default: 0] += 1
        lastReason = reason
        lastOrigin = origin
        lastUpdatedAt = date

        if reason == .notSuitable {
            isNotSuitable = true
            if notSuitableAt == nil {
                notSuitableAt = date
            }
        }
    }
}

enum FirestoreRHRSource: String, Codable {
    case manual
    case healthKit = "health_kit"

    init?(snapshotSource: RestingHeartRateValueSource) {
        switch snapshotSource {
        case .manual:
            self = .manual
        case .healthKit:
            self = .healthKit
        case .unavailable:
            return nil
        }
    }
}

struct FirestoreRHRTracking: Codable, Equatable {
    var baselineBPM: Double
    var baselineAt: Date
    var baselineSource: FirestoreRHRSource
    var latestBPM: Double
    var latestAt: Date
    var latestSource: FirestoreRHRSource
    var lastHealthSyncAt: Date
}

// Holds the three recommended sports and their weekly targets
struct FirestoreSportPlan: Codable {
    var generatedAt: Date
    var sports: [FirestoreSportEntry]  // exactly 3
    var selectedSportId: String?
    var lastSwitchAt: Date?
    var lastSwitchReason: SwitchReason?

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case weekStartDate
        case sports
        case selectedSportId
        case lastSwitchAt
        case lastSwitchReason
    }

    init(
        generatedAt: Date,
        sports: [FirestoreSportEntry],
        selectedSportId: String? = nil,
        lastSwitchAt: Date? = nil,
        lastSwitchReason: SwitchReason? = nil
    ) {
        self.generatedAt = generatedAt
        self.sports = sports
        self.selectedSportId = Self.resolveSelectedSportId(selectedSportId, sports: sports)
        self.lastSwitchAt = lastSwitchAt
        self.lastSwitchReason = lastSwitchReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt =
            try container.decodeIfPresent(Date.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .weekStartDate)
            ?? Date()
        self.sports = try container.decodeIfPresent([FirestoreSportEntry].self, forKey: .sports) ?? []
        let decodedSelectedSportId = try container.decodeIfPresent(String.self, forKey: .selectedSportId)
        self.selectedSportId = Self.resolveSelectedSportId(decodedSelectedSportId, sports: self.sports)
        self.lastSwitchAt = try container.decodeIfPresent(Date.self, forKey: .lastSwitchAt)
        self.lastSwitchReason = try container.decodeIfPresent(SwitchReason.self, forKey: .lastSwitchReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(sports, forKey: .sports)
        try container.encodeIfPresent(
            Self.resolveSelectedSportId(selectedSportId, sports: sports),
            forKey: .selectedSportId
        )
        try container.encodeIfPresent(lastSwitchAt, forKey: .lastSwitchAt)
        try container.encodeIfPresent(lastSwitchReason, forKey: .lastSwitchReason)
    }

    func programWeekIndex(at date: Date = Date()) -> Int {
        let elapsed = max(0, date.timeIntervalSince(generatedAt))
        let weeks = Int(floor(elapsed / FirestoreSportEntry.rollingWeekDuration))
        return weeks + 1
    }

    func resolvedSports(at date: Date = Date()) -> [FirestoreSportEntry] {
        return sports.map {
            let weekIndex = $0.programWeekIndex(at: date, defaultStart: generatedAt)
            return $0.resolvedForProgramWeek(weekIndex)
        }
    }

    var resolvedSelectedSportId: String? {
        Self.resolveSelectedSportId(selectedSportId, sports: sports)
    }

    func activeSportsForCheckIn() -> [FirestoreSportEntry] {
        guard let selectedSportId = resolvedSelectedSportId else { return sports }
        let activeSports = sports.filter { $0.id == selectedSportId }
        return activeSports.isEmpty ? sports : activeSports
    }

    func isSportLocked(_ sport: FirestoreSportEntry) -> Bool {
        guard let selectedSportId = resolvedSelectedSportId else { return false }
        return sport.id != selectedSportId
    }

    mutating func selectSport(id: String) {
        selectedSportId = Self.resolveSelectedSportId(id, sports: sports)
    }

    func selectingSport(id: String) -> FirestoreSportPlan {
        var copy = self
        copy.selectSport(id: id)
        return copy
    }

    private static func resolveSelectedSportId(_ candidate: String?, sports: [FirestoreSportEntry]) -> String? {
        guard !sports.isEmpty else { return nil }
        if let candidate, sports.contains(where: { $0.id == candidate }) {
            return candidate
        }
        return sports.first?.id
    }
}

struct FirestoreSportPrescription: Codable, Equatable {
    var weeklyTargetCount: Int
    var durationMinutes: Int
}

struct FirestoreSportEntry: Codable, Identifiable {
    static let rollingWeekDuration: TimeInterval = 7 * 24 * 60 * 60

    var id: String          // matches ActivityType.rawValue
    var displayName: String
    var weeklyTargetCount: Int
    var completedThisWeek: Int
    var durationMinutes: Int
    var weekResetDate: Date  // start of current rolling 7-day cycle
    var phaseStartDate: Date?
    var pendingDeloadSessions: Int
    var hasProgression: Bool
    var initialPrescription: FirestoreSportPrescription?
    var targetPrescription: FirestoreSportPrescription?

    init(
        id: String,
        displayName: String,
        weeklyTargetCount: Int,
        completedThisWeek: Int,
        durationMinutes: Int,
        weekResetDate: Date,
        phaseStartDate: Date? = nil,
        pendingDeloadSessions: Int = 0,
        hasProgression: Bool = false,
        initialPrescription: FirestoreSportPrescription? = nil,
        targetPrescription: FirestoreSportPrescription? = nil
    ) {
        let legacy = FirestoreSportPrescription(
            weeklyTargetCount: max(1, weeklyTargetCount),
            durationMinutes: max(1, durationMinutes)
        )
        let resolvedInitial = initialPrescription ?? legacy
        let resolvedTarget = targetPrescription ?? legacy

        self.id = id
        self.displayName = displayName
        self.weeklyTargetCount = legacy.weeklyTargetCount
        self.completedThisWeek = max(0, completedThisWeek)
        self.durationMinutes = legacy.durationMinutes
        self.weekResetDate = weekResetDate
        self.phaseStartDate = phaseStartDate
        self.pendingDeloadSessions = max(0, pendingDeloadSessions)
        self.initialPrescription = resolvedInitial
        self.targetPrescription = resolvedTarget
        self.hasProgression = hasProgression || resolvedInitial != resolvedTarget
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case weeklyTargetCount
        case completedThisWeek
        case durationMinutes
        case weekResetDate
        case phaseStartDate
        case pendingDeloadSessions
        case hasProgression
        case initialPrescription
        case targetPrescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decode(String.self, forKey: .id)
        let displayName = try container.decode(String.self, forKey: .displayName)
        let legacyWeekly = try container.decodeIfPresent(Int.self, forKey: .weeklyTargetCount) ?? 1
        let completed = try container.decodeIfPresent(Int.self, forKey: .completedThisWeek) ?? 0
        let legacyDuration = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 20
        let weekReset = try container.decodeIfPresent(Date.self, forKey: .weekResetDate) ?? Date()
        let phaseStart = try container.decodeIfPresent(Date.self, forKey: .phaseStartDate)
        let pendingDeload = try container.decodeIfPresent(Int.self, forKey: .pendingDeloadSessions) ?? 0
        let initial = try container.decodeIfPresent(FirestoreSportPrescription.self, forKey: .initialPrescription)
        let target = try container.decodeIfPresent(FirestoreSportPrescription.self, forKey: .targetPrescription)
        let legacy = FirestoreSportPrescription(
            weeklyTargetCount: max(1, legacyWeekly),
            durationMinutes: max(1, legacyDuration)
        )
        let resolvedInitial = initial ?? legacy
        let resolvedTarget = target ?? legacy
        let progression = (try container.decodeIfPresent(Bool.self, forKey: .hasProgression))
            ?? (resolvedInitial != resolvedTarget)

        self.init(
            id: id,
            displayName: displayName,
            weeklyTargetCount: legacy.weeklyTargetCount,
            completedThisWeek: completed,
            durationMinutes: legacy.durationMinutes,
            weekResetDate: weekReset,
            phaseStartDate: phaseStart,
            pendingDeloadSessions: pendingDeload,
            hasProgression: progression,
            initialPrescription: resolvedInitial,
            targetPrescription: resolvedTarget
        )
    }

    var resolvedInitialPrescription: FirestoreSportPrescription {
        initialPrescription ?? FirestoreSportPrescription(
            weeklyTargetCount: max(1, weeklyTargetCount),
            durationMinutes: max(1, durationMinutes)
        )
    }

    var resolvedTargetPrescription: FirestoreSportPrescription {
        targetPrescription ?? FirestoreSportPrescription(
            weeklyTargetCount: max(1, weeklyTargetCount),
            durationMinutes: max(1, durationMinutes)
        )
    }

    func programWeekIndex(at date: Date = Date(), defaultStart: Date) -> Int {
        let phaseStart = phaseAnchorDate(defaultStart: defaultStart)
        let elapsed = max(0, date.timeIntervalSince(phaseStart))
        let weeks = Int(floor(elapsed / Self.rollingWeekDuration))
        return weeks + 1
    }

    func phaseAnchorDate(defaultStart: Date) -> Date {
        phaseStartDate ?? defaultStart
    }

    func currentCycleStart(at date: Date = Date(), defaultStart: Date) -> Date {
        let anchor = phaseAnchorDate(defaultStart: defaultStart)
        let elapsed = max(0, date.timeIntervalSince(anchor))
        let completedCycles = Int(floor(elapsed / Self.rollingWeekDuration))
        return anchor.addingTimeInterval(TimeInterval(completedCycles) * Self.rollingWeekDuration)
    }

    func shouldResetCycle(at date: Date = Date(), defaultStart: Date) -> Bool {
        weekResetDate < currentCycleStart(at: date, defaultStart: defaultStart)
    }

    func resolvedForProgramWeek(_ weekIndex: Int) -> FirestoreSportEntry {
        let phase = weekIndex <= 1 ? resolvedInitialPrescription : resolvedTargetPrescription
        var copy = self
        copy.weeklyTargetCount = phase.weeklyTargetCount
        if pendingDeloadSessions > 0 {
            let reduced = max(10, Int((Double(phase.durationMinutes) * 0.8).rounded()))
            copy.durationMinutes = reduced
        } else {
            copy.durationMinutes = phase.durationMinutes
        }
        return copy
    }
}

// Maps to the 'titles' Firestore collection
struct FirestoreTitle: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var minTotalActionsRequired: Int
    var displayOrder: Int
}
