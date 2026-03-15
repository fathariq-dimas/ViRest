import Foundation

enum Gender: String, Codable, CaseIterable, Identifiable {
    case female
    case male
    case nonBinary = "non_binary"
    case preferNotToSay = "prefer_not_to_say"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .nonBinary: return "Non-binary"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

enum CurrentRHRBandQuestion: String, Codable, CaseIterable, Identifiable {
    case upTo60 = "up_to_60"
    case from61To75 = "61_75"
    case from76To90 = "76_90"
    case above90 = "above_90"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upTo60: return "<= 60 bpm"
        case .from61To75: return "61-75 bpm"
        case .from76To90: return "76-90 bpm"
        case .above90: return "> 90 bpm"
        }
    }

    var representativeBPM: Int {
        switch self {
        case .upTo60: return 58
        case .from61To75: return 68
        case .from76To90: return 83
        case .above90: return 95
        }
    }
}

enum TargetRHRGoalQuestion: String, Codable, CaseIterable, Identifiable {
    case from90To99 = "90_99"
    case from80To89 = "80_89"
    case from70To79 = "70_79"
    case from60To69 = "60_69"
    case from50To59 = "50_59"
    case below50 = "below_50"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .from90To99: return "90-99 bpm"
        case .from80To89: return "80-89 bpm"
        case .from70To79: return "70-79 bpm"
        case .from60To69: return "60-69 bpm"
        case .from50To59: return "50-59 bpm"
        case .below50: return "< 50 bpm"
        }
    }

    var representativeBPM: Int {
        switch self {
        case .from90To99:
            return 95
        case .from80To89:
            return 85
        case .from70To79:
            return 75
        case .from60To69:
            return 65
        case .from50To59:
            return 55
        case .below50:
            return 48
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case Self.from90To99.rawValue:
            self = .from90To99
        case Self.from80To89.rawValue:
            self = .from80To89
        case Self.from70To79.rawValue:
            self = .from70To79
        case Self.from60To69.rawValue, "around60":
            self = .from60To69
        case Self.from50To59.rawValue, "55_59", "50_54", "around55", "around50":
            self = .from50To59
        case Self.below50.rawValue:
            self = .below50
        default:
            self = .from60To69
        }
    }
}

enum HealthConcernOption: String, Codable, CaseIterable, Identifiable {
    case none
    case kneeStressInjury = "knee_stress_injury"
    case hipStressInjury = "hip_stress_injury"
    case lowBackDisorder = "low_back_disorder"
    case patellofemoralPain = "patellofemoral_pain"
    case kneeOsteoarthritis = "knee_osteoarthritis"
    case severeKneePain = "severe_knee_pain"
    case unexplainedRestingTachycardia = "unexplained_resting_tachycardia"
    case rhrAbove90WithoutMedicalEvaluation = "rhr_above_90_without_medical_evaluation"
    case lowBackInjury = "low_back_injury"
    case chestPainDuringActivity = "chest_pain_during_activity"
    case palpitationsDuringActivity = "palpitations_during_activity"
    case severeCardiovascularSymptoms = "severe_cardiovascular_symptoms"
    case severeCardiovascularInstability = "severe_cardiovascular_instability"
    case orthopnea

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .kneeStressInjury: return "Knee stress injury"
        case .hipStressInjury: return "Hip stress injury"
        case .lowBackDisorder: return "Low back disorder"
        case .patellofemoralPain: return "Patellofemoral pain"
        case .kneeOsteoarthritis: return "Knee osteoarthritis"
        case .severeKneePain: return "Severe knee pain"
        case .unexplainedRestingTachycardia: return "Unexplained resting tachycardia"
        case .rhrAbove90WithoutMedicalEvaluation: return "RHR > 90 without medical evaluation"
        case .lowBackInjury: return "Low back injury"
        case .chestPainDuringActivity: return "Chest pain during activity"
        case .palpitationsDuringActivity: return "Palpitations during activity"
        case .severeCardiovascularSymptoms: return "Severe cardiovascular symptoms"
        case .severeCardiovascularInstability: return "Severe cardiovascular instability"
        case .orthopnea: return "Orthopnea"
        }
    }
}

