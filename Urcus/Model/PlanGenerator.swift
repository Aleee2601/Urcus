import Foundation
import SwiftData

enum PlanGoal: String, CaseIterable, Identifiable, Codable {
    case mountainHalf, trailShort, base

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mountainHalf: "Semimaraton montan (~21 km)"
        case .trailShort: "Trail scurt (10–15 km)"
        case .base: "Formă generală (fără cursă)"
        }
    }

    var peakLongKm: Double {
        switch self {
        case .mountainHalf: 18
        case .trailShort: 12
        case .base: 12
        }
    }

    var peakLongElevation: Double {
        switch self {
        case .mountainHalf: 1100
        case .trailShort: 700
        case .base: 700
        }
    }

    var raceKm: Double? {
        switch self {
        case .mountainHalf: 21
        case .trailShort: 13
        case .base: nil
        }
    }
}

/// În ce zi a săptămânii pică fiecare antrenament (0 = luni … 6 = duminică).
struct WeekSchedule: Codable, Equatable {
    var easyRun = 1
    var gym = 2
    var hill = 3
    var swim = 4
    var long = 5

    static let weekdayNames = ["Luni", "Marți", "Miercuri", "Joi", "Vineri", "Sâmbătă", "Duminică"]
}

struct PlanOptions: Codable, Equatable {
    var name = "Plan de pregătire"
    var goal: PlanGoal = .mountainHalf
    var startDate = Date()
    var raceDate = Cal.addDays(7 * 20, to: Date())
    var startLongKm: Double = 7
    var includeGym = true
    var includeSwim = true
    var schedule = WeekSchedule()
    /// Dealul de lângă tine, pentru antrenamentul de urcare din mijlocul săptămânii.
    var hillName = "Tâmpa"
}

