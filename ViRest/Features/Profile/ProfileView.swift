import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject private var viewModel: ProfileViewModel
    @State private var showAllRecentActivity = false
    @State private var showNotSuitableSports = false
    @State private var manualSwitchTarget: FirestoreSportEntry?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    
    private var historyCard: some View {
        SurfaceCard {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(AppPalette.accent)
                    Text("Recent Activity")
                        .font(AppTypography.title(20))
                        .foregroundStyle(AppPalette.textPrimary)
                }

                Spacer()

                if viewModel.checkInHistory.count > 5 {
                    Button {
                        showAllRecentActivity = true
                    } label: {
                        Text("See more")
                            .font(AppTypography.caption(13))
                            .foregroundStyle(AppPalette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.checkInHistory.isEmpty {
                Text("No sessions logged yet.")
                    .font(AppTypography.body(14))
                    .foregroundStyle(AppPalette.textSecondary)
            } else {
                ForEach(viewModel.checkInHistory.prefix(5)) { entry in
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
    private let onReevaluateRequested: () -> Void

    init(
        viewModel: ProfileViewModel,
        onSignOut: @escaping () -> Void,
        onReevaluateRequested: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onSignOut = onSignOut
        self.onReevaluateRequested = onReevaluateRequested
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.richBlack.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        userInfoCard
                        reminderSettingsCard
                        reEvaluateCard

                        if !viewModel.sportPlanSports.isEmpty {
                            sportSettingsCard
                        }
                        notSuitableSportsCard
                        historyCard

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
            .navigationDestination(isPresented: $showAllRecentActivity) {
                RecentActivityListView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $showNotSuitableSports) {
                NotSuitableSportsListView(viewModel: viewModel)
            }
            .sheet(item: $manualSwitchTarget) { sport in
                ManualSportSwitchSheet(
                    sport: sport,
                    cooldownMessage: viewModel.manualSwitchCooldownMessage(),
                    onConfirm: { reason in
                        viewModel.requestManualSportSwitch(to: sport.id, reason: reason)
                        manualSwitchTarget = nil
                    },
                    onCancel: {
                        manualSwitchTarget = nil
                    }
                )
            }
            .task {
                viewModel.load()
                viewModel.loadCheckInHistory()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshNotificationAuthorizationStatus()
                }
            }
            .onChange(of: viewModel.shouldOpenNotificationSettings) { _, shouldOpen in
                guard shouldOpen else { return }
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
                viewModel.consumeOpenSettingsRequest()
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

    private var userInfoCard: some View {
        SurfaceCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.badgeState.level.title.isEmpty ? "Starter" : viewModel.badgeState.level.title)
                        .font(AppTypography.caption(14))
                        .foregroundStyle(AppPalette.textSecondary)

                    Text(viewModel.profileName)
                        .font(AppTypography.hero(24))
                        .foregroundStyle(AppPalette.textPrimary)
                }

                Spacer()

                ZStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.richBlack)
                        .font(.largeTitle)
                }
                .padding()
                .background(.gray)
                .clipShape(Circle())
            }

            HStack(spacing: 12) {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.vibrantGreen)

                        Text(viewModel.currentRestingHRText)
                            .font(AppTypography.caption(14).bold())
                            .foregroundStyle(AppPalette.textPrimary)
                    }

                    Text("Resting HR")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textPrimary)
                }

                Divider()
                    .overlay(.vibrantGreen)

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "scalemass.fill")
                            .foregroundStyle(.vibrantGreen)

                        Text(viewModel.currentWeightText)
                            .font(AppTypography.caption(14).bold())
                            .foregroundStyle(AppPalette.textPrimary)
                    }

                    Text("Weight")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textPrimary)
                }

                Divider()
                    .overlay(.vibrantGreen)

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "ruler.fill")
                            .foregroundStyle(.vibrantGreen)
                            .rotationEffect(.degrees(90))

                        Text(viewModel.currentHeightText)
                            .font(AppTypography.caption(14).bold())
                            .foregroundStyle(AppPalette.textPrimary)
                    }

                    Text("Height")
                        .font(AppTypography.caption(12))
                        .foregroundStyle(AppPalette.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                viewModel.syncAppleHealthFromProfile()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isAppleHealthSyncing {
                        ProgressView()
                            .tint(AppPalette.accent)
                    } else {
                        Image(systemName: syncAppleHealthIconName)
                    }

                    Text(viewModel.appleHealthSyncButtonTitle)
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(viewModel.isAppleHealthSyncing)
            .opacity(viewModel.isAppleHealthSyncing ? 0.7 : 1)
        }
    }

    private var reminderSettingsCard: some View {
        SurfaceCard {
            reminderSettingsSection
        }
    }

    private var reminderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Reminder Time", icon: "bell.badge")

            Text("\(viewModel.reminderModeDisplayText) • \(viewModel.reminderTimeDisplayText)")
                .font(AppTypography.caption(12))
                .foregroundStyle(AppPalette.textSecondary)

            if viewModel.isNotificationAuthorized {
                HStack(spacing: 10) {
                    Text("Custom reminder")
                        .font(AppTypography.body(14))
                        .foregroundStyle(AppPalette.textPrimary)

                    Spacer()

                    DatePicker(
                        "",
                        selection: $viewModel.reminderPickerDate,
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(AppPalette.accent)
                    .colorScheme(.dark)
                }

                Button("Save Reminder Time") {
                    viewModel.saveCustomReminderTime()
                }
                .buttonStyle(PrimaryActionButtonStyle())

                if viewModel.profile?.customReminderTime != nil {
                    Button("Use Default Time") {
                        viewModel.resetReminderToDefault()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            } else {
                Text("Notifications are off. Enable notifications to customize reminder time.")
                    .font(AppTypography.caption(12))
                    .foregroundStyle(AppPalette.textSecondary)

                Button("Enable Notifications for Reminder") {
                    viewModel.requestNotificationAccessForReminder()
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
    }

    private var syncAppleHealthIconName: String {
        if viewModel.isAppleHealthSynced {
            return "checkmark.circle.fill"
        }
        
        return "heart.text.square.fill"
    }

    private var reEvaluateCard: some View {
        SurfaceCard {
            sectionTitle("Re-evaluate Plan", icon: "arrow.clockwise.circle")

            Text("Run onboarding again to update your profile input and generate new sport recommendations. Your current active plan will be replaced with the new recommendation set.")
                .font(AppTypography.caption(12))
                .foregroundStyle(AppPalette.textSecondary)

            Button("Re-evaluate Recommendations") {
                onReevaluateRequested()
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    private var sportSettingsCard: some View {
        SurfaceCard {
            sectionTitle("Sport Settings", icon: "slider.horizontal.3")

            Text("Choose your active sport for Home. Non-selected sports remain locked.")
                .font(AppTypography.caption(12))
                .foregroundStyle(AppPalette.textSecondary)

            VStack(spacing: 10) {
                ForEach(viewModel.sportPlanSports) { sport in
                    let isSelected = viewModel.selectedSportId == sport.id
                    let isMarkedNotSuitable = viewModel.isSportMarkedNotSuitable(sport.id) && !isSelected
                    Button {
                        guard !isSelected else { return }
                        guard !isMarkedNotSuitable else { return }
                        manualSwitchTarget = sport
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sport.displayName)
                                    .font(AppTypography.body(15))
                                    .foregroundStyle(AppPalette.textPrimary)
                                Text("\(sport.durationMinutes) min/session · \(sport.weeklyTargetCount)x/week")
                                    .font(AppTypography.caption(12))
                                    .foregroundStyle(AppPalette.textSecondary)
                            }

                            Spacer()

                            if isMarkedNotSuitable {
                                Text("Not suitable")
                                    .font(AppTypography.caption(11))
                                    .foregroundStyle(.yellow)
                            } else {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(isSelected ? AppPalette.accent : AppPalette.textSecondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isSelected ? AppPalette.accent.opacity(0.85) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isMarkedNotSuitable)
                    .opacity(isMarkedNotSuitable ? 0.65 : 1)
                }
            }
        }
    }

    private var notSuitableSportsCard: some View {
        SurfaceCard {
            HStack {
                sectionTitle("Not Suitable Sports", icon: "exclamationmark.shield")
                Spacer()
                if viewModel.hasNotSuitableSports {
                    Button("See more") {
                        showNotSuitableSports = true
                    }
                    .buttonStyle(.plain)
                    .font(AppTypography.caption(13))
                    .foregroundStyle(AppPalette.accent)
                }
            }

            if viewModel.notSuitableSportItems.isEmpty {
                Text("No sports are marked as not suitable.")
                    .font(AppTypography.caption(12))
                    .foregroundStyle(AppPalette.textSecondary)
            } else {
                ForEach(viewModel.notSuitableSportItems.prefix(2)) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(AppTypography.body(14))
                                .foregroundStyle(AppPalette.textPrimary)
                            Text("Last reason: \(item.lastReasonText)")
                                .font(AppTypography.caption(12))
                                .foregroundStyle(AppPalette.textSecondary)
                        }

                        Spacer()

                        Text("Blocked")
                            .font(AppTypography.caption(11))
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
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
}

private struct NotSuitableSportsListView: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        ZStack {
            Color.richBlack.ignoresSafeArea()

            if viewModel.notSuitableSportItems.isEmpty {
                Text("No blocked sports right now.")
                    .font(AppTypography.body(14))
                    .foregroundStyle(AppPalette.textSecondary)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(viewModel.notSuitableSportItems) { item in
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(item.displayName)
                                        .font(AppTypography.title(18))
                                        .foregroundStyle(AppPalette.textPrimary)

                                    Text("Last reason: \(item.lastReasonText)")
                                        .font(AppTypography.caption(12))
                                        .foregroundStyle(AppPalette.textSecondary)

                                    Text("Recorded switches: \(item.totalReasonCount)")
                                        .font(AppTypography.caption(12))
                                        .foregroundStyle(AppPalette.textSecondary)

                                    Button {
                                        viewModel.unflagNotSuitableSport(item.sportId)
                                    } label: {
                                        if viewModel.updatingNotSuitableSportId == item.sportId {
                                            HStack(spacing: 8) {
                                                ProgressView().tint(AppPalette.accent)
                                                Text("Allowing...")
                                            }
                                        } else {
                                            Text("Allow Again")
                                        }
                                    }
                                    .buttonStyle(PrimaryActionButtonStyle())
                                    .disabled(viewModel.updatingNotSuitableSportId == item.sportId)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 22)
                }
            }
        }
        .navigationTitle("Not Suitable Sports")
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct RecentActivityListView: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        ZStack {
            Color.richBlack.ignoresSafeArea()

            if viewModel.checkInHistory.isEmpty {
                Text("No sessions logged yet.")
                    .font(AppTypography.body(14))
                    .foregroundStyle(AppPalette.textSecondary)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        SurfaceCard {
                            HStack(spacing: 10) {
                                Image(systemName: "figure.run")
                                    .foregroundStyle(AppPalette.accent)
                                Text("Total activities completed")
                                    .font(AppTypography.body(14))
                                    .foregroundStyle(AppPalette.textSecondary)
                                Spacer()
                                Text("\(viewModel.totalActivityCompletedCount)")
                                    .font(AppTypography.title(18))
                                    .foregroundStyle(AppPalette.textPrimary)
                            }
                        }

                        ForEach(viewModel.checkInHistory) { entry in
                            SurfaceCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.sportName)
                                            .font(AppTypography.title(16))
                                            .foregroundStyle(AppPalette.textPrimary)
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(AppTypography.caption(12))
                                            .foregroundStyle(AppPalette.textSecondary)
                                    }

                                    Spacer()

                                    Text("\(entry.durationMinutes) min")
                                        .font(AppTypography.caption(13).bold())
                                        .foregroundStyle(AppPalette.accent)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 22)
                }
            }
        }
        .navigationTitle("Recent Activity")
        .toolbarTitleDisplayMode(.inline)
        .task {
            viewModel.loadCheckInHistory(limit: 200)
        }
    }
}

private struct ManualSportSwitchSheet: View {
    let sport: FirestoreSportEntry
    let cooldownMessage: String?
    let onConfirm: (SwitchReason) -> Void
    let onCancel: () -> Void

    @State private var selectedReason: SwitchReason = .notSuitable
    @State private var sheetHeight: CGFloat = 420

    var body: some View {
        ZStack {
            AppBottomSheetStyle.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppBottomSheetStyle.contentSpacing) {
                    AppBottomSheetHandle()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Switch Sport")
                            .font(AppTypography.title(22))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text("Switch active sport to \(sport.displayName)?")
                            .font(AppTypography.body(14))
                            .foregroundStyle(AppPalette.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reason")
                            .font(AppTypography.caption(12))
                            .foregroundStyle(AppPalette.textSecondary)

                        ForEach(SwitchReason.allCases) { reason in
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedReason == reason ? AppPalette.accent : AppPalette.textSecondary)
                                    Text(reason.displayName)
                                        .font(AppTypography.body(14))
                                        .foregroundStyle(AppPalette.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let cooldownMessage {
                        Text(cooldownMessage)
                            .font(AppTypography.caption(12))
                            .foregroundStyle(.yellow)
                    }

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("Confirm Switch") {
                            onConfirm(selectedReason)
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(cooldownMessage != nil)
                        .opacity(cooldownMessage == nil ? 1 : 0.6)
                    }
                }
                .padding(.horizontal, AppBottomSheetStyle.horizontalPadding)
                .padding(.bottom, AppBottomSheetStyle.bottomPadding)
                .onIntrinsicHeightChange { contentHeight in
                    sheetHeight = SheetSizing.fittedHeight(
                        from: contentHeight,
                        minHeight: 330,
                        maxFraction: 0.78,
                        extra: 12
                    )
                }
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
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
            authService: seededContainer.authService,
            notificationService: seededContainer.notificationService,
            healthService: seededContainer.healthService,
            healthDataResolver: seededContainer.healthDataResolver,
            sportSwitchOrchestrator: seededContainer.sportSwitchOrchestrator
        )
    }

    var body: some View {
        ProfileView(viewModel: viewModel, onSignOut: { })
    }
}

#Preview("Profile") {
    ProfilePreviewHost()
}
