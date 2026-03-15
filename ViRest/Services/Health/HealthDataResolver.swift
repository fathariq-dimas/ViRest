import Foundation

@MainActor
final class HealthDataResolver: HealthDataResolving {
    private let healthService: HealthDataProviding

    init(healthService: HealthDataProviding) {
        self.healthService = healthService
    }

    func resolveVitals(
        localProfile: UserProfileInput?,
        firestoreUser: FirestoreUser?
    ) async -> ResolvedHealthVitals {
        let snapshot = await healthService.fetchLatestSnapshot(profile: localProfile)

        let resolvedHeight = preferredProfileMetric(localProfile?.heightCm)
            ?? preferredProfileMetric(firestoreUser?.heightCm)
            ?? preferredProfileMetric(snapshot.heightCm)
        let resolvedWeight = preferredProfileMetric(localProfile?.weightKg)
            ?? preferredProfileMetric(firestoreUser?.weightKg)
            ?? preferredProfileMetric(snapshot.weightKg)

        let snapshotRHR = snapshot.restingHeartRate.map { Int($0.rounded()) }
        let latestHealthKitRHR = snapshot.restingHeartRateSource == .healthKit ? snapshotRHR : nil
        let snapshotManualRHR = snapshot.restingHeartRateSource == .manual ? snapshotRHR : nil
        let trackedHealthKitRHR = firestoreUser?.rhrTracking.flatMap { tracking -> Int? in
            guard tracking.latestSource == .healthKit else { return nil }
            return Int(tracking.latestBPM.rounded())
        }
        let trackedManualRHR = firestoreUser?.rhrTracking.flatMap { tracking -> Int? in
            guard tracking.latestSource == .manual else { return nil }
            return Int(tracking.latestBPM.rounded())
        }
        let manualProfileRHR = localProfile?.questionnaireCurrentRHRBand?.representativeBPM
        let resolvedLatestRHR = latestHealthKitRHR
            ?? trackedHealthKitRHR
            ?? manualProfileRHR
            ?? snapshotManualRHR
            ?? trackedManualRHR
            ?? firestoreUser?.restingHeartRate
        let resolvedTargetRHR = localProfile?.questionnaireTargetRHRGoal?.representativeBPM
            ?? firestoreUser?.targetRestingHeartRate

        let resolvedSource: RestingHeartRateValueSource
        if latestHealthKitRHR != nil {
            resolvedSource = .healthKit
        } else if trackedHealthKitRHR != nil {
            resolvedSource = .healthKit
        } else if snapshotManualRHR != nil || trackedManualRHR != nil || manualProfileRHR != nil || firestoreUser?.restingHeartRate != nil {
            resolvedSource = .manual
        } else {
            resolvedSource = .unavailable
        }

        return ResolvedHealthVitals(
            latestRestingHeartRate: resolvedLatestRHR,
            targetRestingHeartRate: resolvedTargetRHR,
            heightCm: resolvedHeight,
            weightKg: resolvedWeight,
            restingHeartRateSource: resolvedSource
        )
    }

    private func preferredProfileMetric(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
