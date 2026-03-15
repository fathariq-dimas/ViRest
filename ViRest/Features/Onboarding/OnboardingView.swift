import SwiftUI

struct OnboardingView: View {
    private enum OnboardingPhase {
        case questions
        case summary
    }

    private enum OnboardingStep: Int, CaseIterable, Identifiable {
        case baseline
        case environment
        case preferredTime
        case duration
        case frequency
        case equipment
        case contraindications
        case targetRHR

        var id: Int {
            rawValue
        }

        var title: String {
            switch self {
            case .baseline:
                return "Sync with Apple Health"
            case .environment:
                return "Where would you prefer to exercise?"
            case .preferredTime:
                return "When do you usually prefer to exercise?"
            case .duration:
                return "How much time can you realistically spend exercising in one session?"
            case .frequency:
                return "How many days per week can you realistically exercise?"
            case .equipment:
                return "What exercise access or equipment do you currently have?"
            case .contraindications:
                return "Do you have any of these conditions that should rule out certain exercises?"
            case .targetRHR:
                return "What resting heart rate would you like to achieve?"
            }
        }

        var sectionTitle: String {
            switch self {
            case .baseline:
                return "Current Health Baseline"
            case .environment, .preferredTime:
                return "Exercise Preference"
            case .duration, .frequency, .equipment:
                return "Exercise Availability & Commitment"
            case .contraindications:
                return "Safety Screening"
            case .targetRHR:
                return "Goal Setting"
            }
        }

        var isLast: Bool {
            self == .targetRHR
        }
    }

    private struct StepOption: Identifiable {
        let id: String
        let title: String
        let isSelected: Bool
        let action: () -> Void
    }

    private enum NumericInputKind {
        case weight
        case height
    }