enum ExerciseAccessOptionQuestion: String, Codable, CaseIterable, Identifiable {
    case none
    case treadmill
    case walkingShoes = "walking_shoes"
    case runningShoes = "running_shoes"
    case bicycle
    case helmet
    case stationaryBike = "stationary_bike"
    case recumbentBike = "recumbent_bike"
    case ellipticalTrainer = "elliptical_trainer"
    case rowingMachine = "rowing_machine"
    case swimmingPool = "swimming_pool"
    case flotationBelt = "flotation_belt"
    case stairClimberMachine = "stair_climber_machine"
    case stairs
    case nordicWalkingPoles = "nordic_walking_poles"
    case yogaMat = "yoga_mat"
    case stableChair = "stable_chair"
    case hikingShoes = "hiking_shoes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .treadmill: return "Treadmill"
        case .walkingShoes: return "Walking shoes"
        case .runningShoes: return "Running shoes"
        case .bicycle: return "Bicycle"
        case .helmet: return "Helmet"
        case .stationaryBike: return "Stationary bike"
        case .recumbentBike: return "Recumbent bike"
        case .ellipticalTrainer: return "Elliptical trainer"
        case .rowingMachine: return "Rowing machine"
        case .swimmingPool: return "Swimming pool"
        case .flotationBelt: return "Flotation belt"
        case .stairClimberMachine: return "Stair climber machine"
        case .stairs: return "Stairs"
        case .nordicWalkingPoles: return "Nordic walking poles"
        case .yogaMat: return "Yoga mat"
        case .stableChair: return "Stable chair"
        case .hikingShoes: return "Hiking shoes"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case Self.none.rawValue:
            self = .none
        case Self.treadmill.rawValue:
            self = .treadmill
        case Self.walkingShoes.rawValue:
            self = .walkingShoes
        case Self.runningShoes.rawValue:
            self = .runningShoes
        case Self.bicycle.rawValue, "outdoor_bicycle":
            self = .bicycle
        case Self.helmet.rawValue:
            self = .helmet
        case Self.stationaryBike.rawValue:
            self = .stationaryBike
        case Self.recumbentBike.rawValue:
            self = .recumbentBike
        case Self.ellipticalTrainer.rawValue, "elliptical_machine":
            self = .ellipticalTrainer
        case Self.rowingMachine.rawValue:
            self = .rowingMachine
        case Self.swimmingPool.rawValue, "pool":
            self = .swimmingPool
        case Self.flotationBelt.rawValue:
            self = .flotationBelt
        case Self.stairClimberMachine.rawValue, "stair_machine":
            self = .stairClimberMachine
        case Self.stairs.rawValue:
            self = .stairs
        case Self.nordicWalkingPoles.rawValue:
            self = .nordicWalkingPoles
        case Self.yogaMat.rawValue, "yoga_mat_or_floor_space":
            self = .yogaMat
        case Self.stableChair.rawValue, "chair":
            self = .stableChair
        case Self.hikingShoes.rawValue, "trail_or_outdoor_route":
            self = .hikingShoes
        case "open_space":
            self = .none
        case "stationary_or_recumbent_bike":
            self = .stationaryBike
        case "stairs_or_stair_machine":
            self = .stairs
        case "dance_or_aerobics_space":
            self = .none
        default:
            self = .none
        }
    }
}

