//
//  CheckInSheetViewModel.swift
//  ViRest
//
//  Created by Joshua Valentine Manik on 13/03/26.
//

import Foundation
import Combine

extension CheckInSheetViewModel: Identifiable {
    var id: String { sport.id }
}

@MainActor
final class CheckInSheetViewModel: ObservableObject {

    enum SheetState {
        case form
        case result
    }

    @Published var state: SheetState = .form
    @Published var difficulty: ActivityDifficulty = .moderate
    @Published var fatigue: FatigueLevel = .moderatelyTired
    @Published var painLevel: PainLevel = .noPain
    @Published var discomfortAreas: Set<DiscomfortArea> = []
    @Published var notes: String = ""
    @Published var isLoading = false
    @Published var isApplyingDecision = false
    @Published var errorMessage: String?

    // Result state
    @Published var assessment: SuitabilityAssessment?
    @Published var appreciationText: String?
    @Published var newBadges: [BadgeEarned] = []
    @Published var newTitleName: String?
    @Published var decisionMessage: String?
    @Published var switchOptions: [FirestoreSportEntry] = []
    @Published var activeSwitchSportId: String?
    @Published var selectedSwitchSportId: String?
    @Published var isLoadingSwitchOptions = false

    private let sport: FirestoreSportEntry
    private let firestoreUserRepository: FirestoreUserRepository
    private let authService: AuthProviding
    private let badgeRepository: BadgeStateRepository
    private let gamificationService: GamificationProviding
    private let notificationService: NotificationScheduling
    private let userProfileRepository: UserProfileRepository
    private let healthService: HealthDataProviding
    private let suitabilityEvaluator: SuitabilityEvaluating
    private let sportSwitchOrchestrator: SportSwitchOrchestrating

    // Called when submit succeeds so HomeViewModel can reload
    var onCompleted: (() -> Void)?

    init(
        sport: FirestoreSportEntry,
        firestoreUserRepository: FirestoreUserRepository,
        authService: AuthProviding,
        badgeRepository: BadgeStateRepository,
        gamificationService: GamificationProviding,
        notificationService: NotificationScheduling,
        userProfileRepository: UserProfileRepository,
        healthService: HealthDataProviding,
        suitabilityEvaluator: SuitabilityEvaluating,
        sportSwitchOrchestrator: SportSwitchOrchestrating
    ) {
        self.sport = sport
        self.firestoreUserRepository = firestoreUserRepository
        self.authService = authService
        self.badgeRepository = badgeRepository
        self.gamificationService = gamificationService
        self.notificationService = notificationService
        self.userProfileRepository = userProfileRepository
        self.healthService = healthService
        self.suitabilityEvaluator = suitabilityEvaluator
        self.sportSwitchOrchestrator = sportSwitchOrchestrator
    }

    var shouldOfferSwitch: Bool {
        guard let decision = assessment?.decision else { return false }
        return decision == .offerSwitch || decision == .offerSwitchNow
    }

    var isRedSwitchDecision: Bool {
        assessment?.decision == .offerSwitchNow
    }

    var hasAlternativeSwitchOption: Bool {
        guard let activeSwitchSportId else { return false }
        return switchOptions.contains(where: { $0.id != activeSwitchSportId })
    }

    func submit() {
        Task { await submitInternal() }
    }

    func prepareSwitchOptions() {
        Task { await loadSwitchOptionsInternal() }
    }

    func switchSport(to sportId: String, reason: SwitchReason) {
        Task { await switchSportInternal(requestedSportId: sportId, reason: reason) }
    }

    func continueCurrentSport() {
        Task { await continueCurrentSportInternal() }
    }

