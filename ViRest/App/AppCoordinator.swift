import Foundation
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    enum Route: Equatable {
        case loading
        case login
        case onboardingLogin
        case main
        case error(String)
    }

    @Published private(set) var route: Route = .loading

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func bootstrap() async {
        await container.authService.restoreSession()

        switch container.authService.authState {
        case .signedOut:
            container.widgetSyncService.clear()
            route = .login
        case .signedIn(let user):
            await container.dailyHealthSyncService.syncIfNeeded(userId: user.id)
            do {
                guard let firestoreUser = try await container.firestoreUserRepository.loadUser(userId: user.id) else {
                    container.widgetSyncService.clear()
                    route = .onboardingLogin
                    return
                }

                if firestoreUser.sportPlan != nil {
                await publishWidgetSnapshot(for: user.id, firestoreUser: firestoreUser)
                route = .main
                } else {
                    container.widgetSyncService.clear()
                    route = .onboardingLogin
                }
            } catch {
                route = .error(error.localizedDescription)
            }
        }
    }

    func retryBootstrap() async {
        route = .loading
        await bootstrap()
    }

    func didAuthenticate() {
        // After sign-in, re-run the full async bootstrap check
        Task {
            switch container.authService.authState {
            case .signedOut:
                container.widgetSyncService.clear()
                route = .login
            case .signedIn(let user):
                await container.dailyHealthSyncService.syncIfNeeded(userId: user.id)
                do {
                    guard let firestoreUser = try await container.firestoreUserRepository.loadUser(userId: user.id) else {
                        container.widgetSyncService.clear()
                        route = .onboardingLogin
                        return
                    }
                    if firestoreUser.sportPlan != nil {
                        await publishWidgetSnapshot(for: user.id, firestoreUser: firestoreUser)
                        route = .main
                    } else {
                        container.widgetSyncService.clear()
                        route = .onboardingLogin
                    }
                } catch {
                    route = .error(error.localizedDescription)
                }
            }
        }
    }

    func syncHealthIfNeededOnActive() async {
        guard case .signedIn(let user) = container.authService.authState else { return }
        await container.dailyHealthSyncService.syncIfNeeded(userId: user.id)
        await publishWidgetSnapshot(for: user.id, firestoreUser: nil)
    }

    func didCompleteOnboarding() {
        route = .main
        Task {
            guard case .signedIn(let user) = container.authService.authState else { return }
            await publishWidgetSnapshot(for: user.id, firestoreUser: nil)
        }
    }

    func signOut() {
        try? container.authService.signOut()
        container.clearLocalUserCache()
        container.widgetSyncService.clear()
        route = .login
    }

    private func publishWidgetSnapshot(for userId: String, firestoreUser: FirestoreUser?) async {
        let resolvedFirestoreUser: FirestoreUser?
        if let firestoreUser {
            resolvedFirestoreUser = firestoreUser
        } else {
            resolvedFirestoreUser = try? await container.firestoreUserRepository.loadUser(userId: userId)
        }

        let localProfile = try? container.userProfileRepository.loadProfile()
        let resolvedVitals = await container.healthDataResolver.resolveVitals(
            localProfile: localProfile,
            firestoreUser: resolvedFirestoreUser
        )

        guard let firestoreUser = resolvedFirestoreUser else {
            let fallbackSnapshot = ViRestWidgetSnapshot(
                updatedAt: Date(),
                latestRestingHR: resolvedVitals.latestRestingHeartRate,
                targetRestingHR: resolvedVitals.targetRestingHeartRate,
                activeSportName: "Open Virest to sync your plan",
                completedSessions: 0,
                targetSessions: 0
            )
            container.widgetSyncService.publish(snapshot: fallbackSnapshot)
            return
        }

        let resolvedSports = firestoreUser.sportPlan?.resolvedSports(at: Date()) ?? []
        let selectedSportId = firestoreUser.sportPlan?.resolvedSelectedSportId
        let activeSport = resolvedSports.first(where: { $0.id == selectedSportId }) ?? resolvedSports.first

        let snapshot = ViRestWidgetSnapshot(
            updatedAt: Date(),
            latestRestingHR: resolvedVitals.latestRestingHeartRate,
            targetRestingHR: resolvedVitals.targetRestingHeartRate,
            activeSportName: activeSport?.displayName,
            completedSessions: activeSport?.completedThisWeek ?? 0,
            targetSessions: activeSport?.weeklyTargetCount ?? 0
        )
        container.widgetSyncService.publish(snapshot: snapshot)
    }
}
