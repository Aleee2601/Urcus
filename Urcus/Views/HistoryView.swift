import SwiftUI
import SwiftData

private struct MonthGroup: Identifiable {
    let start: Date
    let items: [ActivityRecord]
    var id: Date { start }

    var meta: String {
        let km = items.reduce(0) { $0 + $1.distanceKm }
        let elevation = items.reduce(0) { $0 + $1.elevationGain }
        var parts = ["\(items.count)", Fmt.km(km)]
        if elevation > 0 { parts.append("D+ \(Fmt.number(elevation, decimals: 0))") }
        return parts.joined(separator: " · ")
    }
}

struct HistoryView: View {
    @EnvironmentObject private var sync: SyncService
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityRecord.startDate, order: .reverse) private var activities: [ActivityRecord]
    @Query private var workouts: [PlannedWorkout]
    @State private var search = ""
    @State private var filter: Sport?
    @State private var selection: ActivityRecord?

    private var sportsPresent: [Sport] {
        let present = Set(activities.map(\.sport))
        return Sport.allCases.filter { present.contains($0) }
    }

    private var filtered: [ActivityRecord] {
        activities.filter { a in
            (filter == nil || a.sport == filter)
            && (search.isEmpty
                || a.name.localizedCaseInsensitiveContains(search)
                || (a.locationName?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    private var months: [MonthGroup] {
        let grouped = Dictionary(grouping: filtered) { Cal.startOfMonth($0.startDate) }
        return grouped.keys.sorted(by: >).map { MonthGroup(start: $0, items: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if Platform.isMac { macLayout } else { phoneLayout }
            }
            .screenBackground()
            .navigationDestination(for: ActivityRecord.self) { ActivityDetailView(activity: $0) }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private var kicker: String { "\(activities.count) activități din Garmin" }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Toate", isOn: filter == nil) { filter = nil }
                ForEach(sportsPresent) { sport in
                    FilterChip(label: sport.label, isOn: filter == sport) { filter = (filter == sport ? nil : sport) }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.hiking")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.sage)
                .frame(width: 70, height: 70)
                .background(Circle().fill(Theme.sage.opacity(0.12)))
            Text(activities.isEmpty ? "Nicio activitate încă" : "Nimic găsit").appFont(20, .heavy).foregroundStyle(Theme.text)
            Text(activities.isEmpty
                 ? (sync.hasKey ? "Trage în jos sau apasă pe sincronizare ca să aduci istoricul din Garmin." : "Adaugă cheia Garmin în Setări.")
                 : "Încearcă alt filtru sau alt cuvânt.")
                .appFont(14).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(.vertical, 50)
        .frame(maxWidth: .infinity)
    }

    // MARK: iPhone

    private var phoneLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(kicker: kicker, title: "Istoric") { SyncCircleButton() }
                SearchField(text: $search)
                chips
                if months.isEmpty {
                    emptyState
                } else {
                    ForEach(months) { month in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(title: Fmt.month(month.start), trailing: month.meta)
                            CardList(items: month.items) { activity in
                                NavigationLink(value: activity) { ActivityListRow(activity: activity) }
                                    .buttonStyle(.plain)
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
        .refreshable { await sync.sync(context: context) }
    }

    // MARK: Mac

    private var macLayout: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScreenHeader(kicker: kicker, title: "Istoric", titleSize: 36) {
                Button("Sincronizează") { Task { await sync.sync(context: context) } }
                    .buttonStyle(SecondaryButtonStyle(height: 40))
                    .disabled(sync.isSyncing || !sync.hasKey)
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    SearchField(text: $search, fill: Theme.inset)
                    chips
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                            if months.isEmpty { emptyState }
                            ForEach(months) { month in
                                HStack {
                                    Kicker(text: Fmt.month(month.start))
                                    Spacer()
                                    Text(month.meta).appFont(12, .bold).foregroundStyle(Theme.muted).monospacedDigit()
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 14)
                                .padding(.bottom, 6)
                                ForEach(month.items) { activity in
                                    Button { selection = activity } label: {
                                        ActivityListRow(activity: activity, compact: true, selected: selection == activity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .padding(14)
                .frame(width: 400)
                .frame(maxHeight: .infinity, alignment: .top)
                .card()

                Group {
                    if let activity = selection ?? filtered.first {
                        ScrollView {
                            ActivityDetailContent(activity: activity, planned: planned(for: activity), large: true)
                                .padding(28)
                        }
                        .scrollIndicators(.never)
                        .card()
                    } else {
                        emptyState.card()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
        }
    }

    private func planned(for activity: ActivityRecord) -> PlannedWorkout? {
        workouts.first { $0.completedActivityId == activity.garminId }
    }
}

// MARK: - Detaliu

struct ActivityDetailView: View {
    let activity: ActivityRecord
    @Query private var workouts: [PlannedWorkout]

    var body: some View {
        ScrollView {
            ActivityDetailContent(activity: activity,
                                  planned: workouts.first { $0.completedActivityId == activity.garminId },
                                  large: Platform.isMac)
                .padding(.horizontal, Platform.isMac ? 40 : 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle(activity.sport.label)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }
}

struct ActivityDetailContent: View {
    let activity: ActivityRecord
    let planned: PlannedWorkout?
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 24 : 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Chip(text: activity.sport.label, color: activity.sport.color)
                    Spacer()
                    if let url = activity.garminURL, large {
                        Link(destination: url) {
                            Label("Garmin Connect", systemImage: "arrow.up.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(SecondaryButtonStyle(height: 38))
                    }
                }
                Text(activity.name)
                    .appFont(large ? 30 : 32, .heavy)
                    .tracking(-0.5)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Fmt.day(activity.startDate).capitalized(with: Fmt.locale) + " · " + activity.startDate.formatted(.dateTime.hour().minute().locale(Fmt.locale)))
                    .appFont(14, .semibold).foregroundStyle(Theme.muted)
                if let place = activity.locationName, !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse").appFont(13, .semibold).foregroundStyle(Theme.muted)
                }
            }

            HStack(alignment: .top, spacing: large ? 40 : 0) {
                if activity.distanceMeters > 0 {
                    BigStat(label: "Distanță", value: Fmt.number(activity.distanceKm), unit: "km", size: large ? 34 : 30)
                    if !large { Spacer(minLength: 8) }
                }
                if activity.elevationGain > 0 {
                    BigStat(label: "Urcare", value: Fmt.number(activity.elevationGain, decimals: 0), unit: "m", color: Theme.plumLight, size: large ? 34 : 30)
                    if !large { Spacer(minLength: 8) }
                }
                BigStat(label: "Durată", value: Fmt.duration(activity.durationSeconds), size: large ? 34 : 30)
                if !large { Spacer(minLength: 0) }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: large ? 3 : 2), spacing: 8) {
                ForEach(stats, id: \.label) { stat in
                    StatBox(label: stat.label, value: stat.value, color: stat.color, fill: large ? Theme.inset : Theme.surface)
                }
            }

            if let zones = activity.zoneSeconds {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timp în zonele de puls").appFont(14, .heavy).foregroundStyle(Theme.text)
                    ZoneBar(seconds: zones)
                }
                .padding(18)
                .card(fill: large ? Theme.inset : Theme.surface)
            }

            if let planned {
                HStack(spacing: 14) {
                    StatusMark(status: .done, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A bifat „\(planned.title)”").appFont(14, .heavy).foregroundStyle(Theme.text)
                        Text(planComparison(planned)).appFont(13).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .card(radius: 20, fill: Theme.sage.opacity(0.10), stroke: Theme.sage.opacity(0.25))
            }

            if let url = activity.garminURL, !large {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Text("Deschide în Garmin Connect")
                        Image(systemName: "arrow.up.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(height: 50))
            }
        }
    }

    private struct StatItem { let label: String; let value: String; let color: Color }

    private var stats: [StatItem] {
        var s: [StatItem] = []
        if activity.distanceMeters > 0 {
            if activity.sport.usesPace {
                s.append(StatItem(label: "Ritm mediu", value: Fmt.pace(seconds: activity.movingSeconds ?? activity.durationSeconds, km: activity.distanceKm), color: Theme.text))
            } else if let speed = activity.averageSpeed {
                s.append(StatItem(label: "Viteză medie", value: Fmt.speed(metersPerSecond: speed), color: Theme.text))
            }
        }
        if let moving = activity.movingSeconds, moving > 0 {
            s.append(StatItem(label: "În mișcare", value: Fmt.duration(moving), color: Theme.text))
        }
        if let loss = activity.elevationLoss, loss > 0 {
            s.append(StatItem(label: "Coborâre", value: Fmt.meters(loss), color: Theme.text))
        }
        if let hr = activity.averageHR {
            s.append(StatItem(label: "Puls mediu", value: "\(Int(hr)) bpm", color: Theme.coral))
        }
        if let hr = activity.maxHR {
            s.append(StatItem(label: "Puls maxim", value: "\(Int(hr)) bpm", color: Theme.coral))
        }
        if let kcal = activity.calories, kcal > 0 {
            s.append(StatItem(label: "Calorii", value: "\(Int(kcal)) kcal", color: Theme.text))
        }
        return s
    }

    private func planComparison(_ w: PlannedWorkout) -> String {
        var parts: [String] = []
        let target = w.targetSummary
        if !target.isEmpty { parts.append("Plan: \(target)") }
        if let e = w.targetElevation, e > 0, activity.elevationGain > 0 {
            let diff = Int(((activity.elevationGain - Double(e)) / Double(e) * 100).rounded())
            parts.append("\(diff >= 0 ? "+" : "")\(diff)% urcare")
        } else if let km = w.targetDistanceKm, km > 0, activity.distanceKm > 0 {
            let diff = Int(((activity.distanceKm - km) / km * 100).rounded())
            parts.append("\(diff >= 0 ? "+" : "")\(diff)% distanță")
        }
        return parts.joined(separator: " → ")
    }
}
