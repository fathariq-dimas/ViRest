import Foundation

@MainActor
final class CheckInSwiftDataRepository: CheckInRepository {
    private let store: SwiftDataKeyValueStore
    private let authService: AuthProviding

    init(store: SwiftDataKeyValueStore, authService: AuthProviding) {
        self.store = store
        self.authService = authService
    }

    func loadCheckIns() throws -> [SessionCheckIn] {
        try store.load([SessionCheckIn].self, forKey: StorageKeys.checkIns(userId: currentUserScope)) ?? []
    }

    func addCheckIn(_ checkIn: SessionCheckIn) throws {
        var all = try loadCheckIns()
        all.append(checkIn)
        all.sort { $0.checkInDate > $1.checkInDate }
        try store.save(all, forKey: StorageKeys.checkIns(userId: currentUserScope))
    }

    private var currentUserScope: String {
        if case .signedIn(let user) = authService.authState {
            return user.id
        }
        return "guest"
    }
}
