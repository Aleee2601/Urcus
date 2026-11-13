import Foundation
import SwiftData

enum PlanGoal: String, CaseIterable, Identifiable {
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

struct PlanOptions {
    var name = "Plan de pregătire"
    var goal: PlanGoal = .mountainHalf
    var startDate = Date()
    var raceDate = Cal.addDays(7 * 20, to: Date())
    var startLongKm: Double = 7
    var includeGym = true
    var includeSwim = true
}

/// Generează un plan progresiv: bază → dezvoltare → vârf → descărcare înainte de cursă.
/// Săptămâna tip: marți alergare ușoară, miercuri sală, joi Tâmpa, vineri înot, sâmbătă tura lungă.
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
        let weeks = weekCount(o)
        let hasRace = o.goal.raceKm != nil

        let plan = TrainingPlan(name: o.name, goal: o.goal.label, startDate: start, endDate: end)
        context.insert(plan)

        let taperWeeks = hasRace ? min(2, max(0, weeks - 3)) : 0
        let buildWeeks = max(1, weeks - taperWeeks)
        var workouts: [PlannedWorkout] = []

        for w in 0..<weeks {
            let weekStart = Cal.addDays(7 * w, to: start)
            func day(_ offset: Int) -> Date { Cal.addDays(offset, to: weekStart) }

            let isTaper = w >= buildWeeks
            let isLastWeek = w == weeks - 1
            let progress = buildWeeks > 1 ? Double(min(w, buildWeeks - 1)) / Double(buildWeeks - 1) : 1
            let isDeload = !isTaper && (w + 1) % 4 == 0
            var factor = isDeload ? 0.7 : 1.0
            if isTaper { factor = isLastWeek ? 0.4 : 0.65 }

            let phase: String
            if isTaper { phase = "Descărcare" }
            else if isDeload { phase = "Săptămână de refacere" }
            else if progress < 0.4 { phase = "Bază" }
            else if progress < 0.85 { phase = "Dezvoltare" }
            else { phase = "Vârf" }

            let easyMinutes = Int(((30 + 20 * progress) * factor).rounded())
            let tampaElevation = roundTo50((350 + 350 * progress) * factor)
            let longKm = roundTo05((o.startLongKm + (o.goal.peakLongKm - o.startLongKm) * progress) * factor)
            let longElevation = roundTo50((300 + (o.goal.peakLongElevation - 300) * progress) * factor)

            // Marți — alergare ușoară pe plat
            workouts.append(PlannedWorkout(
                date: day(1), sport: .run, title: "Alergare ușoară în parc",
                details: "\(phase). Ritm de conversație, puls în zona 2.",
                minutes: easyMinutes, intensity: .easy))

            // Miercuri — forță
            if o.includeGym && !(hasRace && isLastWeek) {
                workouts.append(PlannedWorkout(
                    date: day(2), sport: .gym, title: "Sală — forță pentru munte",
                    details: "Genuflexiuni, fandări, step-up, îndreptări românești, core. Fără greutăți mari în săptămânile de refacere.",
                    minutes: isTaper ? 35 : 50, intensity: .moderate))
            }

            // Joi — Tâmpa
            workouts.append(PlannedWorkout(
                date: day(3), sport: .trail,
                title: tampaElevation >= 600 ? "Tâmpa — 2 urcări" : "Tâmpa — urcare",
                details: "\(phase). Urcă în ritm susținut, coboară controlat.",
                elevation: Int(tampaElevation), intensity: progress > 0.4 && !isDeload ? .hard : .moderate))

            // Vineri — înot ușor
            if o.includeSwim && !(hasRace && isLastWeek) {
                workouts.append(PlannedWorkout(
                    date: day(4), sport: .swim, title: "Înot ușor",
                    details: "Refacere activă.", minutes: 30, intensity: .easy))
            }

            // Sâmbătă — tura lungă (în săptămâna cursei, cursa o înlocuiește)
            if !(hasRace && isLastWeek) {
                let sport: Sport = progress < 0.3 ? .hike : .trail
                workouts.append(PlannedWorkout(
                    date: day(5), sport: sport,
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

        for workout in workouts {
            context.insert(workout)
            workout.plan = plan
        }
        return plan
    }

    private static func roundTo50(_ v: Double) -> Double { (v / 50).rounded() * 50 }
    private static func roundTo05(_ v: Double) -> Double { (v * 2).rounded() / 2 }
}
