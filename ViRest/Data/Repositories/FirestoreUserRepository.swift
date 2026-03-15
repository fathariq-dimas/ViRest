//
//  FirestoreUserRepository.swift
//  ViRest
//
//  Created by Joshua Valentine Manik on 13/03/26.
//

import Foundation
import FirebaseFirestore

@MainActor
final class FirestoreUserRepository {
    private let db = Firestore.firestore()
    private var cachedUser: FirestoreUser?

    // Create or update user document on sign-in
    func ensureUserExists(authUser: AuthUser) async throws {
        let ref = db.collection("users").document(authUser.id)
        let snapshot = try await ref.getDocument()

        if !snapshot.exists {
            // First sign-in: create document
            var newUser = FirestoreUser(from: authUser)
            // Assign default title (lowest displayOrder)
            let defaultTitle = try await fetchLowestTitle()
            newUser.currentTitleId = defaultTitle?.id ?? ""
            try ref.setData(from: newUser)
        } else {
            // Returning user: update lastActiveAt
            var data: [String: Any] = [
                "lastActiveAt": FieldValue.serverTimestamp()
            ]
            let trimmedName = authUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                data["displayName"] = trimmedName
            }
            try await ref.updateData(data)
        }
    }

    func loadUser(userId: String) async throws -> FirestoreUser? {
        let snapshot = try await db.collection("users").document(userId).getDocument()
        let user = try snapshot.data(as: FirestoreUser.self)
        self.cachedUser = user
        return user
    }

    func loadBadgeState(userId: String) async throws -> BadgeState? {
        try await loadUser(userId: userId)?.badgeState
    }

    func loadSportSuitabilityFlags(userId: String) async throws -> [String: FirestoreSportSuitabilityFlag] {
        try await loadUser(userId: userId)?.sportSuitabilityFlags ?? [:]
    }

    func loadNotSuitableSportIds(userId: String) async throws -> Set<String> {
        let flags = try await loadSportSuitabilityFlags(userId: userId)
        return Set(
            flags.compactMap { key, value in
                value.isNotSuitable ? key : nil
            }
        )
    }

    @discardableResult
    func registerSportSwitchFeedback(
        userId: String,
        sportId: String,
        reason: SwitchReason,
        origin: SwitchOrigin
    ) async throws -> [String: FirestoreSportSuitabilityFlag] {
        let ref = db.collection("users").document(userId)
        let snapshot = try await ref.getDocument()
        let currentUser = snapshot.exists ? try snapshot.data(as: FirestoreUser.self) : nil

        var flags = currentUser?.sportSuitabilityFlags ?? [:]
        var entry = flags[sportId] ?? FirestoreSportSuitabilityFlag()
        entry.register(reason: reason, origin: origin, at: Date())
        flags[sportId] = entry

        let encodedFlags = try Firestore.Encoder().encode(flags)
        try await ref.setData([
            "sportSuitabilityFlags": encodedFlags,
            "lastActiveAt": FieldValue.serverTimestamp()
        ], merge: true)

        if cachedUser?.id == userId {
            cachedUser?.sportSuitabilityFlags = flags
        }
        return flags
    }

    @discardableResult
    func clearSportNotSuitableFlag(
        userId: String,
        sportId: String
    ) async throws -> [String: FirestoreSportSuitabilityFlag] {
        let ref = db.collection("users").document(userId)
        let snapshot = try await ref.getDocument()
        let currentUser = snapshot.exists ? try snapshot.data(as: FirestoreUser.self) : nil

        var flags = currentUser?.sportSuitabilityFlags ?? [:]
        guard var entry = flags[sportId] else { return flags }

        entry.isNotSuitable = false
        entry.notSuitableAt = nil
        entry.lastUpdatedAt = Date()
        flags[sportId] = entry

        let encodedFlags = try Firestore.Encoder().encode(flags)
        try await ref.setData([
            "sportSuitabilityFlags": encodedFlags,
            "lastActiveAt": FieldValue.serverTimestamp()
        ], merge: true)

        if cachedUser?.id == userId {
            cachedUser?.sportSuitabilityFlags = flags
        }
        return flags
    }

    func saveBadgeState(userId: String, state: BadgeState) async throws {
        let ref = db.collection("users").document(userId)
        let encodedState = try Firestore.Encoder().encode(state)
        try await ref.setData([
            "badgeState": encodedState,
            "badgeStateUpdatedAt": Date(),
            "lastActiveAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func upsertRHRTracking(
        userId: String,
        bpm: Double?,
        source: RestingHeartRateValueSource,
        collectedAt: Date
    ) async throws {
        guard let bpm, let mappedSource = FirestoreRHRSource(snapshotSource: source) else {
            return
        }

        let ref = db.collection("users").document(userId)
        let snapshot = try await ref.getDocument()
        let existingUser = snapshot.exists ? try snapshot.data(as: FirestoreUser.self) : nil
        let existingTracking = existingUser?.rhrTracking

        let updatedTracking: FirestoreRHRTracking
        if var existingTracking {
            let shouldReplaceManualBaseline = existingTracking.baselineSource == .manual && mappedSource == .healthKit
            if shouldReplaceManualBaseline {
                existingTracking.baselineBPM = bpm
                existingTracking.baselineAt = collectedAt
                existingTracking.baselineSource = .healthKit
            }

            existingTracking.latestBPM = bpm
            existingTracking.latestAt = collectedAt
            existingTracking.latestSource = mappedSource
            existingTracking.lastHealthSyncAt = Date()
            updatedTracking = existingTracking
        } else {
            updatedTracking = FirestoreRHRTracking(
                baselineBPM: bpm,
                baselineAt: collectedAt,
                baselineSource: mappedSource,
                latestBPM: bpm,
                latestAt: collectedAt,
                latestSource: mappedSource,
                lastHealthSyncAt: Date()
            )
        }

        let encodedTracking = try Firestore.Encoder().encode(updatedTracking)
        try await ref.setData([
            "rhrTracking": encodedTracking,
            "lastActiveAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func saveProfile(userId: String, profile: UserProfileInput) async throws {
        let ref = db.collection("users").document(userId)
        var data: [String: Any] = [
            "age": profile.age as Any,
            "restingHeartRate": profile.questionnaireCurrentRHRBand?.representativeBPM as Any,
            "targetRestingHeartRate": profile.questionnaireTargetRHRGoal?.representativeBPM as Any,
            "heightCm": profile.heightCm as Any,
            "weightKg": profile.weightKg as Any,
            "lastActiveAt": FieldValue.serverTimestamp()
        ]
        let trimmedName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            data["displayName"] = trimmedName
        }
        try await ref.updateData(data)
    }

    func saveSportPlan(userId: String, plan: FirestoreSportPlan) async throws {
        let ref = db.collection("users").document(userId)
        let encoded = try Firestore.Encoder().encode(plan)
        try await ref.updateData(["sportPlan": encoded])
    }

    // Called every time user taps '+' on a sport
    func recordCheckIn(userId: String, sportId: String) async throws {
        let ref = db.collection("users").document(userId)
        try await ref.updateData([
            "totalActionsCompleted": FieldValue.increment(Int64(1)),
            "lastActiveAt": FieldValue.serverTimestamp(),
            // Update the specific sport's completedThisWeek counter
            // Uses dot notation to update nested array item
            // Note: with array of structs you'll need a Cloud Function or
            // re-read + write approach (see Phase 4 for the full pattern)
        ])
        // Re-read and update the sport plan's completedThisWeek
        // (Firestore cannot atomically update inside arrays without transactions)
        try await incrementSportCount(userId: userId, sportId: sportId)
    }

    private func incrementSportCount(userId: String, sportId: String) async throws {
        let ref = db.collection("users").document(userId)
        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do { snapshot = try transaction.getDocument(ref) }
            catch { errorPointer?.pointee = error as NSError; return nil }

            guard var user = try? snapshot.data(as: FirestoreUser.self),
                  var plan = user.sportPlan else { return nil }

            let now = Date()
            for i in plan.sports.indices {
                let currentCycleStart = plan.sports[i].currentCycleStart(
                    at: now,
                    defaultStart: plan.generatedAt
                )
                if plan.sports[i].weekResetDate < currentCycleStart {
                    plan.sports[i].completedThisWeek = 0
                    plan.sports[i].weekResetDate = currentCycleStart
                }
            }

            for i in plan.sports.indices where plan.sports[i].id == sportId {
                plan.sports[i].completedThisWeek += 1
                if plan.sports[i].pendingDeloadSessions > 0 {
                    plan.sports[i].pendingDeloadSessions -= 1
                }
            }
            user.sportPlan = plan
            if let encoded = try? Firestore.Encoder().encode(plan) {
                transaction.updateData(["sportPlan": encoded], forDocument: ref)
            }
            return nil
        }
    }

    // Fetch all titles, return the one with lowest minTotalActionsRequired
    func fetchLowestTitle() async throws -> FirestoreTitle? {
        let snapshot = try await db.collection("titles")
            .order(by: "displayOrder", descending: false)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first.map { try $0.data(as: FirestoreTitle.self) }
    }

    // Evaluate and update title based on totalActionsCompleted
    func updateTitleIfNeeded(userId: String, totalActions: Int) async throws {
        let snapshot = try await db.collection("titles")
            .order(by: "minTotalActionsRequired", descending: false)
            .getDocuments()
        let titles = try snapshot.documents.map { try $0.data(as: FirestoreTitle.self) }

        // Find the highest title the user qualifies for
        let earned = titles.filter { $0.minTotalActionsRequired <= totalActions }
            .max(by: { $0.minTotalActionsRequired < $1.minTotalActionsRequired })

        if let title = earned, let titleId = title.id {
            try await db.collection("users").document(userId)
                .updateData(["currentTitleId": titleId])
        }
    }

    func saveCheckInHistory(
        userId: String,
        sportId: String,
        sportName: String,
        durationMinutes: Int,
        difficulty: ActivityDifficulty? = nil,
        fatigue: FatigueLevel? = nil,
        painLevel: PainLevel? = nil,
        discomfortAreas: [DiscomfortArea] = [],
        zone: SuitabilityZone? = nil,
        decision: ProgressionDecision? = nil
    ) async throws {
        let entry = CheckInHistoryEntry(
            sportId: sportId,
            sportName: sportName,
            createdAt: Date(),
            durationMinutes: durationMinutes,
            difficulty: difficulty,
            fatigue: fatigue,
            painLevel: painLevel,
            discomfortAreas: discomfortAreas,
            zone: zone,
            decision: decision
        )
        let ref = db.collection("users").document(userId)
            .collection("checkIns").document()
        try ref.setData(from: entry)
    }

    func loadCheckInHistory(userId: String, limit: Int = 30) async throws -> [CheckInHistoryEntry] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("checkIns")
            .order(by: "date", descending: true)
            .limit(to: limit)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: CheckInHistoryEntry.self) }
    }

    func loadRecentCheckInHistory(
        userId: String,
        sportId: String,
        limit: Int = 3
    ) async throws -> [CheckInHistoryEntry] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("checkIns")
            .order(by: "date", descending: true)
            .limit(to: max(limit * 8, 24))
            .getDocuments()
        return try snapshot.documents
            .map { try $0.data(as: CheckInHistoryEntry.self) }
            .filter { $0.sportId == sportId }
            .prefix(limit)
            .map { $0 }
    }

}