    private struct StaticPressButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }

    @ObservedObject private var viewModel: OnboardingViewModel
    @State private var phase: OnboardingPhase = .questions
    @State private var currentStep: OnboardingStep = .baseline
    @State private var inlineInputError: String?
    @State private var baselineWeightError: String?
    @State private var baselineHeightError: String?
    @State private var lastValidWeightInput: String = ""
    @State private var lastValidHeightInput: String = ""
    @State private var hideHealthSyncHero = false
    @State private var hasAcceptedMedicalDisclaimer = false
    @State private var scrollProxy: ScrollViewProxy?
    private let onExitFromFirstQuestion: () -> Void
    private let topAnchorID = "onboarding_top_anchor"
    private let headerHorizontalPadding: CGFloat = 20
    private let headerButtonSize: CGFloat = 44

    init(
        viewModel: OnboardingViewModel,
        onExitFromFirstQuestion: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onExitFromFirstQuestion = onExitFromFirstQuestion
    }

    var body: some View {
        ZStack {
            Color.richBlack
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                headerView

                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id(topAnchorID)

                        Group {
                            switch phase {
                            case .questions:
                                stepContent
                            case .summary:
                                programSummaryContent
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        scrollProxy = proxy
                        scrollToTop()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: currentStep) { _, _ in
                inlineInputError = nil
                baselineWeightError = nil
                baselineHeightError = nil
            }
            .onChange(of: currentStep) { _, _ in
                scrollToTop()
            }
            .onChange(of: viewModel.recommendationSummary) { _, summary in
                guard summary != nil else { return }
                hasAcceptedMedicalDisclaimer = false
                phase = .summary
                scrollToTop()
            }
            .onChange(of: viewModel.weightKgText) { _, newValue in
                applyRegexGuard(for: .weight, newValue: newValue)
                baselineWeightError = nil
            }
            .onChange(of: viewModel.heightCmText) { _, newValue in
                applyRegexGuard(for: .height, newValue: newValue)
                baselineHeightError = nil
            }
            .onAppear {
                initializeOnboardingIfNeeded()
            }

            VStack {
                Spacer()

                switch phase {
                case .questions:
                    Button(action: handleNext) {
                        let buttonTitle = viewModel.isLoading ? "Loading..." : "Next"

                        Text(buttonTitle)
                            .font(.title3.bold())
                            .foregroundStyle(.vibrantGreen)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isLoading)
                    .buttonStyle(.glass)
                case .summary:
                    Button {
                        viewModel.continueAfterRecommendation()
                    } label: {
                        Text("Get Started")
                            .font(.title3.bold())
                            .foregroundStyle(.vibrantGreen)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(
                        viewModel.isLoading
                        || viewModel.recommendationSummary?.selectedSportId == nil
                        || !hasAcceptedMedicalDisclaimer
                    )
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var displayedErrorMessage: String? {
        guard phase == .questions else { return nil }
        if currentStep == .baseline {
            return viewModel.errorMessage
        }
        return inlineInputError ?? (currentStep.isLast ? viewModel.errorMessage : nil)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Button(action: handleBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(CircularNavigationBackButtonStyle(size: headerButtonSize))
                .frame(width: headerButtonSize, height: headerButtonSize)

                Spacer()

                Text("Virest")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.slateGray)

                Spacer()

                Color.clear
                    .frame(width: headerButtonSize, height: headerButtonSize)
            }
            .padding(.horizontal, headerHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 14)

            if phase == .questions, currentStep != .baseline {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentStep.sectionTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.vibrantGreen)

                    Text(currentStep.title)
                        .font(.title2)
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, headerHorizontalPadding)
                .padding(.bottom, 24)
            }
        }
    }

    private var stepOptions: [StepOption] {
        switch currentStep {
        case .baseline:
            return [
                StepOption(
                    id: CurrentRHRBandQuestion.upTo60.id,
                    title: "≤ 60 bpm",
                    isSelected: viewModel.questionnaireCurrentRHRBand == .upTo60,
                    action: { viewModel.questionnaireCurrentRHRBand = .upTo60 }
                ),
                StepOption(
                    id: CurrentRHRBandQuestion.from61To75.id,
                    title: "61 – 75 bpm",
                    isSelected: viewModel.questionnaireCurrentRHRBand == .from61To75,
                    action: { viewModel.questionnaireCurrentRHRBand = .from61To75 }
                ),
                StepOption(
                    id: CurrentRHRBandQuestion.from76To90.id,
                    title: "76 – 90 bpm",
                    isSelected: viewModel.questionnaireCurrentRHRBand == .from76To90,
                    action: { viewModel.questionnaireCurrentRHRBand = .from76To90 }
                ),
                StepOption(
                    id: CurrentRHRBandQuestion.above90.id,
                    title: "≥ 90 bpm",
                    isSelected: viewModel.questionnaireCurrentRHRBand == .above90,
                    action: { viewModel.questionnaireCurrentRHRBand = .above90 }
                )
            ]
        case .environment:
            return SportEnvironment.allCases.map { option in
                StepOption(
                    id: option.id,
                    title: option.displayName,
                    isSelected: viewModel.environment == option,
                    action: {
                        viewModel.environment = option
                    }
                )
            }
        case .preferredTime:
            return PreferredTime.allCases.map { option in
                StepOption(
                    id: option.id,
                    title: option.displayName,
                    isSelected: viewModel.preferredTime == option,
                    action: {
                        viewModel.preferredTime = option
                    }
                )
            }
        case .duration:
            return SessionDurationOption.allCases.map { option in
                StepOption(
                    id: option.id,
                    title: option.displayName,
                    isSelected: viewModel.sessionDuration == option,
                    action: {
                        viewModel.sessionDuration = option
                    }
                )
            }
        case .frequency:
            return [
                StepOption(
                    id: DaysPerWeekAvailability.twoToThree.id,
                    title: "2 – 3 days",
                    isSelected: viewModel.daysPerWeek == .twoToThree,
                    action: { viewModel.daysPerWeek = .twoToThree }
                ),
                StepOption(
                    id: DaysPerWeekAvailability.threeToFour.id,
                    title: "3 – 4 days",
                    isSelected: viewModel.daysPerWeek == .threeToFour,
                    action: { viewModel.daysPerWeek = .threeToFour }
                ),
                StepOption(
                    id: DaysPerWeekAvailability.fourToFive.id,
                    title: "4 – 5 days",
                    isSelected: viewModel.daysPerWeek == .fourToFive,
                    action: { viewModel.daysPerWeek = .fourToFive }
                ),
                StepOption(
                    id: DaysPerWeekAvailability.fiveToSeven.id,
                    title: "5 – 7 days",
                    isSelected: viewModel.daysPerWeek == .fiveToSeven,
                    action: { viewModel.daysPerWeek = .fiveToSeven }
                )
            ]
        case .equipment:
            return ExerciseAccessOptionQuestion.allCases.map { option in
                StepOption(
                    id: option.id,
                    title: option.displayName,
                    isSelected: viewModel.accessOptions.contains(option),
                    action: {
                        viewModel.toggleAccessOption(option)
                    }
                )
            }
        case .contraindications:
            return HealthConcernOption.allCases.map { option in
                StepOption(
                    id: option.id,
                    title: option.displayName,
                    isSelected: viewModel.healthConcerns.contains(option),
                    action: {
                        viewModel.toggleHealthConcern(option)
                    }
                )
            }
        case .targetRHR:
            return TargetRHRGoalQuestion.allCases.map { option in
                StepOption(
                    id: option.id,
                    title: option.displayName,
                    isSelected: viewModel.questionnaireTargetRHRGoal == option,
                    action: {
                        viewModel.questionnaireTargetRHRGoal = option
                    }
                )
            }
        }
    }

    private func handleBack() {
        inlineInputError = nil

        if phase == .summary {
            phase = .questions
            return
        }

        if currentStep == .baseline {
            onExitFromFirstQuestion()
            return
        }

        guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previousStep
    }

    private func handleNext() {
        inlineInputError = nil

        guard phase == .questions else { return }
        guard validateCurrentInputStep() else { return }

        if currentStep.isLast {
            viewModel.submit()
            return
        }

        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextStep
    }

    private var stepContent: some View {
        VStack(spacing: 16) {
            switch currentStep {
            case .baseline:
                baselineStepContent
            default:
                VStack(spacing: 16) {
                    ForEach(stepOptions) { option in
                        optionRow(option)
                    }
                }
                .padding(.bottom, 80)
            }
        }
    }

    private var isRHRMappedFromHealthKit: Bool {
        viewModel.isHealthKitSynchronized && viewModel.importedHealthSnapshot?.restingHeartRate != nil
    }

    private var isWeightMappedFromHealthKit: Bool {
        viewModel.isHealthKitSynchronized && viewModel.importedHealthSnapshot?.weightKg != nil
    }

    private var isHeightMappedFromHealthKit: Bool {
        viewModel.isHealthKitSynchronized && viewModel.importedHealthSnapshot?.heightCm != nil
    }

    private func numericInputCard(
        placeholder: String,
        unit: String,
        text: Binding<String>,
        isEnabled: Bool = true
    ) -> some View {
        VStack(spacing: 16) {
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    .disabled(!isEnabled)

                Spacer(minLength: 8)

                Text(unit)
                    .font(.headline)
                    .foregroundStyle(Color.slateGray)
                    .padding(.trailing, 24)
            }
            .glassEffect(.clear)
            .opacity(isEnabled ? 1 : 0.65)
        }
    }

    private var baselineStepContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !hideHealthSyncHero {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Sync with Apple Health")
                        .font(.system(size: 48, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                        .italic()
                        .lineLimit(2)

                    VStack(alignment: .leading, spacing: 16) {
                        syncBenefitRow(icon: "person.circle.fill", text: "Give sport recommendations based on your data")
                        syncBenefitRow(icon: "chart.line.uptrend.xyaxis", text: "Track your fitness progress")
                        syncBenefitRow(icon: "lock.fill", text: "Secure and private")
                    }

                    Button {
                        viewModel.importHealthData()
                    } label: {
                        Text(healthSyncButtonTitle)
                            .font(.title3.bold())
                            .italic()
                            .foregroundStyle(Color.vibrantGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .disabled(viewModel.isLoading)
                }
            }

            HStack(spacing: 16) {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 2)
                Text("OR")
                    .font(.title2.bold())
                    .foregroundStyle(.white.opacity(0.9))
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 2)
            }

            Text("Enter manually")
                .font(.system(size: 48, weight: .bold, design: .default))
                .foregroundStyle(.white)
                .italic()
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 24) {
                Text("What is your current resting heart rate (RHR)?")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(spacing: 12) {
                    ForEach(stepOptions) { option in
                        optionRow(option)
                    }
                }

                if isRHRMappedFromHealthKit {
                    Text("Mapped from Apple Health")
                        .font(.footnote)
                        .foregroundStyle(Color.slateGray)
                }
            }

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What is your current weight?")
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let errorMessage = baselineWeightError {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                numericInputCard(
                    placeholder: "Number input in kg",
                    unit: "kg",
                    text: $viewModel.weightKgText
                )

                if isWeightMappedFromHealthKit {
                    Text("Mapped from Apple Health")
                        .font(.footnote)
                        .foregroundStyle(Color.slateGray)
                }
            }

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What is your current height?")
                        .font(.headline)
                        .foregroundStyle(.white)

                    if let errorMessage = baselineHeightError {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                numericInputCard(
                    placeholder: "Number input in cm",
                    unit: "cm",
                    text: $viewModel.heightCmText
                )

                if isHeightMappedFromHealthKit {
                    Text("Mapped from Apple Health")
                        .font(.footnote)
                        .foregroundStyle(Color.slateGray)
                }
            }
            .padding(.bottom, 80)
        }
    }

    @ViewBuilder
    private var programSummaryContent: some View {
        if let summary = viewModel.recommendationSummary {
            VStack(alignment: .leading, spacing: 16) {
                Text("Top Sport Matches")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(.vibrantGreen)
                    .italic()

                Text("Review your matched sports based on your input profile.")
                    .font(.title3)
                    .foregroundStyle(Color.slateGray)

                Text("Choose one active sport for your Home plan. Other recommendations stay available but locked.")
                    .font(.footnote)
                    .foregroundStyle(Color.slateGray.opacity(0.9))

                VStack(spacing: 14) {
                    ForEach(summary.sports) { sport in
                        sportProgramCard(
                            sport,
                            isSelected: summary.selectedSportId == sport.sportId
                        ) {
                            viewModel.selectRecommendedSport(sport.sportId)
                        }
                    }
                }

                medicalDisclaimerConsentCard
            }
            .padding(.bottom, 110)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Generating your program...")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        }
    }

    private var medicalDisclaimerConsentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medical Notice")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Virest provides exercise recommendations and does not replace medical advice. Please consult a qualified healthcare professional for diagnosis and treatment decisions.")
                .font(.footnote)
                .foregroundStyle(Color.slateGray)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $hasAcceptedMedicalDisclaimer) {
                Text("I understand and agree to continue with this recommendation.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .tint(.vibrantGreen)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func sportProgramCard(
        _ sport: OnboardingViewModel.RecommendationSummary.SportFactor,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Text(sport.sportName)
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        if isSelected {
                            Text("Selected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.vibrantGreen)
                        }

                        Text("\(sport.compatibilityPercent)% Match")
                            .font(.headline)
                            .foregroundStyle(Color.vibrantGreen)
                    }
                }

                if sport.hasProgression {
                    Text("Progressive plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.vibrantGreen)

                    Text("Week 1 uses initial adaptation. Starting week 2, your plan automatically moves to target intensity.")
                        .font(.caption)
                        .foregroundStyle(Color.slateGray)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        phaseInfoCard(
                            title: "Week 1",
                            durationMinutes: sport.weekOneSessionMinutes,
                            frequencyPerWeek: sport.weekOneFrequency
                        )
                        phaseInfoCard(
                            title: "Week 2+",
                            durationMinutes: sport.weekTwoPlusSessionMinutes,
                            frequencyPerWeek: sport.weekTwoPlusFrequency
                        )
                    }
                } else {
                    standardInfoCard(
                        durationMinutes: sport.weekOneSessionMinutes,
                        frequencyPerWeek: sport.weekOneFrequency
                    )
                }

                if !sport.cautions.isEmpty {
                    cautionInfoCard(cautions: sport.cautions)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.vibrantGreen.opacity(0.9) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private func cautionInfoCard(cautions: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.yellow.opacity(0.95))

            VStack(alignment: .leading, spacing: 6) {
                Text("Cautions")
                    .font(.headline)
                    .foregroundStyle(Color.yellow.opacity(0.95))

                ForEach(Array(cautions.prefix(3)), id: \.self) { caution in
                    Text("• \(caution)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.yellow.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.yellow.opacity(0.55), lineWidth: 1)
        )
    }

    private func phaseInfoCard(
        title: String,
        durationMinutes: Int,
        frequencyPerWeek: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.slateGray)
                Text("\(durationMinutes) min")
                    .font(.subheadline)
                    .foregroundStyle(Color.slateGray)
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.slateGray)
                Text("\(frequencyPerWeek)x / week")
                    .font(.subheadline)
                    .foregroundStyle(Color.slateGray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func standardInfoCard(
        durationMinutes: Int,
        frequencyPerWeek: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Standard plan")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.slateGray)
                    Text("\(durationMinutes) min / session")
                        .font(.subheadline)
                        .foregroundStyle(Color.slateGray)
                }

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.slateGray)
                    Text("\(frequencyPerWeek)x / week")
                        .font(.subheadline)
                        .foregroundStyle(Color.slateGray)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func syncBenefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.vibrantGreen)
                .frame(width: 28)

            Text(text)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func optionRow(_ option: StepOption, isEnabled: Bool = true) -> some View {
        Button(action: option.action) {
            HStack(alignment: .center) {
                Text(option.title)
                    .font(.headline)
                    .foregroundStyle(Color.white)

                Spacer()

                ZStack {
                    if option.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12).bold())
                            .foregroundStyle(.vibrantGreen)
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(
                    Circle()
                )
                .overlay(
                    Circle().stroke(option.isSelected ? Color.vibrantGreen : Color.white, lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(StaticPressButtonStyle())
        .glassEffect(option.isSelected ? .clear.interactive() : .identity)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
    }

    private var healthSyncButtonTitle: String {
        if viewModel.isLoading {
            return "Syncing..."
        }

        if viewModel.isHealthKitSynchronized {
            return "Apple Health Synced"
        }

        return "Sync with Apple Health"
    }

    private func initializeOnboardingIfNeeded() {
        phase = .questions
        currentStep = .baseline
        inlineInputError = nil
        baselineWeightError = nil
        baselineHeightError = nil
        hideHealthSyncHero = false
        hasAcceptedMedicalDisclaimer = false

        viewModel.resetForNewOnboarding()

        lastValidWeightInput = normalizeInput(viewModel.weightKgText, kind: .weight)
        lastValidHeightInput = normalizeInput(viewModel.heightCmText, kind: .height)
        scrollToTop()

        Task {
            await viewModel.prepareHealthDataOnEntry()
            lastValidWeightInput = normalizeInput(viewModel.weightKgText, kind: .weight)
            lastValidHeightInput = normalizeInput(viewModel.heightCmText, kind: .height)
        }
    }

    private func scrollToTop() {
        scrollProxy?.scrollTo(topAnchorID, anchor: .top)
    }

    private func regexPattern(for kind: NumericInputKind) -> String {
        switch kind {
        case .weight:
            // 0-3 digit integer, optional decimal with max 1 digit (e.g. 70, 70.5, 120.0)
            return #"^[0-9]{0,3}(?:\.[0-9]{0,1})?$"#
        case .height:
            // 0-3 digit integer, optional decimal with max 1 digit (e.g. 165, 165.5, 180.0)
            return #"^[0-9]{0,3}(?:\.[0-9]{0,1})?$"#
        }
    }

    private func normalizeInput(_ value: String, kind: NumericInputKind) -> String {
        switch kind {
        case .height, .weight:
            var result = ""
            var hasDecimalSeparator = false

            for character in value {
                if character.isNumber {
                    result.append(character)
                    continue
                }

                if character == "." || character == "," {
                    guard !hasDecimalSeparator else { continue }
                    hasDecimalSeparator = true
                    result.append(".")
                }
            }
            return result
        }
    }

    private func applyRegexGuard(for kind: NumericInputKind, newValue: String) {
        let normalized = normalizeInput(newValue, kind: kind)
        let isValid = normalized.range(of: regexPattern(for: kind), options: .regularExpression) != nil

        switch kind {
        case .weight:
            if isValid {
                if viewModel.weightKgText != normalized {
                    viewModel.weightKgText = normalized
                    return
                }
                lastValidWeightInput = normalized
            } else if viewModel.weightKgText != lastValidWeightInput {
                viewModel.weightKgText = lastValidWeightInput
            }
        case .height:
            if isValid {
                if viewModel.heightCmText != normalized {
                    viewModel.heightCmText = normalized
                    return
                }
                lastValidHeightInput = normalized
            } else if viewModel.heightCmText != lastValidHeightInput {
                viewModel.heightCmText = lastValidHeightInput
            }
        }
    }

    private func validateCurrentInputStep() -> Bool {
        switch currentStep {
        case .baseline:
            baselineWeightError = nil
            baselineHeightError = nil

            var isValid = true

            let trimmedWeight = viewModel.weightKgText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedWeight.isEmpty else {
                baselineWeightError = "Please input your weight in kg."
                return false
            }

            guard let weight = Double(trimmedWeight.replacingOccurrences(of: ",", with: ".")), weight > 0 else {
                baselineWeightError = "Please input a valid weight in kg."
                return false
            }

            if weight < 20 || weight > 400 {
                baselineWeightError = "Weight seems out of range."
                isValid = false
            }

            let trimmedHeight = viewModel.heightCmText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHeight.isEmpty else {
                baselineHeightError = "Please input your height in cm."
                return false
            }

            guard let height = Double(trimmedHeight.replacingOccurrences(of: ",", with: ".")), height > 0 else {
                baselineHeightError = "Please input a valid height in cm."
                return false
            }

            if height < 80 || height > 250 {
                baselineHeightError = "Height seems out of range."
                isValid = false
            }

            return isValid
        default:
            return true
        }
    }
}

@MainActor
private struct OnboardingPreviewHost: View {
    private let viewModel = PreviewSupport.makeOnboardingViewModel()

    var body: some View {
        NavigationStack {
            OnboardingView(viewModel: viewModel)
        }
    }
}

#Preview("Onboarding") {
    OnboardingPreviewHost()
}
