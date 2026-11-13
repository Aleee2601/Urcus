import SwiftUI

/// „Cât de odihnită ești azi”, din somn, HRV și Body Battery.
/// Câmpurile sunt căutate după numele obișnuite din Garmin Connect; dacă nu găsim nimic, cardul nu apare.
struct Readiness: Codable, Equatable {
    var sleepScore: Double?
    var sleepHours: Double?
    var hrvLastNight: Double?
    var hrvStatus: String?
    var bodyBattery: Double?

    enum Level: String { case good, moderate, poor }

    var hasData: Bool { signals.count > 0 }

    /// Fiecare semnal valorează 2 (bine), 1 (mediu) sau 0 (slab).
    private var signals: [Int] {
        var s: [Int] = []
        if let score = sleepScore { s.append(score >= 70 ? 2 : score >= 50 ? 1 : 0) }
        else if let h = sleepHours { s.append(h >= 7 ? 2 : h >= 6 ? 1 : 0) }
        if let status = hrvStatus?.uppercased() {
            s.append(status == "BALANCED" ? 2 : status == "UNBALANCED" ? 1 : 0)
        }
        if let bb = bodyBattery { s.append(bb >= 60 ? 2 : bb >= 35 ? 1 : 0) }
        return s
    }

    var level: Level? {
        let s = signals
        guard !s.isEmpty else { return nil }
        let avg = Double(s.reduce(0, +)) / Double(s.count)
        return avg >= 1.5 ? .good : avg >= 0.8 ? .moderate : .poor
    }

    var headline: String {
        switch level {
        case .good: "Ești refăcută — zi bună de antrenament"
        case .moderate: "Refacere medie — ascultă-ți corpul"
        case .poor: "Refacere slabă — ia-o ușor azi"
        case nil: ""
        }
    }

    var details: [String] {
        var d: [String] = []
        if let score = sleepScore { d.append("Somn \(Int(score.rounded()))") }
        else if let h = sleepHours { d.append("Somn \(Fmt.number(h)) h") }
        if let hrv = hrvLastNight { d.append("HRV \(Int(hrv.rounded())) ms") }
        else if let st = hrvStatus { d.append("HRV \(st.lowercased())") }
        if let bb = bodyBattery { d.append("Body Battery \(Int(bb.rounded()))") }
        return d
    }
}

enum ReadinessParser {
    static func parse(sleep: Data?, hrv: Data?, battery: Data?) -> Readiness {
        var r = Readiness()
        if let json = object(sleep) {
            r.sleepScore = number(in: json, path: ["overall", "value"]) ?? number(in: json, keys: ["overallScore"])
            if let secs = number(in: json, keys: ["sleepTimeSeconds"]) { r.sleepHours = secs / 3600 }
        }
        if let json = object(hrv) {
            r.hrvLastNight = number(in: json, keys: ["lastNightAvg"])
            r.hrvStatus = string(in: json, keys: ["status"])
        }
        if let json = object(battery) {
            r.bodyBattery = maxBatteryValue(json) ?? number(in: json, keys: ["bodyBatteryMostRecentValue"])
        }
        return r
    }

    private static func object(_ data: Data?) -> Any? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Primul număr găsit sub una dintre chei, căutând în adâncime.
    static func number(in json: Any, keys: [String]) -> Double? {
        find(json) { dict in
            for k in keys { if let n = (dict[k] as? NSNumber)?.doubleValue, !(dict[k] is Bool) { return n } }
            return nil
        }
    }

    /// Ca mai sus, dar valoarea e cea din interiorul cheii `path[0]` → `path[1]` (ex. overall → value).
    static func number(in json: Any, path: [String]) -> Double? {
        guard path.count == 2 else { return nil }
        return find(json) { dict in
            ((dict[path[0]] as? [String: Any])?[path[1]] as? NSNumber)?.doubleValue
        }
    }

    static func string(in json: Any, keys: [String]) -> String? {
        find(json) { dict in
            for k in keys { if let s = dict[k] as? String, !s.isEmpty { return s } }
            return nil
        }
    }

    private static func find<T>(_ json: Any, _ pick: ([String: Any]) -> T?) -> T? {
        if let dict = json as? [String: Any] {
            if let v = pick(dict) { return v }
            for value in dict.values { if let v = find(value, pick) { return v } }
        } else if let array = json as? [Any] {
            for item in array { if let v = find(item, pick) { return v } }
        }
        return nil
    }

    /// `bodyBatteryValuesArray` = [[timestamp, valoare], …]; luăm cea mai mare valoare a zilei.
    private static func maxBatteryValue(_ json: Any) -> Double? {
        let array: [Any]? = find(json) { $0["bodyBatteryValuesArray"] as? [Any] }
        let values = (array ?? []).compactMap { ($0 as? [Any]).flatMap { $0.count > 1 ? ($0[1] as? NSNumber)?.doubleValue : nil } }
        return values.max()
    }
}

@MainActor
final class ReadinessService: ObservableObject {
    @Published private(set) var readiness: Readiness?
    private let cacheKey = "readinessCache"
    private var lastFetch = Date.distantPast

    init() { readiness = loadCache() }

    func refresh() async {
        guard KeychainStore.get(KeychainStore.apiKeyAccount) != nil,
              Date().timeIntervalSince(lastFetch) > 30 * 60 else { return }
        lastFetch = Date()
        async let sleep = fetch(.sleep)
        async let hrv = fetch(.hrv)
        async let battery = fetch(.bodyBattery)
        let result = ReadinessParser.parse(sleep: await sleep, hrv: await hrv, battery: await battery)
        if result.hasData {
            readiness = result
            saveCache(result)
        }
    }

    private func fetch(_ e: ApiExplorerCard.Endpoint) async -> Data? {
        let req = e.request(for: .now)
        return try? await GarminClient.shared.get(req.path, query: req.query)
    }

    private struct Cached: Codable { var day: String; var value: Readiness }

    private func loadCache() -> Readiness? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let c = try? JSONDecoder().decode(Cached.self, from: data),
              c.day == Fmt.isoDay(.now) else { return nil }
        return c.value
    }

    private func saveCache(_ r: Readiness) {
        if let data = try? JSONEncoder().encode(Cached(day: Fmt.isoDay(.now), value: r)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

struct ReadinessCard: View {
    let readiness: Readiness

    private var color: Color {
        switch readiness.level {
        case .good: Theme.sage
        case .moderate: Theme.sand
        case .poor: Theme.coral
        case nil: Theme.muted
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(color).frame(width: 12, height: 12).padding(.top, 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(readiness.headline).appFont(15, .heavy).foregroundStyle(Theme.text)
                Text(readiness.details.joined(separator: " · "))
                    .appFont(13, .semibold).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18, fill: color.opacity(0.07), stroke: color.opacity(0.25))
        .accessibilityElement(children: .combine)
    }
}
