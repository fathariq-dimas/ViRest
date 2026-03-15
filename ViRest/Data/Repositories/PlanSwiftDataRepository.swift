import Foundation

@MainActor
final class PlanSwiftDataRepository: PlanRepository {
    private let store: SwiftDataKeyValueStore
    private let authService: AuthProviding

    init(store: SwiftDataKeyValueStore, authService: AuthProviding) {
        self.store = store
        self.authService = authService
    }

    func loadCurrentPlan() throws -> WeeklyPlan? {
        try store.load(WeeklyPlan.self, forKey: StorageKeys.currentPlan(userId: currentUserScope))
    }

    func saveCurrentPlan(_ plan: WeeklyPlan) throws {
        try store.save(plan, forKey: StorageKeys.currentPlan(userId: currentUserScope))
    }

    private var currentUserScope: String {
        if case .signedIn(let user) = authService.authState {
            return user.id
        }
        return "guest"
    }
}
