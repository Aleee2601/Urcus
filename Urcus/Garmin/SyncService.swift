import Foundation
import SwiftData

@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published var message: String?
    @Published var errorMessage: String?

    private let lastSyncKey = "lastGarminSync"

    var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set {
            UserDefaults.standard.set(newValue, forKey: lastSyncKey)
            objectWillChange.send()
        }
    }

    var hasKey: Bool { KeychainStore.get(KeychainStore.apiKeyAccount) != nil }

    /// Sincronizează doar dacă ultima sincronizare e mai veche de 30 de minute.
    func syncIfStale(context: ModelContext) async {
        guard hasKey, UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true else { return }
        if let last = lastSync, Date().timeIntervalSince(last) < 30 * 60 { return }
        await sync(context: context)
    }

    func resetAndFullSync(context: ModelContext, days: Int) async {
        lastSync = nil
        await sync(context: context, historyDays: days)
    }

    func sync(context: ModelContext, historyDays: Int = 365) async {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        message = nil
        defer { isSyncing = false }

        let now = Date()
        // Reluăm ultimele 3 zile ca să prindem activitățile sincronizate mai târziu de pe ceas.
        let since = lastSync.map { $0.addingTimeInterval(-3 * 86_400) }
            ?? Cal.addDays(-historyDays, to: now)

        do {
            let limit = 50
            var start = 0
            var newCount = 0
            var total = 0
            for _ in 0..<80 {
                let page = try await GarminClient.shared.searchActivities(
                    start: start, limit: limit, startDate: since, endDate: now)
                for dto in page {
                    if try upsert(dto, context: context) { newCount += 1 }
                    total += 1
                }
                if page.count < limit { break }
                start += limit
            }
            WorkoutMatcher.match(context: context)
            try context.save()
            lastSync = now
            message = newCount == 0
                ? "Totul e la zi (\(total) activități verificate)."
                : "Am adus \(newCount) activități noi."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adaugă sau actualizează o activitate. Întoarce `true` dacă e nouă.
    private func upsert(_ dto: GarminActivityDTO, context: ModelContext) throws -> Bool {
        guard let date = dto.startDate else { return false }
        let id = dto.activityId
        var descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate<ActivityRecord> { $0.garminId == id })
        descriptor.fetchLimit = 1

        let record: ActivityRecord
        var isNew = false
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = ActivityRecord(garminId: id, name: "", typeKey: "", startDate: date)
            context.insert(record)
            isNew = true
        }

        record.name = dto.activityName ?? "Activitate"
        record.typeKey = dto.activityType?.typeKey ?? "other"
        record.startDate = date
        record.distanceMeters = dto.distance ?? 0
        record.durationSeconds = dto.duration ?? 0
        record.movingSeconds = dto.movingDuration
        record.elevationGain = dto.elevationGain ?? 0
        record.elevationLoss = dto.elevationLoss
        record.averageHR = dto.averageHR
        record.maxHR = dto.maxHR
        record.calories = dto.calories
        record.averageSpeed = dto.averageSpeed
        record.locationName = dto.locationName
        record.zoneSeconds = dto.zoneSeconds
        return isNew
    }
}

/// Bifează automat antrenamentele planificate cu activitățile din aceeași zi.
enum WorkoutMatcher {
    @MainActor
    static func match(context: ModelContext) {
        guard let workouts = try? context.fetch(FetchDescriptor<PlannedWorkout>()),
              let activities = try? context.fetch(FetchDescriptor<ActivityRecord>()) else { return }

        var used = Set(workouts.compactMap(\.completedActivityId))
        let byDay = Dictionary(grouping: activities) { Cal.ro.startOfDay(for: $0.startDate) }

        for workout in workouts.sorted(by: { $0.date < $1.date })
        where workout.completedActivityId == nil && !workout.skipped && !workout.ignoreAutoMatch && workout.sport != .rest {
            let day = Cal.ro.startOfDay(for: workout.date)
            guard let candidates = byDay[day] else { continue }
            let best = candidates
                .filter { !used.contains($0.garminId) && $0.sport.matches(workout.sport) }
                .max { $0.durationSeconds < $1.durationSeconds }
            if let best {
                workout.completedActivityId = best.garminId
                used.insert(best.garminId)
            }
        }
    }
}