enum SessionDurationOption: String, Codable, CaseIterable, Identifiable {
    case tenToTwenty = "10_20"
    case twentyToThirty = "20_30"
    case thirtyToFortyFive = "30_45"
    case fortyFiveToSixty = "45_60"
    case sixtyMinutes = "60"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tenToTwenty: return "10-20 minutes"
        case .twentyToThirty: return "20-30 minutes"
        case .thirtyToFortyFive: return "30-45 minutes"
        case .fortyFiveToSixty: return "45-60 minutes"
        case .sixtyMinutes: return "60 minutes"
        }
    }

    var recommendedMinutes: Int {
        switch self {
        case .tenToTwenty: return 15
        case .twentyToThirty: return 25
        case .thirtyToFortyFive: return 38
        case .fortyFiveToSixty: return 52
        case .sixtyMinutes: return 60
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case Self.tenToTwenty.rawValue, "5_10":
            self = .tenToTwenty
        case Self.twentyToThirty.rawValue, "10_20":
            self = .twentyToThirty
        case Self.thirtyToFortyFive.rawValue, "20_30":
            self = .thirtyToFortyFive
        case Self.fortyFiveToSixty.rawValue, "30_45":
            self = .fortyFiveToSixty
        case Self.sixtyMinutes.rawValue, "45_plus":
            self = .sixtyMinutes
        default:
            self = .twentyToThirty
        }
    }
}

enum DaysPerWeekAvailability: String, Codable, CaseIterable, Identifiable {
    case twoToThree = "2_3"
    case threeToFour = "3_4"
    case fourToFive = "4_5"
    case fiveToSeven = "5_7"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twoToThree: return "2-3 times per week"
        case .threeToFour: return "3-4 times per week"
        case .fourToFive: return "4-5 times per week"
        case .fiveToSeven: return "5-7 times per week"
        }
    }

    var targetSessions: Int {
        switch self {
        case .twoToThree: return 3
        case .threeToFour: return 4
        case .fourToFive: return 5
        case .fiveToSeven: return 6
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case Self.twoToThree.rawValue, "1_2":
            self = .twoToThree
        case Self.threeToFour.rawValue, "three", "2_3":
            self = .threeToFour
        case Self.fourToFive.rawValue, "4_5", "daily":
            self = .fourToFive
        case Self.fiveToSeven.rawValue, "5_7":
            self = .fiveToSeven
        default:
            self = .threeToFour
        }
    }
}

enum PreferredTime: String, Codable, CaseIterable, Identifiable {
    case flexible
    case morning
    case midday
    case evening

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flexible: return "Flexible"
        case .morning: return "Morning"
        case .midday: return "Midday"
        case .evening: return "Evening"
        }
    }

    var reminderHour: Int {
        switch self {
        case .morning:
            return 6
        case .midday:
            return 12
        case .evening:
            return 17
        case .flexible:
            return 17
        }
    }

    var reminderDateComponents: DateComponents {
        DateComponents(hour: reminderHour, minute: 0)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case Self.flexible.rawValue, "no_preference":
            self = .flexible
        case Self.morning.rawValue:
            self = .morning
        case Self.midday.rawValue, "lunch_break":
            self = .midday
        case Self.evening.rawValue:
            self = .evening
        default:
            self = .flexible
        }
    }
}

struct CustomReminderTime: Codable, Equatable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 17, minute: components.minute ?? 0)
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    func toDate(calendar: Calendar = .current) -> Date {
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? now
    }
}

