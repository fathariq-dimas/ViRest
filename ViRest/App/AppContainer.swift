import Foundation
import Combine
import SwiftData
import FirebaseFirestore

@MainActor
final class AppContainer: ObservableObject {
    let modelContainer: ModelContainer
    private let keyValueStore: SwiftDataKeyValueStore

    // Auth
    let authService: FirebaseAuthService

    // Firestore
    let firestoreUserRepository: FirestoreUserRepository

    // Services
    let healthService: HealthDataProviding
    let healthDataResolver: HealthDataResolving
    let recommendationEngine: RecommendationProviding
    let planAdjustmentService: PlanAdjusting
    let suitabilityEvaluator: SuitabilityEvaluating
    let sportSwitchOrchestrator: SportSwitchOrchestrating
    let notificationService: UserNotificationService
    let gamificationService: GamificationProviding
    let dailyHealthSyncService: DailyHealthSyncService
    let widgetSyncService: WidgetSyncService

    // Local SwiftData (offline fallback)
    let userProfileRepository: UserProfileRepository
    let planRepository: PlanRepository
    let checkInRepository: CheckInRepository
    let badgeStateRepository: BadgeStateRepository
    let healthDailySnapshotRepository: HealthDailySnapshotRepository

    init(inMemory: Bool = false) {
        let schema = Schema([KeyValueRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData init failed: \(error)")
        }

        let kv = SwiftDataKeyValueStore(modelContainer: modelContainer)
        self.keyValueStore = kv

        self.authService = FirebaseAuthService()
        self.userProfileRepository = UserProfileSwiftDataRepository(store: kv, authService: self.authService)
        self.planRepository = PlanSwiftDataRepository(store: kv, authService: self.authService)
        self.checkInRepository = CheckInSwiftDataRepository(store: kv, authService: self.authService)
        self.badgeStateRepository = BadgeStateSwiftDataRepository(store: kv, authService: self.authService)
        self.healthDailySnapshotRepository = HealthDailySnapshotSwiftDataRepository(store: kv)
        self.firestoreUserRepository = FirestoreUserRepository()
        self.healthService = HealthKitService()
        self.healthDataResolver = HealthDataResolver(healthService: self.healthService)
        self.recommendationEngine = RuleBasedRecommendationEngine()
        self.planAdjustmentService = RuleBasedPlanAdjustmentService()
        self.suitabilityEvaluator = RuleBasedSuitabilityEvaluator()
        self.notificationService = UserNotificationService()
        self.sportSwitchOrchestrator = SportSwitchOrchestrator(
            firestoreUserRepository: self.firestoreUserRepository,
            recommendationEngine: self.recommendationEngine,
            notificationService: self.notificationService
        )
        self.gamificationService = GamificationService()
        self.widgetSyncService = WidgetSyncService()
        self.dailyHealthSyncService = DailyHealthSyncService(
            healthService: self.healthService,
            userProfileRepository: self.userProfileRepository,
            repository: self.healthDailySnapshotRepository,
            firestoreUserRepository: self.firestoreUserRepository
        )
    }

    func clearLocalUserCache() {
        try? keyValueStore.removeAll()
    }
}
