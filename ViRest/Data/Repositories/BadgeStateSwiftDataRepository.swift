import Foundation

@MainActor
final class BadgeStateSwiftDataRepository: BadgeStateRepository {
    private let store: SwiftDataKeyValueStore
    private let authService: AuthProviding

    init(store: SwiftDataKeyValueStore, authService: AuthProviding) {
        self.store = store
        self.authService = authService
    }

    func loadState() throws -> BadgeState {
        if var loaded = try store.load(BadgeState.self, forKey: StorageKeys.badgeState(userId: currentUserScope)) {
            let changed = loaded.normalizeRandomCriteriaIfNeeded()
            if changed {
                try store.save(loaded, forKey: StorageKeys.badgeState(userId: currentUserScope))
            }
            return loaded
        }

        let initial = BadgeState.default
        try store.save(initial, forKey: StorageKeys.badgeState(userId: currentUserScope))
        return initial
    }

    func saveState(_ state: BadgeState) throws {
        var normalized = state
        _ = normalized.normalizeRandomCriteriaIfNeeded()
        try store.save(normalized, forKey: StorageKeys.badgeState(userId: currentUserScope))
    }

    private var currentUserScope: String {
        if case .signedIn(let user) = authService.authState {
            return user.id
        }
        return "guest"
    }
}
