import Foundation

struct ExerciseSeedCatalog: Decodable {
    let rhrBands: [String]
    let bmiCategories: [String]
    let environmentOptions: [String]
    let healthConcernContraindicationOptions: [String]
    let exercises: [ExerciseSeedExercise]

    private enum CodingKeys: String, CodingKey {
        case rhrBands
        case bmiCategories
        case environmentOptions
        case healthConcernContraindicationOptions
        case exercises
    }

    init(
        rhrBands: [String],
        bmiCategories: [String],
        environmentOptions: [String],
        healthConcernContraindicationOptions: [String],
        exercises: [ExerciseSeedExercise]
    ) {
        self.rhrBands = rhrBands
        self.bmiCategories = bmiCategories
        self.environmentOptions = environmentOptions
        self.healthConcernContraindicationOptions = healthConcernContraindicationOptions
        self.exercises = exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rhrBands = try container.decodeIfPresent([String].self, forKey: .rhrBands) ?? []
        self.bmiCategories = try container.decodeIfPresent([String].self, forKey: .bmiCategories) ?? []
        self.environmentOptions = try container.decodeIfPresent([String].self, forKey: .environmentOptions) ?? []
        self.healthConcernContraindicationOptions =
            try container.decodeIfPresent([String].self, forKey: .healthConcernContraindicationOptions) ?? []
        self.exercises = try container.decodeIfPresent([ExerciseSeedExercise].self, forKey: .exercises) ?? []
    }
}

struct ExerciseSeedExercise: Decodable {
    let exercise: String
    let environment: String
    let impactLevel: String?
    let equipment: [String]
    let rhrBands: [ExerciseSeedRHRBandRule]

    private enum CodingKeys: String, CodingKey {
        case exercise
        case name
        case environment
        case impactLevel
        case equipment
        case rhrBands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exercise = try container.decodeIfPresent(String.self, forKey: .exercise)
            ?? container.decode(String.self, forKey: .name)
        self.environment = try container.decode(String.self, forKey: .environment)
        self.impactLevel = try container.decodeIfPresent(String.self, forKey: .impactLevel)
        self.equipment = try container.decodeIfPresent([String].self, forKey: .equipment) ?? []
        self.rhrBands = try container.decodeIfPresent([ExerciseSeedRHRBandRule].self, forKey: .rhrBands) ?? []
    }

    var id: String {
        exercise
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

struct ExerciseSeedRHRBandRule: Decodable {
    let rhrBand: String
    let bmiRules: [ExerciseSeedBMIRule]
}

struct ExerciseSeedBMIRule: Decodable {
    let bmiCategory: String
    let keyCautions: [String]
    let contraindications: [String]
    let durationPrescription: ExerciseSeedDurationPrescription
    let weeklyFrequencyPrescription: ExerciseSeedWeeklyFrequencyPrescription
}

struct ExerciseSeedDurationPrescription: Decodable {
    let isProgression: Bool
    let standardPhase: ExerciseSeedDurationPhase?
    let startPhase: ExerciseSeedDurationPhase?
    let targetPhase: ExerciseSeedDurationPhase?

    var entryRange: ClosedRange<Int>? {
        if isProgression {
            return (startPhase ?? standardPhase ?? targetPhase)?.range
        }
        return (standardPhase ?? startPhase ?? targetPhase)?.range
    }

    var targetRange: ClosedRange<Int>? {
        if isProgression {
            return (targetPhase ?? standardPhase ?? startPhase)?.range
        }
        return (standardPhase ?? targetPhase ?? startPhase)?.range
    }
}

struct ExerciseSeedDurationPhase: Decodable {
    let minMinutes: Int
    let maxMinutes: Int

    var range: ClosedRange<Int> {
        minMinutes...maxMinutes
    }
}

struct ExerciseSeedWeeklyFrequencyPrescription: Decodable {
    let isProgression: Bool
    let standardPhase: ExerciseSeedWeeklyFrequencyPhase?
    let startPhase: ExerciseSeedWeeklyFrequencyPhase?
    let targetPhase: ExerciseSeedWeeklyFrequencyPhase?

    var entryRange: ClosedRange<Int>? {
        if isProgression {
            return (startPhase ?? standardPhase ?? targetPhase)?.range
        }
        return (standardPhase ?? startPhase ?? targetPhase)?.range
    }

    var targetRange: ClosedRange<Int>? {
        if isProgression {
            return (targetPhase ?? standardPhase ?? startPhase)?.range
        }
        return (standardPhase ?? targetPhase ?? startPhase)?.range
    }
}

struct ExerciseSeedWeeklyFrequencyPhase: Decodable {
    let minDaysPerWeek: Int
    let maxDaysPerWeek: Int

    var range: ClosedRange<Int> {
        minDaysPerWeek...maxDaysPerWeek
    }
}

enum ExerciseSeedLoader {
    static func loadCatalog() -> ExerciseSeedCatalog? {
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            let decoder = JSONDecoder()
            if let catalog = try? decoder.decode(ExerciseSeedCatalog.self, from: data),
               !catalog.exercises.isEmpty {
                return catalog
            }
        }
        return nil
    }

    static func loadExercises() -> [ExerciseSeedExercise] {
        loadCatalog()?.exercises ?? []
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let sportsBundled = Bundle.main.url(forResource: "sports", withExtension: "json") {
            urls.append(sportsBundled)
        }

        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(cwdURL.appendingPathComponent("ViRest/sports.json"))
        urls.append(cwdURL.appendingPathComponent("ViRest/Resources/sports.json"))

        return urls
    }
}
