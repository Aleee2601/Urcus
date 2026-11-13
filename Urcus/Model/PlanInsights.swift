import Foundation
import SwiftUI

struct PlanPhase: Identifiable {
    let name: String
    let weeks: Int
    let filled: Double
    let isCurrent: Bool
    let label: String
    var id: String { name }
}

struct PlanWeek: Identifiable {
    let index: Int          // 0-based
    let start: Date
    let workouts: [PlannedWorkout]
    let isDeload: Bool
    let isTaper: Bool
    var id: Date { start }
    var end: Date { Cal.addDays(6, to: start) }
    var isCurrent: Bool { Cal.startOfWeek(.now) == start }

    var shortLabel: String {
        var s = "Săpt. \(index + 1)"
        if isCurrent { s += " · acum" }
        else if isDeload { s += " · refacere" }
        else if isTaper { s += " · descărcare" }
        return s
    }

    var rangeLabel: String { "\(Fmt.short(start)) – \(Fmt.short(end))" }

    var totalsLabel: String {
        let km = workouts.compactMap(\.targetDistanceKm).reduce(0, +)
        let elevation = workouts.compactMap(\.targetElevation).reduce(0, +)
        var parts: [String] = []
        if km > 0 { parts.append(Fmt.km(km)) }
        if elevation > 0 { parts.append("D+ \(Fmt.number(Double(elevation), decimals: 0))") }
        return parts.joined(separator: " · ")
    }
}

extension TrainingPlan {
    var hasRace: Bool { goal != PlanGoal.base.label }

    var totalWeeks: Int {
        let days = Cal.ro.dateComponents([.day], from: Cal.startOfWeek(startDate), to: endDate).day ?? 0
        return max(1, days / 7 + 1)
    }

    var currentWeekIndex: Int {
        let days = Cal.ro.dateComponents([.day], from: Cal.startOfWeek(startDate), to: Cal.startOfWeek(.now)).day ?? 0
        return min(max(0, days / 7), totalWeeks - 1)
    }

    private var taperWeeks: Int { hasRace ? min(2, max(0, totalWeeks - 3)) : 0 }
    private var buildWeeks: Int { max(1, totalWeeks - taperWeeks) }

    var daysLeft: Int {
        Cal.ro.dateComponents([.day], from: Cal.ro.startOfDay(for: .now), to: endDate).day ?? 0
    }

    /// Antrenamentele trecute făcute / totalul celor trecute.
    var adherence: (done: Int, total: Int) {
        let today = Cal.ro.startOfDay(for: .now)
        let past = workouts.filter { $0.date < today }
        return (past.filter(\.isDone).count, past.count)
    }

    var adherencePercent: Int? {
        let a = adherence
        guard a.total > 0 else { return nil }
        return Int((Double(a.done) / Double(a.total) * 100).rounded())
    }

    var phases: [PlanPhase] {
        var counts = [0, 0, 0]
        for w in 0..<buildWeeks {
            let p = buildWeeks > 1 ? Double(w) / Double(buildWeeks - 1) : 1
            if p < 0.4 { counts[0] += 1 } else if p < 0.85 { counts[1] += 1 } else { counts[2] += 1 }
        }
        var list: [(String, Int)] = [("Bază", counts[0]), ("Dezvoltare", counts[1]), ("Vârf", counts[2])]
        if taperWeeks > 0 { list.append(("Descărcare", taperWeeks)) }
        list = list.filter { $0.1 > 0 }

        let current = currentWeekIndex
        var start = 0
        var result: [PlanPhase] = []
        for (name, count) in list {
            let isCurrent = current >= start && current < start + count
            let filled: Double = current >= start + count ? 1 : (isCurrent ? Double(current - start + 1) / Double(count) : 0)
            let label = isCurrent ? "\(name) · săpt. \(current + 1)" : name
            result.append(PlanPhase(name: name, weeks: count, filled: filled, isCurrent: isCurrent, label: label))
            start += count
        }
        return result
    }

    var weeks: [PlanWeek] {
        let start = Cal.startOfWeek(startDate)
        let grouped = Dictionary(grouping: workouts) { Cal.startOfWeek($0.date) }
        return (0..<totalWeeks).map { i in
            let weekStart = Cal.addDays(7 * i, to: start)
            let items = (grouped[weekStart] ?? []).sorted { $0.date < $1.date }
            let isTaper = i >= buildWeeks
            return PlanWeek(index: i, start: weekStart, workouts: items,
                            isDeload: !isTaper && (i + 1) % 4 == 0, isTaper: isTaper)
        }
    }
}

/// Calcule pentru ecranul Azi.
enum WeekSummary {
    static func days(workouts: [PlannedWorkout], activities: [ActivityRecord]) -> [DayDot] {
        let start = Cal.startOfWeek(.now)
        let today = Cal.ro.startOfDay(for: .now)
        return (0..<7).map { offset in
            let day = Cal.addDays(offset, to: start)
            let planned = workouts.filter { Cal.ro.isDate($0.date, inSameDayAs: day) && $0.sport != .rest }
            let done = activities.filter { Cal.ro.isDate($0.startDate, inSameDayAs: day) }
            if let w = planned.first(where: \.isDone) {
                return DayDot(date: day, color: w.sport.color, state: .done)
            }
            if let a = done.first {
                return DayDot(date: day, color: a.sport.color, state: .done)
            }
            if day == today {
                return DayDot(date: day, color: Theme.peach, state: .today)
            }
            if let w = planned.first, day > today {
                return DayDot(date: day, color: w.sport.color, state: .planned)
            }
            return DayDot(date: day, color: Theme.mutedDot, state: .empty)
        }
    }
}
