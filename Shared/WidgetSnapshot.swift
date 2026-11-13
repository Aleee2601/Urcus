import Foundation

/// Ce are nevoie widgetul să știe despre plan. Aplicația îl scrie într-un fișier din App Group,
/// widgetul îl citește. Fișierul e compilat și în aplicație, și în extensia widget.
struct WidgetSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        var day: String          // yyyy-MM-dd
        var title: String
        var symbol: String       // nume SF Symbol
        var colorHex: UInt32
        var summary: String      // „18 km · D+ 1100 m”
        var done: Bool
    }

    var updatedAt: Date
    var items: [Item]            // următoarele zile cu antrenamente, în ordine

    static let groupID = "group.ro.alexandra.urcus"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func write() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Antrenamentele zilei `date`, iar dacă nu sunt, primul antrenament care urmează.
    func today(_ date: Date) -> (items: [Item], next: Item?) {
        let key = Self.dayKey(date)
        let todays = items.filter { $0.day == key }
        let next = items.first { $0.day > key }
        return (todays, next)
    }
}
