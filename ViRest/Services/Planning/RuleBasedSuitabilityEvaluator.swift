import Foundation

struct RuleBasedSuitabilityEvaluator: SuitabilityEvaluating {
    func evaluate(
        feedback: SuitabilityFeedbackInput,
        recentSameSportCheckIns: [CheckInHistoryEntry]
    ) -> SuitabilityAssessment {
        let zone = resolveZone(feedback: feedback)
        let score: Double
        var reasons: [String] = []
        let decision: ProgressionDecision
        let recommendationText: String

        switch zone {
        case .red:
            score = 28
            decision = .offerSwitchNow
            reasons.append("High-risk signals detected from this session.")
            recommendationText = "This activity may not be suitable right now. Consider switching now."

        case .yellow:
            let yellowPatternTriggered = didTriggerYellowPattern(recent: recentSameSportCheckIns)
            score = yellowPatternTriggered ? 48 : 58
            decision = yellowPatternTriggered ? .offerSwitch : .keepAdjusted
            if yellowPatternTriggered {
                reasons.append("2 of your last 3 check-ins are Yellow for this sport.")
                recommendationText = "Your body may need a better match. Consider switching sport."
            } else {
                reasons.append("Session feels somewhat heavy, monitor response next time.")
                recommendationText = "Continue with a lighter adjustment and re-evaluate next check-in."
            }

        case .green:
            score = 86
            decision = .keep
            reasons.append("This activity response looks suitable.")
            recommendationText = "Great fit so far. Continue your current progression."
        }

        if feedback.painLevel != .noPain {
            reasons.append("Pain/discomfort reported. Keep tracking symptoms carefully.")
        }

        return SuitabilityAssessment(
            zone: zone,
            score: score,
            reasons: reasons,
            decision: decision,
            recommendationText: recommendationText
        )
    }

    private func resolveZone(feedback: SuitabilityFeedbackInput) -> SuitabilityZone {
        let hasBreathingDiscomfort = feedback.discomfortAreas.contains(.breathing)
        let isRed =
            feedback.painLevel == .moderatePain ||
            feedback.painLevel == .strongPain ||
            feedback.difficulty == .tooExhausting ||
            feedback.fatigue == .completelyExhausted ||
            hasBreathingDiscomfort

        if isRed {
            return .red
        }

        let isYellow =
            feedback.painLevel == .mildDiscomfort ||
            feedback.difficulty == .veryHard ||
            feedback.fatigue == .veryTired

        return isYellow ? .yellow : .green
    }

    private func didTriggerYellowPattern(recent: [CheckInHistoryEntry]) -> Bool {
        let previousZones = recent.prefix(2).compactMap(\.zone)
        let yellowCount = ([SuitabilityZone.yellow] + previousZones).filter { $0 == .yellow }.count
        return yellowCount >= 2
    }
}

