import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        Form {
            TextField("Active Projects root", text: $store.activeProjectsRoot)
            LabeledContent("New shoot gap") {
                Stepper("\(store.gapHours, specifier: "%.1f") hours", value: $store.gapHours, in: 0.5...12, step: 0.5)
            }
            LabeledContent("Visual sample interval") {
                Stepper("\(store.sampleInterval, specifier: "%.1f") seconds", value: $store.sampleInterval, in: 0.5...10, step: 0.5)
            }
            LabeledContent("Search threshold") {
                Slider(value: $store.minScore, in: 0.1...0.5, step: 0.01) { Text("Search threshold") }
                Text(store.minScore, format: .number.precision(.fractionLength(2))).monospacedDigit()
            }
            LabeledContent("Handles") {
                Stepper("\(store.preHandle, specifier: "%.0f")s before", value: $store.preHandle, in: 0...15)
                Stepper("\(store.postHandle, specifier: "%.0f")s after", value: $store.postHandle, in: 0...15)
            }
            LabeledContent("Minimum SELECTS range") {
                Stepper("\(store.minimumDuration, specifier: "%.0f") seconds", value: $store.minimumDuration, in: 1...30)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
