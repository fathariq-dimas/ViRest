import Foundation

@MainActor
final class HealthDailySnapshotSwiftDataRepository: HealthDailySnapshotRepository {
    private let store: SwiftDataKeyValueStore

    init(store: SwiftDataKeyValueStore) {
        self.store = store
    }

    func loadDailySnapshots(userId: String) throws -> [DailyHealthSnapshot] {
        try store.load(
            [DailyHealthSnapshot].self,
            forKey: StorageKeys.healthDailySnapshots(userId: userId)
        ) ?? []
    }

    func saveDailySnapshots(_ snapshots: [DailyHealthSnapshot], userId: String) throws {
        let sorted = snapshots.sorted { $0.dayStart < $1.dayStart }
        try store.save(sorted, forKey: StorageKeys.healthDailySnapshots(userId: userId))
    }

    func loadLastSyncedDay(userId: String) throws -> Date? {
        try store.load(Date.self, forKey: StorageKeys.healthLastSyncedDay(userId: userId))
    }

    func saveLastSyncedDay(_ dayStart: Date, userId: String) throws {
        try store.save(dayStart, forKey: StorageKeys.healthLastSyncedDay(userId: userId))
    }
}
