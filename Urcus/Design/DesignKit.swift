import SwiftUI

// MARK: - Carduri și text

struct CardStyle: ViewModifier {
    var radius: CGFloat = Theme.radiusM
    var fill: Color = Theme.surface
    var stroke: Color = Theme.line
    var strokeWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(stroke, lineWidth: strokeWidth))
    }
}

extension View {
    func card(radius: CGFloat = Theme.radiusM, fill: Color = Theme.surface,
              stroke: Color = Theme.line, strokeWidth: CGFloat = 1) -> some View {
        modifier(CardStyle(radius: radius, fill: fill, stroke: stroke, strokeWidth: strokeWidth))
    }
}

struct Kicker: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text.uppercased(with: Fmt.locale))
            .appFont(12, .bold)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct ScreenHeader<Trailing: View>: View {
    let kicker: String
    let title: String
    var titleSize: CGFloat = 34
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: kicker)
                Text(title)
                    .appFont(titleSize, .heavy)
                    .tracking(-0.6)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(kicker: String, title: String, titleSize: CGFloat = 34) {
        self.init(kicker: kicker, title: title, titleSize: titleSize) { EmptyView() }
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).appFont(18, .heavy).foregroundStyle(Theme.text)
            Spacer()
            if let trailing {
                Text(trailing).appFont(13, .bold).foregroundStyle(Theme.muted).monospacedDigit()
            }
        }
    }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.sage
    var body: some View {
        Text(text.uppercased(with: Fmt.locale))
            .appFont(11, .heavy)
            .tracking(1.1)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Etichetă mică + cifră mare, cu unitate opțională.
struct BigStat: View {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = Theme.text
    var size: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).appFont(12, .semibold).foregroundStyle(Theme.muted)
            (Text(value).font(AppFont.font(size, .heavy)).foregroundColor(color)
             + Text(unit.map { " \($0)" } ?? "").font(AppFont.font(max(12, size * 0.55), .semibold)).foregroundColor(Theme.muted))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Statistică într-o căsuță (pentru grile).
struct StatBox: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var fill: Color = Theme.surface

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).appFont(12, .semibold).foregroundStyle(Theme.muted)
            Text(value).appFont(20, .heavy).foregroundStyle(color).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(radius: 18, fill: fill)
    }
}

struct SportTile: View {
    let sport: Sport
    var size: CGFloat = 44
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(sport.color.opacity(0.14))
            .overlay(
                Image(systemName: sport.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(sport.color)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 10
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: - Status

struct StatusMark: View {
    let status: WorkoutStatus
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch status {
            case .done:
                Circle().fill(Theme.sage)
                    .overlay(Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .heavy)).foregroundStyle(Theme.bg))
            case .today:
                Circle().strokeBorder(Theme.peach, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            case .upcoming:
                Circle().strokeBorder(Theme.mutedDot, lineWidth: 1.5)
            case .missed:
                Circle().strokeBorder(Theme.coral, lineWidth: 1.5)
                    .overlay(Image(systemName: "exclamationmark").font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(Theme.coral))
            case .skipped:
                Circle().fill(Theme.track)
                    .overlay(Image(systemName: "minus").font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(Theme.muted))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(status.label)
    }
}

struct ProgressRing<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 9
    var color: Color = Theme.sage
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
    }
}

// MARK: - Butoane

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 48
    var fill = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(15, .heavy)
            .foregroundStyle(Theme.onPeach)
            .padding(.horizontal, 20)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.peach))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var tint: Color = Theme.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(14, .bold)
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint == Theme.text ? Theme.lineStrong : tint.opacity(0.4), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

