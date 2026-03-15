import Foundation

// Maps onboarding RHR question bands to the exact labels in sports.json.
// Note: sports.json uses en-dash (–) not hyphen (-)
extension CurrentRHRBandQuestion {
    var sportsJsonBand: String {
        switch self {
        case .upTo60:    return "<= 60 bpm"
        case .from61To75:return "61 – 75 bpm"
        case .from76To90:return "76 – 90 bpm"
        case .above90:   return "> 90 bpm"
        }
    }
}

// Derive BMI category string matching sports.json bmiCategory values
struct BMICalculator {
    static func category(heightCm: Double?, weightKg: Double?) -> String {
        guard let h = heightCm, let w = weightKg, h > 0, w > 0 else {
            return "Any BMI"  // no data — use broadest fallback
        }
        let bmi = w / ((h / 100) * (h / 100))
        switch bmi {
        case ..<25:   return "Normal"
        case 25..<30: return "Overweight"
        default:      return "Obese"
        }
    }
}

struct SportPrescription {
    struct Phase {
        var durationMinutes: Int
        var daysPerWeek: Int
    }

    var sportName: String
    var hasProgression: Bool
    var initial: Phase
    var target: Phase
    var keyCautions: [String]
    var contraindications: [String]
}

final class SportsCatalogLoader {
    static let shared = SportsCatalogLoader()
    private(set) var exercises: [SportsJsonExercise] = []

    init() { load() }

    private func load() {
        let decoder = JSONDecoder()
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let parsed = try decoder.decode(SportsJsonRoot.self, from: data)
                guard !parsed.exercises.isEmpty else { continue }
                self.exercises = parsed.exercises
                print("✅ Loaded \(exercises.count) exercises from \(url.lastPathComponent)")
                return
            } catch {
                print("⚠️ Failed to decode \(url.lastPathComponent): \(error)")
            }
        }
        print("⚠️ Unable to load exercise catalog from sports.json")
    }

    private func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let sportsBundled = Bundle.main.url(forResource: "sports", withExtension: "json") {
            urls.append(sportsBundled)
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(cwd.appendingPathComponent("ViRest/sports.json"))
        urls.append(cwd.appendingPathComponent("ViRest/Resources/sports.json"))

        return urls
    }

    func prescription(
        for sportName: String,
        rhrBand: String,
        bmiCategory: String
    ) -> SportPrescription? {
        let targetSportKey = Self.normalizedToken(sportName)
        guard let exercise = exercises.first(where: { Self.normalizedToken($0.name) == targetSportKey }) else {
            return nil
        }

        // Find matching RHR band, fallback to first available
        let band = exercise.rhrBands.first { $0.rhrBand == rhrBand }
            ?? exercise.rhrBands.first

        guard let band else { return nil }

        // BMI rule lookup with 3-level fallback:
        // 1. Exact match (e.g. "Normal")
        // 2. "Any BMI" rule
        // 3. First rule available
        let rule = band.bmiRules.first { $0.bmiCategory == bmiCategory }
            ?? band.bmiRules.first { $0.bmiCategory == "Any BMI" }
            ?? band.bmiRules.first

        guard let rule else { return nil }

        let duration = resolveDurationPhases(rule.durationPrescription)
        let frequency = resolveFrequencyPhases(rule.weeklyFrequencyPrescription)

        return SportPrescription(
            sportName: exercise.name,
            hasProgression: rule.durationPrescription.isProgression || rule.weeklyFrequencyPrescription.isProgression,
            initial: .init(
                durationMinutes: duration.initial,
                daysPerWeek: frequency.initial
            ),
            target: .init(
                durationMinutes: duration.target,
                daysPerWeek: frequency.target
            ),
            keyCautions: rule.keyCautions,
            contraindications: rule.contraindications
        )
    }

    private func resolveDurationPhases(
        _ prescription: SportsJsonDurationPrescription
    ) -> (initial: Int, target: Int) {
        let standard = prescription.standardPhase?.minMinutes
        let start = prescription.startPhase?.minMinutes
        let target = prescription.targetPhase?.minMinutes

        let initialValue: Int
        let targetValue: Int
        if prescription.isProgression {
            initialValue = start ?? standard ?? target ?? 20
            targetValue = target ?? standard ?? initialValue
        } else {
            let resolved = standard ?? start ?? target ?? 20
            initialValue = resolved
            targetValue = resolved
        }
        return (initial: initialValue, target: targetValue)
    }

    private func resolveFrequencyPhases(
        _ prescription: SportsJsonFrequencyPrescription
    ) -> (initial: Int, target: Int) {
        let standard = prescription.standardPhase?.minDaysPerWeek
        let start = prescription.startPhase?.minDaysPerWeek
        let target = prescription.targetPhase?.minDaysPerWeek

        let initialValue: Int
        let targetValue: Int
        if prescription.isProgression {
            initialValue = start ?? standard ?? target ?? 2
            targetValue = target ?? standard ?? initialValue
        } else {
            let resolved = standard ?? start ?? target ?? 2
            initialValue = resolved
            targetValue = resolved
        }
        return (initial: initialValue, target: targetValue)
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }
}
