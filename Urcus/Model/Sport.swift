import SwiftUI

enum Sport: String, CaseIterable, Identifiable, Codable {
    case run, trail, hike, walk, gym, swim, bike, rest, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: "Alergare"
        case .trail: "Trail"
        case .hike: "Drumeție"
        case .walk: "Mers"
        case .gym: "Sală"
        case .swim: "Înot"
        case .bike: "Bicicletă"
        case .rest: "Odihnă"
        case .other: "Altele"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .trail: "mountain.2"
        case .hike: "figure.hiking"
        case .walk: "figure.walk"
        case .gym: "dumbbell"
        case .swim: "figure.pool.swim"
        case .bike: "bicycle"
        case .rest: "bed.double"
        case .other: "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .run: Theme.peach
        case .trail: Theme.sage
        case .hike: Theme.sand
        case .walk: Color(hex: 0xC9D6A0)
        case .gym: Theme.plum
        case .swim: Theme.sky
        case .bike: Theme.teal
        case .rest: Theme.muted
        case .other: Theme.muted
        }
    }

    /// Sporturi la care are sens să afișăm ritmul (min/km) în loc de viteză.
    var usesPace: Bool { [.run, .trail, .hike, .walk].contains(self) }

    /// Transformă `activityType.typeKey` din Garmin într-o categorie de-a noastră.
    static func from(garminTypeKey key: String) -> Sport {
        let k = key.lowercased()
        if k.contains("trail") { return .trail }
        if k.contains("run") { return .run }
        if k.contains("hik") || k.contains("mountaineer") { return .hike }
        if k.contains("walk") { return .walk }
        if k.contains("swim") { return .swim }
        if k.contains("cycl") || k.contains("bik") { return .bike }
        if ["strength", "cardio", "fitness", "hiit", "yoga", "pilates", "training"].contains(where: { k.contains($0) }) {
            return .gym
        }
        return .other
    }

    /// Dacă o activitate de tipul `other` poate „bifa” un antrenament planificat de tipul `self`.
    func matches(_ other: Sport) -> Bool {
        if self == other { return true }
        let groups: [Set<Sport>] = [[.run, .trail], [.hike, .walk, .trail]]
        return groups.contains { $0.contains(self) && $0.contains(other) }
    }
}

enum Intensity: String, CaseIterable, Identifiable {
    case easy, moderate, hard, race

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: "Ușor"
        case .moderate: "Moderat"
        case .hard: "Intens"
        case .race: "Cursă"
        }
    }
}
