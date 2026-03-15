import Foundation

protocol UserProfileRepository {
    func loadProfile() throws -> UserProfileInput?
    func saveProfile(_ profile: UserProfileInput) throws
}

protocol PlanRepository {
    func loadCurrentPlan() throws -> WeeklyPlan?
    func saveCurrentPlan(_ plan: WeeklyPlan) throws
}

protocol CheckInRepository {
    func loadCheckIns() throws -> [SessionCheckIn]
    func addCheckIn(_ checkIn: SessionCheckIn) throws
}

protocol BadgeStateRepository {
    func loadState() throws -> BadgeState
    func saveState(_ state: BadgeState) throws
}

protocol HealthDailySnapshotRepository {
    func loadDailySnapshots(userId: String) throws -> [DailyHealthSnapshot]
    func saveDailySnapshots(_ snapshots: [DailyHealthSnapshot], userId: String) throws
    func loadLastSyncedDay(userId: String) throws -> Date?
    func saveLastSyncedDay(_ dayStart: Date, userId: String) throws
}
