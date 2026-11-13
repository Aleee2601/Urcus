import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \ActivityRecord.startDate) private var activities: [ActivityRecord]
    @Query private var workouts: [PlannedWorkout]
    @State private var metric: Metric = .distance
    @State private var period: Period = .weeks12

    enum Metric: String, CaseIterable, Identifiable {
        case distance, elevation, time
        var id: String { rawValue }
        var label: String {
            switch self {
            case .distance: "Km"
            case .elevation: "Urcare"
            case .time: "Ore"
            }
        }
        var chartTitle: String {
            switch self {
            case .distance: "Km"
            case .elevation: "Urcare (m)"
            case .time: "Ore"
            }
        }
        func value(_ a: ActivityRecord) -> Double {
            switch self {
            case .distance: a.distanceKm
            case .elevation: a.elevationGain
            case .time: a.durationSeconds / 3600
            }
        }
        func format(_ v: Double) -> String {
            switch self {
            case .distance: Fmt.km(v)
            case .elevation: Fmt.meters(v)
            case .time: Fmt.duration(v * 3600)
            }
        }
    }

    enum Period: String, CaseIterable, Identifiable {
        case weeks4, weeks12, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weeks4: "4 săpt."
            case .weeks12: "12 săpt."
            case .year: "An"
            }
        }
    }

    private struct Bucket: Identifiable {
        let start: Date
        let end: Date
        let label: String
        var id: Date { start }
    }

    private struct Point: Identifiable {
        let bucket: String
        let sport: Sport
        let value: Double
        var id: String { "\(bucket)-\(sport.rawValue)" }
    }

    private var effectivePeriod: Period { Platform.isMac ? period : .weeks12 }

    private var buckets: [Bucket] {
        switch effectivePeriod {
        case .weeks4, .weeks12:
            let count = effectivePeriod == .weeks4 ? 4 : 12
            let current = Cal.startOfWeek(.now)
            return (0..<count).reversed().map { i in
                let start = Cal.addDays(-7 * i, to: current)
                return Bucket(start: start, end: Cal.addDays(7, to: start), label: i == 0 ? "acum" : Fmt.short(start))
            }
        case .year:
            let yearStart = Cal.ro.dateInterval(of: .year, for: .now)?.start ?? .now
            return (0..<12).compactMap { m in
                guard let start = Cal.ro.date(byAdding: .month, value: m, to: yearStart), start <= .now,
                      let end = Cal.ro.date(byAdding: .month, value: 1, to: start) else { return nil }
                let label = start.formatted(.dateTime.month(.abbreviated).locale(Fmt.locale)).replacingOccurrences(of: ".", with: "")
                return Bucket(start: start, end: end, label: label)
            }
        }
    }

    private var periodActivities: [ActivityRecord] {
        guard let first = buckets.first?.start else { return [] }
        return activities.filter { $0.startDate >= first }
    }

    private var points: [Point] {
        var result: [Point] = []
        for b in buckets {
            let inBucket = periodActivities.filter { $0.startDate >= b.start && $0.startDate < b.end }
            let bySport = Dictionary(grouping: inBucket, by: \.sport)
            var added = false
            for sport in Sport.allCases {
                guard let items = bySport[sport] else { continue }
                let v = items.reduce(0) { $0 + metric.value($1) }
                if v > 0 {
                    result.append(Point(bucket: b.label, sport: sport, value: v))
                    added = true
                }
            }
            // Perioadele goale rămân pe axă, cu valoare 0.
            if !added { result.append(Point(bucket: b.label, sport: presentSports.first ?? .other, value: 0)) }
        }
        return result
    }

    private var total: Double { periodActivities.reduce(0) { $0 + metric.value($1) } }
    private var perBucket: Double { buckets.isEmpty ? 0 : total / Double(buckets.count) }

    private struct SportTotal: Identifiable {
        let sport: Sport
        let count: Int
        let km: Double
        let elevation: Double
        let seconds: Double
        var id: String { sport.rawValue }
    }

    private var yearTotals: [SportTotal] {
        let yearStart = Cal.ro.dateInterval(of: .year, for: .now)?.start ?? .now
        let items = activities.filter { $0.startDate >= yearStart }
        return Dictionary(grouping: items, by: \.sport).map { sport, list in
            SportTotal(sport: sport, count: list.count,
                       km: list.reduce(0) { $0 + $1.distanceKm },
                       elevation: list.reduce(0) { $0 + $1.elevationGain },
                       seconds: list.reduce(0) { $0 + $1.durationSeconds })
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private var adherence: (done: Int, total: Int) {
        let today = Cal.ro.startOfDay(for: .now)
        let past = workouts.filter { ($0.plan?.isActive ?? false) && $0.date < today }
        return (past.filter(\.isDone).count, past.count)
    }

    private var periodKicker: String {
        guard let first = buckets.first?.start else { return "" }
        return "\(Fmt.short(first)) – \(Fmt.short(.now))"
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
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    // MARK: iPhone

    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScreenHeader(kicker: "Ultimele 12 săptămâni", title: "Statistici")
            PillSegmented(selection: $metric, options: Metric.allCases.map { ($0, $0.label) })

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    BigStat(label: "Total", value: metric.format(total), size: 40)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Medie / săpt.").appFont(12, .semibold).foregroundStyle(Theme.muted)
                        Text(metric.format(perBucket)).appFont(20, .heavy).foregroundStyle(Theme.text).monospacedDigit()
                    }
                }
                chart(height: 180, labelEvery: 2)
                legend
            }
            .padding(22)
            .card(radius: Theme.radiusL)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Anul \(Calendar.current.component(.year, from: .now))")
                yearCard
            }

            adherenceCard
        }
    }

    // MARK: Mac

    private var macLayout: some View {
        VStack(alignment: .leading, spacing: 28) {
            ScreenHeader(kicker: periodKicker, title: "Statistici", titleSize: 36) {
                HStack(spacing: 10) {
                    PillSegmented(selection: $metric, options: Metric.allCases.map { ($0, $0.label) }, height: 34)
                        .frame(width: 250)
                    PillSegmented(selection: $period, options: Period.allCases.map { ($0, $0.label) }, height: 34)
                        .frame(width: 250)
                }
            }

            HStack(spacing: 16) {
                kpi("Distanță", Fmt.km(periodActivities.reduce(0) { $0 + $1.distanceKm }), avg(periodActivities.reduce(0) { $0 + $1.distanceKm }, Fmt.km))
                kpi("Urcare", Fmt.meters(periodActivities.reduce(0) { $0 + $1.elevationGain }), avg(periodActivities.reduce(0) { $0 + $1.elevationGain }, Fmt.meters), color: Theme.plumLight)
                kpi("Timp", Fmt.duration(periodActivities.reduce(0) { $0 + $1.durationSeconds }), avg(periodActivities.reduce(0) { $0 + $1.durationSeconds }, Fmt.duration))
                kpi("Activități", "\(periodActivities.count)", avg(Double(periodActivities.count)) { "≈ \(Fmt.number($0))" })
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("\(metric.chartTitle) pe \(effectivePeriod == .year ? "lună" : "săptămână")").appFont(16, .heavy).foregroundStyle(Theme.text)
                        Spacer()
                        legend
                    }
                    chart(height: 280, labelEvery: 1)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .card()
                .layoutPriority(1)

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Anul \(Calendar.current.component(.year, from: .now))").appFont(16, .heavy).foregroundStyle(Theme.text)
                        yearRows
                    }
                    .padding(24)
                    .card()
                    adherenceCard
                }
                .frame(width: 320)
            }
        }
    }

    private func avg(_ value: Double, _ format: (Double) -> String) -> String {
        let unit = effectivePeriod == .year ? "lună" : "săpt."
        return "\(format(buckets.isEmpty ? 0 : value / Double(buckets.count))) / \(unit)"
    }

    private func kpi(_ label: String, _ value: String, _ sub: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).appFont(12, .semibold).foregroundStyle(Theme.muted)
            Text(value).appFont(30, .heavy).tracking(-0.4).foregroundStyle(color).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).appFont(12, .semibold).foregroundStyle(Theme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Bucăți comune

    private var presentSports: [Sport] {
        Sport.allCases.filter { s in periodActivities.contains { $0.sport == s && metric.value($0) > 0 } }
    }

    private func chart(height: CGFloat, labelEvery: Int) -> some View {
        let labels = buckets.map(\.label)
        let shown = labels.enumerated().filter { ($0.offset % labelEvery == 0) || $0.offset == labels.count - 1 }.map(\.element)
        let domain = presentSports.isEmpty ? [Sport.other] : presentSports
        return Chart(points) { point in
            BarMark(x: .value("Perioadă", point.bucket), y: .value(metric.chartTitle, point.value))
                .foregroundStyle(by: .value("Sport", point.sport.label))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: domain.map(\.label), range: domain.map(\.color))
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: shown) { _ in
                AxisValueLabel()
                    .font(AppFont.font(10, .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel().foregroundStyle(Theme.muted)
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(metric.chartTitle) pe perioade, pe sporturi")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(presentSports) { sport in
                HStack(spacing: 6) {
                    Dot(color: sport.color, size: 8)
                    Text(sport.label).appFont(12, .bold).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var yearCard: some View {
        yearRows
            .padding(18)
            .card()
    }

    @ViewBuilder
    private var yearRows: some View {
        if yearTotals.isEmpty {
            Text("Încă nu ai activități anul acesta.").appFont(14).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let maxSeconds = yearTotals.map(\.seconds).max() ?? 1
            VStack(spacing: 18) {
                ForEach(yearTotals) { t in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            HStack(spacing: 8) {
                                Dot(color: t.sport.color)
                                Text(t.sport.label).appFont(15, .bold).foregroundStyle(Theme.text)
                            }
                            Spacer()
                            Text(t.km > 0.5 ? Fmt.km(t.km) : Fmt.duration(t.seconds))
                                .appFont(15, .heavy).foregroundStyle(Theme.text).monospacedDigit()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule().fill(t.sport.color).frame(width: geo.size.width * t.seconds / max(1, maxSeconds))
                            }
                        }
                        .frame(height: 6)
                        Text(meta(t)).appFont(12, .semibold).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private func meta(_ t: SportTotal) -> String {
        var parts = ["\(t.count) \(t.count == 1 ? "ieșire" : "ieșiri")"]
        if t.elevation > 0 { parts.append("D+ \(Fmt.meters(t.elevation))") }
        if t.km > 0.5 { parts.append(Fmt.duration(t.seconds)) }
        return parts.joined(separator: " · ")
    }

    private var adherenceCard: some View {
        let a = adherence
        let progress = a.total > 0 ? Double(a.done) / Double(a.total) : 0
        return HStack(spacing: 16) {
            ProgressRing(progress: progress, lineWidth: 7) { EmptyView() }
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if a.total > 0 {
                    Text("\(Int((progress * 100).rounded()))% din plan respectat").appFont(15, .heavy).foregroundStyle(Theme.text)
                    Text("\(a.done) din \(a.total) antrenamente").appFont(13).foregroundStyle(Theme.muted)
                } else {
                    Text("Respectarea planului").appFont(15, .heavy).foregroundStyle(Theme.text)
                    Text("Apare după primele antrenamente din plan.").appFont(13).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .card()
    }
}
