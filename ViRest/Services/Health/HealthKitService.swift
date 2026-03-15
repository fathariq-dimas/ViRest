import Foundation

#if os(iOS)
import HealthKit

@MainActor
final class HealthKitService: HealthDataProviding {
    private let store = HKHealthStore()

    var authorizationState: HealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        guard let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            return .notDetermined
        }

        switch store.authorizationStatus(for: type) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    func shouldPresentAuthorizationPrompt() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let readTypes = requiredReadTypes()
        guard !readTypes.isEmpty else {
            return false
        }

        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                switch status {
                case .shouldRequest:
                    continuation.resume(returning: true)
                case .unnecessary, .unknown:
                    continuation.resume(returning: false)
                @unknown default:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let readTypes = requiredReadTypes()
        guard !readTypes.isEmpty else {
            return false
        }

        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: [], read: readTypes) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func fetchLatestSnapshot(profile: UserProfileInput?) async -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else {
            if let profile {
                return HealthSnapshot.manualFallback(from: profile)
            }

            return HealthSnapshot(
                collectedAt: Date(),
                source: .manual,
                stepCount: nil,
                activeEnergyKCal: nil,
                heightCm: nil,
                weightKg: nil,
                bmi: nil,
                restingHeartRate: nil,
                restingHeartRateSource: .unavailable,
                walkingHeartRateAverage: nil,
                peakHeartRate: nil,
                heartRateRecovery: nil,
                vo2Max: nil,
                dataFreshnessHours: nil
            )
        }

        async let heightMeters = latestQuantity(identifier: .height, unit: .meter())
        async let weightKg = latestQuantity(identifier: .bodyMass, unit: .gramUnit(with: .kilo))
        async let restingHR = latestQuantity(identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))

        let collectedAt = Date()
        let heightCmValue = (await heightMeters).map { $0 * 100 }
        let weightKgValue = await weightKg
        let restingHRValue = await restingHR

        let hasHealthData = heightCmValue != nil || weightKgValue != nil || restingHRValue != nil

        if !hasHealthData {
            if let profile {
                return HealthSnapshot.manualFallback(from: profile)
            }

            return HealthSnapshot(
                collectedAt: collectedAt,
                source: .manual,
                ageYears: nil,
                biologicalGender: nil,
                stepCount: nil,
                activeEnergyKCal: nil,
                heightCm: nil,
                weightKg: nil,
                bmi: nil,
                restingHeartRate: nil,
                restingHeartRateSource: .unavailable,
                walkingHeartRateAverage: nil,
                peakHeartRate: nil,
                heartRateRecovery: nil,
                vo2Max: nil,
                dataFreshnessHours: nil
            )
        }

        let bmiValue: Double?

        if let h = heightCmValue, let w = weightKgValue, h > 0 {
            let meter = h / 100
            bmiValue = w / (meter * meter)
        } else {
            bmiValue = nil
        }

        let manualResting = profile?.questionnaireCurrentRHRBand.map { Double($0.representativeBPM) }
        let resolvedResting = restingHRValue ?? manualResting
        let restingSource: RestingHeartRateValueSource
        if restingHRValue != nil {
            restingSource = .healthKit
        } else if manualResting != nil {
            restingSource = .manual
        } else {
            restingSource = .unavailable
        }
        let usedManualFallbackValues = profile != nil && (heightCmValue == nil || weightKgValue == nil || restingHRValue == nil)
        let source: HealthDataSource = usedManualFallbackValues ? .mixed : .healthKit

        return HealthSnapshot(
            collectedAt: collectedAt,
            source: source,
            ageYears: profile?.age,
            biologicalGender: profile?.gender,
            stepCount: nil,
            activeEnergyKCal: nil,
            heightCm: heightCmValue ?? profile?.heightCm,
            weightKg: weightKgValue ?? profile?.weightKg,
            bmi: bmiValue,
            restingHeartRate: resolvedResting,
            restingHeartRateSource: restingSource,
            walkingHeartRateAverage: nil,
            peakHeartRate: nil,
            heartRateRecovery: nil,
            vo2Max: nil,
            dataFreshnessHours: 0
        )
    }

    func fetchRestingHeartRateTrend(
        range: RestingHeartRateTrendRange,
        profile: UserProfileInput?
    ) async -> [RestingHeartRateTrendBucket] {
        let calendar = Calendar.current
        let now = Date()
        let bucketStarts = trendBucketStarts(for: range, referenceDate: now, calendar: calendar)
        guard !bucketStarts.isEmpty else { return [] }

        guard HKHealthStore.isHealthDataAvailable(),
              HKObjectType.quantityType(forIdentifier: .restingHeartRate) != nil else {
            return fallbackTrendBuckets(bucketStarts: bucketStarts, profile: profile)
        }

        let startDate = bucketStarts[0]
        let samples = await queryRestingHeartRateSamples(from: startDate, to: now)
        let unit = HKUnit.count().unitDivided(by: .minute())
        var groupedValues: [Int: [Double]] = [:]

        for sample in samples {
            guard let bucketIndex = trendBucketIndex(
                for: sample.endDate,
                range: range,
                firstBucketStart: startDate,
                calendar: calendar
            ) else { continue }

            let value = sample.quantity.doubleValue(for: unit)
            groupedValues[bucketIndex, default: []].append(value)
        }

        let manualFallback = profile?.questionnaireCurrentRHRBand.map { Double($0.representativeBPM) }
        let hasAnyHealthValues = !groupedValues.isEmpty

        return bucketStarts.enumerated().map { index, bucketStart in
            let values = groupedValues[index] ?? []
            let average: Double?

            if values.isEmpty {
                average = hasAnyHealthValues ? nil : manualFallback
            } else {
                average = values.reduce(0, +) / Double(values.count)
            }

            return RestingHeartRateTrendBucket(bucketStart: bucketStart, averageBPM: average)
        }
    }

    private func latestQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }

            store.execute(query)
        }
    }

    private func queryRestingHeartRateSamples(from startDate: Date, to endDate: Date) async -> [HKQuantitySample] {
        guard let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate]
            )
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: quantitySamples)
            }

            store.execute(query)
        }
    }

    private func trendBucketStarts(
        for range: RestingHeartRateTrendRange,
        referenceDate: Date,
        calendar: Calendar
    ) -> [Date] {
        switch range {
        case .day:
            let currentHourStart = calendar.dateInterval(of: .hour, for: referenceDate)?.start ?? referenceDate
            let firstHour = calendar.date(byAdding: .hour, value: -23, to: currentHourStart) ?? currentHourStart
            return (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: firstHour) }

        case .week:
            let todayStart = calendar.startOfDay(for: referenceDate)
            let firstDay = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }

        case .month:
            let currentWeekStart = referenceDate.startOfWeek()
            let firstWeek = calendar.date(byAdding: .weekOfYear, value: -3, to: currentWeekStart) ?? currentWeekStart
            return (0..<4).compactMap { calendar.date(byAdding: .weekOfYear, value: $0, to: firstWeek) }
        }
    }

    private func trendBucketIndex(
        for sampleDate: Date,
        range: RestingHeartRateTrendRange,
        firstBucketStart: Date,
        calendar: Calendar
    ) -> Int? {
        switch range {
        case .day:
            let hours = calendar.dateComponents([.hour], from: firstBucketStart, to: sampleDate).hour ?? -1
            guard (0..<24).contains(hours) else { return nil }
            return hours

        case .week:
            let days = calendar.dateComponents([.day], from: firstBucketStart, to: sampleDate).day ?? -1
            guard (0..<7).contains(days) else { return nil }
            return days

        case .month:
            let sampleWeekStart = sampleDate.startOfWeek()
            let weeks = calendar.dateComponents([.weekOfYear], from: firstBucketStart, to: sampleWeekStart).weekOfYear ?? -1
            guard (0..<4).contains(weeks) else { return nil }
            return weeks
        }
    }

    private func fallbackTrendBuckets(
        bucketStarts: [Date],
        profile: UserProfileInput?
    ) -> [RestingHeartRateTrendBucket] {
        let manualBPM = profile?.questionnaireCurrentRHRBand.map { Double($0.representativeBPM) }
        return bucketStarts.map { RestingHeartRateTrendBucket(bucketStart: $0, averageBPM: manualBPM) }
    }

    private func requiredReadTypes() -> Set<HKObjectType> {
        let quantityTypes = [
            HKObjectType.quantityType(forIdentifier: .height),
            HKObjectType.quantityType(forIdentifier: .bodyMass),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        ].compactMap { $0 as HKObjectType? }
        
        return Set(quantityTypes)
    }
}