enum SportEnvironment: String, Codable, CaseIterable, Identifiable {
    case both
    case indoor
    case outdoor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both: return "Both"
        case .indoor: return "Indoor"
        case .outdoor: return "Outdoor"
        }
    }
}

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case briskWalking = "brisk_walking"
    case trailWalking = "trail_walking"
    case flatWalking = "flat_walking"
    case walkingGeneral = "walking_general"
    case intervalWalking = "interval_walking"
    case jogging
    case runWalkIntervals = "run_walk_intervals"
    case roadCycling = "road_cycling"
    case stationaryCycling = "stationary_cycling"
    case recumbentCycling = "recumbent_cycling"
    case rowingMachineCardio = "rowing_machine_cardio"
    case lapSwimming = "lap_swimming"
    case stairClimber = "stair_climber"
    case stairWalking = "stair_walking"
    case poolWalking = "pool_walking"
    case aquaJogging = "aqua_jogging"
    case vinyasaYoga = "vinyasa_yoga"
    case restorativeYoga = "restorative_yoga"
    case chairMarching = "chair_marching"
    case chairAerobics = "chair_aerobics"
    case walking
    case running
    case cyclingOutdoor = "cycling_outdoor"
    case cyclingIndoor = "cycling_indoor"
    case elliptical
    case inclineWalking = "incline_walking"
    case nordicWalking = "nordic_walking"
    case runWalkInterval = "run_walk_interval"
    case cycling
    case indoorCycling = "indoor_cycling"
    case swimming
    case waterAerobics = "water_aerobics"
    case danceCardio = "dance_cardio"
    case aquaAerobics = "aqua_aerobics"
    case stairClimbing = "stair_climbing"
    case stepAerobics = "step_aerobics"
    case hiit
    case taiChi = "tai_chi"
    case ellipticalTrainer = "elliptical_trainer"
    case rowing
    case lowImpactAerobics = "low_impact_aerobics"
    case yoga
    case stretching
    case dancing
    case bodyweightExercise = "bodyweight_exercise"
    case hiking
    case badminton
    case tennisDoubles = "tennis_doubles"
    case lightJogging = "light_jogging"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .briskWalking: return "Brisk walking"
        case .trailWalking: return "Trail walking"
        case .flatWalking: return "Flat walking"
        case .walkingGeneral: return "Walking"
        case .intervalWalking: return "Interval walking"
        case .jogging: return "Jogging"
        case .runWalkIntervals: return "Run-walk intervals"
        case .roadCycling: return "Road cycling"
        case .stationaryCycling: return "Stationary cycling"
        case .recumbentCycling: return "Recumbent cycling"
        case .rowingMachineCardio: return "Rowing machine"
        case .lapSwimming: return "Lap swimming"
        case .stairClimber: return "Stair climber"
        case .stairWalking: return "Stair walking"
        case .poolWalking: return "Pool walking"
        case .aquaJogging: return "Aqua jogging"
        case .vinyasaYoga: return "Vinyasa yoga"
        case .restorativeYoga: return "Restorative yoga"
        case .chairMarching: return "Chair marching"
        case .chairAerobics: return "Chair aerobics"
        case .walking: return "Brisk walking"
        case .running: return "Running"
        case .cyclingOutdoor: return "Outdoor cycling"
        case .cyclingIndoor: return "Indoor cycling"
        case .elliptical: return "Elliptical"
        case .inclineWalking: return "Incline walking"
        case .nordicWalking: return "Nordic walking"
        case .runWalkInterval: return "Run-walk interval"
        case .cycling: return "Outdoor cycling"
        case .indoorCycling: return "Indoor cycling"
        case .swimming: return "Swimming"
        case .waterAerobics: return "Water aerobics"
        case .danceCardio: return "Dance cardio"
        case .aquaAerobics: return "Aqua aerobics"
        case .stairClimbing: return "Stair climbing"
        case .stepAerobics: return "Step aerobics"
        case .hiit: return "HIIT"
        case .taiChi: return "Tai chi"
        case .ellipticalTrainer: return "Elliptical trainer"
        case .rowing: return "Rowing ergometer"
        case .lowImpactAerobics: return "Low-impact aerobics"
        case .yoga: return "Vinyasa yoga"
        case .stretching: return "Dynamic stretching flow"
        case .dancing: return "Dance cardio"
        case .bodyweightExercise: return "Bodyweight cardio circuit"
        case .hiking: return "Hiking"
        case .badminton: return "Badminton (recreational)"
        case .tennisDoubles: return "Tennis doubles"
        case .lightJogging: return "Light jogging"
        }
    }
}

enum CardioExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case lightlyActive = "lightly_active"
    case moderatelyActive = "moderately_active"
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .lightlyActive: return "Lightly active"
        case .moderatelyActive: return "Moderately active"
        case .advanced: return "Advanced"
        }
    }
}

enum IntensityPreference: String, Codable, CaseIterable, Identifiable {
    case veryLight = "very_light"
    case light
    case moderate
    case challenging

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .veryLight: return "Very light"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .challenging: return "Challenging"
        }
    }

    var targetRange: RPERange {
        switch self {
        case .veryLight: return RPERange(min: 2, max: 3)
        case .light: return RPERange(min: 3, max: 4)
        case .moderate: return RPERange(min: 4, max: 6)
        case .challenging: return RPERange(min: 5, max: 6)
        }
    }
}

