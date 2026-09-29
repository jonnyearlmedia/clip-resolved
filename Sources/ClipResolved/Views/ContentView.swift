import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore
    @AppStorage("crTheme") private var themeRaw: String = CRTheme.dark.rawValue

    private var theme: CRTheme { CRTheme(rawValue: themeRaw) ?? .dark }
    private var cr: CRPalette { theme.palette }

    private static let tabOrder: [WorkspaceSection] = [.project, .ingest, .search, .chat, .activity]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            tabBar
            detail
        }
        .background(cr.card)
        .environment(\.cr, cr)
        .preferredColorScheme(theme.colorScheme)
        .tint(cr.accent)
        .sheet(isPresented: Binding(
            get: { store.previewEvidence != nil },
            set: { if !$0 { store.previewEvidence = nil } }
        )) {
            if let evidence = store.previewEvidence {
                FootagePreviewPresentation(
                    evidence: evidence,
                    onClose: { store.previewEvidence = nil }
                )
                .id(evidence.id)
                .environment(\.cr, cr)
            }
        }
        .alert("Clip Resolved", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    // MARK: Chrome

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text("cr")
                .font(CRFont.mono(13, weight: .heavy))
                .foregroundStyle(cr.accentOn)
                .frame(width: 34, height: 34)
                .background(cr.accent, in: RoundedRectangle(cornerRadius: 6))

            Text("clip resolved")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(cr.text)
                .fixedSize()

            Spacer(minLength: 12)

            Text(statusSummary)
                .font(CRFont.mono(12.5))
                .foregroundStyle(cr.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if store.isBusy {
                ProgressView().controlSize(.small)
            }

            CRIconButton(symbol: theme.toggleSymbol, help: theme.toggleHelp) {
                themeRaw = theme.toggled.rawValue
            }

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(cr.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(cr.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(cr.borderStrong) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(cr.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(cr.border).frame(height: 1) }
    }

    private var statusSummary: String {
        guard let project = store.selectedProject else { return "No project open" }
        return "\(project.name) · \(project.indexedAssets) clips indexed"
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 30) {
                ForEach(Array(Self.tabOrder.enumerated()), id: \.element) { index, section in
                    tabItem(section, number: index + 1)
                }
            }
            .padding(.horizontal, 32)
        }
        .scrollIndicators(.never)
        .background(cr.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(cr.border).frame(height: 1) }
    }

    private func tabItem(_ section: WorkspaceSection, number: Int) -> some View {
        let isActive = store.selection == section
        return Button {
            store.selection = section
        } label: {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(CRFont.mono(12.5))
                    .foregroundStyle(isActive ? cr.accent : cr.textTertiary)
                Text(section.rawValue)
                    .font(.system(size: 18, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? cr.text : cr.textTertiary)
            }
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isActive ? cr.accent : .clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        Group {
            switch store.selection {
            case .project: ProjectView(store: store)
            case .ingest: IngestView(store: store)
            case .chat: ChatView(store: store)
            case .search: SearchView(store: store)
            case .activity: ActivityView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cr.card)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(store: store)
        }
    }
}

private struct StatusBar: View {
    @Environment(\.cr) private var cr
    let store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.isBusy ? cr.accent : cr.textTertiary)
                .frame(width: 6, height: 6)
                .accessibilityLabel(store.isBusy ? "Operation running" : "Idle")
            Text(store.progressMessage)
                .font(CRFont.mono(12.5))
                .foregroundStyle(cr.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(store.resolveMessage)
                .font(CRFont.mono(12.5))
                .foregroundStyle(cr.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(cr.bar)
        .overlay(alignment: .top) { Rectangle().fill(cr.border).frame(height: 1) }
    }
}
