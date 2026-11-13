import Testing
import Foundation
@testable import Urcus

private let day = Cal.ro.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))!

private func activity(_ id: Int, _ type: String, km: Double = 0, minutes: Double = 0, gain: Double = 0,
                      at date: Date = day) -> ActivityRecord {
    let a = ActivityRecord(garminId: id, name: "", typeKey: type, startDate: date,
                           distanceMeters: km * 1000, durationSeconds: minutes * 60, elevationGain: gain)
    return a
}

struct WorkoutMatcherTests {
    @Test func shortWalkDoesNotTickTheLongRun() {
        let long = PlannedWorkout(date: day, sport: .trail, title: "Lungă", km: 18, elevation: 900)
        #expect(WorkoutMatcher.score(workout: long, activity: activity(1, "walking", km: 2, minutes: 30)) == nil)
        #expect(WorkoutMatcher.assignments(workouts: [long], activities: [activity(1, "walking", km: 2, minutes: 30)]).isEmpty)
    }

    @Test func flatRunDoesNotTickAHillWorkout() {
        let hill = PlannedWorkout(date: day, sport: .trail, title: "Tâmpa", elevation: 600)
        #expect(WorkoutMatcher.score(workout: hill, activity: activity(1, "running", km: 6, minutes: 40, gain: 30)) == nil)
        #expect(WorkoutMatcher.score(workout: hill, activity: activity(2, "trail_running", km: 6, minutes: 60, gain: 550)) != nil)
    }

    @Test func differentSportNeverMatches() {
        let swim = PlannedWorkout(date: day, sport: .swim, title: "Înot", minutes: 30)
        #expect(WorkoutMatcher.score(workout: swim, activity: activity(1, "running", km: 5, minutes: 30)) == nil)
    }

    @Test func tooShortSessionDoesNotTickGym() {
        let gym = PlannedWorkout(date: day, sport: .gym, title: "Sală", minutes: 50)
        #expect(WorkoutMatcher.score(workout: gym, activity: activity(1, "strength_training", minutes: 8)) == nil)
        #expect(WorkoutMatcher.score(workout: gym, activity: activity(2, "strength_training", minutes: 45)) != nil)
    }

    @Test func twoRunsInOneDayGoToTheRightWorkouts() {
        let easy = PlannedWorkout(date: day, sport: .run, title: "Ușoară", minutes: 45)
        let long = PlannedWorkout(date: day, sport: .trail, title: "Lungă", km: 18)
        let short5 = activity(1, "running", km: 5, minutes: 30)
        let big17 = activity(2, "trail_running", km: 17, minutes: 120)
        let pairs = WorkoutMatcher.assignments(workouts: [easy, long], activities: [short5, big17])
        #expect(pairs.count == 2)
        #expect(pairs.first { $0.0 === long }?.1.garminId == 2)
        #expect(pairs.first { $0.0 === easy }?.1.garminId == 1)
    }

    @Test func oneActivityTicksOnlyOneWorkout() {
        let a = PlannedWorkout(date: day, sport: .run, title: "A", minutes: 40)
        let b = PlannedWorkout(date: day, sport: .run, title: "B", minutes: 40)
        let pairs = WorkoutMatcher.assignments(workouts: [a, b], activities: [activity(1, "running", km: 6, minutes: 40)])
        #expect(pairs.count == 1)
    }

    @Test func respectsManualDecisions() {
        let skipped = PlannedWorkout(date: day, sport: .run, title: "Sărit", minutes: 40)
        skipped.skipped = true
        let unlinked = PlannedWorkout(date: day, sport: .run, title: "Dezlegat", minutes: 40)
        unlinked.ignoreAutoMatch = true
        let taken = PlannedWorkout(date: day, sport: .run, title: "Deja", minutes: 40)
        taken.completedActivityId = 1
        let pairs = WorkoutMatcher.assignments(workouts: [skipped, unlinked, taken],
                                               activities: [activity(1, "running", km: 6, minutes: 40)])
        #expect(pairs.isEmpty)
    }

    @Test func activityOnAnotherDayIsIgnored() {
        let w = PlannedWorkout(date: day, sport: .run, title: "Ușoară", minutes: 40)
        let other = activity(1, "running", km: 6, minutes: 40, at: Cal.addDays(1, to: day))
        #expect(WorkoutMatcher.assignments(workouts: [w], activities: [other]).isEmpty)
    }
}
