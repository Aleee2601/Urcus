import SwiftUI
import SwiftData

/// Editează un antrenament existent sau creează unul nou (când `workout` e nil).
struct WorkoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let workout: PlannedWorkout?
    let plan: TrainingPlan?

    @State private var date = Date()
    @State private var sport: Sport = .run
    @State private var title = ""
    @State private var details = ""
    @State private var km = ""
    @State private var minutes = ""
    @State private var elevation = ""
    @State private var intensity: Intensity = .easy
    @State private var manuallyDone = false
    @State private var skipped = false
    @State private var matched: ActivityRecord?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titlu", text: $title)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    Picker("Sport", selection: $sport) {
                        ForEach(Sport.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Intensitate", selection: $intensity) {
                        ForEach(Intensity.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Ținte") {
                    numberField("Distanță (km)", text: $km, decimal: true)
                    numberField("Durată (min)", text: $minutes)
                    numberField("Urcare D+ (m)", text: $elevation)
                }

                Section("Detalii") {
                    TextEditor(text: $details)
                        .frame(minHeight: 90)
                }

                if workout != nil {
                    Section("Status") {
                        Toggle("Făcut", isOn: $manuallyDone)
                        Toggle("Sar peste el", isOn: $skipped)
                        if let matched {
                            ActivityListRow(activity: matched, compact: true)
                            Button("Nu e activitatea potrivită", role: .destructive) {
                                self.matched = nil
                            }
                        }
                    }
                    Section {
                        Button("Șterge antrenamentul", role: .destructive) {
                            if let workout { context.delete(workout) }
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .formTheme()
            .navigationTitle(workout == nil ? "Antrenament nou" : "Antrenament")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Renunță") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>, decimal: Bool = false) -> some View {
        LabeledContent(label) {
            TextField("–", text: text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                #endif
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let workout else {
            date = Cal.ro.startOfDay(for: .now)
            return
        }
        date = workout.date
        sport = workout.sport
        title = workout.title
        details = workout.details
        km = workout.targetDistanceKm.map { Fmt.number($0) } ?? ""
        minutes = workout.targetDurationMin.map(String.init) ?? ""
        elevation = workout.targetElevation.map(String.init) ?? ""
        intensity = workout.intensity
        manuallyDone = workout.manuallyDone
        skipped = workout.skipped
        if let id = workout.completedActivityId {
            var descriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate<ActivityRecord> { $0.garminId == id })
            descriptor.fetchLimit = 1
            matched = try? context.fetch(descriptor).first
        }
    }

    private func save() {
        let target: PlannedWorkout
        if let workout {
            target = workout
        } else {
            target = PlannedWorkout(date: date, sport: sport, title: title)
            context.insert(target)
            target.plan = plan
        }
        target.date = Cal.ro.startOfDay(for: date)
        target.sport = sport
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.details = details
        target.targetDistanceKm = Fmt.parseNumber(km)
        target.targetDurationMin = Fmt.parseNumber(minutes).map { Int($0) }
        target.targetElevation = Fmt.parseNumber(elevation).map { Int($0) }
        target.intensity = intensity
        target.manuallyDone = manuallyDone
        target.skipped = skipped
        if workout?.completedActivityId != nil && matched == nil {
            target.completedActivityId = nil
            target.ignoreAutoMatch = true
        }
        WorkoutMatcher.match(context: context)
        try? context.save()
        dismiss()
    }
}