    private func submitInternal() async {
        isLoading = true
        errorMessage = nil
        decisionMessage = nil

        guard case .signedIn(let user) = authService.authState else {
            errorMessage = "Not authenticated."
            isLoading = false
            return
        }

        do {
            let resolvedActivity = activityType(for: sport.displayName)
            let resolvedDiscomfortAreas: [DiscomfortArea] =
                painLevel == .noPain ? [] : Array(discomfortAreas)

            let recentHistory = try await firestoreUserRepository.loadRecentCheckInHistory(
                userId: user.id,
                sportId: sport.id,
                limit: 2
            )

            assessment = suitabilityEvaluator.evaluate(
                feedback: SuitabilityFeedbackInput(
                    difficulty: difficulty,
                    fatigue: fatigue,
                    painLevel: painLevel,
                    discomfortAreas: resolvedDiscomfortAreas
                ),
                recentSameSportCheckIns: recentHistory
            )

            let historyEntry = firestoreUserRepository.makeCheckInHistoryEntry(
                userId: user.id,
                sportId: sport.id,
                sportName: sport.displayName,
                durationMinutes: sport.durationMinutes,
                difficulty: difficulty,
                fatigue: fatigue,
                painLevel: painLevel,
                discomfortAreas: resolvedDiscomfortAreas,
                zone: assessment?.zone,
                decision: assessment?.decision
            )

            // Counter, plan mutation, and history are committed atomically.
            try await firestoreUserRepository.recordCheckIn(
                userId: user.id,
                sportId: sport.id,
                historyEntry: historyEntry
            )

            // Evaluate gamification after the durable check-in succeeds.
            let fakeCheckIn = SessionCheckIn(
                sessionId: UUID(),
                checkInDate: Date(),
                activity: resolvedActivity,
                actualDurationMinutes: sport.durationMinutes,
                activityDifficulty: difficulty,
                fatigueLevel: fatigue,
                painLevel: painLevel,
                discomfortAreas: resolvedDiscomfortAreas,
                notes: notes
            )
            let existingState = try badgeRepository.loadState()
            let gamification = gamificationService.evaluate(after: fakeCheckIn, current: existingState)
            try badgeRepository.saveState(gamification.updatedState)
            try await firestoreUserRepository.saveBadgeState(userId: user.id, state: gamification.updatedState)
            appreciationText = gamification.appreciationMessage
            newBadges = gamification.newlyEarnedBadges
            let levelIncreased = gamification.updatedState.level.rawValue > existingState.level.rawValue
            newTitleName = levelIncreased ? gamification.updatedState.level.title : nil

            // 4. Schedule target achieved notification.
            notificationService.scheduleTargetAchievedNotification(for: resolvedActivity)

            isLoading = false
            state = .result

            if shouldOfferSwitch {
                await loadSwitchOptionsInternal()
            }
            onCompleted?()

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadSwitchOptionsInternal() async {
        guard shouldOfferSwitch else {
            switchOptions = []
            activeSwitchSportId = nil
            selectedSwitchSportId = nil
            return
        }
        guard case .signedIn(let user) = authService.authState else { return }

        isLoadingSwitchOptions = true
        defer { isLoadingSwitchOptions = false }

        do {
            guard let loadedUser = try await firestoreUserRepository.loadUser(userId: user.id),
                  let currentPlan = loadedUser.sportPlan else {
                throw SportSwitchError.invalidPlanState
            }

            let resolvedSports = currentPlan.resolvedSports(at: Date())
            let activeId = currentPlan.resolvedSelectedSportId ?? sport.id
            let notSuitableSportIds = try await firestoreUserRepository.loadNotSuitableSportIds(userId: user.id)
            let filteredOptions = resolvedSports.filter {
                $0.id == activeId || !notSuitableSportIds.contains($0.id)
            }
            let usableOptions = filteredOptions

            switchOptions = usableOptions
            activeSwitchSportId = activeId
            selectedSwitchSportId = usableOptions.first(where: { $0.id != activeId })?.id
            if selectedSwitchSportId == nil {
                decisionMessage = "No alternative sport is currently available from your safe recommendations."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func switchSportInternal(requestedSportId: String, reason: SwitchReason) async {
        guard shouldOfferSwitch else { return }
        guard case .signedIn(let user) = authService.authState else { return }

        isApplyingDecision = true
        errorMessage = nil
        decisionMessage = nil

        defer {
            isApplyingDecision = false
        }

        do {
            guard let loadedUser = try await firestoreUserRepository.loadUser(userId: user.id),
                  let currentPlan = loadedUser.sportPlan else {
                throw SportSwitchError.invalidPlanState
            }
            guard requestedSportId != (currentPlan.resolvedSelectedSportId ?? sport.id) else {
                throw SportSwitchError.noCandidateAvailable
            }

            let localProfile = try? userProfileRepository.loadProfile()
            let snapshot = await healthService.fetchLatestSnapshot(profile: localProfile)
            let origin: SwitchOrigin = isRedSwitchDecision ? .feedbackRed : .feedbackYellowPattern

            let outcome = try await sportSwitchOrchestrator.requestSportSwitch(
                userId: user.id,
                currentPlan: currentPlan,
                requestedSportId: requestedSportId,
                reason: reason,
                origin: origin,
                userProfile: localProfile,
                healthSnapshot: snapshot,
                preferredReminderTime: localProfile?.resolvedReminderDateComponents ?? PreferredTime.flexible.reminderDateComponents
            )

            decisionMessage = "Switched to \(outcome.selectedSport.displayName). Week 1 restarted."
            onCompleted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func continueCurrentSportInternal() async {
        guard case .signedIn(let user) = authService.authState else { return }
        guard assessment?.decision == .offerSwitchNow else {
            decisionMessage = "Continuing current sport."
            return
        }

        isApplyingDecision = true
        errorMessage = nil
        decisionMessage = nil

        defer {
            isApplyingDecision = false
        }

        do {
            guard let loadedUser = try await firestoreUserRepository.loadUser(userId: user.id),
                  var plan = loadedUser.sportPlan else {
                throw SportSwitchError.invalidPlanState
            }

            let activeId = plan.resolvedSelectedSportId ?? sport.id
            for index in plan.sports.indices where plan.sports[index].id == activeId {
                plan.sports[index].pendingDeloadSessions = max(1, plan.sports[index].pendingDeloadSessions)
            }

            try await firestoreUserRepository.saveSportPlan(userId: user.id, plan: plan)

            let localProfile = try? userProfileRepository.loadProfile()
            let resolvedSports = plan.resolvedSports(at: Date())
            let activeSports = resolvedSports.filter { $0.id == plan.resolvedSelectedSportId }
            notificationService.scheduleFirestorePlanReminder(
                sports: activeSports.isEmpty ? resolvedSports : activeSports,
                preferredTime: localProfile?.resolvedReminderDateComponents ?? PreferredTime.flexible.reminderDateComponents
            )

            decisionMessage = "Next session will be deloaded for safety, then re-evaluated."
            onCompleted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activityType(for sportName: String) -> ActivityType {
        switch normalizedToken(sportName) {
        case normalizedToken("Brisk walking"): return .briskWalking
        case normalizedToken("Trail walking"): return .trailWalking
        case normalizedToken("Nordic walking"): return .nordicWalking
        case normalizedToken("Flat walking"): return .flatWalking
        case normalizedToken("Walking"): return .walkingGeneral
        case normalizedToken("Interval walking"): return .intervalWalking
        case normalizedToken("Jogging"): return .jogging
        case normalizedToken("Run-walk intervals"): return .runWalkIntervals
        case normalizedToken("Road cycling"): return .roadCycling
        case normalizedToken("Stationary cycling"): return .stationaryCycling
        case normalizedToken("Recumbent cycling"): return .recumbentCycling
        case normalizedToken("Elliptical trainer"): return .ellipticalTrainer
        case normalizedToken("Rowing machine"): return .rowingMachineCardio
        case normalizedToken("Lap swimming"): return .lapSwimming
        case normalizedToken("Dance cardio"): return .danceCardio
        case normalizedToken("Stair climber"): return .stairClimber
        case normalizedToken("Stair walking"): return .stairWalking
        case normalizedToken("Pool walking"): return .poolWalking
        case normalizedToken("Aqua jogging"): return .aquaJogging
        case normalizedToken("Vinyasa yoga"): return .vinyasaYoga
        case normalizedToken("Yoga"): return .yoga
        case normalizedToken("Restorative yoga"): return .restorativeYoga
        case normalizedToken("Chair marching"): return .chairMarching
        case normalizedToken("Chair aerobics"): return .chairAerobics
        case normalizedToken("Tai chi"): return .taiChi
        default: return .walking
        }
    }

    private func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }
}
