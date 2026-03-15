import Foundation

struct RuleBasedPlanAdjustmentService: PlanAdjusting {
    func evaluate(
        checkIn: SessionCheckIn,
        recentCheckIns: [SessionCheckIn],
        currentPlan: WeeklyPlan,
        alternatives: [SportRecommendation],
        latestHealthSnapshot: HealthSnapshot?
    ) -> PlanAdjustmentResult {
        let recent = recentCheckIns.sortedByDateDescending()
        let redTrigger = isRedTrigger(checkIn)
        let repeatedOverfatigue = overfatigueCount(in: recent, including: checkIn) >= 2
        let repeatedEasy = easySessionCount(in: recent, including: checkIn) >= 3

        let zone: SuitabilityZone
        let decision: ProgressionDecision
        var reasons: [String] = []
        var recommendationText: String

        if redTrigger {
            zone = .red
            decision = alternatives.isEmpty ? .downgradeIntensity : .switchAlternative
            reasons.append("Pain or severe exhaustion detected")
            recommendationText = "Switching to safer load profile for upcoming sessions."
        } else if repeatedOverfatigue {
            zone = .yellow
            decision = .reduceVolume
            reasons.append("Repeated over-fatigue pattern")
            recommendationText = "Reducing volume to improve recovery and consistency."
        } else if repeatedEasy {
            zone = .green
            decision = .progress
            reasons.append("Sessions feel manageable without pain")
            recommendationText = "Applying a gradual progression for better cardio stimulus."
        } else {
            zone = .green
            decision = .keep
            reasons.append("Current load appears suitable")
            recommendationText = "Keep current plan and monitor next check-ins."
        }

        if let trend = restingHeartRateTrend(snapshot: latestHealthSnapshot) {
            reasons.append(trend)
        }

        let score = scoreForZone(zone, checkIn: checkIn)
        let assessment = SuitabilityAssessment(
            zone: zone,
            score: score,
            reasons: reasons,
            decision: decision,
            recommendationText: recommendationText
        )

        let updated = apply(decision: decision, currentPlan: currentPlan, alternatives: alternatives)
        return PlanAdjustmentResult(assessment: assessment, updatedPlan: updated)
    }

    private func isRedTrigger(_ checkIn: SessionCheckIn) -> Bool {
        if checkIn.painLevel == .moderatePain || checkIn.painLevel == .strongPain {
            return true
        }

        if checkIn.activityDifficulty == .tooExhausting {
            return true
        }

        return checkIn.discomfortAreas.contains(.breathing)
    }

    private func overfatigueCount(in recent: [SessionCheckIn], including current: SessionCheckIn) -> Int {
        let pool = Array(([current] + recent).prefix(4))
        return pool.filter {
            $0.fatigueLevel == .veryTired ||
            $0.fatigueLevel == .completelyExhausted ||
            $0.activityDifficulty == .veryHard ||
            $0.activityDifficulty == .tooExhausting
        }.count
    }

    private func easySessionCount(in recent: [SessionCheckIn], including current: SessionCheckIn) -> Int {
        let pool = Array(([current] + recent).prefix(5))
        return pool.filter {
            ($0.activityDifficulty == .veryEasy || $0.activityDifficulty == .easy) &&
            $0.painLevel == .noPain
        }.count
    }

    private func scoreForZone(_ zone: SuitabilityZone, checkIn: SessionCheckIn) -> Double {
        var score: Double
        switch zone {
        case .green:
            score = 82
        case .yellow:
            score = 58
        case .red:
            score = 30
        }

        if checkIn.painLevel == .mildDiscomfort {
            score -= 8
        }

        return max(0, min(100, score))
    }

    private func restingHeartRateTrend(snapshot: HealthSnapshot?) -> String? {
        guard let snapshot else { return nil }
        guard let resting = snapshot.restingHeartRate else { return nil }

        if resting >= 80 {
            return "Current resting HR suggests staying in lower-impact training zone."
        }

        if resting <= 60 {
            return "Resting HR is relatively low; plan can progress cautiously."
        }

        return nil
    }

    private func apply(decision: ProgressionDecision, currentPlan: WeeklyPlan, alternatives: [SportRecommendation]) -> WeeklyPlan {
        var plan = currentPlan

        switch decision {
        case .keep:
            return plan

        case .keepAdjusted, .offerSwitch, .offerSwitchNow, .deloadNextSession:
            return plan

        case .downgradeIntensity:
            plan.sessions = plan.sessions.map { session in
                let newMax = max(3, session.targetRPE.max - 1)
                let newMin = min(session.targetRPE.min, newMax)
                let newDuration = max(10, Int(Double(session.plannedDurationMinutes) * 0.9))
                return SessionPlan(
                    id: session.id,
                    sessionNumber: session.sessionNumber,
                    activity: session.activity,
                    scheduledDay: session.scheduledDay,
                    preferredTime: session.preferredTime,
                    plannedDurationMinutes: newDuration,
                    targetRPE: RPERange(min: newMin, max: newMax),
                    completedAt: session.completedAt
                )
            }
            return plan

        case .reduceVolume:
            var sessions = plan.sessions
            if sessions.count > 1 {
                sessions.removeLast()
            }
            sessions = sessions.map { session in
                let newDuration = max(10, Int(Double(session.plannedDurationMinutes) * 0.85))
                return SessionPlan(
                    id: session.id,
                    sessionNumber: session.sessionNumber,
                    activity: session.activity,
                    scheduledDay: session.scheduledDay,
                    preferredTime: session.preferredTime,
                    plannedDurationMinutes: newDuration,
                    targetRPE: session.targetRPE,
                    completedAt: session.completedAt
                )
            }
            plan.sessions = sessions
            return plan

        case .switchAlternative:
            guard let next = alternatives.first else {
                return apply(decision: .downgradeIntensity, currentPlan: plan, alternatives: [])
            }

            plan.primaryRecommendation = next
            plan.alternatives = Array(alternatives.dropFirst())
            plan.sessions = plan.sessions.map { session in
                SessionPlan(
                    id: session.id,
                    sessionNumber: session.sessionNumber,
                    activity: next.activity,
                    scheduledDay: session.scheduledDay,
                    preferredTime: session.preferredTime,
                    plannedDurationMinutes: next.plannedDurationMinutes,
                    targetRPE: next.targetRPE,
                    completedAt: session.completedAt
                )
            }
            return plan

        case .progress:
            plan.sessions = plan.sessions.map { session in
                let newDuration = min(60, Int(Double(session.plannedDurationMinutes) * 1.1))
                let newMax = min(6, session.targetRPE.max + 1)
                let newMin = min(session.targetRPE.min + 1, newMax)
                return SessionPlan(
                    id: session.id,
                    sessionNumber: session.sessionNumber,
                    activity: session.activity,
                    scheduledDay: session.scheduledDay,
                    preferredTime: session.preferredTime,
                    plannedDurationMinutes: newDuration,
                    targetRPE: RPERange(min: newMin, max: newMax),
                    completedAt: session.completedAt
                )
            }
            return plan
        }
    }
}
