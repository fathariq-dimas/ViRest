import Foundation

enum StorageKeys {
    static func userProfile(userId: String) -> String {
        "user_profile_\(userId)"
    }

    static func currentPlan(userId: String) -> String {
        "current_plan_\(userId)"
    }

    static func checkIns(userId: String) -> String {
        "check_ins_\(userId)"
    }

    static func badgeState(userId: String) -> String {
        "badge_state_\(userId)"
    }

    static func healthDailySnapshots(userId: String) -> String {
        "health_daily_snapshots_\(userId)"
    }

    static func healthLastSyncedDay(userId: String) -> String {
        "health_last_synced_day_\(userId)"
    }
}
