import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class ProfileViewModel: ObservableObject {
    struct NotSuitableSportItem: Identifiable {
        var id: String { sportId }
        let sportId: String
        let displayName: String
        let lastReasonText: String
        let totalReasonCount: Int
        let lastUpdatedAt: Date
    }

    @Published var profileName: String = "Virest User"
    @Published var currentRestingHRText: String = "-"
    @Published var currentWeightText: String = "-"
    @Published var currentHeightText: String = "-"
    @Published var isAppleHealthSynced: Bool = false
    @Published var isAppleHealthSyncing: Bool = false
    @Published private(set) var isAppleHealthAuthorized: Bool = false
    @Published private(set) var isNotificationAuthorized: Bool = false
    @Published var reminderPickerDate: Date = Date()
    @Published var shouldOpenNotificationSettings: Bool = false

    @Published var profile: UserProfileInput?
    @Published var badgeState: BadgeState = .default
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var firestoreUser: FirestoreUser?
    @Published var currentTitle: FirestoreTitle?
    @Published var allTitles: [FirestoreTitle] = []
    @Published var checkInHistory: [CheckInHistoryEntry] = []
    @Published var sportPlanSports: [FirestoreSportEntry] = []
    @Published var selectedSportId: String?
    @Published var notSuitableSportIds: Set<String> = []
    @Published var updatingNotSuitableSportId: String?

    var totalActivityCompletedCount: Int {
        let remoteCount = firestoreUser?.totalActionsCompleted ?? 0
        return max(remoteCount, checkInHistory.count)
    }


    private let userProfileRepository: UserProfileRepository
    private let planRepository: PlanRepository
    private let badgeRepository: BadgeStateRepository
    private let firestoreUserRepository: FirestoreUserRepository
    private let authService: AuthProviding
    private let notificationService: NotificationScheduling
    private let healthService: HealthDataProviding
    private let healthDataResolver: HealthDataResolving
    private let sportSwitchOrchestrator: SportSwitchOrchestrating
    private var syncedStatusResetTask: Task<Void, Never>?

    var appleHealthSyncButtonTitle: String {
        if isAppleHealthSynced {
            return "Apple Health Synced"
        }
        
        if isAppleHealthSyncing {
            return "Syncing Apple Health..."
        }
        
        return "Sync with Apple Health"
    }

    var reminderTimeDisplayText: String {
        formatReminderTime(profile?.resolvedReminderDateComponents ?? PreferredTime.flexible.reminderDateComponents)
    }

    var reminderModeDisplayText: String {
        profile?.customReminderTime == nil
            ? "Using default reminder time"
            : "Using custom reminder time"
    }

    init(
        userProfileRepository: UserProfileRepository,
        planRepository: PlanRepository,
        badgeRepository: BadgeStateRepository,
        firestoreUserRepository: FirestoreUserRepository,
        authService: AuthProviding,
        notificationService: NotificationScheduling,
        healthService: HealthDataProviding,
        healthDataResolver: HealthDataResolving,
        sportSwitchOrchestrator: SportSwitchOrchestrating
    ) {
        self.userProfileRepository = userProfileRepository
        self.planRepository = planRepository
        self.badgeRepository = badgeRepository
        self.firestoreUserRepository = firestoreUserRepository
        self.authService = authService
        self.notificationService = notificationService
        self.healthService = healthService
        self.healthDataResolver = healthDataResolver
        self.sportSwitchOrchestrator = sportSwitchOrchestrator
    }

    func load() {
        Task {
            await loadInternal()
        }
    }

    func refreshNotificationAuthorizationStatus() {
        Task {
            isNotificationAuthorized = await notificationService.isAuthorizationGranted()
        }
    }

    func requestNotificationAccessForReminder() {
        Task {
            await requestNotificationAccessForReminderInternal()
        }
    }

    func saveCustomReminderTime() {
        Task {
            await saveCustomReminderTimeInternal()
        }
    }

    func resetReminderToDefault() {
        Task {
            await resetReminderToDefaultInternal()
        }
    }

    func consumeOpenSettingsRequest() {
        shouldOpenNotificationSettings = false
    }

    private func loadInternal() async {
        isLoading = true
        guard case .signedIn(let user) = authService.authState else {
            isLoading = false; return
        }
        do {
            isAppleHealthSynced = false
            isAppleHealthAuthorized = healthService.authorizationState == .authorized
            isNotificationAuthorized = await notificationService.isAuthorizationGranted()
            firestoreUser = try await firestoreUserRepository.loadUser(userId: user.id)
            sportPlanSports = firestoreUser?.sportPlan?.resolvedSports(at: Date()) ?? []
            selectedSportId = firestoreUser?.sportPlan?.resolvedSelectedSportId
            notSuitableSportIds = Set(
                firestoreUser?.sportSuitabilityFlags?.compactMap { key, value in
                    value.isNotSuitable ? key : nil
                } ?? []
            )

            // Load all titles for progress display
            let db = Firestore.firestore()
            let snapshot = try await db.collection("titles")
                .order(by: "displayOrder").getDocuments()
            allTitles = try snapshot.documents.map { try $0.data(as: FirestoreTitle.self) }

            // Identify current title
            if let titleId = firestoreUser?.currentTitleId {
                currentTitle = allTitles.first { $0.id == titleId }
            }

            // Keep local SwiftData in sync (for offline fallback)
            profile = try userProfileRepository.loadProfile()
            if let profile {
                reminderPickerDate = profile.customReminderTime?.toDate() ?? profileDefaultReminderDate(profile)
            } else {
                reminderPickerDate = profileDefaultReminderDate(nil)
            }
            var localBadgeState = try badgeRepository.loadState()
            let didChangeLocalBadgeState = localBadgeState.normalizeRandomCriteriaIfNeeded()
            if didChangeLocalBadgeState {
                try badgeRepository.saveState(localBadgeState)
            }
            if var remoteBadgeState = firestoreUser?.badgeState {
                let remoteChanged = remoteBadgeState.normalizeRandomCriteriaIfNeeded()
                badgeState = remoteBadgeState
                try badgeRepository.saveState(remoteBadgeState)
                if remoteChanged {
                    try? await firestoreUserRepository.saveBadgeState(userId: user.id, state: remoteBadgeState)
                }
            } else {
                badgeState = localBadgeState
                try? await firestoreUserRepository.saveBadgeState(userId: user.id, state: localBadgeState)
            }
            updateProfileName(localProfile: profile)
            await updateVitals(localProfile: profile)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func syncAppleHealthFromProfile() {
        guard !isAppleHealthSyncing else { return }

        Task {
            await syncAppleHealthFromProfileInternal()
        }
    }

    func selectActiveSport(_ sportId: String) {
        Task {
            await selectActiveSportInternal(sportId, reason: .notSuitable, origin: .manualProfile)
        }
    }

    func requestManualSportSwitch(to sportId: String, reason: SwitchReason) {
        Task {
            await selectActiveSportInternal(sportId, reason: reason, origin: .manualProfile)
        }
    }

    func isSportMarkedNotSuitable(_ sportId: String) -> Bool {
        notSuitableSportIds.contains(sportId)
    }

    var hasNotSuitableSports: Bool {
        !notSuitableSportItems.isEmpty
    }

    var notSuitableSportItems: [NotSuitableSportItem] {
        let flags = firestoreUser?.sportSuitabilityFlags ?? [:]
        return flags.compactMap { sportId, flag in
            guard flag.isNotSuitable else { return nil }
            return NotSuitableSportItem(
                sportId: sportId,
                displayName: sportDisplayName(for: sportId),
                lastReasonText: flag.lastReason?.displayName ?? "Not suitable",
                totalReasonCount: flag.reasonCounts.values.reduce(0, +),
                lastUpdatedAt: flag.lastUpdatedAt
            )
        }
        .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    func unflagNotSuitableSport(_ sportId: String) {
        Task {
            await unflagNotSuitableSportInternal(sportId)
        }
    }

    func manualSwitchCooldownMessage() -> String? {
        guard let plan = firestoreUser?.sportPlan else { return nil }
        guard let remaining = sportSwitchOrchestrator.cooldownRemaining(
            for: plan,
            origin: .manualProfile,
            now: Date()
        ) else {
            return nil
        }

        let days = Int(ceil(remaining / 86_400))
        if days <= 1 {
            return "You can switch again in less than 1 day."
        }
        return "You can switch again in \(days) days."
    }
    
    func loadCheckInHistory(limit: Int = 30) {
        Task {
            guard case .signedIn(let user) = authService.authState else { return }
            do {
                checkInHistory = try await firestoreUserRepository.loadCheckInHistory(userId: user.id, limit: limit)
            } catch {
                // Non-fatal — just leave history empty
                print("Could not load check-in history: \(error)")
            }
        }
    }

    private func syncAppleHealthFromProfileInternal() async {
        isAppleHealthSyncing = true
        defer { isAppleHealthSyncing = false }

        if !isAppleHealthAuthorized {
            let granted = await healthService.requestAuthorization()
            isAppleHealthAuthorized = granted || healthService.authorizationState == .authorized
            guard isAppleHealthAuthorized else {
                errorMessage = "Health access denied. You can enable permissions from iOS Settings > Health > Data Access."
                return
            }
        }

        var resolvedProfile = profile ?? (try? userProfileRepository.loadProfile())
        if resolvedProfile == nil {
            resolvedProfile = UserProfileInput(
                fullName: profileName == "Virest User" ? "" : profileName,
                age: firestoreUser?.age,
                questionnaireCurrentRHRBand: currentRHRBand(from: firestoreUser?.restingHeartRate),
                questionnaireTargetRHRGoal: targetRHRGoal(from: firestoreUser?.targetRestingHeartRate),
                heightCm: firestoreUser?.heightCm,
                weightKg: firestoreUser?.weightKg,
                preferredTime: .flexible,
                updatedAt: Date()
            )
        }
        let snapshot = await healthService.fetchLatestSnapshot(profile: resolvedProfile)

        var didUpdateProfile = false
        if var profileToUpdate = resolvedProfile {
            if isProfileMetricEmpty(profileToUpdate.heightCm), let importedHeight = snapshot.heightCm {
                profileToUpdate.heightCm = importedHeight
                didUpdateProfile = true
            }
            if isProfileMetricEmpty(profileToUpdate.weightKg), let importedWeight = snapshot.weightKg {
                profileToUpdate.weightKg = importedWeight
                didUpdateProfile = true
            }

            if didUpdateProfile {
                profileToUpdate.updatedAt = Date()
                do {
                    try userProfileRepository.saveProfile(profileToUpdate)
                    if case .signedIn(let user) = authService.authState {
                        try await firestoreUserRepository.saveProfile(userId: user.id, profile: profileToUpdate)
                    }
                    profile = profileToUpdate
                    resolvedProfile = profileToUpdate
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }

        await updateVitals(localProfile: resolvedProfile)
        if case .signedIn(let user) = authService.authState {
            try? await firestoreUserRepository.upsertRHRTracking(
                userId: user.id,
                bpm: snapshot.restingHeartRate,
                source: snapshot.restingHeartRateSource,
                collectedAt: snapshot.collectedAt
            )
        }
        showTemporarySyncedStatus()
    }

    private func showTemporarySyncedStatus() {
        syncedStatusResetTask?.cancel()
        isAppleHealthSynced = true
        syncedStatusResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isAppleHealthSynced = false
            }
        }
    }

    private func selectActiveSportInternal(_ sportId: String, reason: SwitchReason, origin: SwitchOrigin) async {
        guard case .signedIn(let user) = authService.authState else { return }
        guard var plan = firestoreUser?.sportPlan else { return }
        guard plan.resolvedSelectedSportId != sportId else { return }

        isLoading = true
        errorMessage = nil

        do {
            let resolvedProfile = (try? userProfileRepository.loadProfile()) ?? profile
            let healthSnapshot = await healthService.fetchLatestSnapshot(profile: resolvedProfile)
            let outcome = try await sportSwitchOrchestrator.requestSportSwitch(
                userId: user.id,
                currentPlan: plan,
                requestedSportId: sportId,
                reason: reason,
                origin: origin,
                userProfile: resolvedProfile,
                healthSnapshot: healthSnapshot,
                preferredReminderTime: resolvedProfile?.resolvedReminderDateComponents ?? PreferredTime.flexible.reminderDateComponents
            )
            plan = outcome.updatedPlan
            firestoreUser?.sportPlan = plan
            sportPlanSports = plan.resolvedSports(at: Date())
            selectedSportId = plan.resolvedSelectedSportId

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func unflagNotSuitableSportInternal(_ sportId: String) async {
        guard case .signedIn(let user) = authService.authState else { return }

        updatingNotSuitableSportId = sportId
        defer { updatingNotSuitableSportId = nil }

        do {
            let updatedFlags = try await firestoreUserRepository.clearSportNotSuitableFlag(
                userId: user.id,
                sportId: sportId
            )

            firestoreUser?.sportSuitabilityFlags = updatedFlags
            notSuitableSportIds = Set(
                updatedFlags.compactMap { key, value in
                    value.isNotSuitable ? key : nil
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reminderSportsForNotification(plan: FirestoreSportPlan) -> [FirestoreSportEntry] {
        let resolvedSports = plan.resolvedSports(at: Date())
        guard let selectedSportId = plan.resolvedSelectedSportId else { return resolvedSports }
        let activeSports = resolvedSports.filter { $0.id == selectedSportId }
        return activeSports.isEmpty ? resolvedSports : activeSports
    }

    private func requestNotificationAccessForReminderInternal() async {
        if await notificationService.isAuthorizationGranted() {
            isNotificationAuthorized = true
            return
        }

        let granted = await notificationService.requestAuthorization()
        let currentAuthorization = await notificationService.isAuthorizationGranted()
        let authorizedNow = granted || currentAuthorization
        isNotificationAuthorized = authorizedNow

        guard !authorizedNow else { return }
        shouldOpenNotificationSettings = true
    }

    private func saveCustomReminderTimeInternal() async {
        if !isNotificationAuthorized {
            await requestNotificationAccessForReminderInternal()
            guard isNotificationAuthorized else { return }
        }

        var localProfile = resolvedReminderEditableProfile()
        localProfile.customReminderTime = CustomReminderTime(date: reminderPickerDate)
        localProfile.updatedAt = Date()
        await persistProfileAndReschedule(localProfile)
    }

    private func resetReminderToDefaultInternal() async {
        var localProfile = resolvedReminderEditableProfile()
        localProfile.customReminderTime = nil
        localProfile.updatedAt = Date()
        reminderPickerDate = profileDefaultReminderDate(localProfile)
        await persistProfileAndReschedule(localProfile)
    }

    private func resolvedReminderEditableProfile() -> UserProfileInput {
        if let profile {
            return profile
        }

        return UserProfileInput(
            fullName: profileName == "Virest User" ? "" : profileName,
            preferredTime: .flexible,
            updatedAt: Date()
        )
    }

    private func persistProfileAndReschedule(_ updatedProfile: UserProfileInput) async {
        do {
            try userProfileRepository.saveProfile(updatedProfile)
            if case .signedIn(let user) = authService.authState {
                try await firestoreUserRepository.saveProfile(userId: user.id, profile: updatedProfile)
            }
            profile = updatedProfile
            reminderPickerDate = updatedProfile.customReminderTime?.toDate() ?? profileDefaultReminderDate(updatedProfile)
            reschedulePlanReminder(using: updatedProfile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reschedulePlanReminder(using localProfile: UserProfileInput) {
        let reminderSports: [FirestoreSportEntry]
        if let plan = firestoreUser?.sportPlan {
            reminderSports = reminderSportsForNotification(plan: plan)
        } else {
            reminderSports = []
        }

        notificationService.scheduleFirestorePlanReminder(
            sports: reminderSports,
            preferredTime: localProfile.resolvedReminderDateComponents
        )
    }

    private func profileDefaultReminderDate(_ profile: UserProfileInput?) -> Date {
        let components = profile?.preferredTime.reminderDateComponents ?? PreferredTime.flexible.reminderDateComponents
        var date = Calendar.current.date(from: DateComponents(
            year: 2001, month: 1, day: 1,
            hour: components.hour ?? 17,
            minute: components.minute ?? 0
        ))
        if date == nil {
            date = Date()
        }
        return date ?? Date()
    }

    private func formatReminderTime(_ components: DateComponents) -> String {
        var fixed = DateComponents(year: 2001, month: 1, day: 1)
        fixed.hour = components.hour ?? 17
        fixed.minute = components.minute ?? 0
        let date = Calendar.current.date(from: fixed) ?? Date()

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func updateProfileName(localProfile: UserProfileInput?) {
        let localName = localProfile?.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localName, !localName.isEmpty {
            profileName = localName
            return
        }

        if case .signedIn(let authUser) = authService.authState {
            let authName = authUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !authName.isEmpty {
                profileName = authName
                return
            }
        }

        let remoteName = firestoreUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remoteName, !remoteName.isEmpty {
            profileName = remoteName
            return
        }

        profileName = "Virest User"
    }

    private func updateVitals(localProfile: UserProfileInput?) async {
        let resolvedVitals = await healthDataResolver.resolveVitals(
            localProfile: localProfile,
            firestoreUser: firestoreUser
        )
        let resolvedRHR = resolvedVitals.latestRestingHeartRate

        if let resolvedRHR {
            currentRestingHRText = "\(resolvedRHR) bpm"
        } else {
            currentRestingHRText = "-"
        }

        if let resolvedWeight = resolvedVitals.weightKg {
            currentWeightText = formatWeight(resolvedWeight)
        } else {
            currentWeightText = "-"
        }

        if let resolvedHeight = resolvedVitals.heightCm {
            currentHeightText = formatHeight(resolvedHeight)
        } else {
            currentHeightText = "-"
        }
    }

    private func formatWeight(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.01 {
            return String(format: "%.0f kg", rounded)
        }
        return String(format: "%.1f kg", rounded)
    }

    private func formatHeight(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.01 {
            return String(format: "%.0f cm", rounded)
        }
        return String(format: "%.1f cm", rounded)
    }

    private func isProfileMetricEmpty(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value <= 0
    }

    private func currentRHRBand(from bpm: Int?) -> CurrentRHRBandQuestion? {
        guard let bpm else { return nil }
        switch bpm {
        case ..<61: return .upTo60
        case 61..<76: return .from61To75
        case 76..<91: return .from76To90
        default: return .above90
        }
    }

    private func targetRHRGoal(from bpm: Int?) -> TargetRHRGoalQuestion? {
        guard let bpm else { return nil }
        switch bpm {
        case ..<50: return .below50
        case 50..<60: return .from50To59
        case 60..<70: return .from60To69
        case 70..<80: return .from70To79
        case 80..<90: return .from80To89
        default: return .from90To99
        }
    }

    private func sportDisplayName(for sportId: String) -> String {
        if let byResolved = sportPlanSports.first(where: { $0.id == sportId })?.displayName {
            return byResolved
        }
        if let byStored = firestoreUser?.sportPlan?.sports.first(where: { $0.id == sportId })?.displayName {
            return byStored
        }

        return sportId
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
