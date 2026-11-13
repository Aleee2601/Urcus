import SwiftUI
import SwiftData

enum Platform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif
}

// MARK: - Butonul de sincronizare

struct SyncCircleButton: View {
    @EnvironmentObject private var sync: SyncService
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            Task { await sync.sync(context: context) }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .rotationEffect(.degrees(sync.isSyncing ? 360 : 0))
                .animation(sync.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: sync.isSyncing)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(sync.isSyncing || !sync.hasKey)
        .accessibilityLabel("Sincronizează cu Garmin")
        .help("Sincronizează cu Garmin")
    }
}

// MARK: - Cardul zilei

struct TodayHeroCard: View {
    let workout: PlannedWorkout
    var large = false
    var onToggleDone: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 16 : 14) {
            HStack(spacing: 8) {
                Chip(text: workout.sport.label, color: workout.sport.color)
                Chip(text: workout.intensity.label, color: Theme.peach)
                Spacer()
                if workout.isDone { StatusMark(status: .done, size: 26) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.title)
                    .appFont(large ? 34 : 28, .heavy)
                    .tracking(-0.5)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !workout.details.isEmpty {
                    Text(workout.details)
                        .appFont(large ? 15 : 14)
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                        .frame(maxWidth: 420, alignment: .leading)
                }
            }
            targets
            HStack(spacing: 10) {
                Button(workout.isDone ? "Marchează nefăcut" : "Marchează făcut", action: onToggleDone)
                    .buttonStyle(PrimaryButtonStyle(fill: !large))
                Button(action: onOpen) {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold))
                        .frame(width: 24)
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .accessibilityLabel("Detalii antrenament")
            }
            .padding(.top, 4)
        }
        .padding(large ? 28 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            MountainBackdrop()
                .frame(height: large ? 140 : 120)
                .padding(.trailing, -20)
                .offset(y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        .card(radius: Theme.radiusL)
    }

    private var targetItems: [(label: String, value: String, unit: String?)] {
        var items: [(label: String, value: String, unit: String?)] = []
        if let e = workout.targetElevation, e > 0 { items.append(("Urcare", Fmt.number(Double(e), decimals: 0), "m")) }
        if let km = workout.targetDistanceKm, km > 0 { items.append(("Distanță", Fmt.number(km), "km")) }
        if let m = workout.targetDurationMin, m > 0 { items.append(("Durată", "\(m)", "min")) }
        if items.count < 3 { items.append(("Intensitate", workout.intensity.label, nil)) }
        return items
    }

    private var targets: some View {
        let size: CGFloat = large ? 28 : 24
        let items = targetItems
        return HStack(spacing: large ? 36 : 24) {
            ForEach(items.indices, id: \.self) { i in
                BigStat(label: items[i].label, value: items[i].value, unit: items[i].unit, size: size)
            }
        }
        .padding(.top, 4)
    }
}

struct RestDayCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "leaf")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.sage)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.sage.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Zi de odihnă").appFont(20, .heavy).foregroundStyle(Theme.text)
                Text("Nimic planificat azi. Mers liber sau refacere.").appFont(14).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .card(radius: Theme.radiusL)
    }
}

// MARK: - Progresul săptămânii

struct WeekProgressCard: View {
    let done: Int
    let planned: Int
    let km: Double
    let elevation: Double
    let seconds: Double
    var large = false

    var body: some View {
        HStack(spacing: large ? 22 : 18) {
            ProgressRing(progress: planned > 0 ? Double(done) / Double(planned) : 0, lineWidth: large ? 10 : 9) {
                VStack(spacing: 0) {
                    Text(planned > 0 ? "\(done)/\(planned)" : "–").appFont(large ? 26 : 24, .heavy).foregroundStyle(Theme.text).monospacedDigit()
                    Text("DIN PLAN").appFont(10, .bold).tracking(0.6).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: large ? 110 : 96, height: large ? 110 : 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) din \(planned) antrenamente făcute")

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 14) {
                BigStat(label: "Distanță", value: Fmt.km(km), size: 20)
                BigStat(label: "Urcare", value: Fmt.meters(elevation), color: Theme.plumLight, size: 20)
                BigStat(label: "Timp", value: Fmt.duration(seconds), size: 20)
                BigStat(label: "Rămase", value: "\(max(0, planned - done))", size: 20)
            }
        }
        .padding(large ? 24 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Rânduri

struct ActivityListRow: View {
    let activity: ActivityRecord
    var compact = false
    var selected = false

    var body: some View {
        HStack(spacing: compact ? 12 : 14) {
            SportTile(sport: activity.sport, size: compact ? 38 : 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name).appFont(compact ? 14 : 15, .bold).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).appFont(compact ? 12 : 13).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.distanceMeters > 0 ? Fmt.km(activity.distanceKm) : Fmt.duration(activity.durationSeconds))
                    .appFont(compact ? 14 : 15, .heavy).foregroundStyle(Theme.text).monospacedDigit()
                if activity.elevationGain > 0 {
                    Text("D+ \(Fmt.meters(activity.elevationGain))").appFont(12, .bold).foregroundStyle(Theme.plumLight).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 10 : 14)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.peach.opacity(0.5), lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [Fmt.weekdayShort(activity.startDate)]
        if let place = activity.locationName, !place.isEmpty { parts.append(place) }
        if activity.sport.usesPace && activity.distanceMeters > 0 {
            parts.append(Fmt.pace(seconds: activity.movingSeconds ?? activity.durationSeconds, km: activity.distanceKm))
        } else {
            parts.append(Fmt.duration(activity.durationSeconds))
        }
        return parts.joined(separator: " · ")
    }
}

struct UpcomingRow: View {
    let workout: PlannedWorkout

    var body: some View {
        HStack(spacing: 14) {
            SportTile(sport: workout.sport)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).appFont(15, .bold).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).appFont(13).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x5E6B65))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let tomorrow = Cal.addDays(1, to: Cal.ro.startOfDay(for: .now))
        let day = Cal.ro.isDate(workout.date, inSameDayAs: tomorrow)
            ? "Mâine"
            : workout.date.formatted(.dateTime.weekday(.wide).locale(Fmt.locale)).capitalized(with: Fmt.locale)
        let target = workout.targetSummary
        return target.isEmpty ? day : "\(day) · \(target)"
    }
}