/// Generează un plan progresiv: bază → dezvoltare → vârf → descărcare înainte de cursă.
/// Zilele săptămânii sunt cele din `WeekSchedule` (implicit: marți ușor, miercuri sală, joi deal, vineri înot, sâmbătă tura lungă).
enum PlanGenerator {
    static func weekCount(_ o: PlanOptions) -> Int {
        let start = Cal.startOfWeek(o.startDate)
        let end = Cal.ro.startOfDay(for: o.raceDate)
        let days = Cal.ro.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days / 7 + 1)
    }

    @MainActor
    static func create(_ o: PlanOptions, in context: ModelContext) -> TrainingPlan {
        let start = Cal.startOfWeek(o.startDate)
        let end = Cal.ro.startOfDay(for: o.raceDate)

        let plan = TrainingPlan(name: o.name, goal: o.goal.label, startDate: start, endDate: end)
        plan.optionsData = try? JSONEncoder().encode(o)
        context.insert(plan)

        for workout in makeWorkouts(o) {
            context.insert(workout)
            workout.plan = plan
        }
        return plan
    }

    /// Construiește antrenamentele (fără să le salveze).
    /// - Parameters:
    ///   - firstWeek: de la ce săptămână (0-based) generăm; restul planului rămâne cel de la început.
    ///   - startLongKm: de la ce lungime pornește tura lungă în `firstWeek` (implicit `o.startLongKm`).
    static func makeWorkouts(_ o: PlanOptions, firstWeek: Int = 0, startLongKm: Double? = nil) -> [PlannedWorkout] {
        let start = Cal.startOfWeek(o.startDate)
        let end = Cal.ro.startOfDay(for: o.raceDate)
        let weeks = weekCount(o)
        let hasRace = o.goal.raceKm != nil
        let s = o.schedule

        let taperWeeks = hasRace ? min(2, max(0, weeks - 3)) : 0
        let buildWeeks = max(1, weeks - taperWeeks)
        func progressAt(_ w: Int) -> Double {
            buildWeeks > 1 ? Double(min(w, buildWeeks - 1)) / Double(buildWeeks - 1) : 1
        }
        let firstWeek = min(max(0, firstWeek), weeks - 1)
        let p0 = progressAt(firstWeek)
        let longStart = startLongKm ?? o.startLongKm
        var workouts: [PlannedWorkout] = []

        for w in firstWeek..<weeks {
            let weekStart = Cal.addDays(7 * w, to: start)
            func day(_ offset: Int) -> Date { Cal.addDays(offset, to: weekStart) }

            let isTaper = w >= buildWeeks
            let isLastWeek = w == weeks - 1
            let progress = progressAt(w)
            let isDeload = !isTaper && (w + 1) % 4 == 0
            var factor = isDeload ? 0.7 : 1.0
            if isTaper { factor = isLastWeek ? 0.4 : 0.65 }

            let phase: String
            if isTaper { phase = "Descărcare" }
            else if isDeload { phase = "Săptămână de refacere" }
            else if progress < 0.4 { phase = "Bază" }
            else if progress < 0.85 { phase = "Dezvoltare" }
            else { phase = "Vârf" }

            // Tura lungă pornește de la nivelul de azi (`longStart`) și urcă spre vârf.
            let longProgress = p0 < 1 ? max(0, (progress - p0) / (1 - p0)) : 1
            let easyMinutes = Int(((30 + 20 * progress) * factor).rounded())
            let hillElevation = roundTo50((350 + 350 * progress) * factor)
            let longKm = roundTo05((longStart + (o.goal.peakLongKm - longStart) * longProgress) * factor)
            let longElevation = roundTo50((300 + (o.goal.peakLongElevation - 300) * progress) * factor)

            workouts.append(PlannedWorkout(
                date: day(s.easyRun), sport: .run, title: "Alergare ușoară în parc",
                details: "\(phase). Ritm de conversație, puls în zona 2.",
                minutes: easyMinutes, intensity: .easy))

            if o.includeGym && !(hasRace && isLastWeek) {
                workouts.append(PlannedWorkout(
                    date: day(s.gym), sport: .gym, title: "Sală — forță pentru munte",
                    details: "Genuflexiuni, fandări, step-up, îndreptări românești, core. Fără greutăți mari în săptămânile de refacere.",
                    minutes: isTaper ? 35 : 50, intensity: .moderate))
            }

            let hill = o.hillName.trimmingCharacters(in: .whitespaces).isEmpty ? "Deal" : o.hillName
            workouts.append(PlannedWorkout(
                date: day(s.hill), sport: .trail,
                title: hillElevation >= 600 ? "\(hill) — 2 urcări" : "\(hill) — urcare",
                details: "\(phase). Urcă în ritm susținut, coboară controlat.",
                elevation: Int(hillElevation), intensity: progress > 0.4 && !isDeload ? .hard : .moderate))

            if o.includeSwim && !(hasRace && isLastWeek) {
                workouts.append(PlannedWorkout(
                    date: day(s.swim), sport: .swim, title: "Înot ușor",
                    details: "Refacere activă.", minutes: 30, intensity: .easy))
            }

            if !(hasRace && isLastWeek) {
                let sport: Sport = progress < 0.3 ? .hike : .trail
                workouts.append(PlannedWorkout(
                    date: day(s.long), sport: sport,
                    title: sport == .hike ? "Tură lungă la munte" : "Alergare lungă pe munte",
                    details: "\(phase). Exersează hidratarea și mâncatul pe traseu.",
                    km: longKm, elevation: Int(longElevation),
                    intensity: .moderate))
            }
        }

        if let raceKm = o.goal.raceKm {
            workouts.removeAll { $0.date >= end }
            workouts.append(PlannedWorkout(
                date: end, sport: .trail, title: "Ziua cursei 🏁",
                details: "Pornește prudent, mănâncă devreme, bucură-te de traseu.",
                km: raceKm, intensity: .race))
        } else {
            workouts.removeAll { $0.date > end }
        }
        return workouts
    }

    // MARK: - Recalculare

    /// Cât de lungă a fost cea mai lungă ieșire din ultimele 4 săptămâni (km), rotunjită la 0,5.
    static func recentLongKm(activities: [ActivityRecord], now: Date = .now) -> Double? {
        let since = Cal.addDays(-28, to: now)
        let longest = activities
            .filter { $0.startDate >= since && $0.startDate <= now && [.run, .trail, .hike].contains($0.sport) }
            .map(\.distanceKm)
            .max()
        return longest.map(roundTo05)
    }

    /// Nivelul de la care repornește tura lungă: ce ai făcut de curând, între 3 km și vârful planului.
    static func resumeLongKm(options o: PlanOptions, activities: [ActivityRecord], now: Date = .now) -> Double {
        let recent = recentLongKm(activities: activities, now: now) ?? o.startLongKm
        return min(max(3, recent), o.goal.peakLongKm)
    }

    /// Opțiunile planului: cele salvate la creare sau, pentru planuri mai vechi, reconstruite din antrenamente.
    @MainActor
    static func options(for plan: TrainingPlan) -> PlanOptions {
        if let data = plan.optionsData, var o = try? JSONDecoder().decode(PlanOptions.self, from: data) {
            o.name = plan.name
            return o
        }
        var o = PlanOptions()
        o.name = plan.name
        o.goal = PlanGoal.allCases.first { $0.label == plan.goal } ?? .base
        o.startDate = plan.startDate
        o.raceDate = plan.endDate
        o.includeGym = plan.workouts.contains { $0.sport == .gym }
        o.includeSwim = plan.workouts.contains { $0.sport == .swim }
        return o
    }

    /// Înlocuiește antrenamentele nefăcute de azi încolo cu unele noi, pornind de la ce ai alergat de fapt.
    /// Ce e în trecut sau deja făcut rămâne neatins. Întoarce numărul de antrenamente noi.
    @MainActor
    @discardableResult
    static func replan(_ plan: TrainingPlan, activities: [ActivityRecord], context: ModelContext, now: Date = .now) -> Int {
        let today = Cal.ro.startOfDay(for: now)
        let o = options(for: plan)
        guard today <= Cal.ro.startOfDay(for: plan.endDate) else { return 0 }

        let firstWeek = max(0, (Cal.ro.dateComponents([.day], from: Cal.startOfWeek(plan.startDate), to: Cal.startOfWeek(today)).day ?? 0) / 7)
        let longKm = resumeLongKm(options: o, activities: activities, now: now)
        let fresh = makeWorkouts(o, firstWeek: firstWeek, startLongKm: longKm).filter { $0.date >= today }

        for old in plan.workouts where old.date >= today && !old.isDone {
            context.delete(old)
        }
        let kept = plan.workouts.filter { $0.date >= today && $0.isDone }
        var added = 0
        for w in fresh {
            if kept.contains(where: { Cal.ro.isDate($0.date, inSameDayAs: w.date) && $0.sport == w.sport }) { continue }
            context.insert(w)
            w.plan = plan
            added += 1
        }
        return added
    }

    private static func roundTo50(_ v: Double) -> Double { (v / 50).rounded() * 50 }
    private static func roundTo05(_ v: Double) -> Double { (v * 2).rounded() / 2 }
}
