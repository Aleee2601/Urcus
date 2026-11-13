import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Pune în App Group antrenamentele următoarelor zile, pentru widgetul de pe ecranul principal (iPhone).
enum WidgetSync {
    @MainActor
    static func update(context: ModelContext, now: Date = .now) {
        #if os(iOS)
        guard let plans = try? context.fetch(FetchDescriptor<TrainingPlan>()) else { return }
        let plan = plans.first(where: \.isActive) ?? plans.first
        let today = Cal.ro.startOfDay(for: now)
        let horizon = Cal.addDays(21, to: today)

        let items = (plan?.workouts ?? [])
            .filter { $0.date >= today && $0.date < horizon && !$0.skipped && $0.sport != .rest }
            .sorted { $0.date < $1.date }
            .map { w in
                WidgetSnapshot.Item(day: WidgetSnapshot.dayKey(w.date), title: w.title, symbol: w.sport.symbol,
                                    colorHex: w.sport.hex, summary: w.targetSummary, done: w.isDone)
            }
        let snapshot = WidgetSnapshot(updatedAt: now, items: items)
        if snapshot != WidgetSnapshot.read() {
            snapshot.write()
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
