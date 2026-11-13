import WidgetKit
import SwiftUI

private let bg = Color(red: 14/255, green: 21/255, blue: 18/255)
private let text = Color(red: 238/255, green: 241/255, blue: 236/255)
private let muted = Color(red: 154/255, green: 168/255, blue: 161/255)
private let peach = Color(red: 242/255, green: 180/255, blue: 140/255)
private let sage = Color(red: 127/255, green: 203/255, blue: 164/255)

struct DayEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshot.Item]
    let next: WidgetSnapshot.Item?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, items: [.init(day: WidgetSnapshot.dayKey(.now), title: "Alergare ușoară",
                                           symbol: "figure.run", colorHex: 0xF2B48C, summary: "45 min", done: false)], next: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        // O intrare pentru azi și una pentru fiecare zi următoare, schimbate la miezul nopții.
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        var entries = [entry(for: .now)]
        for offset in 1...7 {
            if let d = cal.date(byAdding: .day, value: offset, to: start) { entries.append(entry(for: d)) }
        }
        completion(Timeline(entries: entries, policy: .after(cal.date(byAdding: .hour, value: 6, to: .now) ?? .now)))
    }

    private func entry(for date: Date) -> DayEntry {
        let t = WidgetSnapshot.read()?.today(date)
        return DayEntry(date: date, items: t?.items ?? [], next: t?.next)
    }
}

struct UrcusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "ro_RO"))).uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(muted)
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "leaf").font(.title2).foregroundStyle(sage)
                Text("Zi de odihnă").font(.system(size: 16, weight: .heavy)).foregroundStyle(text)
                if let next = entry.next {
                    Text("Urmează: \(next.title)").font(.system(size: 12, weight: .semibold)).foregroundStyle(muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.items.prefix(family == .systemSmall ? 1 : 2).enumerated()), id: \.offset) { _, item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(bg, for: .widget)
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        let color = Color(red: Double((item.colorHex >> 16) & 0xFF) / 255,
                          green: Double((item.colorHex >> 8) & 0xFF) / 255,
                          blue: Double(item.colorHex & 0xFF) / 255)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.done ? "checkmark.circle.fill" : item.symbol)
                    .foregroundStyle(item.done ? sage : color)
                if item.done { Text("Făcut").font(.system(size: 11, weight: .heavy)).foregroundStyle(sage) }
            }
            Text(item.title).font(.system(size: 15, weight: .heavy)).foregroundStyle(text).lineLimit(2)
            if !item.summary.isEmpty {
                Text(item.summary).font(.system(size: 12, weight: .semibold)).foregroundStyle(peach).lineLimit(1)
            }
        }
    }
}

struct UrcusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UrcusToday", provider: Provider()) { entry in
            UrcusWidgetView(entry: entry)
        }
        .configurationDisplayName("Antrenamentul de azi")
        .description("Ce ai de făcut azi din planul tău.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct UrcusWidgetBundle: WidgetBundle {
    var body: some Widget { UrcusWidget() }
}
