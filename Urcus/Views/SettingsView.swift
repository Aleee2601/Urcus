import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var sync: SyncService
    @Environment(\.modelContext) private var context
    @AppStorage("autoSync") private var autoSync = true
    @AppStorage("garminKeyExpiry") private var keyExpiry: Double = 0
    @State private var keyInput = ""
    @State private var newKeyExpiry = Cal.ro.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var hasKey = KeychainStore.get(KeychainStore.apiKeyAccount) != nil
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false
    @State private var historyDays = 365
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Platform.isMac ? 28 : 20) {
                    ScreenHeader(kicker: "Cont, sincronizare, date", title: "Setări", titleSize: Platform.isMac ? 36 : 34)
                    if Platform.isMac {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 20) { garminCard; syncCard }
                            VStack(spacing: 20) { ApiExplorerCard(enabled: hasKey); dataCard }
                        }
                    } else {
                        garminCard
                        syncCard
                        ApiExplorerCard(enabled: hasKey)
                        dataCard
                        Text("Urcuș · date din Garmin Connect Personal API. Fontul Manrope e licențiat OFL.")
                            .appFont(12).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, Platform.isMac ? 40 : 20)
                .padding(.top, Platform.isMac ? 36 : 12)
                .padding(.bottom, Platform.isMac ? 48 : 120)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .confirmationDialog("Ștergi toate activitățile din aplicație?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Șterge", role: .destructive) {
                    try? context.delete(model: ActivityRecord.self)
                    try? context.save()
                    sync.lastSync = nil
                }
            } message: {
                Text("Contul tău Garmin rămâne neatins.")
            }
        }
    }

    // MARK: Garmin

    private var garminCard: some View {
        SettingsCard {
            HStack(spacing: 14) {
                Image(systemName: "applewatch")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(hasKey ? Theme.sage : Theme.muted)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill((hasKey ? Theme.sage : Theme.muted).opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Garmin Connect").appFont(18, .heavy).foregroundStyle(Theme.text)
                    Text(hasKey ? "Conectat · Personal API" : "Neconectat").appFont(13, .bold).foregroundStyle(hasKey ? Theme.sage : Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)

            if hasKey {
                SettingRow("Cheie") {
                    Label("Salvată în Keychain", systemImage: "lock.fill").foregroundStyle(Theme.text)
                }
                SettingRow("Expiră", last: true) {
                    Text(expiryText).foregroundStyle(expiryColor)
                }
                HStack(spacing: 10) {
                    Button { Task { await test() } } label: {
                        HStack(spacing: 8) {
                            if testing { ProgressView().controlSize(.small) }
                            Text("Testează conexiunea")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 40))
                    .disabled(testing)
                    Button("Înlocuiește cheia") {
                        KeychainStore.delete(KeychainStore.apiKeyAccount)
                        Task { await GarminClient.shared.forgetToken() }
                        hasKey = false
                        testResult = nil
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 40, tint: Theme.coral))
                }
                .padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField("Lipește cheia Personal API", text: $keyInput)
                        .textFieldStyle(.plain)
                        .appFont(15, .medium)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .card(radius: 14, fill: Theme.inset)
                    DatePicker("Expiră pe", selection: $newKeyExpiry, in: Date()..., displayedComponents: .date)
                        .appFont(14, .semibold)
                        .foregroundStyle(Theme.muted)
                    Button("Salvează cheia") { saveKey() }
                        .buttonStyle(PrimaryButtonStyle(height: 44))
                        .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Cheia o creezi pe connect.garmin.com → Setări → Personal API Key. Rămâne doar pe acest dispozitiv, criptată în Keychain.")
                        .appFont(12).foregroundStyle(Theme.muted)
                }
            }

            if let testResult {
                Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .appFont(13, .semibold)
                    .foregroundStyle(testResult.ok ? Theme.sage : Theme.coral)
                    .padding(.top, 10)
            }
        }
    }

    private var expiryText: String {
        guard keyExpiry > 0 else { return "nu știm" }
        let date = Date(timeIntervalSince1970: keyExpiry)
        let days = Cal.ro.dateComponents([.day], from: .now, to: date).day ?? 0
        let formatted = date.formatted(.dateTime.day().month(.wide).year().locale(Fmt.locale))
        if days < 0 { return "a expirat (\(formatted))" }
        if days <= 14 { return "\(formatted) · în \(days) zile" }
        return formatted
    }

    private var expiryColor: Color {
        guard keyExpiry > 0 else { return Theme.muted }
        let days = Cal.ro.dateComponents([.day], from: .now, to: Date(timeIntervalSince1970: keyExpiry)).day ?? 0
        return days <= 14 ? Theme.coral : Theme.text
    }

    // MARK: Sincronizare

    private var syncCard: some View {
        SettingsCard {
            Text("Sincronizare").appFont(18, .heavy).foregroundStyle(Theme.text).padding(.bottom, 6)
            SettingRow("Ultima sincronizare") {
                Text(sync.lastSync.map { Fmt.dateTime($0) } ?? "niciodată")
            }
            SettingRow("Automat la deschidere") {
                Toggle("", isOn: $autoSync).labelsHidden().tint(Theme.sage)
            }
            SettingRow("Cât istoric aduc", last: true) {
                PillSegmented(selection: $historyDays, options: [(365, "1 an"), (730, "2 ani"), (1825, "5 ani")], height: 28)
                    .frame(width: 200)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await sync.sync(context: context) }
                } label: {
                    HStack(spacing: 8) {
                        if sync.isSyncing { ProgressView().controlSize(.small).tint(Theme.onPeach) }
                        Text("Sincronizează acum")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 40))
                .disabled(!hasKey || sync.isSyncing)
                Button("Reia de la zero") {
                    Task { await sync.resetAndFullSync(context: context, days: historyDays) }
                }
                .buttonStyle(SecondaryButtonStyle(height: 40))
                .disabled(!hasKey || sync.isSyncing)
            }
            .padding(.top, 12)
            if let message = sync.message {
                Text(message).appFont(13, .semibold).foregroundStyle(Theme.sage).padding(.top, 8)
            }
            if let error = sync.errorMessage {
                Text(error).appFont(13, .semibold).foregroundStyle(Theme.coral).padding(.top, 8)
            }
        }
    }

    // MARK: Date locale

    private var dataCard: some View {
        SettingsCard {
            Text("Date locale").appFont(18, .heavy).foregroundStyle(Theme.text)
            Text("Șterge activitățile salvate în aplicație. Contul Garmin rămâne neatins; la următoarea sincronizare se aduc din nou.")
                .appFont(13).foregroundStyle(Theme.muted).padding(.vertical, 6)
            Button("Șterge activitățile din aplicație") { confirmWipe = true }
                .buttonStyle(SecondaryButtonStyle(height: 40, tint: Theme.coral))
        }
    }

    // MARK: Acțiuni

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard KeychainStore.set(key, for: KeychainStore.apiKeyAccount) else {
            testResult = (false, "Nu am putut salva cheia în Keychain.")
            return
        }
        keyExpiry = newKeyExpiry.timeIntervalSince1970
        keyInput = ""
        hasKey = true
        Task {
            await test()
            if testResult?.ok == true { await sync.sync(context: context) }
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            try await GarminClient.shared.testConnection()
            testResult = (true, "Conexiunea cu Garmin merge.")
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }
}