#else

@MainActor
final class HealthKitService: HealthDataProviding {
    var authorizationState: HealthAuthorizationState { .unavailable }

    func shouldPresentAuthorizationPrompt() async -> Bool { false }

    func requestAuthorization() async -> Bool { false }

    func fetchLatestSnapshot(profile: UserProfileInput?) async -> HealthSnapshot {
        if let profile {
            return HealthSnapshot.manualFallback(from: profile)
        }

        return HealthSnapshot(
            collectedAt: Date(),
            source: .manual,
            ageYears: profile?.age,
            biologicalGender: profile?.gender,
            stepCount: nil,
            activeEnergyKCal: nil,
            heightCm: nil,
            weightKg: nil,
            bmi: nil,
            restingHeartRate: nil,
            restingHeartRateSource: .unavailable,
            walkingHeartRateAverage: nil,
            peakHeartRate: nil,
            heartRateRecovery: nil,
            vo2Max: nil,
            dataFreshnessHours: nil
        )
    }

    func fetchRestingHeartRateTrend(
        range: RestingHeartRateTrendRange,
        profile: UserProfileInput?
    ) async -> [RestingHeartRateTrendBucket] {
        let now = Date()
        let calendar = Calendar.current
        let manualBPM = profile?.questionnaireCurrentRHRBand.map { Double($0.representativeBPM) }

        switch range {
        case .day:
            let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let firstHour = calendar.date(byAdding: .hour, value: -23, to: currentHourStart) ?? currentHourStart
            return (0..<24).compactMap { offset in
                guard let date = calendar.date(byAdding: .hour, value: offset, to: firstHour) else { return nil }
                return RestingHeartRateTrendBucket(bucketStart: date, averageBPM: manualBPM)
            }

        case .week:
            let todayStart = calendar.startOfDay(for: now)
            let firstDay = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return (0..<7).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
                return RestingHeartRateTrendBucket(bucketStart: date, averageBPM: manualBPM)
            }

        case .month:
            let firstWeek = calendar.date(byAdding: .weekOfYear, value: -3, to: now.startOfWeek()) ?? now.startOfWeek()
            return (0..<4).compactMap { offset in
                guard let date = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeek) else { return nil }
                return RestingHeartRateTrendBucket(bucketStart: date, averageBPM: manualBPM)
            }
        }
    }
}

#endif
