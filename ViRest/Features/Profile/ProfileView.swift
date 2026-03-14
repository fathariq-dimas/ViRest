import SwiftUI

struct ProfileView: View {
    @ObservedObject private var viewModel: ProfileViewModel
    
    private var historyCard: some View {
        SurfaceCard {
            Text("Recent Activity")
                .font(AppTypography.title(18))
                .foregroundStyle(AppPalette.textPrimary)

            if viewModel.checkInHistory.isEmpty {
                Text("No sessions logged yet.")
                    .font(AppTypography.body(14))
                    .foregroundStyle(AppPalette.textSecondary)
            } else {
                ForEach(viewModel.checkInHistory.prefix(10)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.sportName)
                                .font(AppTypography.body(14))
                                .foregroundStyle(AppPalette.textPrimary)
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(AppTypography.caption(12))
                                .foregroundStyle(AppPalette.textSecondary)
                        }
                        Spacer()
                        Text("\(entry.durationMinutes) min")
                            .font(AppTypography.caption(13))
                            .foregroundStyle(AppPalette.accent)
                    }
                    Divider().overlay(Color.white.opacity(0.1))
                }
            }
        }
    }

    private let onSignOut: () -> Void

    init(viewModel: ProfileViewModel, onSignOut: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.richBlack.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if let profile = viewModel.profile {
                            profileCard(profile)
                            goalCard
                            gamificationCard
                        } else {
                            SurfaceCard {
                                Text("Profile not found.")
                                    .font(AppTypography.body(15))
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                        }
                        historyCard

                        if let info = viewModel.infoMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.white)
                                Text(info)
                                    .font(AppTypography.caption(13))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(11)
                            .background(
                                LinearGradient(
                                    colors: [AppPalette.auroraA.opacity(0.85), AppPalette.auroraB.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button {
                            onSignOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }
                    .padding(16)
                    .padding(.bottom, 22)
                }
            }
            .navigationTitle("Profile")
            .toolbarTitleDisplayMode(.inline)
            .task {
                viewModel.load()
                viewModel.loadCheckInHistory()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func profileCard(_ profile: UserProfileInput) -> some View {
        SurfaceCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.fullName)
                        .font(AppTypography.hero(28))
                        .foregroundStyle(AppPalette.textPrimary)
                    Text("Personal profile")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textSecondary)
                }

                Spacer()

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(AppPalette.accent)
            }

            row("Height", value: profile.heightCm.map { String(format: "%.0f cm", $0) } ?? "-")
            row("Weight", value: profile.weightKg.map { String(format: "%.1f kg", $0) } ?? "-")
            row("Target RHR", value: profile.questionnaireTargetRHRGoal?.displayName ?? "-")
        }
    }

    private var goalCard: some View {
        SurfaceCard {
            sectionTitle("Weekly Goal", icon: "target")

            lockedGoalRow(label: "Time frame", value: "Per Week")
            lockedGoalRow(label: "Goal type", value: "Activity")
            lockedGoalRow(label: "Frequency", value: viewModel.weeklyGoal.weeklySummary)

            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                Text("Goal is locked after onboarding setup.")
                    .font(AppTypography.caption(12))
            }
            .foregroundStyle(AppPalette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var gamificationCard: some View {
        SurfaceCard {
            sectionTitle("Progress", icon: "sparkles.rectangle.stack")

            row("Level", value: "Level \(viewModel.badgeState.level.rawValue) · \(viewModel.badgeState.level.title)")
            row("Completed sessions", value: "\(viewModel.badgeState.completedSessions)")
            row("Current streak", value: "\(viewModel.badgeState.currentStreak) days")

            if let nextTarget = viewModel.badgeState.level.nextTargetSessions {
                let remaining = max(0, nextTarget - viewModel.badgeState.completedSessions)
                row("Next level", value: "\(remaining) more activities")
            } else {
                row("Next level", value: "Max level reached")
            }

            if !viewModel.badgeState.earnedBadges.isEmpty {
                Text("Badges")
                    .font(AppTypography.caption(13))
                    .foregroundStyle(AppPalette.textSecondary)

                ForEach(viewModel.badgeState.earnedBadges) { badge in
                    Text("• \(badge.type.title)")
                        .font(AppTypography.body(14))
                        .foregroundStyle(AppPalette.textPrimary)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppPalette.accent)
            Text(title)
                .font(AppTypography.title(20))
                .foregroundStyle(AppPalette.textPrimary)
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.caption(13))
                .foregroundStyle(AppPalette.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.body(15))
                .foregroundStyle(AppPalette.textPrimary)
        }
        .padding(.vertical, 2)
    }

    private func lockedGoalRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.caption(13))
                .foregroundStyle(AppPalette.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.body(15))
                .foregroundStyle(AppPalette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@MainActor
private struct ProfilePreviewHost: View {
    private let container: AppContainer
    private let viewModel: ProfileViewModel

    init() {
        let seededContainer = PreviewSupport.makeSeededContainer()
        self.container = seededContainer
        self.viewModel = ProfileViewModel(
            userProfileRepository: seededContainer.userProfileRepository,
            planRepository: seededContainer.planRepository,
            badgeRepository: seededContainer.badgeStateRepository,
            firestoreUserRepository: seededContainer.firestoreUserRepository,
            authService: seededContainer.authService
        )
    }

    var body: some View {
        ProfileView(viewModel: viewModel, onSignOut: { })
    }
}

#Preview("Profile") {
    ProfilePreviewHost()
}