enum SocialPreference: String, Codable, CaseIterable, Identifiable {
    case solo
    case withFriends = "with_friends"
    case classes
    case either

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solo: return "Solo"
        case .withFriends: return "With friends"
        case .classes: return "Classes"
        case .either: return "Either"
        }
    }
}

enum ConsistencyLevel: String, Codable, CaseIterable, Identifiable {
    case quitEasily = "quit_easily"
    case somewhatConsistent = "somewhat_consistent"
    case veryDisciplined = "very_disciplined"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quitEasily: return "I quit easily"
        case .somewhatConsistent: return "Somewhat consistent"
        case .veryDisciplined: return "Very disciplined"
        }
    }
}

struct UserProfileInput: Codable, Identifiable, Equatable {
    var id: UUID
    var fullName: String
    var age: Int?
    var gender: Gender?
    var questionnaireCurrentRHRBand: CurrentRHRBandQuestion?
    var questionnaireTargetRHRGoal: TargetRHRGoalQuestion?
    var heightCm: Double?
    var weightKg: Double?
    var questionnaireHealthConcerns: [HealthConcernOption]?
    var sessionDuration: SessionDurationOption
    var daysPerWeek: DaysPerWeekAvailability
    var preferredTime: PreferredTime
    var customReminderTime: CustomReminderTime?
    var environment: SportEnvironment
    var questionnaireAccessOptions: [ExerciseAccessOptionQuestion]?
    var enjoyableActivities: [ActivityType]
    var intensityPreference: IntensityPreference
    var socialPreference: SocialPreference
    var consistency: ConsistencyLevel
    var cardioExperienceLevel: CardioExperienceLevel?
    var acceptedDisclaimer: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        fullName: String = "",
        age: Int? = nil,
        gender: Gender? = nil,
        questionnaireCurrentRHRBand: CurrentRHRBandQuestion? = nil,
        questionnaireTargetRHRGoal: TargetRHRGoalQuestion? = nil,
        heightCm: Double? = nil,
        weightKg: Double? = nil,
        questionnaireHealthConcerns: [HealthConcernOption]? = nil,
        sessionDuration: SessionDurationOption = .twentyToThirty,
        daysPerWeek: DaysPerWeekAvailability = .threeToFour,
        preferredTime: PreferredTime = .flexible,
        customReminderTime: CustomReminderTime? = nil,
        environment: SportEnvironment = .both,
        questionnaireAccessOptions: [ExerciseAccessOptionQuestion]? = nil,
        enjoyableActivities: [ActivityType] = [.walking],
        intensityPreference: IntensityPreference = .light,
        socialPreference: SocialPreference = .either,
        consistency: ConsistencyLevel = .somewhatConsistent,
        cardioExperienceLevel: CardioExperienceLevel? = nil,
        acceptedDisclaimer: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fullName = fullName
        self.age = age
        self.gender = gender
        self.questionnaireCurrentRHRBand = questionnaireCurrentRHRBand
        self.questionnaireTargetRHRGoal = questionnaireTargetRHRGoal
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.questionnaireHealthConcerns = questionnaireHealthConcerns
        self.sessionDuration = sessionDuration
        self.daysPerWeek = daysPerWeek
        self.preferredTime = preferredTime
        self.customReminderTime = customReminderTime
        self.environment = environment
        self.questionnaireAccessOptions = questionnaireAccessOptions
        self.enjoyableActivities = enjoyableActivities
        self.intensityPreference = intensityPreference
        self.socialPreference = socialPreference
        self.consistency = consistency
        self.cardioExperienceLevel = cardioExperienceLevel
        self.acceptedDisclaimer = acceptedDisclaimer
        self.updatedAt = updatedAt
    }

    var resolvedReminderDateComponents: DateComponents {
        customReminderTime?.dateComponents ?? preferredTime.reminderDateComponents
    }
}
