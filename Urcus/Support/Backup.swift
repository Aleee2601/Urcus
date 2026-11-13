import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Copie de siguranță a planurilor tale (activitățile se readuc din Garmin).
struct BackupFile: Codable {
    struct Workout: Codable {
        var date: Date
        var sportRaw: String
        var title: String
        var details: String
        var targetDistanceKm: Double?
        var targetDurationMin: Int?
        var targetElevation: Int?
        var intensityRaw: String
        var completedActivityId: Int?
        var manuallyDone: Bool
        var skipped: Bool
        var ignoreAutoMatch: Bool
    }

    struct Plan: Codable {
        var name: String
        var goal: String
        var startDate: Date
        var endDate: Date
        var isActive: Bool
        var createdAt: Date
        var optionsData: Data?
        var workouts: [Workout]
    }

    var version = 1
    var exportedAt = Date()
    var plans: [Plan]
}

enum BackupService {
    @MainActor
    static func export(context: ModelContext) throws -> Data {
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\.createdAt)]))
        let file = BackupFile(plans: plans.map { plan in
            BackupFile.Plan(
                name: plan.name, goal: plan.goal, startDate: plan.startDate, endDate: plan.endDate,
                isActive: plan.isActive, createdAt: plan.createdAt, optionsData: plan.optionsData,
                workouts: plan.workouts.sorted { $0.date < $1.date }.map { w in
                    BackupFile.Workout(
                        date: w.date, sportRaw: w.sportRaw, title: w.title, details: w.details,
                        targetDistanceKm: w.targetDistanceKm, targetDurationMin: w.targetDurationMin,
                        targetElevation: w.targetElevation, intensityRaw: w.intensityRaw,
                        completedActivityId: w.completedActivityId, manuallyDone: w.manuallyDone,
                        skipped: w.skipped, ignoreAutoMatch: w.ignoreAutoMatch)
                })
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Adaugă planurile din copie. Un plan care există deja (același nume și aceeași dată de creare) e sărit.
    /// Întoarce câte planuri noi s-au adăugat.
    @MainActor
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        let existing = try context.fetch(FetchDescriptor<TrainingPlan>())
        var added = 0
        for p in file.plans {
            if existing.contains(where: { $0.name == p.name && abs($0.createdAt.timeIntervalSince(p.createdAt)) < 1 }) { continue }
            let plan = TrainingPlan(name: p.name, goal: p.goal, startDate: p.startDate, endDate: p.endDate, isActive: false)
            plan.createdAt = p.createdAt
            plan.optionsData = p.optionsData
            context.insert(plan)
            for w in p.workouts {
                let workout = PlannedWorkout(date: w.date, sport: Sport(rawValue: w.sportRaw) ?? .other, title: w.title,
                                             details: w.details, km: w.targetDistanceKm, minutes: w.targetDurationMin,
                                             elevation: w.targetElevation, intensity: Intensity(rawValue: w.intensityRaw) ?? .easy)
                workout.completedActivityId = w.completedActivityId
                workout.manuallyDone = w.manuallyDone
                workout.skipped = w.skipped
                workout.ignoreAutoMatch = w.ignoreAutoMatch
                context.insert(workout)
                workout.plan = plan
            }
            added += 1
        }
        // Dacă nu e niciun plan activ, îl activăm pe cel mai recent.
        let all = try context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        if !all.contains(where: \.isActive) { all.first?.isActive = true }
        try context.save()
        return added
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
