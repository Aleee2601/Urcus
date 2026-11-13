import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @State private var showGenerator = false
    @State private var editing: PlannedWorkout?
    @State private var addingNew = false
    @State private var confirmDelete = false
    @State private var selectedWeek: Int?

    private var activePlan: TrainingPlan? { plans.first(where: \.isActive) ?? plans.first }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = activePlan {
                    if Platform.isMac { MacPlanLayout(plan: plan, menu: { planMenu }, onAdd: { addingNew = true }, onEdit: { editing = $0 }) }
                    else { phoneLayout(plan) }
                } else {
                    emptyState
                }
            }
            .screenBackground()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showGenerator) { PlanGeneratorView() }
            .sheet(item: $editing) { WorkoutEditor(workout: $0, plan: $0.plan) }
            .sheet(isPresented: $addingNew) { WorkoutEditor(workout: nil, plan: activePlan) }
            .confirmationDialog("Ștergi planul „\(activePlan?.name ?? "")”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Șterge planul și antrenamentele", role: .destructive) {
                    if let plan = activePlan { context.delete(plan); try? context.save() }
                }
            } message: {
                Text("Activitățile din Garmin rămân neatinse.")
            }
        }
    }

    // MARK: Meniu comun

    @ViewBuilder
    private var planMenu: some View {
        Button("Antrenament nou", systemImage: "plus") { addingNew = true }
            .disabled(activePlan == nil)
        Button("Plan nou…", systemImage: "wand.and.stars") { showGenerator = true }
        if plans.count > 1 {
            Section("Planurile mele") {
                ForEach(plans) { plan in
                    Button {
                        for p in plans { p.isActive = (p == plan) }
                        try? context.save()
                    } label: {
                        if plan.isActive { Label(plan.name, systemImage: "checkmark") } else { Text(plan.name) }
                    }
                }
            }
        }
        if activePlan != nil {
            Divider()
            Button("Șterge planul", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
    }

    // MARK: Gol

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.peach)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Theme.peach.opacity(0.12)))
            Text("Niciun plan încă").appFont(24, .heavy).foregroundStyle(Theme.text)
            Text("Creează un plan progresiv până la cursa ta. Activitățile din Garmin îl bifează automat.")
                .appFont(15).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 340)
            Button("Creează un plan") { showGenerator = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: iPhone

    private func phoneLayout(_ plan: TrainingPlan) -> some View {
        let weeks = plan.weeks
        let current = selectedWeek ?? plan.currentWeekIndex
        let week = weeks[min(max(0, current), weeks.count - 1)]

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(kicker: plan.goal, title: plan.name) {
                    Menu { planMenu } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.onPeach)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.peach))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Opțiuni plan")
                }

                PlanSummaryCard(plan: plan)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(weeks) { w in
                                FilterChip(label: w.shortLabel, isOn: w.index == week.index, height: 40) {
                                    withAnimation(.snappy) { selectedWeek = w.index }
                                }
                                .id(w.index)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(week.index, anchor: .center) }
                }

                SectionHeading(title: longRange(week), trailing: week.totalsLabel)

                VStack(spacing: 10) {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = Cal.addDays(offset, to: week.start)
                        let items = week.workouts.filter { Cal.ro.isDate($0.date, inSameDayAs: day) }
                        if items.isEmpty {
                            RestDayRow(date: day)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, w in
                                Button { editing = w } label: { PlanDayRow(workout: w, showDate: i == 0) }
                                    .buttonStyle(.plain)
                                    .contextMenu { WorkoutContextMenu(workout: w) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    private func longRange(_ week: PlanWeek) -> String {
        let startDay = week.start.formatted(.dateTime.day().locale(Fmt.locale))
        let end = week.end.formatted(.dateTime.day().month(.wide).locale(Fmt.locale))
        return "\(startDay) – \(end)"
    }
}

struct WorkoutContextMenu: View {
    @Environment(\.modelContext) private var context
    let workout: PlannedWorkout

    var body: some View {
        Button(workout.isDone ? "Marchează nefăcut" : "Marchează făcut", systemImage: "checkmark") {
            if workout.isDone {
                workout.manuallyDone = false
                if workout.completedActivityId != nil { workout.completedActivityId = nil; workout.ignoreAutoMatch = true }
            } else {
                workout.manuallyDone = true
            }
            try? context.save()
        }
        Button(workout.skipped ? "Nu mai sar" : "Sar peste", systemImage: "forward") {
            workout.skipped.toggle()
            try? context.save()
        }
        Button("Șterge", systemImage: "trash", role: .destructive) {
            context.delete(workout)
            try? context.save()
        }
    }
}

struct PlanSummaryCard: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                BigStat(label: plan.daysLeft >= 0 ? (plan.hasRace ? "Până la cursă" : "Până la final") : "Plan încheiat",
                        value: "\(max(0, plan.daysLeft))", unit: "zile", size: 44)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Respectat").appFont(12, .semibold).foregroundStyle(Theme.muted)
                    Text(plan.adherencePercent.map { "\($0)%" } ?? "–").appFont(24, .heavy).foregroundStyle(Theme.sage)
                }
            }
            PhaseBar(phases: plan.phases)
        }
        .padding(22)
        .card(radius: Theme.radiusL)
    }
}

