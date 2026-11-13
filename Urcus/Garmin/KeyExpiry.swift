import Foundation
import UserNotifications

/// Cât mai e valabilă cheia Garmin și când te avertizăm.
enum KeyExpiry {
    enum Status: Equatable {
        case unknown
        case ok(days: Int)
        case soon(days: Int)   // în ultimele 14 zile
        case expired

        var needsAttention: Bool {
            switch self {
            case .soon, .expired: true
            default: false
            }
        }
    }

    static let warnDays = 14

    /// `expiry` e `timeIntervalSince1970`, cu 0 = necunoscut (cum e salvat în AppStorage).
    static func status(expiry: Double, now: Date = .now) -> Status {
        guard expiry > 0 else { return .unknown }
        let today = Cal.ro.startOfDay(for: now)
        let day = Cal.ro.startOfDay(for: Date(timeIntervalSince1970: expiry))
        let days = Cal.ro.dateComponents([.day], from: today, to: day).day ?? 0
        if days < 0 { return .expired }
        return days <= warnDays ? .soon(days: days) : .ok(days: days)
    }

    static func message(for status: Status) -> String? {
        switch status {
        case .expired:
            return "Cheia Garmin a expirat. Creează una nouă pe connect.garmin.com și pune-o în Setări."
        case .soon(let days):
            return days == 0
                ? "Cheia Garmin expiră azi. Creează una nouă pe connect.garmin.com."
                : "Cheia Garmin expiră în \(days) \(days == 1 ? "zi" : "zile"). Creează una nouă pe connect.garmin.com."
        default:
            return nil
        }
    }

    // MARK: Notificări locale

    private static let ids = ["urcus.keyExpiry.14", "urcus.keyExpiry.3"]

    /// Programează două mementouri (cu 14 și cu 3 zile înainte), la ora 10.
    static func scheduleReminders(expiry: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            for (id, before) in zip(ids, [14, 3]) {
                guard let when = Cal.ro.date(byAdding: .day, value: -before, to: Cal.ro.startOfDay(for: expiry)),
                      let at = Cal.ro.date(bySettingHour: 10, minute: 0, second: 0, of: when),
                      at > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Cheia Garmin expiră curând"
                content.body = "Mai sunt \(before) zile. Creează una nouă ca sincronizarea să nu se oprească."
                let parts = Cal.ro.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    static func cancelReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