/// Coloana cu ziua și data, în stânga rândurilor din plan.
struct DateColumn: View {
    let date: Date
    var dimmed = false

    var body: some View {
        let isToday = Cal.ro.isDateInToday(date)
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.locale))
                    .uppercased(with: Fmt.locale).replacingOccurrences(of: ".", with: ""))
                .appFont(11, isToday ? .heavy : .bold)
                .foregroundStyle(isToday ? Theme.peach : Theme.muted)
            Text(date.formatted(.dateTime.day().locale(Fmt.locale)))
                .appFont(18, .heavy)
                .foregroundStyle(isToday ? Theme.peach : (dimmed ? Theme.muted : Theme.text))
        }
        .frame(width: 40)
        .padding(.top, 14)
    }
}

struct RestDayRow: View {
    let date: Date
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DateColumn(date: date, dimmed: true)
            Text("Odihnă").appFont(14, .semibold).foregroundStyle(Theme.muted)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
    }
}

/// Rândul unei zile din plan (iPhone): coloana cu data + cardul antrenamentului.
struct PlanDayRow: View {
    let workout: PlannedWorkout
    var showDate = true

    var body: some View {
        let status = workout.status
        let isToday = Cal.ro.isDateInToday(workout.date) && status != .done
        HStack(alignment: .top, spacing: 14) {
            if showDate {
                DateColumn(date: workout.date)
            } else {
                Color.clear.frame(width: 40, height: 1)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.title)
                            .appFont(15, isToday ? .heavy : .bold)
                            .foregroundStyle(status == .skipped ? Theme.muted : Theme.text)
                            .strikethrough(status == .skipped)
                        Text(subtitle).appFont(13).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    StatusMark(status: status)
                }
                if !pills.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(pills.indices, id: \.self) { i in
                            Text(pills[i].text)
                                .appFont(12, .heavy)
                                .foregroundStyle(pills[i].elevation ? Theme.plumLight : Theme.text)
                                .monospacedDigit()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(pills[i].elevation ? Theme.plum.opacity(0.16) : Theme.track))
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 20, fill: isToday ? Theme.surface2 : Theme.surface,
                  stroke: isToday ? Theme.peach : Theme.line, strokeWidth: isToday ? 1.5 : 1)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if workout.completedActivityId != nil { return "Bifat din Garmin" }
        if Cal.ro.isDateInToday(workout.date) { return "Azi · \(workout.intensity.label.lowercased(with: Fmt.locale))" }
        return workout.intensity.label
    }

    private var pills: [(text: String, elevation: Bool)] {
        var p: [(text: String, elevation: Bool)] = []
        if let km = workout.targetDistanceKm, km > 0 { p.append((Fmt.km(km), false)) }
        if let e = workout.targetElevation, e > 0 { p.append(("D+ \(e) m", true)) }
        if let m = workout.targetDurationMin, m > 0 { p.append(("\(m) min", false)) }
        return p
    }
}

struct LastActivityCard: View {
    let activity: ActivityRecord
    var planTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name).appFont(16, .heavy).foregroundStyle(Theme.text).lineLimit(1)
                    Text(subtitle).appFont(13).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                if planTitle != nil { Chip(text: "Făcut", color: Theme.sage) }
            }
            HStack(spacing: 22) {
                if activity.distanceMeters > 0 {
                    Text(Fmt.km(activity.distanceKm)).appFont(15, .heavy).foregroundStyle(Theme.text)
                }
                if activity.elevationGain > 0 {
                    Text("D+ \(Fmt.meters(activity.elevationGain))").appFont(15, .heavy).foregroundStyle(Theme.plumLight)
                }
                Text(Fmt.duration(activity.durationSeconds)).appFont(15, .heavy).foregroundStyle(Theme.text)
            }
            .monospacedDigit()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [Fmt.day(activity.startDate).capitalized(with: Fmt.locale), activity.sport.label]
        if planTitle != nil { parts.append("bifat din plan") }
        return parts.joined(separator: " · ")
    }
}

/// Container de tip listă: rânduri separate de linii fine, într-un singur card.
struct CardList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 { Hairline() }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
    }
}
