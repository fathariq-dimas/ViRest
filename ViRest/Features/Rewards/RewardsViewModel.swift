import Foundation
import Combine

@MainActor
final class RewardsViewModel: ObservableObject {
    @Published var badgeState: BadgeState = .default
    @Published var firestoreUser: FirestoreUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let badgeRepository: BadgeStateRepository
    private let firestoreUserRepository: FirestoreUserRepository
    private let authService: AuthProviding

    init(
        badgeRepository: BadgeStateRepository,
        firestoreUserRepository: FirestoreUserRepository,
        authService: AuthProviding
    ) {
        self.badgeRepository = badgeRepository
        self.firestoreUserRepository = firestoreUserRepository
        self.authService = authService
    }

    func load() {
        Task { await loadInternal() }
    }

    var totalActivitiesCount: Int {
        max(badgeState.completedSessions, firestoreUser?.totalActionsCompleted ?? 0)
    }

    var resolvedLevel: ProgressionLevel {
        ProgressionLevel.from(completedSessions: totalActivitiesCount)
    }

    var levelProgress: Double {
        let level = resolvedLevel
        guard let nextTarget = level.nextTargetSessions else { return 1 }
        let completed = totalActivitiesCount
        let span = max(1, nextTarget - level.minSessions)
        let progressed = max(0, completed - level.minSessions)
        return min(1, Double(progressed) / Double(span))
    }

    var levelSummary: String {
        "Level \(resolvedLevel.rawValue) · \(resolvedLevel.title)"
    }

    var currentTitleName: String {
        resolvedLevel.title
    }

    var nextLevelTitle: String? {
        guard let _ = resolvedLevel.nextTargetSessions else { return nil }
        return ProgressionLevel(rawValue: resolvedLevel.rawValue + 1)?.title
    }

    var nextLevelDetail: String {
        guard let nextTarget = resolvedLevel.nextTargetSessions else {
            return "Maximum level reached."
        }

        let remaining = max(0, nextTarget - totalActivitiesCount)
        
        if let nextLevelTitle {
            return "\(remaining) more activities to reach next level."
        }

        return "\(remaining) more activities to reach next level."
    }

    private func loadInternal() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var localState = try badgeRepository.loadState()
            let localStateChanged = localState.normalizeRandomCriteriaIfNeeded()
            if localStateChanged {
                try badgeRepository.saveState(localState)
            }

            guard case .signedIn(let user) = authService.authState else {
                badgeState = localState
                return
            }

            firestoreUser = try await firestoreUserRepository.loadUser(userId: user.id)
            if var remoteBadgeState = firestoreUser?.badgeState {
                let remoteChanged = remoteBadgeState.normalizeRandomCriteriaIfNeeded()
                badgeState = remoteBadgeState
                try badgeRepository.saveState(remoteBadgeState)
                if remoteChanged {
                    try? await firestoreUserRepository.saveBadgeState(userId: user.id, state: remoteBadgeState)
                }
            } else {
                badgeState = localState
                try? await firestoreUserRepository.saveBadgeState(userId: user.id, state: localState)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
