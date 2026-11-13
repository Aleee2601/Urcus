import Testing
import Foundation
import SwiftData
@testable import Urcus

/// Luni, 5 ianuarie 2026, ora 12.
private let monday = Cal.ro.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!

private func options(weeks: Int = 12, goal: PlanGoal = .mountainHalf) -> PlanOptions {
    var o = PlanOptions()
    o.goal = goal
    o.startDate = monday
    // Ziua cursei: sâmbăta ultimei săptămâni.
    o.raceDate = Cal.addDays(7 * (weeks - 1) + 5, to: monday)
    o.startLongKm = 7
    return o
}

private func weekIndex(_ w: PlannedWorkout) -> Int {
    (Cal.ro.dateComponents([.day], from: Cal.startOfWeek(monday), to: Cal.startOfWeek(w.date)).day ?? 0) / 7
}

private func weekday(_ w: PlannedWorkout) -> Int {
    Cal.ro.dateComponents([.day], from: Cal.startOfWeek(w.date), to: Cal.ro.startOfDay(for: w.date)).day ?? -1
}

struct PlanGeneratorTests {
    @Test func weekCountMatchesRaceDate() {
        #expect(PlanGenerator.weekCount(options(weeks: 12)) == 12)
        #expect(PlanGenerator.weekCount(options(weeks: 1)) == 1)
    }

    @Test func raceDayIsLastAndNothingFollowsIt() {
        let o = options()
        let workouts = PlanGenerator.makeWorkouts(o).sorted { $0.date < $1.date }
        let last = try! #require(workouts.last)
        #expect(last.intensity == .race)
        #expect(last.targetDistanceKm == 21)
        #expect(Cal.ro.isDate(last.date, inSameDayAs: o.raceDate))
        #expect(workouts.filter { $0.date > o.raceDate }.isEmpty)
    }

    @Test func raceWeekHasNoGymSwimOrLongRun() {
        let workouts = PlanGenerator.makeWorkouts(options())
        let lastWeek = workouts.filter { weekIndex($0) == 11 }
        #expect(!lastWeek.contains { $0.sport == .gym || $0.sport == .swim || $0.sport == .hike })
        #expect(lastWeek.filter { $0.title.contains("lungă") }.isEmpty)
    }

    @Test func defaultScheduleUsesTheUsualDays() {
        let workouts = PlanGenerator.makeWorkouts(options())
        let week = workouts.filter { weekIndex($0) == 2 }
        #expect(week.first { $0.sport == .run }.map(weekday) == 1)
        #expect(week.first { $0.sport == .gym }.map(weekday) == 2)
        #expect(week.first { $0.title.hasPrefix("Tâmpa") }.map(weekday) == 3)
        #expect(week.first { $0.sport == .swim }.map(weekday) == 4)
        #expect(week.first { $0.title.contains("lungă") }.map(weekday) == 5)
    }

    @Test func customScheduleAndHillNameAreUsed() {
        var o = options()
        o.schedule = WeekSchedule(easyRun: 0, gym: 2, hill: 4, swim: 3, long: 6)
        o.hillName = "Postăvarul"
        let week = PlanGenerator.makeWorkouts(o).filter { weekIndex($0) == 2 }
        #expect(week.first { $0.sport == .run }.map(weekday) == 0)
        #expect(week.first { $0.title.hasPrefix("Postăvarul") }.map(weekday) == 4)
        #expect(week.first { $0.title.contains("lungă") }.map(weekday) == 6)
        #expect(!week.contains { $0.title.hasPrefix("Tâmpa") })
    }

    @Test func gymAndSwimCanBeSwitchedOff() {
        var o = options()
        o.includeGym = false
        o.includeSwim = false
        let workouts = PlanGenerator.makeWorkouts(o)
        #expect(!workouts.contains { $0.sport == .gym || $0.sport == .swim })
    }

    @Test func longRunGrowsAndDeloadWeeksAreLighter() {
        let o = options()
        let longs = PlanGenerator.makeWorkouts(o)
            .filter { $0.title.contains("lungă") }
            .sorted { $0.date < $1.date }
        let build = longs.filter { weekIndex($0) < 10 }
        // Săptămânile de refacere (a 4-a, a 8-a) sunt mai ușoare decât săptămâna dinainte.
        for deload in [3, 7] {
            let before = build.first { weekIndex($0) == deload - 1 }!.targetDistanceKm!
            let during = build.first { weekIndex($0) == deload }!.targetDistanceKm!
            #expect(during < before)
        }
        // În rest, tura lungă nu scade și nu depășește vârful.
        let normal = build.filter { ($0.date >= monday) && (weekIndex($0) + 1) % 4 != 0 }.compactMap(\.targetDistanceKm)
        #expect(normal == normal.sorted())
        #expect(normal.max()! <= PlanGoal.mountainHalf.peakLongKm)
        #expect(normal.first == 7)
    }

