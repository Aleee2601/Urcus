import SwiftUI
import SwiftData

struct PlanGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var plans: [TrainingPlan]
    @State private var options = PlanOptions()

    private var weeks: Int { PlanGenerator.weekCount(options) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Obiectiv") {
                    TextField("Numele planului", text: $options.name)
                    Picker("Tip", selection: $options.goal) {
                        ForEach(PlanGoal.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Perioadă") {
                    DatePicker("Începe", selection: $options.startDate, displayedComponents: .date)
                    DatePicker(options.goal.raceKm == nil ? "Se termină" : "Data cursei",
                               selection: $options.raceDate,
                               in: options.startDate...,
                               displayedComponents: .date)
                    LabeledContent("Durată", value: "\(weeks) săptămâni")
                }

                Section {
                    Stepper(value: $options.startLongKm, in: 3...20, step: 1) {
                        LabeledContent("Tura lungă la început", value: "\(Int(options.startLongKm)) km")
                    }
                    Toggle("Sală (forță)", isOn: $options.includeGym)
                    Toggle("Înot", isOn: $options.includeSwim)
                } header: {
                    Text("Nivel de pornire")
                }

                Section {
                    LabeledContent("Dealul tău") {
                        TextField("ex. Tâmpa", text: $options.hillName)
                            .multilineTextAlignment(.trailing)
                    }
                    dayPicker("Alergare ușoară", \.easyRun)
                    if options.includeGym { dayPicker("Sală", \.gym) }
                    dayPicker(options.hillName.isEmpty ? "Urcare" : options.hillName, \.hill)
                    if options.includeSwim { dayPicker("Înot", \.swim) }
                    dayPicker("Tura lungă", \.long)
                } header: {
                    Text("Săptămâna ta")
                } footer: {
                    Text("La fiecare a 4-a săptămână volumul scade, iar în ultimele 2 săptămâni dinaintea cursei se reduce treptat. Poți modifica orice antrenament după aceea.")
                }

                if weeks < 6 {
                    Section {
                        Label("Sub 6 săptămâni e puțin pentru o pregătire progresivă.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .formTheme()
            .navigationTitle("Plan nou")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Renunță") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Creează") { create() }
                        .disabled(options.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func dayPicker(_ title: String, _ key: WritableKeyPath<WeekSchedule, Int>) -> some View {
        Picker(title, selection: Binding(
            get: { options.schedule[keyPath: key] },
            set: { options.schedule[keyPath: key] = $0 })) {
            ForEach(0..<7, id: \.self) { Text(WeekSchedule.weekdayNames[$0]).tag($0) }
        }
    }

    private func create() {
        for plan in plans { plan.isActive = false }
        _ = PlanGenerator.create(options, in: context)
        WorkoutMatcher.match(context: context)
        try? context.save()
        dismiss()
    }
}
