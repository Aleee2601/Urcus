import SwiftUI
import SwiftData

@main
struct UrcusApp: App {
    @StateObject private var sync = SyncService()

    init() {
        AppFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sync)
                .preferredColorScheme(.dark)
                .tint(Theme.peach)
        }
        .modelContainer(for: [ActivityRecord.self, TrainingPlan.self, PlannedWorkout.self])
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, plan, history, stats, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Azi"
        case .plan: "Plan"
        case .history: "Istoric"
        case .stats: "Statistici"
        case .settings: "Setări"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .plan: "calendar"
        case .history: "mountain.2"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var sync: SyncService
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .today

    var body: some View {
        content
            .task { await sync.syncIfStale(context: context) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await sync.syncIfStale(context: context) } }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        NavigationSplitView {
            MacSidebar(selection: $tab)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            screen(for: tab)
        }
        .background(Theme.bg)
        #else
        ZStack(alignment: .bottom) {
            screen(for: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            FloatingTabBar(selection: $tab)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        #endif
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .plan: PlanView()
        case .history: HistoryView()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - iPhone: bara de tab-uri plutitoare

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isOn = tab == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: isOn ? .bold : .medium))
                            .frame(height: 24)
                        Text(tab.label).appFont(10, isOn ? .heavy : .bold)
                    }
                    .foregroundStyle(isOn ? Theme.peach : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 68)
        .background(
            Capsule().fill(Theme.surface2.opacity(0.92))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

// MARK: - Mac: meniul lateral

struct MacSidebar: View {
    @Binding var selection: AppTab
    @EnvironmentObject private var sync: SyncService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.peach)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x2E5248)))
                Text("Urcuș").appFont(18, .heavy).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 22)

            ForEach(AppTab.allCases) { tab in
                let isOn = tab == selection
                Button { selection = tab } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbol).font(.system(size: 15, weight: .semibold)).frame(width: 20)
                        Text(tab.label).appFont(14, isOn ? .heavy : .semibold)
                        Spacer()
                    }
                    .foregroundStyle(isOn ? Theme.text : Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isOn ? Theme.surface2 : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(sync.hasKey ? "Garmin conectat" : "Garmin neconectat")
                    .appFont(12, .heavy)
                    .foregroundStyle(sync.hasKey ? Theme.sage : Theme.muted)
                Text(syncStatus).appFont(12).foregroundStyle(Theme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 14)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }

    private var syncStatus: String {
        if sync.isSyncing { return "Se sincronizează…" }
        guard let last = sync.lastSync else { return "Încă nesincronizat" }
        let minutes = Int(Date().timeIntervalSince(last) / 60)
        if minutes < 1 { return "Sincronizat acum" }
        if minutes < 60 { return "Sincronizat acum \(minutes) min" }
        return "Sincronizat \(Fmt.dateTime(last))"
    }
}
