import Foundation

// Client pentru Garmin Connect Personal API.
// Flux: cheia personală → POST la endpoint-ul de token → JWT valabil 24h → cereri GET cu Bearer.
// Endpoint-urile sunt cele din clientul oficial Garmin (garmin-connect-personal-api-python 1.0.0).

enum GarminError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Nu ai salvat cheia Garmin. Mergi în Setări."
        case .http(let code, let body):
            if code == 401 || code == 403 {
                return "Garmin a refuzat cheia (\(code)). Verifică dacă e corectă și dacă n-a expirat."
            }
            if code == 429 { return "Prea multe cereri către Garmin. Încearcă din nou peste câteva minute." }
            return "Eroare Garmin \(code): \(body.prefix(200))"
        case .badResponse:
            return "Garmin a trimis un răspuns pe care nu l-am putut citi."
        }
    }
}

struct GarminActivityDTO: Decodable {
    struct ActivityType: Decodable { let typeKey: String? }

    let activityId: Int
    let activityName: String?
    let startTimeLocal: String?
    let startTimeGMT: String?
    let beginTimestamp: Double?
    let activityType: ActivityType?
    let distance: Double?
    let duration: Double?
    let movingDuration: Double?
    let elevationGain: Double?
    let elevationLoss: Double?
    let averageHR: Double?
    let maxHR: Double?
    let calories: Double?
    let averageSpeed: Double?
    let locationName: String?
    let hrTimeInZone_1: Double?
    let hrTimeInZone_2: Double?
    let hrTimeInZone_3: Double?
    let hrTimeInZone_4: Double?
    let hrTimeInZone_5: Double?

    var zoneSeconds: [Double]? {
        let zones = [hrTimeInZone_1, hrTimeInZone_2, hrTimeInZone_3, hrTimeInZone_4, hrTimeInZone_5]
        guard zones.contains(where: { ($0 ?? 0) > 0 }) else { return nil }
        return zones.map { $0 ?? 0 }
    }

    var startDate: Date? {
        if let g = startTimeGMT, let d = Self.parse(g, timeZone: TimeZone(identifier: "UTC")!) { return d }
        if let ms = beginTimestamp { return Date(timeIntervalSince1970: ms / 1000) }
        if let l = startTimeLocal, let d = Self.parse(l, timeZone: .current) { return d }
        return nil
    }

    static func parse(_ text: String, timeZone: TimeZone) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss.S", "yyyy-MM-dd'T'HH:mm:ss.S"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}

/// Decodează fiecare element separat, ca o singură activitate ciudată să nu strice toată lista.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

actor GarminClient {
    static let shared = GarminClient()

    private let baseURL = "https://personal.connectapi.garmin.com"
    private let tokenPath = "/personalapitoken-service/personal-api/personal-api-key/token"
    private var token: String?
    private var tokenExpiry = Date.distantPast
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func forgetToken() {
        token = nil
        tokenExpiry = .distantPast
    }

    /// Verifică dacă cheia e bună (cere un token nou).
    func testConnection() async throws {
        forgetToken()
        _ = try await accessToken(force: true)
    }

    func searchActivities(start: Int, limit: Int, startDate: Date?, endDate: Date?) async throws -> [GarminActivityDTO] {
        var query = ["start": String(start), "limit": String(limit)]
        if let startDate { query["startDate"] = Fmt.isoDay(startDate) }
        if let endDate { query["endDate"] = Fmt.isoDay(endDate) }
        let data = try await get("/activitylist-service/activities/search/activities", query: query)
        return try Self.decodeActivityList(data)
    }

    /// Răspunsul brut, formatat frumos (pentru exploratorul de date).
    func prettyJSON(_ path: String, query: [String: String] = [:]) async throws -> String {
        let data = try await get(path, query: query)
        guard !data.isEmpty else { return "(răspuns gol)" }
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: pretty, as: UTF8.self)
        }
        return String(decoding: data, as: UTF8.self)
    }

    func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(string: baseURL + path)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw GarminError.badResponse }

        for attempt in 0..<2 {
            let bearer = try await accessToken(force: attempt > 0)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401, attempt == 0 {
                continue // tokenul a expirat între timp — mai încercăm o dată cu unul nou
            }
            try Self.check(response, data)
            return data
        }
        throw GarminError.badResponse
    }

    private func accessToken(force: Bool) async throws -> String {
        if !force, let token, tokenExpiry.timeIntervalSinceNow > 3600 { return token }

        guard let key = KeychainStore.get(KeychainStore.apiKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw GarminError.missingKey
        }
        guard let url = URL(string: baseURL + tokenPath) else { throw GarminError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("ApiKey \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)

        let newToken = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newToken.isEmpty else { throw GarminError.badResponse }
        token = newToken
        tokenExpiry = Self.jwtExpiry(newToken) ?? Date().addingTimeInterval(20 * 3600)
        return newToken
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GarminError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GarminError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    private static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (payload["exp"] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func decodeActivityList(_ data: Data) throws -> [GarminActivityDTO] {
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([Lenient<GarminActivityDTO>].self, from: data) {
            return list.compactMap(\.value)
        }
        // Dacă lista vine împachetată într-un obiect, căutăm primul array din el.
        if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for value in dict.values {
                if let array = value as? [Any],
                   let sub = try? JSONSerialization.data(withJSONObject: array),
                   let list = try? decoder.decode([Lenient<GarminActivityDTO>].self, from: sub) {
                    return list.compactMap(\.value)
                }
            }
        }
        throw GarminError.badResponse
    }
}