    @Test func goalWithoutRaceEndsOnEndDate() {
        let o = options(weeks: 8, goal: .base)
        let workouts = PlanGenerator.makeWorkouts(o)
        #expect(!workouts.contains { $0.intensity == .race })
        #expect(workouts.filter { $0.date > o.raceDate }.isEmpty)
    }

    @Test func resumingMidPlanStartsLongRunAtGivenLevel() {
        let o = options()
        let fresh = PlanGenerator.makeWorkouts(o, firstWeek: 4, startLongKm: 5)
        #expect(fresh.allSatisfy { weekIndex($0) >= 4 })
        let first = fresh.first { $0.title.contains("lungă") && weekIndex($0) == 4 }!
        #expect(first.targetDistanceKm == 5)
        let peakWeek = fresh.filter { $0.title.contains("lungă") && weekIndex($0) == 9 }.first!
        #expect(peakWeek.targetDistanceKm == PlanGoal.mountainHalf.peakLongKm)
    }

    @Test func resumeLevelFollowsRecentActivitiesAndStaysInRange() {
        let o = options()
        let now = Cal.addDays(30, to: monday)
        func run(_ km: Double, daysAgo: Int) -> ActivityRecord {
            ActivityRecord(garminId: daysAgo * 1000 + Int(km), name: "", typeKey: "trail_running",
                           startDate: Cal.addDays(-daysAgo, to: now), distanceMeters: km * 1000)
        }
        #expect(PlanGenerator.resumeLongKm(options: o, activities: [run(9.2, daysAgo: 6), run(4, daysAgo: 2)], now: now) == 9)
        // O ieșire veche de 40 de zile nu contează → rămâne nivelul de pornire.
        #expect(PlanGenerator.resumeLongKm(options: o, activities: [run(15, daysAgo: 40)], now: now) == 7)
        // Nu urcăm peste vârful planului, nici sub 3 km.
        #expect(PlanGenerator.resumeLongKm(options: o, activities: [run(30, daysAgo: 3)], now: now) == 18)
        #expect(PlanGenerator.resumeLongKm(options: o, activities: [run(1, daysAgo: 3)], now: now) == 3)
    }

    @Test @MainActor func replanKeepsPastAndDoneAndRebuildsTheRest() throws {
        let container = try ModelContainer(for: ActivityRecord.self, TrainingPlan.self, PlannedWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let o = options()
        let plan = PlanGenerator.create(o, in: context)
        try context.save()

        // Miercuri din săptămâna 5 (index 4).
        let now = Cal.addDays(28 + 2, to: monday)
        let pastBefore = plan.workouts.filter { $0.date < Cal.ro.startOfDay(for: now) }.count
        let futureDone = plan.workouts.first { $0.date > now && $0.sport == .swim }!
        futureDone.manuallyDone = true

        let recent = ActivityRecord(garminId: 1, name: "", typeKey: "trail_running",
                                    startDate: Cal.addDays(-10, to: now), distanceMeters: 5000)
        let added = PlanGenerator.replan(plan, activities: [recent], context: context, now: now)
        try context.save()

        #expect(added > 0)
        #expect(plan.workouts.filter { $0.date < Cal.ro.startOfDay(for: now) }.count == pastBefore)
        #expect(plan.workouts.contains { $0 === futureDone && $0.isDone })
        let nextLong = plan.workouts.first { $0.title.contains("lungă") && weekIndex($0) == 4 }!
        #expect(nextLong.targetDistanceKm == 5)
        // Ziua cursei există exact o dată.
        #expect(plan.workouts.filter { $0.intensity == .race }.count == 1)
        // Fără dubluri: o singură tură lungă pe săptămână.
        let longPerWeek = Dictionary(grouping: plan.workouts.filter { $0.title.contains("lungă") }, by: weekIndex)
        #expect(longPerWeek.values.allSatisfy { $0.count == 1 })
    }

    @Test @MainActor func replanAfterPlanEndsDoesNothing() throws {
        let container = try ModelContainer(for: ActivityRecord.self, TrainingPlan.self, PlannedWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let plan = PlanGenerator.create(options(), in: container.mainContext)
        let after = Cal.addDays(7 * 14, to: monday)
        #expect(PlanGenerator.replan(plan, activities: [], context: container.mainContext, now: after) == 0)
    }

    @Test @MainActor func optionsAreStoredAndReadBack() throws {
        let container = try ModelContainer(for: ActivityRecord.self, TrainingPlan.self, PlannedWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var o = options()
        o.hillName = "Cozla"
        o.schedule.long = 6
        let plan = PlanGenerator.create(o, in: container.mainContext)
        let back = PlanGenerator.options(for: plan)
        #expect(back.hillName == "Cozla")
        #expect(back.schedule.long == 6)

        // Plan vechi, fără opțiuni salvate: le reconstruim din antrenamente.
        plan.optionsData = nil
        let rebuilt = PlanGenerator.options(for: plan)
        #expect(rebuilt.goal == .mountainHalf)
        #expect(rebuilt.includeGym && rebuilt.includeSwim)
    }
}
