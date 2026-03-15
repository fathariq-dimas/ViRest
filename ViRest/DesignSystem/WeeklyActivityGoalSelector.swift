import SwiftUI

struct WeeklyActivityGoalSelector: View {
    @Binding var goal: WeeklyGoalFrequency

    @State private var draftGoal: WeeklyGoalFrequency
    @State private var showFrequencyPicker = false
    @State private var frequencySheetHeight: CGFloat = 340

    init(goal: Binding<WeeklyGoalFrequency>) {
        _goal = goal
        _draftGoal = State(initialValue: goal.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TIME FRAME")
                    .font(AppTypography.title(30).smallCaps())
                    .tracking(1.8)
                    .foregroundStyle(AppPalette.textPrimary)

                Text("Set your goal timeframe for better progress tracking.")
                    .font(AppTypography.body(15))
                    .foregroundStyle(AppPalette.textSecondary)

                staticOption(title: "Per Week", selected: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("GOAL TYPE")
                    .font(AppTypography.title(30).smallCaps())
                    .tracking(1.8)
                    .foregroundStyle(AppPalette.textPrimary)

                Text("Use activity-based goals to stay consistent each week.")
                    .font(AppTypography.body(15))
                    .foregroundStyle(AppPalette.textSecondary)

                staticOption(title: "Activity", selected: true)

                Button {
                    draftGoal = goal
                    showFrequencyPicker = true
                } label: {
                    HStack {
                        Text("Frequency")
                            .font(AppTypography.body(16))
                            .foregroundStyle(AppPalette.textSecondary)

                        Spacer()

                        Text(goal.displayName)
                            .font(AppTypography.title(18))
                            .foregroundStyle(AppPalette.textPrimary)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showFrequencyPicker) {
            frequencyPickerSheet
                .onIntrinsicHeightChange { contentHeight in
                    frequencySheetHeight = SheetSizing.fittedHeight(
                        from: contentHeight,
                        minHeight: 300,
                        maxFraction: 0.58,
                        extra: 12
                    )
                }
                .presentationDetents([.height(frequencySheetHeight)])
                .presentationDragIndicator(.hidden)
        }
    }

    private func staticOption(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.title(16))
                .foregroundStyle(selected ? AppPalette.textPrimary : AppPalette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.white.opacity(0.78) : Color.white.opacity(0.15), lineWidth: selected ? 1.8 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(selected ? 1 : 0.75)
    }

    private var frequencyPickerSheet: some View {
        ZStack {
            AppBottomSheetStyle.backgroundColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppBottomSheetStyle.contentSpacing) {
                    AppBottomSheetHandle()

                    HStack {
                        Button("Cancel") {
                            showFrequencyPicker = false
                        }
                        .font(AppTypography.caption(14))
                        .foregroundStyle(AppPalette.textSecondary)

                        Spacer()

                        Button("Done") {
                            goal = draftGoal
                            showFrequencyPicker = false
                        }
                        .font(AppTypography.caption(14))
                        .foregroundStyle(AppPalette.accent)
                    }

                    Divider().overlay(Color.white.opacity(0.12))

                    Picker("Frequency", selection: $draftGoal) {
                        ForEach(WeeklyGoalFrequency.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                }
                .padding(.horizontal, AppBottomSheetStyle.horizontalPadding)
                .padding(.bottom, AppBottomSheetStyle.bottomPadding)
            }
        }
    }
}
