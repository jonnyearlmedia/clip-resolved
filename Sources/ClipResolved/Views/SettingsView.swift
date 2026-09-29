import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore
    @AppStorage("crTheme") private var themeRaw: String = CRTheme.dark.rawValue

    private var theme: CRTheme { CRTheme(rawValue: themeRaw) ?? .dark }

    var body: some View {
        SettingsBody(store: store, theme: theme) { themeRaw = theme.toggled.rawValue }
            .environment(\.cr, theme.palette)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.palette.accent)
    }
}

private struct SettingsBody: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore
    let theme: CRTheme
    let toggleTheme: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Settings")
                        .font(CRFont.title(22))
                        .foregroundStyle(cr.text)
                    Spacer()
                    CRIconButton(symbol: theme.toggleSymbol, help: theme.toggleHelp, action: toggleTheme)
                }

                SettingRow(
                    label: "Active Projects folder",
                    sub: "Where new projects are created"
                ) {
                    HStack(spacing: 8) {
                        TextField("Active Projects root", text: $store.activeProjectsRoot)
                            .textFieldStyle(CRFieldStyle())
                            .frame(minWidth: 220)
                        Button("Choose…") {
                            if let url = FolderPicker.chooseFolder(
                                prompt: "Choose the Active Projects folder",
                                startingAt: store.activeProjectsRoot
                            ) {
                                store.activeProjectsRoot = url.path
                            }
                        }
                        .buttonStyle(CRSecondaryButtonStyle())
                    }
                }

                SettingRow(
                    label: "New shoot gap",
                    sub: "A pause longer than this starts a new shoot"
                ) {
                    Stepper(
                        value: $store.gapHours, in: 0.5...12, step: 0.5,
                        label: { settingValue(String(format: "%.1f hours", store.gapHours)) }
                    )
                }

                SettingRow(
                    label: "Visual sample interval",
                    sub: "How often a frame is sampled while indexing"
                ) {
                    Stepper(
                        value: $store.sampleInterval, in: 0.5...10, step: 0.5,
                        label: { settingValue(String(format: "%.1f seconds", store.sampleInterval)) }
                    )
                }

                SettingRow(
                    label: "Search threshold",
                    sub: "Still being tuned against real footage — not finalized"
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $store.minScore, in: 0.1...0.5, step: 0.01)
                            .frame(width: 150)
                        settingValue(String(format: "%.2f", store.minScore))
                    }
                }

                SettingRow(
                    label: "Handle length",
                    sub: "Extra source frames kept before and after each range"
                ) {
                    HStack(spacing: 10) {
                        Stepper(
                            value: $store.preHandle, in: 0...15,
                            label: { settingValue(String(format: "%.0fs before", store.preHandle)) }
                        )
                        Stepper(
                            value: $store.postHandle, in: 0...15,
                            label: { settingValue(String(format: "%.0fs after", store.postHandle)) }
                        )
                    }
                }

                SettingRow(
                    label: "Minimum usable duration",
                    sub: "Ranges shorter than this are dropped from SELECTS"
                ) {
                    Stepper(
                        value: $store.minimumDuration, in: 1...30,
                        label: { settingValue(String(format: "%.0f seconds", store.minimumDuration)) }
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(cr.card)
    }

    private func settingValue(_ text: String) -> some View {
        Text(text)
            .font(CRFont.mono(12))
            .foregroundStyle(cr.textSecondary)
            .frame(minWidth: 96, alignment: .trailing)
    }
}

private struct SettingRow<Control: View>: View {
    @Environment(\.cr) private var cr
    let label: String
    let sub: String
    @ViewBuilder var control: Control

    var body: some View {
        CRCard(padding: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(CRFont.heading(13.5))
                        .foregroundStyle(cr.text)
                    Text(sub)
                        .font(CRFont.body(11.5))
                        .foregroundStyle(cr.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                control
            }
        }
    }
}
