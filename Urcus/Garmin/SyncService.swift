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
/// O activitate bifează un antrenament doar dacă seamănă cu ținta lui (distanță, urcare, durată),
/// ca o plimbare de 2 km să nu bifeze tura lungă de 18 km.
enum WorkoutMatcher {
    /// Cât din țintă trebuie atins ca activitatea să fie considerată potrivită.
    static let minFraction = 0.4

    /// Scor de potrivire între 0 și 1, sau `nil` dacă activitatea nu poate bifa antrenamentul.
    static func score(workout: PlannedWorkout, activity: ActivityRecord) -> Double? {
        guard activity.sport.matches(workout.sport) else { return nil }

        var ratios: [Double] = []
        if let km = workout.targetDistanceKm, km > 0 { ratios.append(activity.distanceKm / km) }
        if let e = workout.targetElevation, e >= 150 { ratios.append(activity.elevationGain / Double(e)) }
        if let m = workout.targetDurationMin, m > 0 { ratios.append(activity.durationSeconds / 60 / Double(m)) }

        if ratios.contains(where: { $0 < minFraction }) { return nil }

        // Cu cât activitatea e mai aproape de țintă (în ambele sensuri), cu atât scorul e mai mare.
        let closeness = ratios.isEmpty ? 0.5 : ratios.map { min($0, 1 / $0) }.reduce(0, +) / Double(ratios.count)
        let sameSport = activity.sport == workout.sport ? 1.0 : 0.6
        return sameSport * 0.5 + closeness * 0.5
    }

    /// Perechi (antrenament, activitate) alese greedy pe scor, câte o activitate la un antrenament.
    static func assignments(workouts: [PlannedWorkout], activities: [ActivityRecord]) -> [(PlannedWorkout, ActivityRecord)] {
        var used = Set(workouts.compactMap(\.completedActivityId))
        let byDay = Dictionary(grouping: activities) { Cal.ro.startOfDay(for: $0.startDate) }
        let open = workouts.filter {
            $0.completedActivityId == nil && !$0.skipped && !$0.ignoreAutoMatch && $0.sport != .rest
        }

        var pairs: [(w: PlannedWorkout, a: ActivityRecord, score: Double)] = []
        for w in open {
            for a in byDay[Cal.ro.startOfDay(for: w.date)] ?? [] where !used.contains(a.garminId) {
                if let s = score(workout: w, activity: a) { pairs.append((w, a, s)) }
            }
        }
        pairs.sort { $0.score != $1.score ? $0.score > $1.score : $0.w.date < $1.w.date }

        var done = Set<ObjectIdentifier>()
        var result: [(PlannedWorkout, ActivityRecord)] = []
        for p in pairs where !used.contains(p.a.garminId) && !done.contains(ObjectIdentifier(p.w)) {
            used.insert(p.a.garminId)
            done.insert(ObjectIdentifier(p.w))
            result.append((p.w, p.a))
        }
        return result
    }

    @MainActor
    static func match(context: ModelContext) {
        guard let workouts = try? context.fetch(FetchDescriptor<PlannedWorkout>()),
              let activities = try? context.fetch(FetchDescriptor<ActivityRecord>()) else { return }
        for (workout, activity) in assignments(workouts: workouts, activities: activities) {
            workout.completedActivityId = activity.garminId
        }
    }
}
