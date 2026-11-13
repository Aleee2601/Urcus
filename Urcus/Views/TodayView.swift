import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject private var sync: SyncService
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedWorkout.date) private var allWorkouts: [PlannedWorkout]
    @Query(sort: \ActivityRecord.startDate, order: .reverse) private var activities: [ActivityRecord]
    @Query(sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @StateObject private var readiness = ReadinessService()
    @AppStorage("garminKeyExpiry") private var keyExpiry: Double = 0
    @State private var editing: PlannedWorkout?
    @State private var addingNew = false

    private var activePlan: TrainingPlan? { plans.first(where: \.isActive) ?? plans.first }
    private var workouts: [PlannedWorkout] { allWorkouts.filter { $0.plan?.isActive ?? true } }
    private var todays: [PlannedWorkout] { workouts.filter { Cal.ro.isDateInToday($0.date) } }

    private var weekStart: Date { Cal.startOfWeek(.now) }
    private var weekWorkouts: [PlannedWorkout] {
        let end = Cal.addDays(7, to: weekStart)
        return workouts.filter { $0.date >= weekStart && $0.date < end }
    }
    private var weekActivities: [ActivityRecord] { activities.filter { $0.startDate >= weekStart } }

    private var upcoming: [PlannedWorkout] {
        let tomorrow = Cal.addDays(1, to: Cal.ro.startOfDay(for: .now))
        return Array(workouts.filter { $0.date >= tomorrow && !$0.isDone && !$0.skipped }.prefix(Platform.isMac ? 4 : 2))
    }

    private var kicker: String {
        var s = Fmt.day(.now)
        if Platform.isMac, let plan = activePlan {
            s += " · \(plan.name), săpt. \(plan.currentWeekIndex + 1)"
        }
        return s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if Platform.isMac { macLayout } else { phoneLayout }
                }
                .padding(.horizontal, Platform.isMac ? 40 : 20)
                .padding(.top, Platform.isMac ? 36 : 12)
                .padding(.bottom, Platform.isMac ? 48 : 120)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .refreshable { await sync.sync(context: context) }
            .task { await readiness.refresh() }
            .navigationDestination(for: ActivityRecord.self) { ActivityDetailView(activity: $0) }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(item: $editing) { WorkoutEditor(workout: $0, plan: $0.plan) }
            .sheet(isPresented: $addingNew) { WorkoutEditor(workout: nil, plan: activePlan) }
        }
    }

    // MARK: iPhone

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScreenHeader(kicker: kicker, title: "Azi") { SyncCircleButton() }

            errorBanner

            if let workout = todays.first {
                TodayHeroCard(workout: workout, onToggleDone: { toggle(workout) }, onOpen: { editing = workout })
                ForEach(todays.dropFirst()) { extra in
                    Button { editing = extra } label: { PlanDayRow(workout: extra, showDate: false) }
                        .buttonStyle(.plain)
                }
            } else {
                RestDayCard()
            }

            readinessCard

            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Săptămâna asta", trailing: weekRange)
                WeekStrip(days: WeekSummary.days(workouts: workouts, activities: activities))
                weekCard(large: false)
            }

            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Urmează")
                    CardList(items: upcoming) { w in
                        Button { editing = w } label: { UpcomingRow(workout: w) }.buttonStyle(.plain)
                    }
                }
            }

            lastActivity
        }
    }

    // MARK: Mac

    private var macLayout: some View {
        VStack(alignment: .leading, spacing: 28) {
            ScreenHeader(kicker: kicker, title: "Azi", titleSize: 36) {
                HStack(spacing: 10) {
                    Button("Sincronizează") { Task { await sync.sync(context: context) } }
                        .buttonStyle(SecondaryButtonStyle(height: 40))
                        .disabled(sync.isSyncing || !sync.hasKey)
                    Button("Antrenament nou") { addingNew = true }
                        .buttonStyle(PrimaryButtonStyle(height: 40))
                        .disabled(activePlan == nil)
                }
            }

            errorBanner

            readinessCard

            HStack(alignment: .top, spacing: 20) {
                Group {
                    if let workout = todays.first {
                        TodayHeroCard(workout: workout, large: true, onToggleDone: { toggle(workout) }, onOpen: { editing = workout })
                    } else {
                        RestDayCard()
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Săptămâna asta").appFont(16, .heavy).foregroundStyle(Theme.text)
                    weekCard(large: true)
                    if let last = activities.first {
                        NavigationLink(value: last) { LastActivityCard(activity: last, planTitle: planTitle(for: last)) }
                            .buttonStyle(.plain)
                    }
                }
                .frame(width: 340)
            }

            if let plan = activePlan {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Planul săptămânii", trailing: "\(weekRange) · \(plan.weeks[plan.currentWeekIndex].totalsLabel)")
                    MacWeekColumns(start: weekStart, workouts: weekWorkouts) { editing = $0 }
                }
            }
        }
    }

    // MARK: Bucăți comune

    @ViewBuilder
    private var readinessCard: some View {
        if let r = readiness.readiness, r.hasData { ReadinessCard(readiness: r) }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let text = KeyExpiry.message(for: KeyExpiry.status(expiry: keyExpiry)), sync.hasKey {
            Label(text, systemImage: "key.fill")
                .appFont(14, .semibold)
                .foregroundStyle(Theme.peach)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 16, fill: Theme.peach.opacity(0.08), stroke: Theme.peach.opacity(0.3))
        }
        if let error = sync.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .appFont(14, .semibold)
                .foregroundStyle(Theme.peach)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 16, fill: Theme.peach.opacity(0.08), stroke: Theme.peach.opacity(0.3))
        } else if !sync.hasKey {
            HStack(spacing: 12) {
                Image(systemName: "applewatch.radiowaves.left.and.right").foregroundStyle(Theme.sage)
                Text("Adaugă cheia Garmin în Setări ca să-ți aducem istoricul.")
                    .appFont(14, .semibold).foregroundStyle(Theme.text)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 16)
        }
    }

    private func weekCard(large: Bool) -> some View {
        WeekProgressCard(
            done: weekWorkouts.filter(\.isDone).count,
            planned: weekWorkouts.count,
            km: weekActivities.reduce(0) { $0 + $1.distanceKm },
            elevation: weekActivities.reduce(0) { $0 + $1.elevationGain },
            seconds: weekActivities.reduce(0) { $0 + $1.durationSeconds },
            large: large)
    }

    @ViewBuilder
    private var lastActivity: some View {
        if let last = activities.first {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Ultima activitate")
                NavigationLink(value: last) { LastActivityCard(activity: last, planTitle: planTitle(for: last)) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var weekRange: String { "\(Fmt.short(weekStart)) – \(Fmt.short(Cal.addDays(6, to: weekStart)))" }

    private func planTitle(for activity: ActivityRecord) -> String? {
        allWorkouts.first { $0.completedActivityId == activity.garminId }?.title
    }

    private func toggle(_ workout: PlannedWorkout) {
        withAnimation(.snappy) {
            if workout.isDone {
                workout.manuallyDone = false
                if workout.completedActivityId != nil {
                    workout.completedActivityId = nil
                    workout.ignoreAutoMatch = true
                }
            } else {
                workout.manuallyDone = true
            }
        }
        try? context.save()
    }
}

/// Cele 7 zile ale săptămânii, pe coloane (Mac).
struct MacWeekColumns: View {
    let start: Date
    let workouts: [PlannedWorkout]
    var onSelect: (PlannedWorkout) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = Cal.addDays(offset, to: start)
                    let items = workouts.filter { Cal.ro.isDate($0.date, inSameDayAs: day) }
                    VStack(spacing: 8) {
                        if items.isEmpty {
                            MacDayCell(date: day, workout: nil)
                        } else {
                            ForEach(items) { w in
                                Button { onSelect(w) } label: { MacDayCell(date: day, workout: w) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(minWidth: 120, maxWidth: .infinity)
                }
            }
        }
    }
}

struct MacDayCell: View {
    let date: Date
    let workout: PlannedWorkout?
    var showDate = true
    var minHeight: CGFloat = 120

    var body: some View {
        let isToday = Cal.ro.isDateInToday(date)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if showDate {
                    Text(dayLabel).appFont(11, .heavy).foregroundStyle(isToday ? Theme.peach : Theme.muted)
                }
                Spacer(minLength: 4)
                if let workout { statusLabel(workout.status) }
            }
            if let workout {
                Capsule().fill(workout.sport.color).frame(width: 24, height: 4)
                Text(workout.title)
                    .appFont(14, .heavy)
                    .foregroundStyle(workout.status == .skipped ? Theme.muted : Theme.text)
                    .strikethrough(workout.status == .skipped)
                    .fixedSize(horizontal: false, vertical: true)
                if !workout.targetSummary.isEmpty {
                    Text(workout.targetSummary).appFont(12, .semibold).foregroundStyle(Theme.muted).monospacedDigit()
                }
            } else {
                Text("Odihnă").appFont(13, .semibold).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background {
            if workout == nil {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            } else {
                let today = isToday && workout?.status != .done
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(today ? Theme.surface2 : Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(today ? Theme.peach : Theme.line, lineWidth: today ? 1.5 : 1))
            }
        }
        .contentShape(Rectangle())
    }

    private var dayLabel: String {
        date.formatted(.dateTime.weekday(.abbreviated).day().locale(Fmt.locale))
            .uppercased(with: Fmt.locale).replacingOccurrences(of: ".", with: "")
    }

    @ViewBuilder
    private func statusLabel(_ status: WorkoutStatus) -> some View {
        switch status {
        case .done: Text("FĂCUT").appFont(10, .heavy).tracking(0.6).foregroundStyle(Theme.sage)
        case .today: Text("AZI").appFont(10, .heavy).tracking(0.6).foregroundStyle(Theme.peach)
        case .upcoming: Text("URMEAZĂ").appFont(10, .heavy).tracking(0.6).foregroundStyle(Theme.muted)
        case .missed: Text("RATAT").appFont(10, .heavy).tracking(0.6).foregroundStyle(Theme.coral)
        case .skipped: Text("SĂRIT").appFont(10, .heavy).tracking(0.6).foregroundStyle(Theme.muted)
        }
    }
}
