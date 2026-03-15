import SwiftUI

struct RewardsView: View {
    @ObservedObject private var viewModel: RewardsViewModel
    private let levelCardIconSlotWidth: CGFloat = 24
    private let levelCardIconTextSpacing: CGFloat = 12

    init(viewModel: RewardsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.richBlack.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        levelCard
                        badgesCard
                    }
                    .padding(16)
                    .padding(.bottom, 22)
                }
            }
            .navigationTitle("Rewards")
            .toolbarTitleDisplayMode(.inline)
            .task { viewModel.load() }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var levelCard: some View {
        SurfaceCard {
            HStack(spacing: levelCardIconTextSpacing) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: levelCardIconSlotWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Level Progress")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textSecondary)

                    Text(viewModel.levelSummary)
                        .font(AppTypography.title(20))
                        .foregroundStyle(AppPalette.textPrimary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activities")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(viewModel.totalActivitiesCount)")
                            .font(AppTypography.hero(24))
                            .foregroundStyle(AppPalette.accent)

                        Text("/\(viewModel.resolvedLevel.nextTargetSessions.map(String.init) ?? "-")")
                            .font(AppTypography.body(16))
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }
            }

            HStack(alignment: .center, spacing: levelCardIconTextSpacing) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: levelCardIconSlotWidth, alignment: .center)
                
                Text("Title: \(viewModel.currentTitleName)")
                    .font(AppTypography.body(14))
                    .foregroundStyle(AppPalette.textPrimary)

                Spacer()

                NavigationLink {
                    TitleLevelsView(currentLevel: viewModel.resolvedLevel)
                } label: {
                    Text("See more")
                        .font(AppTypography.caption(13))
                        .foregroundStyle(AppPalette.accent)
                }
            }
            .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 16) {
                HStack(alignment: .top, spacing: levelCardIconTextSpacing) {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                        .foregroundStyle(.vibrantGreen)
                        .frame(width: levelCardIconSlotWidth, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        if let title = viewModel.nextLevelTitle {
                            Text(title)
                                .font(AppTypography.body(16).bold())
                                .foregroundStyle(AppPalette.accent)
                        }

                        Text(viewModel.nextLevelDetail)
                            .font(AppTypography.body(12))
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }

                Spacer()

                circularProgressRing(
                    progress: viewModel.levelProgress,
                    label: "\(Int((viewModel.levelProgress * 100).rounded()))%"
                )
            }
        }
    }

    private var badgesCard: some View {
        SurfaceCard {
            HStack(spacing: 8) {
                Image(systemName: "rosette")
                    .foregroundStyle(AppPalette.accent)
                Text("Badges")
                    .font(AppTypography.title(20))
                    .foregroundStyle(AppPalette.textPrimary)
                Spacer()
                NavigationLink {
                    BadgeGalleryView(viewModel: viewModel)
                } label: {
                    Text("See more")
                        .font(AppTypography.caption(13))
                        .foregroundStyle(AppPalette.accent)
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(BadgeType.allCases.prefix(3))) { badgeType in
                    badgeRow(for: badgeType)
                }
            }
        }
    }

    private func badgeRow(for badgeType: BadgeType) -> some View {
        let earned = viewModel.badgeState.earnedBadges.first { $0.type == badgeType }
        let criterion = viewModel.badgeState.criterion(for: badgeType)
        let target = max(1, criterion?.targetValue ?? 1)
        let current = criterion.map { viewModel.badgeState.metricValue(for: $0.kind) } ?? 0
        let progress = min(1.0, Double(current) / Double(target))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: badgeType.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(earned == nil ? AppPalette.textSecondary : AppPalette.accent)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(badgeType.title)
                        .font(AppTypography.body(15))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text(criterion?.summary ?? "Random criteria is being prepared.")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textSecondary)
                }

                Spacer()

                if let earned {
                    Text("Unlocked")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.green.opacity(0.4), lineWidth: 1)
                        )
                        .accessibilityLabel("Unlocked on \(earned.earnedAt.formatted(date: .abbreviated, time: .omitted))")
                } else {
                    Text(criterion?.kind.progressText(current: current, target: target) ?? "0/0")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textSecondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(earned == nil ? AppPalette.accentSecondary : .green)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func circularProgressRing(progress: Double, label: String) -> some View {
        let clampedProgress = min(1, max(0, progress))

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 8)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    AppPalette.accent,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(label)
                    .font(AppTypography.body(13))
                    .foregroundStyle(AppPalette.textPrimary)
                Text("Progress")
                    .font(AppTypography.caption(10))
                    .foregroundStyle(AppPalette.textSecondary)
            }
        }
        .frame(width: 86, height: 86)
    }
}

@MainActor
private struct RewardsPreviewHost: View {
    private let container = PreviewSupport.makeSeededContainer()
    private let viewModel: RewardsViewModel

    init() {
        self.viewModel = RewardsViewModel(
            badgeRepository: container.badgeStateRepository,
            firestoreUserRepository: container.firestoreUserRepository,
            authService: container.authService
        )
    }

    var body: some View {
        RewardsView(viewModel: viewModel)
    }
}

#Preview("Rewards") {
    RewardsPreviewHost()
}

private struct TitleLevelsView: View {
    let currentLevel: ProgressionLevel

    var body: some View {
        ZStack {
            Color.richBlack.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(ProgressionLevel.allCases, id: \.rawValue) { level in
                        titleRow(level: level)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Title Levels")
        .toolbarTitleDisplayMode(.inline)
    }

    private func titleRow(level: ProgressionLevel) -> some View {
        let unlocked = level.rawValue <= currentLevel.rawValue
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(unlocked ? AppPalette.accent.opacity(0.2) : Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                Text("\(level.rawValue)")
                    .font(AppTypography.caption(13))
                    .foregroundStyle(unlocked ? AppPalette.accent : AppPalette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(level.title)
                    .font(AppTypography.body(15))
                    .foregroundStyle(AppPalette.textPrimary)
                Text("Unlock at \(level.minSessions) activities")
                    .font(AppTypography.caption(12))
                    .foregroundStyle(AppPalette.textSecondary)
            }

            Spacer()

            Text(unlocked ? "Unlocked" : "Locked")
                .font(AppTypography.caption(12))
                .foregroundStyle(unlocked ? .green : AppPalette.textSecondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