struct CircleIconButton: View {
    let systemImage: String
    let label: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? Theme.onPeach : Theme.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(filled ? Theme.peach : Theme.surface))
                .overlay(Circle().strokeBorder(filled ? .clear : Theme.lineStrong, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Selectoare

struct PillSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let label = options[i].1
                let isOn = selection == value
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                } label: {
                    Text(label)
                        .appFont(14, isOn ? .heavy : .bold)
                        .foregroundStyle(isOn ? Theme.bg : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isOn ? Theme.text : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

struct FilterChip: View {
    let label: String
    let isOn: Bool
    var height: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .appFont(13, isOn ? .heavy : .bold)
                .foregroundStyle(isOn ? Theme.bg : Theme.muted)
                .padding(.horizontal, 14)
                .frame(height: height)
                .background(Capsule().fill(isOn ? Theme.text : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.lineStrong, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Caută după nume sau loc"
    var fill: Color = Theme.surface

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .appFont(15, .medium)
                .foregroundStyle(Theme.text)
                .accessibilityLabel("Caută activități")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Șterge căutarea")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .card(radius: 16, fill: fill)
    }
}

// MARK: - Decor

/// Creasta de munte din spatele cardului zilei.
struct MountainRidge: Shape {
    var closed: Bool
    private let points: [CGPoint] = [
        .init(x: 0, y: 0.92), .init(x: 0.15, y: 0.77), .init(x: 0.28, y: 0.82), .init(x: 0.41, y: 0.50),
        .init(x: 0.51, y: 0.62), .init(x: 0.64, y: 0.25), .init(x: 0.74, y: 0.43), .init(x: 0.85, y: 0.32),
        .init(x: 1, y: 0.58)
    ]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, pt) in points.enumerated() {
            let point = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

struct MountainBackdrop: View {
    var body: some View {
        ZStack {
            MountainRidge(closed: true).fill(Theme.surface2)
            MountainRidge(closed: false).stroke(Color(hex: 0x2C3B34), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Plan: faze și săptămână

struct PhaseBar: View {
    let phases: [PlanPhase]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, phases.reduce(0) { $0 + $1.weeks })
            let spacing: CGFloat = 4
            let available = geo.size.width - spacing * CGFloat(max(0, phases.count - 1))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(phases) { phase in
                    let width = available * CGFloat(phase.weeks) / CGFloat(total)
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.peach).frame(width: max(0, width * phase.filled))
                        }
                        .frame(height: 8)
                        Text(phase.label)
                            .appFont(11, phase.isCurrent ? .heavy : .bold)
                            .foregroundStyle(phase.isCurrent ? Theme.peach : Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: width, alignment: .leading)
                }
            }
        }
        .frame(height: 30)
    }
}

struct DayDot: Identifiable {
    enum State { case done, today, planned, empty }
    let date: Date
    let color: Color
    let state: State
    var id: Date { date }
    var isToday: Bool { Cal.ro.isDateInToday(date) }
    var letter: String {
        let symbols = ["D", "L", "M", "M", "J", "V", "S"]
        return symbols[(Cal.ro.component(.weekday, from: date) - 1) % 7]
    }
}

struct WeekStrip: View {
    let days: [DayDot]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 8) {
                    Text(day.letter).appFont(11, day.isToday ? .heavy : .bold)
                    dot(day)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(day.isToday ? Theme.bg : Theme.muted)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(day.isToday ? Theme.text : Theme.surface))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Săptămâna curentă")
    }

    @ViewBuilder
    private func dot(_ day: DayDot) -> some View {
        switch day.state {
        case .done: Circle().fill(day.color).frame(width: 10, height: 10)
        case .today: Circle().strokeBorder(Theme.bg, lineWidth: 2).frame(width: 10, height: 10)
        case .planned: Circle().strokeBorder(day.color, lineWidth: 1.5).frame(width: 10, height: 10)
        case .empty: Circle().strokeBorder(Theme.mutedDot, lineWidth: 1.5).frame(width: 10, height: 10)
        }
    }
}

/// Bara cu timpul în zonele de puls.
struct ZoneBar: View {
    let seconds: [Double]
    private let colors: [Color] = [Theme.mutedDot, Theme.sage, Theme.sand, Theme.peach, Theme.coral]

    var body: some View {
        let total = max(1, seconds.reduce(0, +))
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(seconds.indices, id: \.self) { i in
                        Rectangle().fill(colors[i % colors.count])
                            .frame(width: max(0, (geo.size.width - 8) * seconds[i] / total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack {
                ForEach(seconds.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Z\(i + 1)").appFont(11, .heavy).foregroundStyle(i == 0 ? Theme.muted : colors[i])
                        Text("\(Int((seconds[i] / total * 100).rounded()))%").appFont(13, .bold).foregroundStyle(Theme.text).monospacedDigit()
                    }
                    if i < seconds.count - 1 { Spacer() }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

extension View {
    /// Fundalul aplicației pe tot ecranul.
    func screenBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }
}

extension View {
    /// Formularele (foi de editare) în culorile aplicației.
    func formTheme() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .tint(Theme.peach)
    }
}
