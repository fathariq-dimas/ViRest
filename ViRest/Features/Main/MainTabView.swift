import SwiftUI
import UIKit

struct MainTabView: View {
    @StateObject private var mainCoordinator = MainCoordinator()
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var rewardsViewModel: RewardsViewModel
    @StateObject private var profileViewModel: ProfileViewModel
    @StateObject private var reevaluateOnboardingViewModel: OnboardingViewModel
    @State private var homeRootID = UUID()
    @State private var rewardsRootID = UUID()
    @State private var profileRootID = UUID()
    @State private var isShowingReevaluateOnboarding = false

    private let onSignOut: () -> Void

    init(container: AppContainer, onSignOut: @escaping () -> Void) {
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            firestoreUserRepository: container.firestoreUserRepository,
            userProfileRepository: container.userProfileRepository,
            authService: container.authService,
            healthService: container.healthService,
            healthDataResolver: container.healthDataResolver,
            notificationService: container.notificationService,
            gamificationService: container.gamificationService,
            badgeRepository: container.badgeStateRepository,
            suitabilityEvaluator: container.suitabilityEvaluator,
            sportSwitchOrchestrator: container.sportSwitchOrchestrator,
            widgetSyncService: container.widgetSyncService
        ))

        _rewardsViewModel = StateObject(wrappedValue: RewardsViewModel(
            badgeRepository: container.badgeStateRepository,
            firestoreUserRepository: container.firestoreUserRepository,
            authService: container.authService
        ))

        _profileViewModel = StateObject(wrappedValue: ProfileViewModel(
            userProfileRepository: container.userProfileRepository,
            planRepository: container.planRepository,
            badgeRepository: container.badgeStateRepository,
            firestoreUserRepository: container.firestoreUserRepository,
            authService: container.authService,
            notificationService: container.notificationService,
            healthService: container.healthService,
            healthDataResolver: container.healthDataResolver,
            sportSwitchOrchestrator: container.sportSwitchOrchestrator
        ))

        _reevaluateOnboardingViewModel = StateObject(wrappedValue: OnboardingViewModel(
            userProfileRepository: container.userProfileRepository,
            planRepository: container.planRepository,
            healthService: container.healthService,
            recommendationEngine: container.recommendationEngine,
            notificationService: container.notificationService,
            firestoreUserRepository: container.firestoreUserRepository,
            authService: container.authService,
            onCompleted: {
                NotificationCenter.default.post(name: .reevaluateOnboardingCompleted, object: nil)
            }
        ))

        self.onSignOut = onSignOut
        Self.configureTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $mainCoordinator.selectedTab) {
            HomeView(viewModel: homeViewModel)
                .id(homeRootID)
                .tabItem {
                    Label("Plan", systemImage: "heart.text.square.fill")
                }
                .tag(MainCoordinator.Tab.home)

            RewardsView(viewModel: rewardsViewModel)
                .id(rewardsRootID)
                .tabItem {
                    Label("Rewards", systemImage: "rosette")
                }
                .tag(MainCoordinator.Tab.rewards)

            ProfileView(
                viewModel: profileViewModel,
                onSignOut: onSignOut,
                onReevaluateRequested: {
                    beginReevaluationFlow()
                }
            )
                .id(profileRootID)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
                .tag(MainCoordinator.Tab.profile)
        }
        .tint(AppPalette.accent)
        .fullScreenCover(isPresented: $isShowingReevaluateOnboarding) {
            NavigationStack {
                OnboardingView(
                    viewModel: reevaluateOnboardingViewModel,
                    onExitFromFirstQuestion: {
                        isShowingReevaluateOnboarding = false
                    }
                )
            }
        }
        .onChange(of: mainCoordinator.selectedTab) { oldTab, newTab in
            guard oldTab != newTab else { return }
            resetState(for: oldTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .widgetCheckInRequested)) { _ in
            mainCoordinator.selectedTab = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .reevaluateOnboardingCompleted)) { _ in
            finishReevaluationFlow()
        }
    }

    private func resetState(for tab: MainCoordinator.Tab) {
        switch tab {
        case .home:
            homeRootID = UUID()
        case .rewards:
            rewardsRootID = UUID()
        case .profile:
            profileRootID = UUID()
        }
    }

    private func beginReevaluationFlow() {
        reevaluateOnboardingViewModel.resetForNewOnboarding()
        isShowingReevaluateOnboarding = true
    }

    private func finishReevaluationFlow() {
        isShowingReevaluateOnboarding = false
        mainCoordinator.selectedTab = .home
        homeRootID = UUID()
        rewardsRootID = UUID()
        profileRootID = UUID()
        homeViewModel.load()
        rewardsViewModel.load()
        profileViewModel.load()
        profileViewModel.loadCheckInHistory()
    }

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.richBlack).withAlphaComponent(0.95)

        let normal = appearance.stackedLayoutAppearance.normal
        normal.iconColor = UIColor(AppPalette.textSecondary)
        normal.titleTextAttributes = [
            .foregroundColor: UIColor(AppPalette.textSecondary),
            .font: UIFont(name: "AvenirNext-Medium", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .medium)
        ]

        let selected = appearance.stackedLayoutAppearance.selected
        selected.iconColor = UIColor(AppPalette.accent)
        selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppPalette.accent),
            .font: UIFont(name: "AvenirNext-DemiBold", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

}

extension Notification.Name {
    static let widgetCheckInRequested = Notification.Name("widgetCheckInRequested")
    static let reevaluateOnboardingCompleted = Notification.Name("reevaluateOnboardingCompleted")
}

@MainActor
private struct MainTabPreviewHost: View {
    private let container = PreviewSupport.makeSeededContainer()

    var body: some View {
        MainTabView(container: container, onSignOut: { })
    }
}

#Preview("Main Tab") {
    MainTabPreviewHost()
}
