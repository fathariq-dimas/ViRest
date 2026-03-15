//
//  CheckInSheetView.swift
//  ViRest
//
//  Created by Joshua Valentine Manik on 13/03/26.
//

import SwiftUI

struct CheckInSheetView: View {
    @ObservedObject var viewModel: CheckInSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sheetHeight: CGFloat = 470
    @State private var showSwitchSelectionSheet = false
    @State private var activeFeedbackField: FeedbackSelectionField?

    var body: some View {
        ZStack {
            AppBottomSheetStyle.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppBottomSheetStyle.contentSpacing) {
                    AppBottomSheetHandle()

                    switch viewModel.state {
                    case .form:
                        formContent
                    case .result:
                        resultContent
                    }
                }
                .padding(.horizontal, AppBottomSheetStyle.horizontalPadding)
                .padding(.bottom, AppBottomSheetStyle.bottomPadding)
                .onIntrinsicHeightChange { contentHeight in
                    let screenHeight = UIScreen.main.bounds.height
                    let minHeight: CGFloat = viewModel.state == .form
                        ? max(500, screenHeight * 0.80)
                        : max(360, screenHeight * 0.55)
                    let maxFraction: CGFloat = viewModel.state == .form ? 0.96 : 0.82
                    sheetHeight = SheetSizing.fittedHeight(
                        from: contentHeight,
                        minHeight: minHeight,
                        maxFraction: maxFraction,
                        extra: 12
                    )
                }
            }
        }
        .presentationDetents(viewModel.state == .form ? [.large] : [.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showSwitchSelectionSheet) {
            FeedbackSwitchSelectionSheet(
                viewModel: viewModel,
                onCancel: {
                    showSwitchSelectionSheet = false
                },
                onConfirm: { sportId, reason in
                    viewModel.switchSport(to: sportId, reason: reason)
                    showSwitchSelectionSheet = false
                }
            )
        }
        .sheet(item: $activeFeedbackField) { field in
            FeedbackOptionSelectionSheet(
                title: field.title,
                options: feedbackOptions(for: field),
                selectedOptionID: selectedOptionID(for: field),
                onSelect: { optionID in
                    applySelection(optionID: optionID, for: field)
                }
            )
        }
    }

    // ─── FORM ───────────────────────────────────────
    private var formContent: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppPalette.accent)
                Text("How did it go?")
                    .font(AppTypography.title(24))
                    .foregroundStyle(.white)
                Text("Your feedback helps us fine-tune your plan.")
                    .font(AppTypography.body(14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            // Difficulty
            questionCard(title: "How difficult was it?", icon: "flame") {
                AnyView(
                    feedbackSelectionRow(value: viewModel.difficulty.displayName) {
                        activeFeedbackField = .difficulty
                    }
                )
            }

            // Fatigue
            questionCard(title: "How tired do you feel?", icon: "battery.25") {
                AnyView(
                    feedbackSelectionRow(value: viewModel.fatigue.displayName) {
                        activeFeedbackField = .fatigue
                    }
                )
            }

            // Pain
            questionCard(title: "Any pain during activity?", icon: "cross.circle") {
                AnyView(
                    feedbackSelectionRow(value: viewModel.painLevel.displayName) {
                        activeFeedbackField = .pain
                    }
                )
            }

            // Discomfort areas (conditional)
            if viewModel.painLevel != .noPain {
                questionCard(title: "Where did you feel discomfort?", icon: "figure.stand") {
                    AnyView(
                        FlowLayout(spacing: 8) {
                            ForEach(DiscomfortArea.allCases) { area in
                                chipToggle(
                                    label: area.displayName,
                                    selected: viewModel.discomfortAreas.contains(area)
                                ) {
                                    if viewModel.discomfortAreas.contains(area) {
                                        viewModel.discomfortAreas.remove(area)
                                    } else {
                                        viewModel.discomfortAreas.insert(area)
                                    }
                                }
                            }
                        }
                    )
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(AppTypography.caption(13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.submit()
            } label: {
                
                HStack {
                    Text(viewModel.isLoading ? "Saving..." : "Submit Check-In")
                        .font(AppTypography.body(15).bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppPalette.accent)
                        .clipShape(Capsule())
                    
                    if viewModel.isLoading {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    }
                }
            }
            .disabled(viewModel.isLoading)
        }
        .animation(.none, value: viewModel.difficulty)
        .animation(.none, value: viewModel.fatigue)
        .animation(.none, value: viewModel.painLevel)
    }

    private var resultContent: some View {
        VStack(spacing: 20) {
            // Zone indicator
            if let assessment = viewModel.assessment {
                VStack(spacing: 10) {
                    Image(systemName: zoneIcon(assessment.zone))
                        .font(.system(size: 48))
                        .foregroundStyle(zoneColor(assessment.zone))

                    Text(zoneName(assessment.zone))
                        .font(AppTypography.hero(28))
                        .foregroundStyle(zoneColor(assessment.zone))

                    Text(assessment.recommendationText)
                        .font(AppTypography.body(15))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(assessment.reasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.top, 2)
                                Text(reason)
                                    .font(AppTypography.caption(13))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // New title earned
            if let title = viewModel.newTitleName {
                resultBadgeCard(
                    icon: "crown.fill",
                    color: .yellow,
                    title: "Title Earned",
                    subtitle: title
                )
            }

            // Appreciation message
            if let appreciation = viewModel.appreciationText {
                resultBadgeCard(
                    icon: "hands.clap.fill",
                    color: AppPalette.accent,
                    title: "Great work!",
                    subtitle: appreciation
                )
            }

            // New badges
            if !viewModel.newBadges.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("New Badges", systemImage: "rosette")
                        .font(AppTypography.title(18))
                        .foregroundStyle(.white)

                    ForEach(viewModel.newBadges) { badge in
                        resultBadgeCard(
                            icon: "star.fill",
                            color: .orange,
                            title: badge.type.title,
                            subtitle: badge.type.title
                        )
                    }
                }
            }

            if viewModel.shouldOfferSwitch {
                VStack(spacing: 10) {
                    Button {
                        viewModel.prepareSwitchOptions()
                        showSwitchSelectionSheet = true
                    } label: {
                        HStack {
                            if viewModel.isApplyingDecision || viewModel.isLoadingSwitchOptions {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            }
                            Text("Choose New Sport")
                                .font(AppTypography.body(15).bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .frame(height: 52)
                    .disabled(
                        viewModel.isApplyingDecision
                        || viewModel.isLoadingSwitchOptions
                        || !viewModel.hasAlternativeSwitchOption
                    )

                    Button {
                        viewModel.continueCurrentSport()
                    } label: {
                        Text("Continue Current")
                            .font(AppTypography.body(15))
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .frame(height: 52)
                    .disabled(viewModel.isApplyingDecision)
                }
            }

            if let decisionMessage = viewModel.decisionMessage {
                Text(decisionMessage)
                    .font(AppTypography.caption(13))
                    .foregroundStyle(AppPalette.accent)
                    .multilineTextAlignment(.center)
            }

            // Done button
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(AppTypography.body(16))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func questionCard(title: String, icon: String, content: () -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(AppTypography.body(14))
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.8))
            content()
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func feedbackSelectionRow(value: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(value)
                    .font(AppTypography.body(15))
                    .foregroundStyle(Color.vibrantGreen)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vibrantGreen)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func feedbackOptions(for field: FeedbackSelectionField) -> [FeedbackOptionItem] {
        switch field {
        case .difficulty:
            return ActivityDifficulty.allCases.map { FeedbackOptionItem(id: $0.rawValue, title: $0.displayName) }
        case .fatigue:
            return FatigueLevel.allCases.map { FeedbackOptionItem(id: $0.rawValue, title: $0.displayName) }
        case .pain:
            return PainLevel.allCases.map { FeedbackOptionItem(id: $0.rawValue, title: $0.displayName) }
        }
    }

    private func selectedOptionID(for field: FeedbackSelectionField) -> String {
        switch field {
        case .difficulty:
            return viewModel.difficulty.rawValue
        case .fatigue:
            return viewModel.fatigue.rawValue
        case .pain:
            return viewModel.painLevel.rawValue
        }
    }

    private func applySelection(optionID: String, for field: FeedbackSelectionField) {
        switch field {
        case .difficulty:
            if let value = ActivityDifficulty(rawValue: optionID) {
                viewModel.difficulty = value
            }
        case .fatigue:
            if let value = FatigueLevel(rawValue: optionID) {
                viewModel.fatigue = value
            }
        case .pain:
            if let value = PainLevel(rawValue: optionID) {
                viewModel.painLevel = value
            }
        }
    }

    private func chipToggle(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppTypography.caption(13))
                .foregroundStyle(Color.vibrantGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.vibrantGreen.opacity(0.2) : Color.white.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(selected ? Color.vibrantGreen.opacity(0.95) : Color.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
    }

    private func resultBadgeCard(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.body(14))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(AppTypography.caption(13))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func zoneIcon(_ zone: SuitabilityZone) -> String {
        switch zone {
        case .green:  return "checkmark.seal.fill"
        case .yellow: return "exclamationmark.triangle.fill"
        case .red:    return "xmark.octagon.fill"
        }
    }

    private func zoneColor(_ zone: SuitabilityZone) -> Color {
        switch zone {
        case .green:  return .vibrantGreen
        case .yellow: return .yellow
        case .red:    return .red
        }
    }

    private func zoneName(_ zone: SuitabilityZone) -> String {
        switch zone {
        case .green:  return "Green Zone"
        case .yellow: return "Yellow Zone"
        case .red:    return "Red Zone"
        }
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        let maxWidth = proposal.width ?? 0
        for subview in subviews {
            let width = subview.sizeThatFits(.unspecified).width
            if x + width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(subview)
            x += width + spacing
        }
        return rows
    }
}

private enum FeedbackSelectionField: String, Identifiable {
    case difficulty
    case fatigue
    case pain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .difficulty: return "How difficult was it?"
        case .fatigue: return "How tired do you feel?"
        case .pain: return "Any pain during activity?"
        }
    }
}

private struct FeedbackOptionItem: Identifiable {
    let id: String
    let title: String
}

private struct FeedbackOptionSelectionSheet: View {
    let title: String
    let options: [FeedbackOptionItem]
    let selectedOptionID: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sheetHeight: CGFloat = 340

    var body: some View {
        ZStack {
            AppBottomSheetStyle.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppBottomSheetStyle.contentSpacing) {
                    AppBottomSheetHandle()

                    Text(title)
                        .font(AppTypography.title(20))
                        .foregroundStyle(.white)

                    VStack(spacing: 10) {
                        ForEach(options) { option in
                            let isSelected = option.id == selectedOptionID

                            Button {
                                onSelect(option.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? AppPalette.accent : AppPalette.textSecondary)

                                    Text(option.title)
                                        .font(AppTypography.body(15))
                                        .foregroundStyle(isSelected ? Color.vibrantGreen : .white)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isSelected ? AppPalette.accent.opacity(0.85) : Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, AppBottomSheetStyle.horizontalPadding)
                .padding(.bottom, AppBottomSheetStyle.bottomPadding)
                .onIntrinsicHeightChange { contentHeight in
                    sheetHeight = SheetSizing.fittedHeight(
                        from: contentHeight,
                        minHeight: 320,
                        maxFraction: 0.72,
                        extra: 12
                    )
                }
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
    }
}

private struct FeedbackSwitchSelectionSheet: View {
    @ObservedObject var viewModel: CheckInSheetViewModel
    let onCancel: () -> Void
    let onConfirm: (_ sportId: String, _ reason: SwitchReason) -> Void

    @State private var selectedSportId: String?
    @State private var selectedReason: SwitchReason = .notSuitable
    @State private var sheetHeight: CGFloat = 420

    private var canConfirm: Bool {
        guard let selectedSportId else { return false }
        guard selectedSportId != viewModel.activeSwitchSportId else { return false }
        return !viewModel.isApplyingDecision
    }

    var body: some View {
        ZStack {
            AppBottomSheetStyle.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppBottomSheetStyle.contentSpacing) {
                    AppBottomSheetHandle()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Switch Sport")
                            .font(AppTypography.title(22))
                            .foregroundStyle(.white)

                        Text("This activity looks less suitable. Choose another sport from your current recommendations.")
                            .font(AppTypography.body(14))
                            .foregroundStyle(AppPalette.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose Sport")
                            .font(AppTypography.caption(12))
                            .foregroundStyle(AppPalette.textSecondary)

                        if viewModel.isLoadingSwitchOptions && viewModel.switchOptions.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Loading available sports...")
                                    .font(AppTypography.body(14))
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            ForEach(viewModel.switchOptions) { option in
                                let isCurrent = option.id == viewModel.activeSwitchSportId
                                let isSelected = option.id == selectedSportId

                                Button {
                                    guard !isCurrent else { return }
                                    selectedSportId = option.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isCurrent ? "lock.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                                            .foregroundStyle(isCurrent ? AppPalette.textSecondary : (isSelected ? AppPalette.accent : AppPalette.textSecondary))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.displayName)
                                                .font(AppTypography.body(14))
                                                .foregroundStyle(.white)
                                            Text("\(option.durationMinutes) min/session · \(option.weeklyTargetCount)x/week")
                                                .font(AppTypography.caption(12))
                                                .foregroundStyle(AppPalette.textSecondary)
                                        }

                                        Spacer()

                                        if isCurrent {
                                            Text("Current")
                                                .font(AppTypography.caption(11))
                                                .foregroundStyle(AppPalette.textSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSelected && !isCurrent ? AppPalette.accent.opacity(0.85) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isCurrent)
                                .opacity(isCurrent ? 0.55 : 1)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reason")
                            .font(AppTypography.caption(12))
                            .foregroundStyle(AppPalette.textSecondary)

                        ForEach(SwitchReason.allCases) { reason in
                            let isSelected = selectedReason == reason
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? AppPalette.accent : AppPalette.textSecondary)
                                    Text(reason.displayName)
                                        .font(AppTypography.body(14))
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button("Confirm Switch") {
                            guard let selectedSportId else { return }
                            onConfirm(selectedSportId, selectedReason)
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(!canConfirm)
                        .opacity(canConfirm ? 1 : 0.6)
                    }
                }
                .padding(.horizontal, AppBottomSheetStyle.horizontalPadding)
                .padding(.bottom, AppBottomSheetStyle.bottomPadding)
                .onIntrinsicHeightChange { contentHeight in
                    sheetHeight = SheetSizing.fittedHeight(
                        from: contentHeight,
                        minHeight: 360,
                        maxFraction: 0.78,
                        extra: 12
                    )
                }
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            if selectedSportId == nil || selectedSportId == viewModel.activeSwitchSportId {
                selectedSportId = viewModel.switchOptions.first(where: { $0.id != viewModel.activeSwitchSportId })?.id
            }
        }
        .onReceive(viewModel.$switchOptions) { options in
            if selectedSportId == nil || selectedSportId == viewModel.activeSwitchSportId {
                selectedSportId = options.first(where: { $0.id != viewModel.activeSwitchSportId })?.id
            }
        }
    }
}
