import Foundation

enum Cal {
    /// Calendar românesc: săptămâna începe luni.
    static let ro: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ro_RO")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    static func startOfWeek(_ date: Date) -> Date {
        ro.dateInterval(of: .weekOfYear, for: date)?.start ?? ro.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date) -> Date {
        ro.dateInterval(of: .month, for: date)?.start ?? ro.startOfDay(for: date)
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        ro.date(byAdding: .day, value: days, to: date) ?? date
    }
}

enum Fmt {
    static let locale = Locale(identifier: "ro_RO")

    static func number(_ value: Double, decimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)).locale(locale))
    }

    static func km(_ value: Double) -> String { "\(number(value)) km" }

    static func meters(_ value: Double) -> String { "\(Int(value.rounded())) m" }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        return "\(m) min"
    }

    /// Ritm în min/km.
    static func pace(seconds: Double, km: Double) -> String {
        guard km > 0.05 else { return "–" }
        let perKm = Int((seconds / km).rounded())
        return "\(perKm / 60):\(String(format: "%02d", perKm % 60)) /km"
    }

    static func speed(metersPerSecond: Double) -> String {
        "\(number(metersPerSecond * 3.6)) km/h"
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    static func weekdayShort(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().locale(locale))
    }

    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized(with: locale)
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    /// Data în formatul cerut de Garmin (yyyy-MM-dd), în fusul orar local.
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func parseNumber(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }
}