// MARK: - Bucăți

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

struct SettingRow<Value: View>: View {
    let label: String
    var last = false
    @ViewBuilder var value: () -> Value

    init(_ label: String, last: Bool = false, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.last = last
        self.value = value
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label).appFont(14, .semibold).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                value().appFont(14, .bold).foregroundStyle(Theme.text)
            }
            .padding(.vertical, 13)
            if !last { Hairline() }
        }
    }
}

struct ApiExplorerCard: View {
    let enabled: Bool

    enum Endpoint: String, CaseIterable, Identifiable {
        case sleep, hrv, bodyBattery, dailySummary, heartRate, stress, hrZones
        var id: String { rawValue }

        var label: String {
            switch self {
            case .sleep: "Somn"
            case .hrv: "HRV"
            case .bodyBattery: "Body Battery"
            case .dailySummary: "Rezumat zilnic"
            case .heartRate: "Puls"
            case .stress: "Stres"
            case .hrZones: "Zone de puls"
            }
        }

        func request(for date: Date) -> (path: String, query: [String: String]) {
            let d = Fmt.isoDay(date)
            switch self {
            case .sleep: return ("/sleep-service/sleep/dailySleep", ["date": d])
            case .hrv: return ("/hrv-service/hrv/\(d)", [:])
            case .bodyBattery: return ("/wellness-service/wellness/bodyBattery/reports/daily", ["startDate": d, "endDate": d])
            case .dailySummary: return ("/usersummary-service/v2/dailysummaries", ["startDate": d, "endDate": d])
            case .heartRate: return ("/wellness-service/wellness/dailyHeartRate", ["date": d])
            case .stress: return ("/usersummary-service/stats/stress/daily/\(d)/\(d)", [:])
            case .hrZones: return ("/biometric-service/heartRateZones/v2", [:])
            }
        }
    }

    @State private var endpoint: Endpoint = .sleep
    @State private var date = Date()
    @State private var output = ""
    @State private var loading = false

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explorator date Garmin").appFont(18, .heavy).foregroundStyle(Theme.text)
                Text("Datele brute din care construim ecranele de recuperare.").appFont(13).foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Endpoint.allCases) { e in
                        FilterChip(label: e.label, isOn: endpoint == e, height: 32) { endpoint = e }
                    }
                }
            }
            .padding(.vertical, 14)
            HStack(spacing: 10) {
                DatePicker("Ziua", selection: $date, in: ...Date(), displayedComponents: .date)
                    .appFont(14, .semibold)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Button {
                    Task { await load() }
                } label: {
                    HStack(spacing: 8) {
                        if loading { ProgressView().controlSize(.small).tint(Theme.onPeach) }
                        Text("Încarcă")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 40))
                .disabled(!enabled || loading)
            }
            if !output.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    Text(output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xC9D3CE))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(maxHeight: 320)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x0B110F)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
                .padding(.top, 14)
                ShareLink(item: output) { Label("Trimite JSON-ul", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle(height: 38))
                    .padding(.top, 10)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let req = endpoint.request(for: date)
        do {
            let json = try await GarminClient.shared.prettyJSON(req.path, query: req.query)
            output = json.count > 20_000 ? String(json.prefix(20_000)) + "\n… (trunchiat)" : json
        } catch {
            output = "Eroare: \(error.localizedDescription)"
        }
    }
}
