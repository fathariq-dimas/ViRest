import Foundation

enum HealthDataSource: String, Codable {
    case healthKit = "health_kit"
    case manual
    case mixed
}

enum RestingHeartRateValueSource: String, Codable {
    case healthKit = "health_kit"
    case manual
    case unavailable
}

enum RestingHeartRateTrendRange: String, Codable, CaseIterable, Identifiable, Hashable {
    case day
    case week
    case month

    var id: String { rawValue }

    var compactTitle: String {
        switch self {
        case .day: return "D"
        case .week: return "W"
        case .month: return "M"
        }
    }
}

struct RestingHeartRateTrendBucket: Codable, Equatable, Identifiable {
    let bucketStart: Date
    let averageBPM: Double?

    var id: Date { bucketStart }
}

struct DailyHealthSnapshot: Codable, Equatable, Identifiable {
    let dayStart: Date
    let syncedAt: Date
    let source: HealthDataSource
    let restingHeartRate: Double?
    let heightCm: Double?
    let weightKg: Double?

    var id: Date { dayStart }
}

struct HealthSnapshot: Codable, Equatable {
    var collectedAt: Date
    var source: HealthDataSource
    var ageYears: Int? = nil
    var biologicalGender: Gender? = nil
    var stepCount: Double?
    var activeEnergyKCal: Double?
    var heightCm: Double?
    var weightKg: Double?
    var bmi: Double?
    var restingHeartRate: Double?
    var restingHeartRateSource: RestingHeartRateValueSource = .unavailable
    var walkingHeartRateAverage: Double?
    var peakHeartRate: Double?
    var heartRateRecovery: Double?
    var vo2Max: Double?
    var dataFreshnessHours: Double?

    static func manualFallback(from profile: UserProfileInput) -> HealthSnapshot {
        let resting = profile.questionnaireCurrentRHRBand.map { Double($0.representativeBPM) }
        let heightCm = profile.heightCm
        let weightKg = profile.weightKg
        let bmi: Double?

        if let h = heightCm, let w = weightKg, h > 0 {
            let meter = h / 100
            bmi = w / (meter * meter)
        } else {
            bmi = nil
        }

        return HealthSnapshot(
            collectedAt: Date(),
            source: .manual,
            ageYears: profile.age,
            biologicalGender: profile.gender,
            stepCount: nil,
            activeEnergyKCal: nil,
            heightCm: heightCm,
            weightKg: weightKg,
            bmi: bmi,
            restingHeartRate: resting,
            restingHeartRateSource: resting == nil ? .unavailable : .manual,
            walkingHeartRateAverage: nil,
            peakHeartRate: nil,
            heartRateRecovery: nil,
            vo2Max: nil,
            dataFreshnessHours: nil
        )
    }
}

struct ResolvedHealthVitals: Equatable {
    var latestRestingHeartRate: Int?
    var targetRestingHeartRate: Int?
    var heightCm: Double?
    var weightKg: Double?
    var restingHeartRateSource: RestingHeartRateValueSource
}

enum HealthAuthorizationState: Equatable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}
