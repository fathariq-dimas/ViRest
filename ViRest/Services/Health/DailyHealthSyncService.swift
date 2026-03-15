import Foundation

@MainActor
final class DailyHealthSyncService {
    private let healthService: HealthDataProviding
    private let userProfileRepository: UserProfileRepository
    private let repository: HealthDailySnapshotRepository
    private let firestoreUserRepository: FirestoreUserRepository
    private let calendar: Calendar
    private let historyLimit: Int

    init(
        healthService: HealthDataProviding,
        userProfileRepository: UserProfileRepository,
        repository: HealthDailySnapshotRepository,
        firestoreUserRepository: FirestoreUserRepository,
        calendar: Calendar = .current,
        historyLimit: Int = 365
    ) {
        self.healthService = healthService
        self.userProfileRepository = userProfileRepository
        self.repository = repository
        self.firestoreUserRepository = firestoreUserRepository
        self.calendar = calendar
        self.historyLimit = historyLimit
    }

    func syncIfNeeded(userId: String) async {
        let todayStart = calendar.startOfDay(for: Date())

        do {
            if let lastSyncedDay = try repository.loadLastSyncedDay(userId: userId),
               calendar.isDate(lastSyncedDay, inSameDayAs: todayStart) {
                return
            }

            let localProfile = try userProfileRepository.loadProfile()
            let snapshot = await healthService.fetchLatestSnapshot(profile: localProfile)
            let dailySnapshot = DailyHealthSnapshot(
                dayStart: todayStart,
                syncedAt: Date(),
                source: snapshot.source,
                restingHeartRate: snapshot.restingHeartRate,
                heightCm: snapshot.heightCm,
                weightKg: snapshot.weightKg
            )

            var history = try repository.loadDailySnapshots(userId: userId)
            if let existingIndex = history.firstIndex(where: { calendar.isDate($0.dayStart, inSameDayAs: todayStart) }) {
                history[existingIndex] = dailySnapshot
            } else {
                history.append(dailySnapshot)
            }

            if history.count > historyLimit {
                let sorted = history.sorted { $0.dayStart < $1.dayStart }
                history = Array(sorted.suffix(historyLimit))
            }

            try repository.saveDailySnapshots(history, userId: userId)
            try repository.saveLastSyncedDay(todayStart, userId: userId)
            try await firestoreUserRepository.upsertRHRTracking(
                userId: userId,
                bpm: snapshot.restingHeartRate,
                source: snapshot.restingHeartRateSource,
                collectedAt: snapshot.collectedAt
            )
        } catch {
#if DEBUG
            print("DailyHealthSyncService sync failed: \(error.localizedDescription)")
#endif
        }
    }
}
