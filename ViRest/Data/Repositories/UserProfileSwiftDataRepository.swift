import Foundation

@MainActor
final class UserProfileSwiftDataRepository: UserProfileRepository {
    private let store: SwiftDataKeyValueStore
    private let authService: AuthProviding

    init(store: SwiftDataKeyValueStore, authService: AuthProviding) {
        self.store = store
        self.authService = authService
    }

    func loadProfile() throws -> UserProfileInput? {
        try store.load(UserProfileInput.self, forKey: StorageKeys.userProfile(userId: currentUserScope))
    }

    func saveProfile(_ profile: UserProfileInput) throws {
        try store.save(profile, forKey: StorageKeys.userProfile(userId: currentUserScope))
    }

    private var currentUserScope: String {
        if case .signedIn(let user) = authService.authState {
            return user.id
        }
        return "guest"
    }
}
