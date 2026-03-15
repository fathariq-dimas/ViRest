import SwiftUI

struct HomeView: View {
    private typealias RestingHRRange = RestingHeartRateTrendRange

    private struct RestingHRSample: Identifiable {
        let id: Int
        let bpm: Double?
        let shortLabel: String
        let fullLabel: String
        let date: Date
    }

    private struct YAxisTick: Identifiable {
        let id = UUID()
        let value: Int
        let normalizedY: Double
    }

    @ObservedObject private var viewModel: HomeViewModel
    @State private var checkInSheetVM: CheckInSheetViewModel?
    @State private var pendingConfirmSport: FirestoreSportEntry?
    @State private var selectedRestingHRRange: RestingHRRange = .day
    @State private var isRestingHRCardExpanded = false
    private let restingHRChartHeight: CGFloat = 180

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    restingHREvaluationCard

                    VStack(alignment: .leading) {
                        Text("Sport Recommendations")
                            .font(AppTypography.hero(24))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text("Only your selected sport is active. Change active sport from Profile settings.")
                            .font(AppTypography.caption(12))
                            .foregroundStyle(AppPalette.textSecondary)

                        if viewModel.isLoading {
                            ProgressView().tint(.white).padding(.top, 40)
                        } else if viewModel.sports.isEmpty {
                            emptyCard
                        } else {
                            VStack(spacing: 16) {
                                ForEach(viewModel.sports) { sport in
                                    let isLocked = viewModel.isSportLocked(sport)
                                    SportCheckInCard(sport: sport, isLocked: isLocked) {
                                        guard !isLocked else { return }
                                        pendingConfirmSport = sport
                                    }
                                }
                            }
                        }
                    }

