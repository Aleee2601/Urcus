import Foundation
import SwiftData

/// O activitate adusă din Garmin Connect.
@Model
final class ActivityRecord {
    @Attribute(.unique) var garminId: Int
    var name: String
    var typeKey: String
    var startDate: Date
    var distanceMeters: Double
    var durationSeconds: Double
    var movingSeconds: Double?
    var elevationGain: Double
    var elevationLoss: Double?
    var averageHR: Double?
    var maxHR: Double?
    var calories: Double?
    var averageSpeed: Double?
    var locationName: String?
    /// Secunde în zonele de puls 1–5, dacă Garmin le trimite.
    var zoneSeconds: [Double]?

    init(garminId: Int, name: String, typeKey: String, startDate: Date,
         distanceMeters: Double = 0, durationSeconds: Double = 0, elevationGain: Double = 0) {
        self.garminId = garminId
        self.name = name
        self.typeKey = typeKey
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.elevationGain = elevationGain
    }

    var sport: Sport { Sport.from(garminTypeKey: typeKey) }
    var distanceKm: Double { distanceMeters / 1000 }
    var garminURL: URL? { URL(string: "https://connect.garmin.com/modern/activity/\(garminId)") }
}

@Model
final class TrainingPlan {
    var name: String
    var goal: String
    var startDate: Date
    var endDate: Date
    var isActive: Bool
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PlannedWorkout.plan)
    var workouts: [PlannedWorkout] = []

    init(name: String, goal: String, startDate: Date, endDate: Date, isActive: Bool = true) {
        self.name = name
        self.goal = goal
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.createdAt = .now
    }
}

@Model
final class PlannedWorkout {
    var date: Date
    var sportRaw: String
    var title: String
    var details: String
    var targetDistanceKm: Double?
    var targetDurationMin: Int?
    var targetElevation: Int?
    var intensityRaw: String
    /// Activitatea Garmin care a bifat antrenamentul (potrivită automat sau manual).
    var completedActivityId: Int?
    var manuallyDone: Bool
    var skipped: Bool
    /// Dacă ai dezlegat manual o activitate, nu o mai potrivim automat.
    var ignoreAutoMatch: Bool
    var plan: TrainingPlan?

    init(date: Date, sport: Sport, title: String, details: String = "",
         km: Double? = nil, minutes: Int? = nil, elevation: Int? = nil,
         intensity: Intensity = .easy) {
        self.date = date
        self.sportRaw = sport.rawValue
        self.title = title
        self.details = details
        self.targetDistanceKm = km
        self.targetDurationMin = minutes
        self.targetElevation = elevation
        self.intensityRaw = intensity.rawValue
        self.manuallyDone = false
        self.skipped = false
        self.ignoreAutoMatch = false
    }

    var sport: Sport {
        get { Sport(rawValue: sportRaw) ?? .other }
        set { sportRaw = newValue.rawValue }
    }

    var intensity: Intensity {
        get { Intensity(rawValue: intensityRaw) ?? .easy }
        set { intensityRaw = newValue.rawValue }
    }

    var isDone: Bool { completedActivityId != nil || manuallyDone }

    var status: WorkoutStatus {
        if isDone { return .done }
        if skipped { return .skipped }
        let today = Cal.ro.startOfDay(for: .now)
        let day = Cal.ro.startOfDay(for: date)
        if day < today { return .missed }
        if day == today { return .today }
        return .upcoming
    }

    var targetSummary: String {
        var parts: [String] = []
        if let km = targetDistanceKm, km > 0 { parts.append(Fmt.km(km)) }
        if let m = targetDurationMin, m > 0 { parts.append("\(m) min") }
        if let e = targetElevation, e > 0 { parts.append("D+ \(e) m") }
        return parts.joined(separator: " · ")
    }
}

enum WorkoutStatus {
    case done, skipped, missed, today, upcoming

    var symbol: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .missed: "exclamationmark.circle"
        case .today: "circle.dashed"
        case .upcoming: "circle"
        }
    }

    var label: String {
        switch self {
        case .done: "Făcut"
        case .skipped: "Sărit"
        case .missed: "Ratat"
        case .today: "Azi"
        case .upcoming: "Urmează"
        }
    }
}