// MARK: - Mac

struct MacPlanLayout<MenuContent: View>: View {
    let plan: TrainingPlan
    @ViewBuilder var menu: () -> MenuContent
    var onAdd: () -> Void
    var onEdit: (PlannedWorkout) -> Void

    var body: some View {
        let weeks = plan.weeks
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenHeader(kicker: "\(plan.goal) · \(Fmt.short(plan.startDate)) – \(Fmt.short(plan.endDate))", title: plan.name, titleSize: 36) {
                        HStack(spacing: 10) {
                            Menu { menu() } label: { Text("Planurile mele") }
                                .menuStyle(.button)
                                .buttonStyle(SecondaryButtonStyle(height: 40))
                                .fixedSize()
                            Button("Antrenament nou", action: onAdd)
                                .buttonStyle(PrimaryButtonStyle(height: 40))
                        }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Fazele planului").appFont(16, .heavy).foregroundStyle(Theme.text)
                            PhaseBar(phases: plan.phases)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                        .layoutPriority(1)

                        BigStat(label: plan.hasRace ? "Până la cursă" : "Până la final", value: "\(max(0, plan.daysLeft))", unit: "zile", size: 40)
                            .padding(24)
                            .frame(width: 210, alignment: .leading)
                            .frame(maxHeight: .infinity)
                            .card()
                        BigStat(label: "Respectat", value: plan.adherencePercent.map { "\($0)%" } ?? "–", color: Theme.sage, size: 40)
                            .padding(24)
                            .frame(width: 210, alignment: .leading)
                            .frame(maxHeight: .infinity)
                            .card()
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow {
                            Color.clear.frame(width: 130, height: 1)
                            ForEach(["LUN", "MAR", "MIE", "JOI", "VIN", "SÂM", "DUM"], id: \.self) { d in
                                Text(d).appFont(11, .heavy).tracking(0.8).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        ForEach(weeks) { week in
                            GridRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(week.shortLabel).appFont(13, .heavy).foregroundStyle(week.isCurrent ? Theme.peach : Theme.text)
                                    Text(week.rangeLabel).appFont(11, .semibold).foregroundStyle(Theme.muted)
                                    if !week.totalsLabel.isEmpty {
                                        Text(week.totalsLabel).appFont(11, .semibold).foregroundStyle(Theme.muted).monospacedDigit()
                                    }
                                }
                                .frame(width: 130, alignment: .leading)
                                .padding(.top, 6)

                                ForEach(0..<7, id: \.self) { offset in
                                    let day = Cal.addDays(offset, to: week.start)
                                    let items = week.workouts.filter { Cal.ro.isDate($0.date, inSameDayAs: day) }
                                    VStack(spacing: 6) {
                                        if items.isEmpty {
                                            MacDayCell(date: day, workout: nil, showDate: false, minHeight: 86)
                                        } else {
                                            ForEach(items) { w in
                                                Button { onEdit(w) } label: { MacDayCell(date: day, workout: w, showDate: false, minHeight: 86) }
                                                    .buttonStyle(.plain)
                                                    .contextMenu { WorkoutContextMenu(workout: w) }
                                            }
                                        }
                                    }
                                    .frame(minWidth: 110, maxWidth: .infinity)
                                }
                            }
                            .id(week.index)
                        }
                    }

                    Text("Click dreapta pe un antrenament ca să-l marchezi făcut, să sari peste el sau să-l ștergi. Activitățile din Garmin îl bifează automat.")
                        .appFont(13).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
            }
            .onAppear { proxy.scrollTo(max(0, plan.currentWeekIndex - 1), anchor: .top) }
        }
    }
}