                    if let msg = viewModel.checkInSuccess {
                        successBanner(msg)
                    }
                }
                .padding(16)
                .padding(.bottom, 22)
            }
            .background(.richBlack)
            .navigationTitle("Virest")
            .toolbarTitleDisplayMode(.inline)
            .task { viewModel.load() }
            .overlay {
                if let pendingSport = pendingConfirmSport {
                    ZStack {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture {
                                pendingConfirmSport = nil
                            }

                        activityConfirmationPopup(for: pendingSport)
                    }
                }
            }
            .sheet(item: $checkInSheetVM) { vm in
                CheckInSheetView(viewModel: vm)
            }
            .onReceive(NotificationCenter.default.publisher(for: .widgetCheckInRequested)) { _ in
                handleWidgetCheckInRequest()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var restingHRSamples: [RestingHRSample] {
        let buckets = viewModel.restingHeartRateTrendBuckets(for: selectedRestingHRRange)
        guard !buckets.isEmpty else {
            return fallbackRestingHRSamples(for: selectedRestingHRRange)
        }

        return buckets.enumerated().map { index, bucket in
            let labels = labelsForSample(
                at: index,
                total: buckets.count,
                date: bucket.bucketStart,
                range: selectedRestingHRRange
            )

            return RestingHRSample(
                id: index,
                bpm: bucket.averageBPM,
                shortLabel: labels.short,
                fullLabel: labels.full,
                date: bucket.bucketStart
            )
        }
    }

    private var availableBPMValues: [Double] {
        restingHRSamples.compactMap(\.bpm)
    }

    private var latestAvailableBPM: Int? {
        restingHRSamples
            .compactMap(\.bpm)
            .last
            .map { Int($0.rounded()) }
    }

    private var selectedRangeAverageBPM: Int {
        guard !availableBPMValues.isEmpty else { return viewModel.currentRestingHRValue ?? 0 }
        let sum = availableBPMValues.reduce(0, +)
        return Int((sum / Double(availableBPMValues.count)).rounded())
    }

    private var displayedRestingHRValue: Int {
        switch selectedRestingHRRange {
        case .day:
            return latestAvailableBPM ?? viewModel.currentRestingHRValue ?? 0
        case .week, .month:
            return selectedRangeAverageBPM
        }
    }

    private var restingHRMetricTitle: String {
        switch selectedRestingHRRange {
        case .day:
            return "TODAY RHR"
        case .week, .month:
            return "AVERAGE RHR"
        }
    }

    private var selectedRangeDateText: String {
        guard let start = restingHRSamples.first?.date,
              let end = restingHRSamples.last?.date else {
            return Date().formatted(date: .abbreviated, time: .omitted)
        }

        switch selectedRestingHRRange {
        case .day:
            return end.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "\(formattedDayMonth(start)) – \(formattedDayMonthYear(end))"
        case .month:
            return "\(formattedDayMonth(start)) – \(formattedDayMonthYear(end))"
        }
    }

    private var yAxisTicks: [YAxisTick] {
        guard !availableBPMValues.isEmpty else {
            return [
                YAxisTick(value: 80, normalizedY: 0),
                YAxisTick(value: 70, normalizedY: 0.5),
                YAxisTick(value: 60, normalizedY: 1)
            ]
        }

        let minValue = availableBPMValues.min() ?? 60
        let maxValue = availableBPMValues.max() ?? 80

        var minTick = Int(floor((minValue - 2) / 5) * 5)
        var maxTick = Int(ceil((maxValue + 2) / 5) * 5)

        if maxTick - minTick < 10 {
            maxTick += 5
            minTick -= 5
        }

        let midRaw = (maxTick + minTick) / 2
        let midTick = Int((Double(midRaw) / 5.0).rounded() * 5)

        let span = Double(max(maxTick - minTick, 1))

        return [
            YAxisTick(value: maxTick, normalizedY: 0),
            YAxisTick(value: midTick, normalizedY: (Double(maxTick - midTick) / span)),
            YAxisTick(value: minTick, normalizedY: 1)
        ]
    }

    private var yAxisMinValue: Double {
        Double(yAxisTicks.last?.value ?? 60)
    }

    private var yAxisMaxValue: Double {
        Double(yAxisTicks.first?.value ?? 80)
    }

    private var restingHREvaluationCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                restingHRSegmentedControl

                VStack(alignment: .leading, spacing: 12) {
                    Text(restingHRMetricTitle)
                        .font(AppTypography.caption(13))
                        .foregroundStyle(AppPalette.textSecondary.opacity(0.95))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(displayedRestingHRValue)")
                            .font(AppTypography.hero(36))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text("BPM")
                            .font(AppTypography.title(38))
                            .foregroundStyle(AppPalette.textSecondary)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text(selectedRangeDateText)
                            .font(AppTypography.title(18))
                            .foregroundStyle(AppPalette.textSecondary)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.textSecondary)
                            .rotationEffect(.degrees(isRestingHRCardExpanded ? 180 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isRestingHRCardExpanded)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleRestingHRCardExpansion()
                }

                if isRestingHRCardExpanded {
                    VStack(spacing: 12) {
                        HStack(alignment: .bottom, spacing: 8) {
                            restingHRChart(samples: restingHRSamples)
                                .frame(height: restingHRChartHeight)

                            yAxisLabelColumn(height: restingHRChartHeight)
                        }

                        restingHRAxisLabels(samples: restingHRSamples)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func toggleRestingHRCardExpansion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRestingHRCardExpanded.toggle()
        }
    }

    private var restingHRSegmentedControl: some View {
        Picker("Resting heart rate range", selection: $selectedRestingHRRange) {
            ForEach(RestingHRRange.allCases) { range in
                Text(range.compactTitle).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private func restingHRAxisLabels(samples: [RestingHRSample]) -> some View {
        HStack(spacing: 0) {
            ForEach(samples) { sample in
                Text(sample.shortLabel)
                    .font(AppTypography.caption(10))
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func restingHRChart(samples: [RestingHRSample]) -> some View {
        GeometryReader { geometry in
            let points = chartPoints(samples: samples, in: geometry.size)

            ZStack {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)

                chartVerticalGrid(sampleCount: samples.count, in: geometry.size)
                chartHorizontalGrid(ticks: yAxisTicks, in: geometry.size)
                chartDots(points: points)
            }
        }
    }

    private func chartPoints(samples: [RestingHRSample], in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let valueRange = max(1, yAxisMaxValue - yAxisMinValue)

        return samples.enumerated().compactMap { index, sample in
            guard let bpm = sample.bpm else { return nil }
            let xProgress = Double(index) / Double(max(samples.count - 1, 1))
            let yProgress = (bpm - yAxisMinValue) / valueRange
            let x = size.width * xProgress
            let y = size.height * (1 - yProgress)
            return CGPoint(x: x, y: y)
        }
    }

    private func chartVerticalGrid(sampleCount: Int, in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<sampleCount, id: \.self) { index in
                let xProgress = Double(index) / Double(max(sampleCount - 1, 1))
                let x = size.width * xProgress
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                .stroke(
                    Color.white.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
        }
    }

    private func chartHorizontalGrid(ticks: [YAxisTick], in size: CGSize) -> some View {
        ZStack {
            ForEach(ticks) { tick in
                let y = size.height * tick.normalizedY
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func chartDots(points: [CGPoint]) -> some View {
        ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.richBlack)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(AppPalette.accent, lineWidth: 2)
                    )
                    .position(point)
            }
        }
    }

    private func yAxisLabelColumn(height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(yAxisTicks) { tick in
                    Text("\(tick.value)")
                        .font(AppTypography.caption(11))
                        .foregroundStyle(AppPalette.textSecondary.opacity(0.9))
                        .position(
                            x: 14,
                            y: max(8, min(geometry.size.height - 8, geometry.size.height * tick.normalizedY))
                        )
                }
            }
        }
        .frame(width: 28, height: height)
    }

    private func formattedDayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func formattedDayMonthYear(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func fallbackRestingHRSamples(for range: RestingHRRange) -> [RestingHRSample] {
        let calendar = Calendar.current
        let now = Date()
        let fallbackBPM = Double(viewModel.currentRestingHRValue ?? 68)

        switch range {
        case .day:
            let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let firstHour = calendar.date(byAdding: .hour, value: -23, to: currentHourStart) ?? currentHourStart
            return (0..<24).compactMap { index in
                guard let date = calendar.date(byAdding: .hour, value: index, to: firstHour) else { return nil }
                let labels = labelsForSample(at: index, total: 24, date: date, range: range)
                return RestingHRSample(id: index, bpm: fallbackBPM, shortLabel: labels.short, fullLabel: labels.full, date: date)
            }

        case .week:
            let todayStart = calendar.startOfDay(for: now)
            let firstDay = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return (0..<7).compactMap { index in
                guard let date = calendar.date(byAdding: .day, value: index, to: firstDay) else { return nil }
                let labels = labelsForSample(at: index, total: 7, date: date, range: range)
                return RestingHRSample(id: index, bpm: fallbackBPM, shortLabel: labels.short, fullLabel: labels.full, date: date)
            }

        case .month:
            let firstWeek = calendar.date(byAdding: .weekOfYear, value: -3, to: now.startOfWeek()) ?? now.startOfWeek()
            return (0..<4).compactMap { index in
                guard let date = calendar.date(byAdding: .weekOfYear, value: index, to: firstWeek) else { return nil }
                let labels = labelsForSample(at: index, total: 4, date: date, range: range)
                return RestingHRSample(id: index, bpm: fallbackBPM, shortLabel: labels.short, fullLabel: labels.full, date: date)
            }
        }
    }

    private func labelsForSample(
        at index: Int,
        total: Int,
        date: Date,
        range: RestingHRRange
    ) -> (short: String, full: String) {
        let calendar = Calendar.current

        switch range {
        case .day:
            let hour = calendar.component(.hour, from: date)
            let short = (hour % 6 == 0 || index == total - 1) ? String(format: "%02d", hour) : ""
            let full = date.formatted(date: .omitted, time: .shortened)
            return (short, full)

        case .week:
            let short = date.formatted(.dateTime.weekday(.abbreviated))
            let full = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return (short, full)

        case .month:
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: date) ?? date
            let short = "W\(index + 1)"
            let full = "\(date.formatted(.dateTime.day().month(.abbreviated))) - \(weekEnd.formatted(.dateTime.day().month(.abbreviated)))"
            return (short, full)
        }
    }

    private func activityConfirmationPopup(for sport: FirestoreSportEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Activity")
                .font(AppTypography.title(22))
                .foregroundStyle(.white)

            Text("Have you completed a \(sport.displayName) session?")
                .font(AppTypography.body(15))
                .foregroundStyle(Color.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 16) {
                Button {
                    let vm = viewModel.makeCheckInSheetViewModel(for: sport)
                    checkInSheetVM = vm
                    pendingConfirmSport = nil
                } label: {
                    Text("Yes, I completed this activity")
                        .font(AppTypography.body(15).bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppPalette.accent)
                        .clipShape(Capsule())
                }
                
                Button {
                    pendingConfirmSport = nil
                } label: {
                    Text("Cancel")
                        .font(AppTypography.body(15).bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 360)
        .background(Color.richBlack.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func handleWidgetCheckInRequest() {
        guard !viewModel.isLoading else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                handleWidgetCheckInRequest()
            }
            return
        }

        guard let preferredSport = viewModel.preferredSportForCheckIn() else {
            viewModel.errorMessage = "No active sport available to check in yet."
            return
        }

        pendingConfirmSport = preferredSport
    }

    private var emptyCard: some View {
        SurfaceCard {
            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 36))
                    .foregroundStyle(AppPalette.accent)
                Text("No sports recommended yet")
                    .font(AppTypography.title(20))
                    .foregroundStyle(AppPalette.textPrimary)
                Text("Complete onboarding to get your personalised sport recommendations.")
                    .font(AppTypography.body(14))
                    .foregroundStyle(AppPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func successBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
            Text(msg).font(AppTypography.body(14)).foregroundStyle(.white)
            Spacer()
        }
        .padding(12)
        .background(Color.green.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                viewModel.checkInSuccess = nil
            }
        }
    }
}

@MainActor
private struct HomePreviewHost: View {
    private let container: AppContainer
    private let viewModel: HomeViewModel

    init() {
        let seededContainer = PreviewSupport.makeSeededContainer()
        self.container = seededContainer
        self.viewModel = HomeViewModel(
            firestoreUserRepository: seededContainer.firestoreUserRepository,
            userProfileRepository: seededContainer.userProfileRepository,
            authService: seededContainer.authService,
            healthService: seededContainer.healthService,
            healthDataResolver: seededContainer.healthDataResolver,
            notificationService: seededContainer.notificationService,
            gamificationService: seededContainer.gamificationService,
            badgeRepository: seededContainer.badgeStateRepository,
            suitabilityEvaluator: seededContainer.suitabilityEvaluator,
            sportSwitchOrchestrator: seededContainer.sportSwitchOrchestrator,
            widgetSyncService: seededContainer.widgetSyncService
        )
    }

    var body: some View {
        HomeView(viewModel: viewModel)
    }
}

#Preview("Home") {
    HomePreviewHost()
}
