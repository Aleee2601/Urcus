import Testing
import Foundation
import SwiftData
@testable import Urcus

struct KeyExpiryTests {
    private let now = Cal.ro.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 15))!
    private func expiry(inDays d: Int) -> Double { Cal.addDays(d, to: now).timeIntervalSince1970 }

    @Test func statuses() {
        #expect(KeyExpiry.status(expiry: 0, now: now) == .unknown)
        #expect(KeyExpiry.status(expiry: expiry(inDays: -1), now: now) == .expired)
        #expect(KeyExpiry.status(expiry: expiry(inDays: 0), now: now) == .soon(days: 0))
        #expect(KeyExpiry.status(expiry: expiry(inDays: 14), now: now) == .soon(days: 14))
        #expect(KeyExpiry.status(expiry: expiry(inDays: 15), now: now) == .ok(days: 15))
    }

    @Test func onlyWarnsWhenNeeded() {
        #expect(KeyExpiry.message(for: .ok(days: 200)) == nil)
        #expect(KeyExpiry.message(for: .unknown) == nil)
        #expect(KeyExpiry.message(for: .soon(days: 1))?.contains("1 zi") == true)
        #expect(KeyExpiry.message(for: .expired)?.contains("expirat") == true)
    }
}

struct ReadinessTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func parsesTheUsualGarminShapes() {
        let sleep = data(#"{"dailySleepDTO":{"sleepTimeSeconds":27000,"sleepScores":{"overall":{"value":82,"qualifierKey":"GOOD"}}}}"#)
        let hrv = data(#"{"hrvSummary":{"lastNightAvg":54,"status":"BALANCED"}}"#)
        let battery = data(#"[{"bodyBatteryValuesArray":[[1,40],[2,78],[3,65]]}]"#)
        let r = ReadinessParser.parse(sleep: sleep, hrv: hrv, battery: battery)
        #expect(r.sleepScore == 82)
        #expect(r.sleepHours == 7.5)
        #expect(r.hrvLastNight == 54)
        #expect(r.hrvStatus == "BALANCED")
        #expect(r.bodyBattery == 78)
        #expect(r.level == .good)
    }

    @Test func poorSignalsGiveRedLevel() {
        let r = Readiness(sleepScore: 38, sleepHours: nil, hrvLastNight: 30, hrvStatus: "LOW", bodyBattery: 20)
        #expect(r.level == .poor)
    }

    @Test func mixedSignalsGiveModerate() {
        let r = Readiness(sleepScore: 75, sleepHours: nil, hrvLastNight: nil, hrvStatus: "UNBALANCED", bodyBattery: 30)
        #expect(r.level == .moderate)
    }

    @Test func unknownOrEmptyDataMeansNoCard() {
        let r = ReadinessParser.parse(sleep: data("{}"), hrv: nil, battery: data("garbage"))
        #expect(!r.hasData)
        #expect(r.level == nil)
    }

    @Test func fallsBackToSleepHoursWithoutScore() {
        #expect(Readiness(sleepHours: 5).level == .poor)
        #expect(Readiness(sleepHours: 8).level == .good)
    }
}

struct BackupTests {
    @Test @MainActor func exportAndRestoreRoundTrip() throws {
        let schema: [any PersistentModel.Type] = [ActivityRecord.self, TrainingPlan.self, PlannedWorkout.self]
        let source = try ModelContainer(for: Schema(schema), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var o = PlanOptions()
        o.name = "Zănoaga"
        o.hillName = "Cozla"
        let plan = PlanGenerator.create(o, in: source.mainContext)
        let edited = plan.workouts.sorted { $0.date < $1.date }[1]
        edited.title = "Editat de mine"
        edited.skipped = true
        let count = plan.workouts.count
        let data = try BackupService.export(context: source.mainContext)

        let target = try ModelContainer(for: Schema(schema), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #expect(try BackupService.restore(data, into: target.mainContext) == 1)
        let restored = try target.mainContext.fetch(FetchDescriptor<TrainingPlan>())
        #expect(restored.count == 1)
        #expect(restored[0].name == "Zănoaga")
        #expect(restored[0].isActive)
        #expect(restored[0].workouts.count == count)
        #expect(restored[0].workouts.contains { $0.title == "Editat de mine" && $0.skipped })
        #expect(PlanGenerator.options(for: restored[0]).hillName == "Cozla")

        // A doua importare nu dublează planul.
        #expect(try BackupService.restore(data, into: target.mainContext) == 0)
        #expect(try target.mainContext.fetch(FetchDescriptor<TrainingPlan>()).count == 1)
    }

    @Test @MainActor func garbageFileThrows() throws {
        let container = try ModelContainer(for: ActivityRecord.self, TrainingPlan.self, PlannedWorkout.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #expect(throws: (any Error).self) { try BackupService.restore(Data("nu e json".utf8), into: container.mainContext) }
    }
}
